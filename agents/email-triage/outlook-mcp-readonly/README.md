# outlook-mcp-readonly

**A read-only Outlook MCP server for Windows.** Gives Claude Desktop, Claude
Code, or any [Model Context Protocol](https://modelcontextprotocol.io) (MCP)
client safe, local access to your **classic desktop Outlook** mailbox and
calendar — no Azure/Entra app registration, no OAuth consent screen, no
cloud relay, and no tool anywhere in this codebase capable of sending,
deleting, or modifying anything in your inbox.

[![Platform: Windows](https://img.shields.io/badge/platform-Windows-0078D6?logo=windows)](#requirements)
[![Outlook: Classic desktop only](https://img.shields.io/badge/Outlook-classic%20desktop%20only-D83B01?logo=microsoftoutlook)](#requirements)
[![Python 3.10+](https://img.shields.io/badge/python-3.10%2B-blue?logo=python)](pyproject.toml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

If you searched for an **Outlook MCP server**, an **MCP server for Outlook
email**, or a way to connect **Claude to Outlook on Windows** without
handing over write access to your mailbox — this is that project.

## Table of contents

- [Why read-only, specifically](#why-read-only-specifically)
- [Requirements](#requirements)
- [Tools exposed](#tools-exposed)
- [Installation](#installation)
- [Configure Claude Desktop](#configure-claude-desktop)
- [Configure Claude Code (CLI)](#configure-claude-code-cli)
- [Verify it's working](#verify-its-working)
- [How it works](#how-it-works)
- [Troubleshooting / exceptions](#troubleshooting--exceptions)
- [Limitations](#limitations)
- [FAQ](#faq)
- [Contributing](#contributing)
- [License](#license)

## Why read-only, specifically

Most community Outlook MCP servers bundle send/delete/move tools because
they're built for full inbox automation. This one deliberately does not.
There is **no tool in this codebase capable of sending, deleting, moving, or
otherwise modifying anything in your mailbox.** That's not a config flag you
can flip on — the code to do those things simply isn't written.

If you want to verify that yourself before trusting it with your inbox:

```bash
grep -n "\.Send(\|\.Delete(\|\.Move(\|\.Save(\|UnRead = \|\.Display(" src/outlook_readonly_mcp/*.py
```

Every match should be inside a comment or docstring, not a live call. That's
intentional — it's meant to be a two-minute audit for anyone reviewing this
before pointing it at their real mailbox.

The only thing this server writes anywhere is `save_attachment`, which saves
an attachment's bytes to a folder on **your local disk** — it doesn't touch
Outlook's data at all.

## Requirements

This project is intentionally narrow-scoped. Read this section before
installing — most setup issues come from one of these constraints.

- **Windows only.** There is no macOS or Linux support, and none is planned —
  the server depends on Windows COM automation (`pywin32`), which doesn't
  exist on other platforms.
- **Classic desktop Outlook only** (`OUTLOOK.EXE`, sometimes called
  "Outlook (classic)" or "Outlook for Windows — legacy"). The new,
  Store-distributed **"New Outlook" (`olk.exe`) is not supported** — it has
  no COM object model to automate. If your Outlook shows a **"Try the new
  Outlook"** toggle in the top-right corner, make sure it's switched **off**.
- **Python 3.10+**, installed on the same Windows machine.
- **Outlook must already be running and signed in.** This server attaches to
  your existing, already-authenticated Outlook session — it does not manage
  its own login, so there's no username/password/OAuth flow to configure.
- **Both Outlook and your MCP client (Claude Desktop or Claude Code) need to
  be open at the same time.** There's no background or always-on mode.

## Tools exposed

| Tool | What it does |
|---|---|
| `list_folders` | Lists all mail folders with item/unread counts |
| `list_emails` | Lists recent email metadata (subject, sender, date, unread flag) in a folder |
| `search_emails` | Searches subject (and optionally body) for text |
| `get_email` | Full details of one email by EntryID, including body and attachment list |
| `list_attachments` | Attachment filenames/sizes for an email |
| `save_attachment` | Saves one attachment to a local folder (disk write only, not an Outlook write) |
| `get_unread_summary` | Unread count + newest unread subjects for a folder — good for a daily check-in |
| `list_calendar_events` | Calendar events (including recurring instances) in a date window |

## Installation

Run these from **Command Prompt (`cmd.exe`) or PowerShell** on Windows:

```bat
git clone https://github.com/r-rohit/outlook-mcp-readonly.git
cd outlook-mcp-readonly
python -m venv .venv
```

Activate the virtual environment — the command differs by shell:

```bat
:: cmd.exe
.venv\Scripts\activate.bat
```

```powershell
# PowerShell
.venv\Scripts\Activate.ps1
```

> If PowerShell refuses to run the activation script with a "running
> scripts is disabled on this system" error, run
> `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` first, then
> re-run the activation command.

Then install the package:

```bat
pip install -e .
```

If `pip install` succeeds but Outlook automation still fails with a COM
registration error, run pywin32's post-install script once (this registers
the COM support DLLs that `pip` doesn't always wire up automatically):

```bat
python .venv\Scripts\pywin32_postinstall.py -install
```

## Configure Claude Desktop

Edit `%APPDATA%\Claude\claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "outlook-readonly": {
      "command": "C:\\path\\to\\outlook-mcp-readonly\\.venv\\Scripts\\python.exe",
      "args": ["-m", "outlook_readonly_mcp.server"]
    }
  }
}
```

Restart Claude Desktop. With Outlook also open, try asking:

> "What unread emails do I have in my inbox, and do any of them mention a deadline?"
> "What's on my calendar for the rest of this week?"

## Configure Claude Code (CLI)

```bash
claude mcp add outlook-readonly -- C:\path\to\outlook-mcp-readonly\.venv\Scripts\python.exe -m outlook_readonly_mcp.server
```

> **PowerShell gotcha:** `claude mcp add ... -- <command> <args>` is known to
> silently mis-parse arguments after `--` when run from PowerShell (an
> upstream Claude Code CLI bug on Windows). If the server fails to connect
> after adding it this way, use one of these workarounds instead:
> - Run the `claude mcp add` command from `cmd.exe` instead of PowerShell, or
> - Edit `%USERPROFILE%\.claude.json` directly and add the server under the
>   top-level `mcpServers` key using the same `command`/`args` shape as the
>   Claude Desktop config above.

## Verify it's working

- **Claude Desktop:** open a new chat and confirm the tool icon shows
  `outlook-readonly` connected, or just ask an Outlook-related question.
- **Claude Code:** run `/mcp` inside a session — `outlook-readonly` should
  show as connected.

## How it works

```
Claude Desktop / Claude Code → this MCP server (local Python, stdio)
  → win32com (pywin32) → OUTLOOK.EXE (already running) → your mailbox
```

Everything runs on your machine. No network calls are made by this server
itself (Outlook's own sync with Exchange/M365 happens independently, as it
always does).

## Troubleshooting / exceptions

| Symptom / error message | Cause | Fix |
|---|---|---|
| `pywin32 is not installed or this isn't Windows.` | Running on macOS/Linux, or `pywin32` failed to install. | This server only runs on Windows. Re-run `pip install -e .` on a Windows machine. |
| `Could not attach to Outlook via COM. Make sure classic desktop Outlook (OUTLOOK.EXE) is installed and can be launched.` | Outlook isn't running, isn't installed, or you're on the new Outlook (`olk.exe`). | Launch classic Outlook and sign in first. If you see a "Try the new Outlook" toggle, switch it **off**, then restart Outlook. |
| `Folder '<path>' not found (missing segment '<part>').` | The `folder_path` argument doesn't match your mailbox's actual folder names/nesting. | Call `list_folders` first to get the exact `/`-separated path, then pass that path verbatim. |
| COM registration / `class not registered` errors on first run | `pywin32` installed via `pip` but its COM DLLs weren't registered. | Run `python .venv\Scripts\pywin32_postinstall.py -install` (see [Installation](#installation)). |
| Server shows as disconnected in Claude Desktop/Code | Outlook isn't open, or the `command`/`args` path in your MCP config is wrong. | Confirm Outlook is running, and that the `python.exe` path points at `.venv\Scripts\python.exe` inside this project. |
| Claude Code CLI silently drops arguments after `--` on Windows | Known PowerShell parsing bug in the Claude Code CLI. | See the PowerShell gotcha note under [Configure Claude Code (CLI)](#configure-claude-code-cli). |
| Antivirus/EDR blocks the COM automation call | Some corporate endpoint security tools flag COM automation of Office apps by default. | Ask your IT/security team to allow COM automation for this script, or run it under a policy exception — this repo can't work around endpoint security by design. |

## Limitations

- Windows + classic Outlook only (no macOS/Linux, no "new Outlook").
- Only works while both Outlook and your MCP client (Claude Desktop or
  Claude Code) are open — there's no background/always-on piece, by design
  (matches the read-only, on-demand scope of this project).
- Reads the default mail store only; additional shared mailboxes or
  secondary accounts added to the same Outlook profile aren't explicitly
  tested.
- No contacts/tasks tools yet (mail + calendar only) — contributions welcome.

## FAQ

**Does this work with the new Outlook (`olk.exe`) or Outlook on the web (OWA)?**
No. Neither exposes the COM object model this server relies on. You need
classic desktop Outlook.

**Does this work on macOS or Linux?**
No — Windows only. `pywin32`/COM automation of Outlook is a Windows-only
mechanism.

**Can Claude send, delete, or reply to emails with this?**
No. There is no such tool in this codebase, and that's intentional — see
[Why read-only, specifically](#why-read-only-specifically).

**Do I need to register an Azure/Entra app or set up OAuth?**
No. This server talks to Outlook via local COM automation, not the Microsoft
Graph API, so there's no cloud app registration, client secret, or OAuth
consent screen involved.

**Does it work with Exchange/Microsoft 365 accounts, or only local PST files?**
Either — it reads through whatever account(s) your already-signed-in
Outlook client has configured, regardless of whether the mailbox is on
Exchange/M365 or a local PST/OST.

## Contributing

Issues and PRs welcome. If you're adding a tool, it must not call `.Send()`,
`.Delete()`, `.Move()`, `.Save()`, or set `.UnRead`/`.Display()` on any
Outlook item — that's the one hard rule of this project. Anything that only
reads COM properties (or writes to local disk, like `save_attachment`) is
fair game.

## License

MIT — see [LICENSE](LICENSE).
