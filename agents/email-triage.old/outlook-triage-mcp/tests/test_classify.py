"""Unit tests for the deterministic classification heuristics.

Runs entirely against fixture JSON — no Graph, no login, no LLM.
"""

from __future__ import annotations

import json

import pytest

from outlook_triage_mcp.classify import (
    ACTION_NEEDED,
    FYI,
    NEWSLETTER,
    URGENT,
    ClassifierConfig,
    classify_message,
)

EXPECTED = {
    "msg-urgent-unread": URGENT,
    "msg-urgent-read": FYI,  # urgency demoted: already read
    "msg-vip": ACTION_NEEDED,
    "msg-action-keyword": ACTION_NEEDED,
    "msg-action-read": FYI,  # action demoted: already read
    "msg-newsletter-sender": NEWSLETTER,
    "msg-newsletter-keyword": NEWSLETTER,
    "msg-self": FYI,
    "msg-fyi": FYI,
    "msg-noise-urgent-bait": NEWSLETTER,  # noise filtered before urgency
}


@pytest.fixture
def config() -> ClassifierConfig:
    return ClassifierConfig(
        vip_senders=["vip@example.com"],
        user_email="user@example.com",
    )


def test_every_fixture_message_gets_expected_category(messages, config):
    for message in messages:
        category, reason = classify_message(message, config)
        assert category == EXPECTED[message["id"]], (
            f"{message['id']}: expected {EXPECTED[message['id']]}, "
            f"got {category} ({reason})"
        )
        assert reason  # every classification is explained


def test_classification_is_deterministic(messages, config):
    first = [classify_message(m, config) for m in messages]
    second = [classify_message(m, config) for m in messages]
    assert first == second


def test_read_messages_never_urgent_or_action(messages, config):
    for message in messages:
        read_copy = dict(message, isRead=True)
        category, _ = classify_message(read_copy, config)
        assert category in (FYI, NEWSLETTER)


def test_automated_sender_beats_urgency_keyword(config):
    bait = {
        "id": "x",
        "subject": "URGENT action required",
        "bodyPreview": "act now",
        "from": {"emailAddress": {"address": "noreply@example.com"}},
        "isRead": False,
    }
    category, reason = classify_message(bait, config)
    assert category == NEWSLETTER
    assert "noreply@" in reason


def test_missing_fields_do_not_crash(config):
    category, reason = classify_message({}, config)
    assert category == FYI


def test_config_from_env_overrides(monkeypatch):
    monkeypatch.setenv("OUTLOOK_MCP_URGENT_KEYWORDS", "meltdown, red alert")
    monkeypatch.setenv("OUTLOOK_MCP_VIP_SENDERS", "boss@example.com")
    monkeypatch.setenv("OUTLOOK_MCP_USER_EMAIL", "Me@Example.com")
    config = ClassifierConfig.from_env()
    assert config.urgent_keywords == ["meltdown", "red alert"]
    assert config.vip_senders == ["boss@example.com"]
    assert config.user_email == "me@example.com"

    message = {
        "subject": "Red alert in the data center",
        "bodyPreview": "",
        "from": {"emailAddress": {"address": "ops@example.com"}},
        "isRead": False,
    }
    assert classify_message(message, config)[0] == URGENT
    # Default urgency words are replaced, not appended.
    generic = dict(message, subject="urgent thing")
    assert classify_message(generic, config)[0] == FYI


def test_config_from_json_file(monkeypatch, tmp_path):
    rules_file = tmp_path / "classify.json"
    rules_file.write_text(
        json.dumps({"action_keywords": ["ping me"], "vip_senders": ["ceo@example.com"]}),
        encoding="utf-8",
    )
    monkeypatch.setenv("OUTLOOK_MCP_CLASSIFY_FILE", str(rules_file))
    config = ClassifierConfig.from_env()
    assert config.action_keywords == ["ping me"]
    assert config.vip_senders == ["ceo@example.com"]
    # Keys absent from the file keep their defaults.
    assert "urgent" in config.urgent_keywords
