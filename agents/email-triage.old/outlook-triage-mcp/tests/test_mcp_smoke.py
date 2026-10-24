"""MCP stdio smoke test: boot the real server, list tools, call one tool.

Uses the official MCP SDK client against a subprocess of this package.
No network and no Microsoft login — the token cache is pointed at an empty
temp dir, so tools must respond with a graceful auth-required payload.
"""

from __future__ import annotations

import os
import sys

import pytest
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

EXPECTED_TOOLS = {
    "auth_status",
    "search_messages",
    "get_message",
    "daily_briefing",
    "list_inbox_rules",
    "ensure_inbox_rule",
}


def server_params(tmp_path) -> StdioServerParameters:
    env = {k: v for k, v in os.environ.items() if not k.startswith("OUTLOOK_MCP_")}
    env["OUTLOOK_MCP_CACHE_DIR"] = str(tmp_path / "cache")  # guarantees: no cached token
    return StdioServerParameters(
        command=sys.executable,
        args=["-m", "outlook_triage_mcp"],
        env=env,
    )


@pytest.mark.asyncio
async def test_stdio_server_lists_all_tools(tmp_path):
    async with stdio_client(server_params(tmp_path)) as (read, write):
        async with ClientSession(read, write) as session:
            init = await session.initialize()
            assert init.serverInfo.name == "outlook-triage"

            result = await session.list_tools()
            tool_names = {tool.name for tool in result.tools}
            assert tool_names == EXPECTED_TOOLS

            # The single write tool is flagged; everything else is read-only.
            by_name = {tool.name: tool for tool in result.tools}
            for name, tool in by_name.items():
                annotations = tool.annotations
                assert annotations is not None, f"{name} missing annotations"
                expected_readonly = name != "ensure_inbox_rule"
                assert annotations.readOnlyHint is expected_readonly, name


@pytest.mark.asyncio
async def test_read_tool_reports_auth_required_without_login(tmp_path):
    async with stdio_client(server_params(tmp_path)) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            result = await session.call_tool("search_messages", {"top": 1})
            text = " ".join(
                block.text for block in result.content if hasattr(block, "text")
            )
            assert "not_authenticated" in text
            assert "auth_status" in text


@pytest.mark.asyncio
async def test_write_tool_is_disabled_by_default(tmp_path):
    async with stdio_client(server_params(tmp_path)) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            result = await session.call_tool(
                "ensure_inbox_rule",
                {"name": "x", "from_contains": "a@b", "move_to_folder": "F"},
            )
            text = " ".join(
                block.text for block in result.content if hasattr(block, "text")
            )
            assert "write_disabled" in text
            assert "OUTLOOK_MCP_ENABLE_WRITE" in text
