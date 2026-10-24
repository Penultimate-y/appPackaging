"""Live Microsoft Graph tests — SKIPPED by default.

These hit the real Graph API with a real signed-in account. Enable with:

    OUTLOOK_MCP_LIVE_TESTS=1 pytest tests/test_graph_live.py -v

You must have completed device-code sign-in at least once (run the server
and call auth_status) so a token cache exists.
"""

from __future__ import annotations

import os

import pytest

pytestmark = pytest.mark.skipif(
    not os.environ.get("OUTLOOK_MCP_LIVE_TESTS"),
    reason="live Graph tests disabled (set OUTLOOK_MCP_LIVE_TESTS=1 to enable)",
)


def test_live_token_and_message_listing():
    from outlook_triage_mcp.auth import AuthManager
    from outlook_triage_mcp.config import Settings
    from outlook_triage_mcp.graph import GraphClient

    auth = AuthManager(Settings.from_env())
    graph = GraphClient(auth.get_token)
    response = graph.get(
        "me/mailFolders/inbox/messages",
        params={"$top": 1, "$select": "id,subject"},
    )
    assert "value" in response


def test_live_rules_listing():
    from outlook_triage_mcp import rules
    from outlook_triage_mcp.auth import AuthManager
    from outlook_triage_mcp.config import Settings
    from outlook_triage_mcp.graph import GraphClient

    auth = AuthManager(Settings.from_env())
    graph = GraphClient(auth.get_token)
    assert isinstance(rules.list_rules(graph), list)
