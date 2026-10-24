"""Tests for the daily-briefing Markdown digest (pure rendering, offline)."""

from __future__ import annotations

from datetime import datetime, timezone

from outlook_triage_mcp.briefing import build_briefing, classify_batch
from outlook_triage_mcp.classify import ACTION_NEEDED, NEWSLETTER, URGENT, ClassifierConfig

CONFIG = ClassifierConfig(vip_senders=["vip@example.com"], user_email="user@example.com")
FIXED_NOW = datetime(2026, 7, 6, 12, 0, tzinfo=timezone.utc)


def test_batch_counts_match_fixture_expectations(messages):
    grouped = classify_batch(messages, CONFIG)
    assert len(grouped[URGENT]) == 1
    assert len(grouped[ACTION_NEEDED]) == 2
    assert len(grouped[NEWSLETTER]) == 3
    total = sum(len(v) for v in grouped.values())
    assert total == len(messages)


def test_briefing_markdown_structure(messages):
    briefing = build_briefing(messages, CONFIG, hours=24, now=FIXED_NOW)
    assert briefing.startswith("# Inbox briefing — 2026-07-06 12:00 UTC")
    for section in ("## Urgent (1)", "## Action needed (2)",
                    "## FYI (4)", "## Newsletters & automated (3)"):
        assert section in briefing
    # Urgent entries carry the message id so follow-up get_message calls work.
    assert "`msg-urgent-unread`" in briefing
    # Read-only promise is stated.
    assert "nothing was sent, moved, deleted" in briefing.lower()


def test_briefing_is_deterministic(messages):
    a = build_briefing(messages, CONFIG, hours=24, now=FIXED_NOW)
    b = build_briefing(messages, CONFIG, hours=24, now=FIXED_NOW)
    assert a == b


def test_briefing_with_no_messages():
    briefing = build_briefing([], CONFIG, hours=12, now=FIXED_NOW)
    assert "0 messages" in briefing
    assert "_None._" in briefing
