"""Deterministic, heuristic e-mail classification. No LLM calls at runtime.

Extracted from a production daily-briefing robot and genericized: categories
and keyword lists are configurable via environment variables or a JSON file,
so the same rules engine adapts to any inbox.

Categories:

- ``urgent``        — explicit urgency signals; answer first.
- ``action_needed`` — a person is waiting on you (priority sender or an
                      explicit request keyword).
- ``fyi``           — informational; read when convenient (the default).
- ``newsletter``    — automated senders, bulk mail, notifications.

Rules of note (both proven in production):

1. Noise is filtered first — an automated sender never becomes "urgent".
2. Messages already read are never urgent/action_needed: if you opened it,
   you have already decided what to do; it is demoted to ``fyi`` so the
   briefing only surfaces genuinely pending items.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from typing import Any

URGENT = "urgent"
ACTION_NEEDED = "action_needed"
FYI = "fyi"
NEWSLETTER = "newsletter"

CATEGORIES = [URGENT, ACTION_NEEDED, FYI, NEWSLETTER]

DEFAULT_URGENT_KEYWORDS = [
    "urgent",
    "asap",
    "immediately",
    "action required",
    "by eod",
    "by end of day",
    "critical",
    "emergency",
    "deadline today",
    "overdue",
]

DEFAULT_ACTION_KEYWORDS = [
    "please review",
    "please approve",
    "please confirm",
    "please validate",
    "approval needed",
    "action needed",
    "need your",
    "waiting for your",
    "could you",
    "can you",
    "sign off",
    "feedback requested",
    "respond by",
    "your input",
]

DEFAULT_NEWSLETTER_SENDER_PATTERNS = [
    "no-reply@",
    "noreply@",
    "donotreply@",
    "do-not-reply@",
    "newsletter@",
    "marketing@",
    "notifications@",
    "notification@",
    "mailer-daemon@",
    "digest@",
]

DEFAULT_NEWSLETTER_KEYWORDS = [
    "unsubscribe",
    "view this email in your browser",
    "weekly digest",
    "monthly digest",
]


def _env_list(name: str) -> list[str] | None:
    raw = os.environ.get(name)
    if raw is None:
        return None
    items = [part.strip().lower() for part in raw.split(",") if part.strip()]
    return items or None


@dataclass
class ClassifierConfig:
    """Keyword lists and priority senders driving classification."""

    urgent_keywords: list[str] = field(default_factory=lambda: list(DEFAULT_URGENT_KEYWORDS))
    action_keywords: list[str] = field(default_factory=lambda: list(DEFAULT_ACTION_KEYWORDS))
    newsletter_sender_patterns: list[str] = field(
        default_factory=lambda: list(DEFAULT_NEWSLETTER_SENDER_PATTERNS)
    )
    newsletter_keywords: list[str] = field(
        default_factory=lambda: list(DEFAULT_NEWSLETTER_KEYWORDS)
    )
    vip_senders: list[str] = field(default_factory=list)
    user_email: str = ""

    @classmethod
    def from_env(cls) -> "ClassifierConfig":
        """Build config from defaults, an optional JSON file, then env overrides.

        JSON file (``OUTLOOK_MCP_CLASSIFY_FILE``) may define any of:
        ``urgent_keywords``, ``action_keywords``, ``newsletter_sender_patterns``,
        ``newsletter_keywords``, ``vip_senders``.

        Env overrides (comma-separated): ``OUTLOOK_MCP_URGENT_KEYWORDS``,
        ``OUTLOOK_MCP_ACTION_KEYWORDS``, ``OUTLOOK_MCP_NEWSLETTER_SENDERS``,
        ``OUTLOOK_MCP_NEWSLETTER_KEYWORDS``, ``OUTLOOK_MCP_VIP_SENDERS``.
        """
        config = cls()

        path = os.environ.get("OUTLOOK_MCP_CLASSIFY_FILE")
        if path and os.path.exists(path):
            with open(path, encoding="utf-8") as handle:
                data = json.load(handle)
            for key in (
                "urgent_keywords",
                "action_keywords",
                "newsletter_sender_patterns",
                "newsletter_keywords",
                "vip_senders",
            ):
                if isinstance(data.get(key), list):
                    setattr(config, key, [str(v).lower() for v in data[key]])

        for env_name, attr in [
            ("OUTLOOK_MCP_URGENT_KEYWORDS", "urgent_keywords"),
            ("OUTLOOK_MCP_ACTION_KEYWORDS", "action_keywords"),
            ("OUTLOOK_MCP_NEWSLETTER_SENDERS", "newsletter_sender_patterns"),
            ("OUTLOOK_MCP_NEWSLETTER_KEYWORDS", "newsletter_keywords"),
            ("OUTLOOK_MCP_VIP_SENDERS", "vip_senders"),
        ]:
            override = _env_list(env_name)
            if override is not None:
                setattr(config, attr, override)

        config.user_email = os.environ.get("OUTLOOK_MCP_USER_EMAIL", "").strip().lower()
        return config


def classify_message(
    message: dict[str, Any], config: ClassifierConfig
) -> tuple[str, str]:
    """Classify one Graph message resource. Returns ``(category, reason)``.

    Pure function of (message, config) — deterministic and unit-testable
    against fixture JSON, no network and no LLM involved.
    """
    subject = (message.get("subject") or "").lower()
    preview = (message.get("bodyPreview") or "").lower()
    sender = (
        (message.get("from") or {}).get("emailAddress", {}).get("address") or ""
    ).lower()
    is_read = bool(message.get("isRead"))
    text = f"{subject} {preview}"

    def demote_if_read(category: str, reason: str) -> tuple[str, str]:
        if category in (URGENT, ACTION_NEEDED) and is_read:
            return FYI, f"{reason} (already read — assumed handled)"
        return category, reason

    # 0. Message sent by the mailbox owner (a reply bouncing back, a
    #    self-addressed note) is never a pending action.
    if config.user_email and sender == config.user_email:
        return FYI, "Sent by the mailbox owner"

    # 1. Automated/bulk senders first — noise never escalates.
    for pattern in config.newsletter_sender_patterns:
        if pattern in sender:
            return NEWSLETTER, f"Automated sender pattern: '{pattern}'"

    for keyword in config.newsletter_keywords:
        if keyword in preview:
            return NEWSLETTER, f"Bulk-mail keyword in body: '{keyword}'"

    # 2. Explicit urgency signals.
    for keyword in config.urgent_keywords:
        if keyword in text:
            return demote_if_read(URGENT, f"Urgency keyword: '{keyword}'")

    # 3. Priority senders get action_needed by default.
    if sender in (s.lower() for s in config.vip_senders):
        return demote_if_read(ACTION_NEEDED, f"Priority sender: {sender}")

    # 4. Explicit request keywords.
    for keyword in config.action_keywords:
        if keyword in text:
            return demote_if_read(ACTION_NEEDED, f"Action keyword: '{keyword}'")

    # 5. Default: informational.
    return FYI, "No clear action signal"
