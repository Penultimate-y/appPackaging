"""
outlook_client.py

Thin wrapper around the Outlook COM (MAPI) object model via pywin32.

SAFETY GUARANTEE
-----------------
This module never calls any Outlook method that mutates mailbox state:
no .Send(), .Delete(), .Move(), .Save() on Outlook items, no UnRead
assignment, no folder creation. Every function here either reads
properties off existing COM objects or (for save_attachment) writes
bytes to a file on the LOCAL DISK — which does not touch Outlook data
at all.

If you are auditing this file for safety, grep for these tokens and
confirm none of them appear outside of comments/docstrings:
    .Send(  .Delete(  .Move(  .Save(  .UnRead =  .Display(
"""

from __future__ import annotations

import datetime as _dt
from typing import Any

# Outlook constants (from the Outlook Object Model). Hardcoded so this
# module doesn't depend on win32com's makepy-generated constants cache.
OL_FOLDER_INBOX = 6
OL_FOLDER_CALENDAR = 9
OL_MAIL_ITEM_CLASS = 43  # MailItem.Class == olMail

_MAX_ITEMS_HARD_CAP = 500  # safety valve so a bad query can't hang / dump everything


class OutlookConnectionError(RuntimeError):
    """Raised when Outlook isn't running or COM can't attach to it."""


def _get_namespace():
    try:
        import win32com.client  # imported lazily: only exists on Windows
    except ImportError as exc:  # pragma: no cover - non-Windows dev environment
        raise OutlookConnectionError(
            "pywin32 is not installed or this isn't Windows. "
            "This server only works on Windows with desktop Outlook installed."
        ) from exc

    try:
        outlook = win32com.client.Dispatch("Outlook.Application")
        return outlook.GetNamespace("MAPI")
    except Exception as exc:  # noqa: BLE001
        raise OutlookConnectionError(
            "Could not attach to Outlook via COM. Make sure classic desktop "
            "Outlook (OUTLOOK.EXE) is installed and can be launched. "
            "Note: the 'new Outlook' (olk.exe) does not support COM automation."
        ) from exc


def _resolve_folder(ns, folder_path: str | None):
    """Resolve a folder by a '/'-separated path, e.g. 'Inbox/Projects/2026'.

    None or '' resolves to the default Inbox.
    """
    if not folder_path or folder_path.strip().lower() == "inbox":
        return ns.GetDefaultFolder(OL_FOLDER_INBOX)

    parts = [p for p in folder_path.split("/") if p]
    # Walk from the default store's top-level folder list.
    root = ns.GetDefaultFolder(OL_FOLDER_INBOX).Parent  # the mailbox root
    current = root
    for part in parts:
        found = None
        for f in current.Folders:
            if f.Name.lower() == part.lower():
                found = f
                break
        if found is None:
            raise ValueError(f"Folder '{folder_path}' not found (missing segment '{part}').")
        current = found
    return current


def _folder_path(folder) -> str:
    """Best-effort human-readable path for a folder (for list_folders output)."""
    try:
        # FolderPath looks like "\\\\user@example.com\\Inbox\\Sub"
        raw = folder.FolderPath
        segments = [s for s in raw.split("\\") if s]
        return "/".join(segments[1:]) if len(segments) > 1 else segments[0]
    except Exception:  # noqa: BLE001
        return folder.Name


def _mail_summary(item) -> dict[str, Any]:
    return {
        "entry_id": item.EntryID,
        "subject": getattr(item, "Subject", ""),
        "sender_name": getattr(item, "SenderName", ""),
        "sender_email": _safe_sender_email(item),
        "received_time": _iso(getattr(item, "ReceivedTime", None)),
        "unread": bool(getattr(item, "UnRead", False)),
        "has_attachments": bool(getattr(item, "Attachments", None) and item.Attachments.Count > 0),
        "importance": _importance_label(getattr(item, "Importance", 1)),
        "categories": getattr(item, "Categories", "") or "",
    }


def _safe_sender_email(item) -> str:
    try:
        return item.SenderEmailAddress or ""
    except Exception:  # noqa: BLE001
        return ""


def _importance_label(value: int) -> str:
    return {0: "low", 1: "normal", 2: "high"}.get(value, "normal")


def _iso(value) -> str | None:
    if value is None:
        return None
    try:
        return value.isoformat()
    except Exception:  # noqa: BLE001
        return str(value)


# --------------------------------------------------------------------------
# Public read-only operations
# --------------------------------------------------------------------------


def list_folders() -> list[dict[str, Any]]:
    """List all mail folders in the default store, with item/unread counts."""
    ns = _get_namespace()
    root = ns.GetDefaultFolder(OL_FOLDER_INBOX).Parent

    results: list[dict[str, Any]] = []

    def walk(folder, depth: int) -> None:
        try:
            results.append(
                {
                    "path": _folder_path(folder),
                    "name": folder.Name,
                    "depth": depth,
                    "item_count": folder.Items.Count,
                    "unread_count": getattr(folder, "UnReadItemCount", 0),
                }
            )
        except Exception:  # noqa: BLE001
            pass
        for sub in folder.Folders:
            walk(sub, depth + 1)

    walk(root, 0)
    return results


def list_emails(
    folder_path: str = "Inbox",
    limit: int = 25,
    unread_only: bool = False,
) -> list[dict[str, Any]]:
    """List recent emails (metadata only, no body) in a folder, newest first."""
    limit = max(1, min(limit, _MAX_ITEMS_HARD_CAP))
    ns = _get_namespace()
    folder = _resolve_folder(ns, folder_path)

    items = folder.Items
    items.Sort("[ReceivedTime]", True)  # descending

    results: list[dict[str, Any]] = []
    for item in items:
        if len(results) >= limit:
            break
        try:
            if item.Class != OL_MAIL_ITEM_CLASS:
                continue
            if unread_only and not item.UnRead:
                continue
            results.append(_mail_summary(item))
        except Exception:  # noqa: BLE001
            continue
    return results


