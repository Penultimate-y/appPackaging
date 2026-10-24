"""Daily-briefing digest: classify a batch of messages and render Markdown.

Pure rendering — no network. The caller fetches messages via Graph; this
module classifies them with the deterministic heuristics and groups them
into a digest ordered by attention priority.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from .classify import ACTION_NEEDED, FYI, NEWSLETTER, URGENT, ClassifierConfig, classify_message

SECTION_TITLES = {
    URGENT: "Urgent",
    ACTION_NEEDED: "Action needed",
    FYI: "FYI",
    NEWSLETTER: "Newsletters & automated",
}

SECTION_ORDER = [URGENT, ACTION_NEEDED, FYI, NEWSLETTER]


def _sender_line(message: dict[str, Any]) -> str:
    email_address = (message.get("from") or {}).get("emailAddress", {})
    name = email_address.get("name") or ""
    address = email_address.get("address") or ""
    if name and address:
        return f"{name} <{address}>"
    return name or address or "(unknown sender)"


def _clean_preview(message: dict[str, Any], limit: int = 180) -> str:
    """First relevant lines of the preview, quote history stripped."""
    preview = (message.get("bodyPreview") or "").strip()
    if not preview:
        return ""
    quote_markers = ("________", "From:", "Sent:", "To:", "Cc:", "Subject:", ">")
    lines: list[str] = []
    for raw_line in preview.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith(quote_markers):
            break  # reached quoted history
        lines.append(line)
    text = " ".join(lines)
    if len(text) > limit:
        text = text[: limit - 1].rsplit(" ", 1)[0] + "…"
    return text


def classify_batch(
    messages: list[dict[str, Any]], config: ClassifierConfig
) -> dict[str, list[tuple[dict[str, Any], str]]]:
    """Group messages by category. Returns {category: [(message, reason), ...]}."""
    grouped: dict[str, list[tuple[dict[str, Any], str]]] = {c: [] for c in SECTION_ORDER}
    for message in messages:
        category, reason = classify_message(message, config)
        grouped[category].append((message, reason))
    return grouped


def build_briefing(
    messages: list[dict[str, Any]],
    config: ClassifierConfig,
    hours: int = 24,
    now: datetime | None = None,
) -> str:
    """Render the Markdown digest for a window of messages."""
    now = now or datetime.now(timezone.utc)
    grouped = classify_batch(messages, config)

    lines: list[str] = []
    lines.append(f"# Inbox briefing — {now:%Y-%m-%d %H:%M} UTC")
    lines.append("")
    lines.append(f"Window: last {hours}h · {len(messages)} messages")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    for category in SECTION_ORDER:
        lines.append(f"- **{SECTION_TITLES[category]}**: {len(grouped[category])}")
    lines.append("")

    for category in SECTION_ORDER:
        entries = grouped[category]
        lines.append(f"## {SECTION_TITLES[category]} ({len(entries)})")
        lines.append("")
        if not entries:
            lines.append("_None._")
            lines.append("")
            continue

        if category in (URGENT, ACTION_NEEDED):
            for message, reason in entries:
                subject = message.get("subject") or "(no subject)"
                lines.append(f"### {subject}")
                lines.append(f"- **From:** {_sender_line(message)}")
                lines.append(f"- **Received:** {message.get('receivedDateTime', '')}")
                lines.append(f"- **Why:** {reason}")
                preview = _clean_preview(message)
                if preview:
                    lines.append(f"- **Preview:** {preview}")
                lines.append(f"- **Id:** `{message.get('id', '')}`")
                lines.append("")
        else:
            for message, reason in entries:
                subject = message.get("subject") or "(no subject)"
                lines.append(f"- **{subject}** — {_sender_line(message)}")
            lines.append("")

    lines.append("---")
    lines.append(
        "_Read-only digest: nothing was sent, moved, deleted, or marked as read._"
    )
    return "\n".join(lines)
