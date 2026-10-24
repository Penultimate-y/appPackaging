"""
outlook-readonly-mcp server

Exposes classic desktop Outlook (Windows, COM automation) to MCP clients
such as Claude Desktop — with ONLY read operations available. There is no
send, delete, move, reply, or write-to-Outlook tool anywhere in this file
or in outlook_client.py, by design. See README.md for the safety notes.
"""

from __future__ import annotations

from typing import Any

from mcp.server.fastmcp import FastMCP

from . import outlook_client as oc

mcp = FastMCP(
    "outlook-readonly",
    instructions=(
        "Read-only access to the user's local desktop Outlook mailbox and "
        "calendar via COM automation. There are no tools capable of sending, "
        "deleting, moving, or modifying anything in Outlook. When summarizing "
        "emails, prefer concise, action-oriented summaries (deadlines, asks, "
        "follow-ups) over reproducing full message text."
    ),
)


@mcp.tool()
def list_folders() -> list[dict[str, Any]]:
    """List all mail folders in the default Outlook store with item and unread counts."""
    return oc.list_folders()


@mcp.tool()
def list_emails(folder_path: str = "Inbox", limit: int = 25, unread_only: bool = False) -> list[dict[str, Any]]:
    """List recent emails (metadata only — subject/sender/date/unread flag) in a folder, newest first.

    folder_path: '/'-separated path, e.g. 'Inbox' or 'Inbox/Projects'.
    limit: max results (capped at 500).
    unread_only: if True, only return unread messages.
    """
    return oc.list_emails(folder_path=folder_path, limit=limit, unread_only=unread_only)


@mcp.tool()
def search_emails(query: str, folder_path: str = "Inbox", limit: int = 25, search_body: bool = True) -> list[dict[str, Any]]:
    """Search a folder for emails whose subject (and optionally body) contains the query text."""
    return oc.search_emails(query=query, folder_path=folder_path, limit=limit, search_body=search_body)


@mcp.tool()
def get_email(entry_id: str, include_body: bool = True) -> dict[str, Any]:
    """Get full details of one email (sender, recipients, date, body, attachment list) by EntryID.

    Reading a message here does NOT mark it as read in Outlook.
    """
    return oc.get_email(entry_id=entry_id, include_body=include_body)


@mcp.tool()
def list_attachments(entry_id: str) -> list[dict[str, Any]]:
    """List attachment filenames and sizes for a given email."""
    return oc.list_attachments(entry_id=entry_id)


@mcp.tool()
def save_attachment(entry_id: str, attachment_index: int, save_dir: str) -> dict[str, Any]:
    """Save one attachment to a local folder on this computer.

    This writes a file to your local disk only — it does not change
    anything inside Outlook itself.
    """
    return oc.save_attachment(entry_id=entry_id, attachment_index=attachment_index, save_dir=save_dir)


@mcp.tool()
def get_unread_summary(folder_path: str = "Inbox") -> dict[str, Any]:
    """Get the unread count and newest unread subjects for a folder — good for a quick daily check-in."""
    return oc.get_unread_summary(folder_path=folder_path)


@mcp.tool()
def list_calendar_events(days_ahead: int = 7, days_back: int = 0) -> list[dict[str, Any]]:
    """List calendar events (including recurring instances) within a date window around today."""
    return oc.list_calendar_events(days_ahead=days_ahead, days_back=days_back)


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
