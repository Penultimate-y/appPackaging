# Email Triage Agent

A personal Kiro agent that reviews your Microsoft 365 inbox for the last 7 days, summarizes
what's in it, and ranks messages into priority buckets. Outputs a ranked summary in chat and
a single rolling markdown file (`output/summary.md`, overwritten each run — not a log).

Read-only. The agent and the underlying MCP server never send, delete, move, or mark your mail.

## How it works

- **MCP server**: [`outlook-triage-mcp`](https://github.com/giuseppeferretti/outlook-triage-mcp),
  installed locally in `outlook-triage-mcp/.venv`. Talks to Microsoft Graph using delegated,
  read-only scopes (`Mail.Read`, `MailboxSettings.Read`) via device-code sign-in — no password or
  client secret stored anywhere.
- **Kiro agent**: `email-triage`, defined at `../.kiro/agents/email-triage.json`. Reads
  `config/priorities.json` for rules, calls the MCP server for mail, classifies and ranks, then
  writes the chat summary + `output/summary.md`.
- **Priority config**: `config/priorities.json` — edit this anytime to change the lookback
  window, VIP senders, or bucket keywords. No code changes needed.

## One-time setup

### 1. Install (already done on this machine)

The server was installed with [`uv`](https://docs.astral.sh/uv/) into an isolated Python 3.12
virtual environment (the system Python was 3.9; this package requires 3.11+):

```powershell
cd email-triage/outlook-triage-mcp
$env:UV_NATIVE_TLS = "1"   # needed if you're behind a TLS-inspecting proxy
uv venv --python 3.12 .venv
uv pip install -e ".[attachments]" --python .venv
```

If you ever need to reinstall or update, re-run the `uv pip install` line above from this folder.

### 2. Register the MCP server

Add this to your user-level `~/.kiro/settings/mcp.json` under `"mcpServers"` (Kiro blocks
automated edits to this file, so it has to be done by hand):

```json
"outlook-triage": {
  "command": "C:\\DWX_Dev_Sync\\dwx-aj-personal-projects-repo\\email-triage\\outlook-triage-mcp\\.venv\\Scripts\\outlook-triage-mcp.exe",
  "args": [],
  "env": {
    "OUTLOOK_MCP_USER_EMAIL": "ajohnson@group1001.com",
    "OUTLOOK_MCP_CLASSIFY_FILE": "C:\\DWX_Dev_Sync\\dwx-aj-personal-projects-repo\\email-triage\\config\\priorities.json"
  },
  "disabled": false,
  "autoApprove": []
}
```

Note `OUTLOOK_MCP_ENABLE_WRITE` is intentionally **not set**. Leaving it unset keeps the server
read-only. Don't set it unless you specifically want to manage inbox rules through this agent.

After saving, reconnect the server from the MCP Server view in Kiro's feature panel (or restart
Kiro).

### 3. Sign in

The first time you (or the agent) call `auth_status`, it returns a Microsoft sign-in URL and a
short code. Open the URL in any browser, enter the code, sign in with your M365 account. The
token is cached locally at `~/.local/share/outlook-triage-mcp/` (0600 permissions, never in this
repo) and refreshes silently after that — you shouldn't need to repeat this often.

## Day-to-day use

Open this workspace in Kiro and invoke the `email-triage` agent, or just ask in chat: "run email
triage." It will:

1. Pull mail from the last `lookback_days` (default 7) via the MCP server.
2. Classify each message into a bucket from `config/priorities.json`.
3. Print a ranked summary in chat, highest priority first.
4. Overwrite `output/summary.md` with the same breakdown.

## Updating priority buckets, VIP senders, or keywords

Edit `config/priorities.json` directly, or just ask the agent, e.g.:

- "Add jane.doe@company.com as a VIP sender"
- "Add 'board meeting' as a keyword under Needs Response"
- "Add a new bucket called 'Personal' ranked above FYI, for keywords like 'family', 'doctor'"

The agent will update the JSON file and confirm the change — no restart needed, it's read fresh
on every run.

### `priorities.json` structure

```json
{
  "lookback_days": 7,
  "vip_senders": ["someone@example.com"],
  "buckets": [
    {
      "name": "Needs Response",
      "rank": 1,
      "description": "...",
      "keywords": ["..."]
    }
  ]
}
```

Lower `rank` = higher priority. Mail from a VIP sender is always promoted to at least
"Important - Read Only" regardless of keyword matches.

## Troubleshooting

- **"Not authenticated" / auth_status loop**: re-run the device-code sign-in (step 3 above).
- **TLS / certificate errors during `uv` commands**: this network has a TLS-inspecting proxy. Set
  `$env:UV_NATIVE_TLS = "1"` before running `uv` commands so it trusts the system cert store.
- **Server won't start in Kiro**: confirm the `command` path in `mcp.json` matches
  `outlook-triage-mcp\.venv\Scripts\outlook-triage-mcp.exe` exactly, and that the file exists.
