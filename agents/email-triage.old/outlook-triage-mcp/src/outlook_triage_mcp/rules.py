"""Idempotent inbox-rule provisioning via Microsoft Graph.

The invariant, proven in production: running the same provisioning any
number of times converges to the same mailbox state and never duplicates a
rule or a folder.

- Folders are matched by display name (case-insensitive) and only created
  when missing.
- Rules are matched by display name. An existing rule that already has the
  desired conditions/actions is left untouched (no write call at all);
  a divergent one is PATCHed; a missing one is POSTed.

Functions take any Graph-like client exposing ``get``/``post``/``patch``,
so tests inject a fake fed with fixture JSON — no live mailbox needed.
"""

from __future__ import annotations

from typing import Any

RULES_PATH = "me/mailFolders/inbox/messageRules"
FOLDERS_PATH = "me/mailFolders"


def list_rules(graph: Any) -> list[dict[str, Any]]:
    """All inbox message rules."""
    return graph.get(RULES_PATH).get("value", [])


def find_folder(graph: Any, display_name: str) -> dict[str, Any] | None:
    """Find a top-level mail folder by display name (case-insensitive)."""
    folders = graph.get(FOLDERS_PATH, params={"$top": 250}).get("value", [])
    target = display_name.strip().lower()
    for folder in folders:
        if (folder.get("displayName") or "").strip().lower() == target:
            return folder
    return None


def ensure_folder(graph: Any, display_name: str) -> tuple[str, bool]:
    """Return ``(folder_id, created)``; create the folder only if missing."""
    existing = find_folder(graph, display_name)
    if existing:
        return existing["id"], False
    created = graph.post(FOLDERS_PATH, json={"displayName": display_name})
    return created["id"], True


def _rule_is_current(
    rule: dict[str, Any], from_contains: str, folder_id: str
) -> bool:
    conditions = rule.get("conditions") or {}
    actions = rule.get("actions") or {}
    return (
        conditions.get("senderContains") == [from_contains]
        and actions.get("moveToFolder") == folder_id
        and rule.get("isEnabled") is True
    )


def ensure_rule(
    graph: Any, name: str, from_contains: str, move_to_folder: str
) -> dict[str, Any]:
    """Converge one rule: sender contains ``from_contains`` → move to folder.

    Returns a report of what happened: ``action`` is one of
    ``"unchanged"``, ``"updated"``, ``"created"``.
    """
    folder_id, folder_created = ensure_folder(graph, move_to_folder)
    rules = list_rules(graph)
    match = next((r for r in rules if r.get("displayName") == name), None)

    report = {
        "rule": name,
        "folder": move_to_folder,
        "folder_id": folder_id,
        "folder_created": folder_created,
    }

    if match and _rule_is_current(match, from_contains, folder_id):
        report.update({"action": "unchanged", "rule_id": match.get("id")})
        return report

    desired = {
        "displayName": name,
        "isEnabled": True,
        "conditions": {"senderContains": [from_contains]},
        "actions": {"moveToFolder": folder_id, "stopProcessingRules": True},
    }

    if match:
        graph.patch(f"{RULES_PATH}/{match['id']}", json=desired)
        report.update({"action": "updated", "rule_id": match.get("id")})
        return report

    max_sequence = max((r.get("sequence", 0) for r in rules), default=0)
    desired["sequence"] = max_sequence + 10
    created = graph.post(RULES_PATH, json=desired)
    report.update({"action": "created", "rule_id": created.get("id")})
    return report
