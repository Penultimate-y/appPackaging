# CLAUDE.md — outlook-readonly-mcp

Context for Claude Code when working in this repository. Read this before making changes.

## What this project is

A local MCP (Model Context Protocol) server that gives Claude read-only
access to classic desktop Outlook on Windows, via COM automation
(`pywin32`). Built so the user (Rohit) can ask Claude about emails,
deadlines, and follow-ups without granting any write access to his mailbox.

No Azure/Entra app registration, no OAuth, no cloud calls. The server
attaches to whatever Outlook session is already running and signed in on
the local machine.

## The one hard rule of this codebase

**No tool may call `.Send()`, `.Delete()`, `.Move()`, `.Save()` on any
Outlook item, or set `.UnRead =`, or call `.Display()`.** This is not a
config flag — the code to do these things simply doesn't exist in this
repo, by design.

Before merging any change, audit with:
```powershell
Select-String -Path "src\outlook_readonly_mcp\*.py" -Pattern "\.Send\(|\.Delete\(|\.Move\(|\.Save\(|UnRead\s*=|\.Display\("
```
Every match must be inside a comment or docstring, never a live call.

The only exception: `save_attachment` writes bytes to a file on the local
disk. That's fine — it never modifies anything inside Outlook itself.

## Architecture

```
Claude (Desktop app / Code tab) → this MCP server (local Python, stdio)
  → win32com (pywin32) → OUTLOOK.EXE (already running) → mailbox
```

- `src/outlook_readonly_mcp/outlook_client.py` — all COM logic, one
  function per capability, each reads properties off COM objects and
  returns a plain dict.
- `src/outlook_readonly_mcp/server.py` — MCP tool registrations
  (`FastMCP`). Currently exposes exactly 8 tools: `list_folders`,
  `list_emails`, `search_emails`, `get_email`, `list_attachments`,
  `save_attachment`, `get_unread_summary`, `list_calendar_events`.

## Environment constraints

- **Windows + classic desktop Outlook only.** The "new Outlook" (`olk.exe`)
  has no COM surface and will not work.
- Requires Outlook and the MCP client (Claude Desktop / Code tab) both
  running at the same time — there is no background/always-on mode.
- Python 3.10+, dependencies limited to `mcp[cli]` and `pywin32`
  (see `pyproject.toml` — flag any new dependency for review).

## Known setup gotcha (Windows + PowerShell)

`claude mcp add ... -- <command> <args>` silently mis-parses arguments
after `--` when run from PowerShell (confirmed upstream Claude Code CLI
bug on Windows). Workarounds that work:
- Edit `%USERPROFILE%\.claude.json` directly and add the server under the
  top-level `mcpServers` key, or
- Run the `claude mcp add` command from `cmd.exe` instead of PowerShell.

## Current status

- Server built, reviewed line-by-line by the user, and confirmed working
  locally via the Code tab (`/mcp` shows it connected).
- About to be pushed to a public GitHub repo (MIT licensed) for the
  community — see README.md for the intended install/audit instructions
  once published.
- Before publishing: update the placeholder `authors` field in
  `pyproject.toml` and the clone URL in `README.md` to the real repo URL.

## Guidance for future changes

- Any new tool must be read-only per the hard rule above — no exceptions,
  even if the user asks for a "just this once" write capability.
- Keep the tool count and behavior documented in this file in sync with
  `server.py` — update the tool list above if tools are added or removed.
- If extending beyond mail/calendar (e.g. contacts, tasks), follow the
  same pattern: COM property reads only, returned as plain dicts.