def search_emails(
    query: str,
    folder_path: str = "Inbox",
    limit: int = 25,
    search_body: bool = True,
) -> list[dict[str, Any]]:
    """Search a folder's subject (and optionally body) for a text query."""
    limit = max(1, min(limit, _MAX_ITEMS_HARD_CAP))
    ns = _get_namespace()
    folder = _resolve_folder(ns, folder_path)

    escaped = query.replace('"', '""')
    subject_filter = f'@SQL="urn:schemas:httpmail:subject" LIKE \'%{escaped}%\''
    body_filter = f'@SQL="urn:schemas:httpmail:textdescription" LIKE \'%{escaped}%\''

    items = folder.Items
    items.Sort("[ReceivedTime]", True)

    seen_ids: set[str] = set()
    results: list[dict[str, Any]] = []

    for dasl_filter in ([subject_filter, body_filter] if search_body else [subject_filter]):
        try:
            restricted = items.Restrict(dasl_filter)
        except Exception:  # noqa: BLE001
            continue
        for item in restricted:
            if len(results) >= limit:
                break
            try:
                if item.Class != OL_MAIL_ITEM_CLASS or item.EntryID in seen_ids:
                    continue
                seen_ids.add(item.EntryID)
                results.append(_mail_summary(item))
            except Exception:  # noqa: BLE001
                continue
        if len(results) >= limit:
            break

    return results


def get_email(entry_id: str, include_body: bool = True) -> dict[str, Any]:
    """Fetch full details of a single email by its EntryID. Read-only: does
    not mark the message as read (that only happens via .Display(), which
    this server never calls)."""
    ns = _get_namespace()
    item = ns.GetItemFromID(entry_id)

    data = _mail_summary(item)
    data["to"] = getattr(item, "To", "")
    data["cc"] = getattr(item, "CC", "")
    data["sent_on"] = _iso(getattr(item, "SentOn", None))
    if include_body:
        data["body"] = getattr(item, "Body", "")
    attachments = []
    try:
        for att in item.Attachments:
            attachments.append({"index": att.Index, "filename": att.FileName, "size_bytes": att.Size})
    except Exception:  # noqa: BLE001
        pass
    data["attachments"] = attachments
    return data


def list_attachments(entry_id: str) -> list[dict[str, Any]]:
    """List attachment metadata (filename, size) for a given email."""
    ns = _get_namespace()
    item = ns.GetItemFromID(entry_id)
    results = []
    for att in item.Attachments:
        results.append({"index": att.Index, "filename": att.FileName, "size_bytes": att.Size})
    return results


def save_attachment(entry_id: str, attachment_index: int, save_dir: str) -> dict[str, Any]:
    """Save one attachment to a LOCAL file. This writes to disk only — it
    does not modify anything inside Outlook (no .Save() on the mail item,
    no state change to the mailbox)."""
    import os

    ns = _get_namespace()
    item = ns.GetItemFromID(entry_id)
    att = item.Attachments.Item(attachment_index)

    os.makedirs(save_dir, exist_ok=True)
    dest_path = os.path.join(save_dir, att.FileName)
    att.SaveAsFile(dest_path)  # writes local file; not an Outlook mutation
    return {"saved_path": dest_path, "size_bytes": att.Size}


def get_unread_summary(folder_path: str = "Inbox") -> dict[str, Any]:
    """Quick unread count + the newest few unread subjects for a folder."""
    ns = _get_namespace()
    folder = _resolve_folder(ns, folder_path)
    unread_count = getattr(folder, "UnReadItemCount", 0)

    items = folder.Items
    items.Sort("[ReceivedTime]", True)
    preview = []
    for item in items:
        if len(preview) >= 10:
            break
        try:
            if item.Class == OL_MAIL_ITEM_CLASS and item.UnRead:
                preview.append(_mail_summary(item))
        except Exception:  # noqa: BLE001
            continue

    return {"folder": folder_path, "unread_count": unread_count, "newest_unread": preview}


def list_calendar_events(days_ahead: int = 7, days_back: int = 0) -> list[dict[str, Any]]:
    """List calendar events (including recurring instances) in a date window."""
    ns = _get_namespace()
    calendar = ns.GetDefaultFolder(OL_FOLDER_CALENDAR)

    items = calendar.Items
    items.IncludeRecurrences = True
    items.Sort("[Start]")

    start = _dt.datetime.now() - _dt.timedelta(days=max(0, days_back))
    end = _dt.datetime.now() + _dt.timedelta(days=max(0, days_ahead))
    restriction = (
        "[Start] >= '" + start.strftime("%m/%d/%Y %H:%M %p") + "' AND "
        "[Start] <= '" + end.strftime("%m/%d/%Y %H:%M %p") + "'"
    )

    results: list[dict[str, Any]] = []
    try:
        restricted = items.Restrict(restriction)
    except Exception:  # noqa: BLE001
        restricted = items

    for item in restricted:
        if len(results) >= _MAX_ITEMS_HARD_CAP:
            break
        try:
            results.append(
                {
                    "subject": getattr(item, "Subject", ""),
                    "start": _iso(getattr(item, "Start", None)),
                    "end": _iso(getattr(item, "End", None)),
                    "location": getattr(item, "Location", ""),
                    "organizer": getattr(item, "Organizer", ""),
                    "is_recurring": bool(getattr(item, "IsRecurring", False)),
                    "response_status": getattr(item, "ResponseStatus", None),
                    "entry_id": getattr(item, "EntryID", ""),
                }
            )
        except Exception:  # noqa: BLE001
            continue
    return results
