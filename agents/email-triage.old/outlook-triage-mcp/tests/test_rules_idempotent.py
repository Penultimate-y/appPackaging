"""Idempotency tests for inbox-rule provisioning, against a fake Graph.

The invariant: re-running ensure_rule any number of times converges and
never duplicates a rule or folder — and an already-correct rule triggers
zero write calls.
"""

from __future__ import annotations

from outlook_triage_mcp import rules

RULES_PATH = "me/mailFolders/inbox/messageRules"


def test_creates_rule_and_folder_when_absent(fake_graph):
    report = rules.ensure_rule(
        fake_graph, "Move recruiter mail", "recruiting@", "Recruiters"
    )
    assert report["action"] == "created"
    assert report["folder_created"] is True
    posts = [c for c in fake_graph.write_calls() if c[0] == "POST"]
    assert ("POST", "me/mailFolders") in posts
    assert ("POST", RULES_PATH) in posts

    created = next(
        r for r in fake_graph.rules if r["displayName"] == "Move recruiter mail"
    )
    assert created["conditions"]["senderContains"] == ["recruiting@"]
    assert created["actions"]["stopProcessingRules"] is True
    # Sequence goes after the existing rules (10, 20).
    assert created["sequence"] == 30


def test_existing_correct_rule_triggers_zero_writes(fake_graph):
    report = rules.ensure_rule(
        fake_graph, "Move build notifications", "builds@ci.example.com",
        "CI Notifications",
    )
    assert report["action"] == "unchanged"
    assert report["folder_created"] is False
    assert fake_graph.write_calls() == []


def test_divergent_rule_is_patched_not_duplicated(fake_graph):
    # rule-2 currently points at folder-old-target; converge to Newsletters.
    report = rules.ensure_rule(
        fake_graph, "Move newsletters", "newsletter@", "Newsletters"
    )
    assert report["action"] == "updated"
    assert fake_graph.write_calls() == [("PATCH", f"{RULES_PATH}/rule-2")]
    assert len([r for r in fake_graph.rules if r["displayName"] == "Move newsletters"]) == 1
    patched = next(r for r in fake_graph.rules if r["id"] == "rule-2")
    assert patched["actions"]["moveToFolder"] == "folder-news"


def test_running_twice_converges_to_unchanged(fake_graph):
    first = rules.ensure_rule(fake_graph, "Archive vendor mail", "vendor@", "Vendors")
    assert first["action"] == "created"
    writes_after_first = len(fake_graph.write_calls())

    second = rules.ensure_rule(fake_graph, "Archive vendor mail", "vendor@", "Vendors")
    assert second["action"] == "unchanged"
    assert len(fake_graph.write_calls()) == writes_after_first  # no new writes
    assert (
        len([r for r in fake_graph.rules if r["displayName"] == "Archive vendor mail"])
        == 1
    )
    assert len([f for f in fake_graph.folders if f["displayName"] == "Vendors"]) == 1


def test_folder_match_is_case_insensitive(fake_graph):
    folder_id, created = rules.ensure_folder(fake_graph, "newsletters")
    assert created is False
    assert folder_id == "folder-news"
