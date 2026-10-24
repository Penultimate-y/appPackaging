"""outlook-triage-mcp — FastMCP server exposing Microsoft 365 mail triage tools.

Tools (all read-only except ``ensure_inbox_rule``):

- ``auth_status``       — token state; starts device-code sign-in when needed
- ``search_messages``   — search/list messages in a folder
- ``get_message``       — full message body (+ optional attachment text)
- ``daily_briefing``    — classified digest of the last N hours
- ``list_inbox_rules``  — inbox rules inventory
- ``ensure_inbox_rule`` — idempotent rule provisioning (THE ONLY WRITE TOOL,
  disabled unless OUTLOOK_MCP_ENABLE_WRITE=1)
"""

from __future__ import annotations

import logging
import re
import sys
from datetime import datetime, timedelta, timezone
from typing import Any

from mcp.server.fastmcp import FastMCP
from mcp.types import ToolAnnotations

from . import briefing as briefing_mod
from . import rules as rules_mod
from .attachments import fetch_attachment_texts
from .auth import AuthManager, AuthRequiredError
from .classify import ClassifierConfig
from .config import Settings
from .graph import GraphClient, GraphError

# MCP stdio servers must keep stdout pristine (protocol channel) — log to stderr.
logging.basicConfig(level=logging.INFO, stream=sys.stderr,
                    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
log = logging.getLogger(__name__)

MESSAGE_LIST_FIELDS = (
    "id,subject,from,receivedDateTime,bodyPreview,isRead,"
    "hasAttachments,importance,categories"
)
TEXT_BODY_HEADER = {"Prefer": 'outlook.body-content-type="text"'}
WELL_KNOWN_FOLDERS = {
    "inbox", "archive", "drafts", "sentitems", "deleteditems",
    "junkemail", "outbox",
}

mcp = FastMCP(
    "outlook-triage",
    instructions=(
        "Microsoft 365 mail triage over Microsoft Graph. Read-only by "
        "default; ensure_inbox_rule is the only write tool and requires "
        "OUTLOOK_MCP_ENABLE_WRITE=1. If a tool reports that authentication "
        "is required, call auth_status and relay the verification URL and "
        "code to the user."
    ),
)

# Lazy singletons so importing this module (and listing tools) never touches
# the network or the token cache.
_auth_manager: AuthManager | None = None
_graph_client: GraphClient | None = None


def _auth() -> AuthManager:
    global _auth_manager
    if _auth_manager is None:
        _auth_manager = AuthManager(Settings.from_env())
    return _auth_manager


def _graph() -> GraphClient:
    global _graph_client
    if _graph_client is None:
        _graph_client = GraphClient(lambda: _auth().get_token())
    return _graph_client


def _auth_error() -> dict[str, Any]:
    return {
        "error": "not_authenticated",
        "hint": (
            "Call the auth_status tool to start device-code sign-in, then "
            "give the user the verification URL and code."
        ),
    }


def _compact_message(message: dict[str, Any]) -> dict[str, Any]:
    email_address = (message.get("from") or {}).get("emailAddress", {})
    preview = (message.get("bodyPreview") or "")[:200]
    return {
        "id": message.get("id"),
        "subject": message.get("subject"),
        "from_name": email_address.get("name"),
        "from_address": email_address.get("address"),
        "received": message.get("receivedDateTime"),
        "is_read": message.get("isRead"),
        "has_attachments": message.get("hasAttachments"),
        "importance": message.get("importance"),
        "preview": preview,
    }


def _parse_since(since: str) -> datetime:
    """Accept ISO 8601 ('2026-07-01T00:00:00Z') or relative ('24h', '7d')."""
    relative = re.fullmatch(r"(\d+)([hd])", since.strip().lower())
    if relative:
        amount, unit = int(relative.group(1)), relative.group(2)
        delta = timedelta(hours=amount) if unit == "h" else timedelta(days=amount)
        return datetime.now(timezone.utc) - delta
    parsed = datetime.fromisoformat(since.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def _resolve_folder(folder: str) -> str:
    """Map a folder name to a Graph folder segment (well-known id or real id)."""
    normalized = folder.strip().lower().replace(" ", "")
    if normalized in WELL_KNOWN_FOLDERS:
        return normalized
    found = rules_mod.find_folder(_graph(), folder)
    if not found:
        raise GraphError(404, f"Mail folder not found: '{folder}'")
    return found["id"]


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


@mcp.tool(
    annotations=ToolAnnotations(title="Authentication status", readOnlyHint=True)
)
def auth_status() -> dict:
    """Check Microsoft 365 auth state; start device-code sign-in if needed.

    When sign-in is required, returns a verification URL and a user code —
    relay both to the user, then call this tool again to confirm completion.
    """
    auth = _auth()
    state = auth.status()
    if state.get("authenticated") or state.get("state") == "awaiting_sign_in":
        return state
    try:
        flow = auth.begin_device_flow()
    except Exception as exc:
        return {
            "authenticated": False,
            "state": "error",
            "error": f"Could not start device-code flow: {exc}",
        }
    flow.update(
        {
            "authenticated": False,
            "state": "awaiting_sign_in",
            "instructions": (
                f"Open {flow['verification_uri']} and enter code "
                f"{flow['user_code']}. Then call auth_status again to confirm."
            ),
        }
    )
    return flow


@mcp.tool(annotations=ToolAnnotations(title="Search messages", readOnlyHint=True))
def search_messages(
    query: str = "",
    folder: str = "inbox",
    top: int = 20,
    since: str | None = None,
) -> dict:
    """Search or list mail messages. Read-only.

    Args:
        query: Free-text search (Graph $search / KQL, e.g. 'invoice',
            'from:alice subject:report'). Empty = list newest first.
        folder: Well-known folder (inbox, archive, drafts, sentitems,
            deleteditems, junkemail, outbox) or a custom folder display name.
        top: Max messages to return (1-100).
        since: Only messages received after this point. ISO 8601
            ('2026-07-01T00:00:00Z') or relative ('24h', '7d').
    """
    top = max(1, min(int(top), 100))
    try:
        folder_segment = _resolve_folder(folder)
        path = f"me/mailFolders/{folder_segment}/messages"
        since_dt = _parse_since(since) if since else None

        if query:
            # Graph does not allow $search combined with $filter/$orderby;
            # the 'since' cutoff is applied client-side instead.
            params: dict[str, Any] = {
                "$search": f'"{query}"',
                "$top": top,
                "$select": MESSAGE_LIST_FIELDS,
            }
            messages = _graph().get(path, params=params,
                                    headers=TEXT_BODY_HEADER).get("value", [])
            if since_dt:
                cutoff = since_dt.strftime("%Y-%m-%dT%H:%M:%SZ")
                messages = [
                    m for m in messages if (m.get("receivedDateTime") or "") >= cutoff
                ]
        else:
            params = {
                "$top": top,
                "$orderby": "receivedDateTime desc",
                "$select": MESSAGE_LIST_FIELDS,
            }
            if since_dt:
                params["$filter"] = (
                    f"receivedDateTime ge {since_dt.strftime('%Y-%m-%dT%H:%M:%SZ')}"
                )
            messages = _graph().get(path, params=params,
                                    headers=TEXT_BODY_HEADER).get("value", [])
    except AuthRequiredError:
        return _auth_error()
    except (GraphError, ValueError) as exc:
        return {"error": str(exc)}

    return {
        "folder": folder,
        "count": len(messages),
        "messages": [_compact_message(m) for m in messages],
    }


@mcp.tool(annotations=ToolAnnotations(title="Get message", readOnlyHint=True))
def get_message(message_id: str, include_attachments: bool = False) -> dict:
    """Fetch one message: full plain-text body plus metadata. Read-only.

    Args:
        message_id: Graph message id (from search_messages or daily_briefing).
        include_attachments: Also download attachments and extract text
            locally from PDF / DOCX / XLSX (other types are listed only).
    """
    try:
        message = _graph().get(
            f"me/messages/{message_id}",
            params={
                "$select": (
                    "id,subject,from,toRecipients,ccRecipients,receivedDateTime,"
                    "body,isRead,hasAttachments,importance,categories"
                )
            },
            headers=TEXT_BODY_HEADER,
        )
        result = _compact_message(message)
        result["to"] = [
            r.get("emailAddress", {}).get("address")
            for r in message.get("toRecipients", [])
        ]
        result["cc"] = [
            r.get("emailAddress", {}).get("address")
            for r in message.get("ccRecipients", [])
        ]
        result["body"] = (message.get("body") or {}).get("content", "")
        result["categories"] = message.get("categories", [])

        if include_attachments and message.get("hasAttachments"):
            settings = Settings.from_env()
            result["attachments"] = fetch_attachment_texts(
                _graph(), message_id, max_bytes=settings.max_attachment_bytes
            )
        return result
    except AuthRequiredError:
        return _auth_error()
    except GraphError as exc:
        return {"error": str(exc)}


@mcp.tool(annotations=ToolAnnotations(title="Daily briefing", readOnlyHint=True))
def daily_briefing(hours: int = 24) -> str:
    """Classified digest of recent inbox mail. Read-only, no LLM calls.

    Groups messages from the last N hours into: urgent, action_needed, fyi,
    newsletter — using deterministic keyword heuristics (configurable via
    OUTLOOK_MCP_* env vars or a JSON rules file). Returns Markdown.
    """
    hours = max(1, min(int(hours), 24 * 30))
    since = datetime.now(timezone.utc) - timedelta(hours=hours)
    try:
        messages = _graph().get_paged(
            "me/mailFolders/inbox/messages",
            params={
                "$filter": (
                    f"receivedDateTime ge {since.strftime('%Y-%m-%dT%H:%M:%SZ')}"
                ),
                "$orderby": "receivedDateTime desc",
                "$top": 100,
                "$select": MESSAGE_LIST_FIELDS,
            },
            headers=TEXT_BODY_HEADER,
            max_items=200,
        )
    except AuthRequiredError:
        return (
            "Not authenticated with Microsoft 365. Call the auth_status tool "
            "to start device-code sign-in."
        )
    except GraphError as exc:
        return f"Graph error while fetching messages: {exc}"

    config = ClassifierConfig.from_env()
    return briefing_mod.build_briefing(messages, config, hours=hours)


@mcp.tool(annotations=ToolAnnotations(title="List inbox rules", readOnlyHint=True))
def list_inbox_rules() -> dict:
    """List all inbox message rules (name, state, conditions, actions). Read-only."""
    try:
        rules = rules_mod.list_rules(_graph())
    except AuthRequiredError:
        return _auth_error()
    except GraphError as exc:
        return {"error": str(exc)}
    return {
        "count": len(rules),
        "rules": [
            {
                "id": rule.get("id"),
                "name": rule.get("displayName"),
                "enabled": rule.get("isEnabled"),
                "sequence": rule.get("sequence"),
                "conditions": rule.get("conditions"),
                "actions": rule.get("actions"),
            }
            for rule in rules
        ],
    }


@mcp.tool(
    annotations=ToolAnnotations(
        title="Ensure inbox rule (WRITE)",
        readOnlyHint=False,
        destructiveHint=False,
        idempotentHint=True,
    )
)
def ensure_inbox_rule(name: str, from_contains: str, move_to_folder: str) -> dict:
    """Idempotently provision one inbox rule. THE ONLY WRITE TOOL.

    Creates (or converges) a rule: messages whose sender matches
    ``from_contains`` are moved to folder ``move_to_folder`` (created if
    missing). Safe to run repeatedly — an already-correct rule results in
    zero write calls; never duplicates rules or folders.

    Disabled unless the server runs with OUTLOOK_MCP_ENABLE_WRITE=1
    (which also requires re-consenting to write scopes on next sign-in).

    Args:
        name: Rule display name — the idempotency key.
        from_contains: Substring matched against the sender address/name.
        move_to_folder: Target folder display name.
    """
    settings = Settings.from_env()
    if not settings.write_enabled:
        return {
            "error": "write_disabled",
            "hint": (
                "This server runs read-only. Set OUTLOOK_MCP_ENABLE_WRITE=1 "
                "in the server environment, restart it, and re-authenticate "
                "(write scopes require a new consent)."
            ),
        }
    try:
        return rules_mod.ensure_rule(_graph(), name, from_contains, move_to_folder)
    except AuthRequiredError:
        return _auth_error()
    except GraphError as exc:
        return {"error": str(exc)}


def main() -> None:
    """Entry point: run the MCP server on stdio."""
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
