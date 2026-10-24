"""Shared fixtures: fixture JSON loading and a fake Graph client.

Everything here runs offline — no live Microsoft Graph, no login.
"""

from __future__ import annotations

import json
import uuid
from pathlib import Path
from typing import Any

import pytest

FIXTURES = Path(__file__).parent / "fixtures"


def load_fixture(name: str) -> Any:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


@pytest.fixture
def messages() -> list[dict[str, Any]]:
    return load_fixture("messages.json")


class FakeGraph:
    """In-memory stand-in for GraphClient, seeded with fixture JSON.

    Records every call so tests can assert exactly which writes happened —
    the heart of the idempotency tests.
    """

    def __init__(self, folders: list | None = None, rules: list | None = None):
        self.folders = list(folders or [])
        self.rules = list(rules or [])
        self.calls: list[tuple[str, str]] = []

    # -- GraphClient-compatible surface -----------------------------------

    def get(self, path: str, params: dict | None = None,
            headers: dict | None = None) -> dict:
        self.calls.append(("GET", path))
        if path == "me/mailFolders":
            return {"value": self.folders}
        if path == "me/mailFolders/inbox/messageRules":
            return {"value": self.rules}
        raise AssertionError(f"FakeGraph: unexpected GET {path}")

    def post(self, path: str, json: dict | None = None) -> dict:
        self.calls.append(("POST", path))
        if path == "me/mailFolders":
            folder = {"id": f"folder-{uuid.uuid4().hex[:8]}", **(json or {})}
            self.folders.append(folder)
            return folder
        if path == "me/mailFolders/inbox/messageRules":
            rule = {"id": f"rule-{uuid.uuid4().hex[:8]}", **(json or {})}
            self.rules.append(rule)
            return rule
        raise AssertionError(f"FakeGraph: unexpected POST {path}")

    def patch(self, path: str, json: dict | None = None) -> dict:
        self.calls.append(("PATCH", path))
        prefix = "me/mailFolders/inbox/messageRules/"
        if path.startswith(prefix):
            rule_id = path[len(prefix):]
            for rule in self.rules:
                if rule["id"] == rule_id:
                    rule.update(json or {})
                    return rule
        raise AssertionError(f"FakeGraph: unexpected PATCH {path}")

    # -- assertion helpers --------------------------------------------------

    def write_calls(self) -> list[tuple[str, str]]:
        return [c for c in self.calls if c[0] in ("POST", "PATCH")]


@pytest.fixture
def fake_graph() -> FakeGraph:
    return FakeGraph(
        folders=load_fixture("folders_existing.json"),
        rules=load_fixture("rules_existing.json"),
    )
