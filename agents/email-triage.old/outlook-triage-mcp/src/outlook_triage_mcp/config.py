"""Configuration loaded from environment variables.

All settings have safe defaults so the server starts with zero config.
Nothing here reads or writes secrets — the MSAL token cache location is the
only filesystem path, and it always lives outside the repository.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

GRAPH_BASE = "https://graph.microsoft.com/v1.0"

# Public client ID of the Microsoft Graph CLI (mgc).
#
# Why this one: the classic Azure CLI public client (04b07795-...) is blocked
# by Microsoft's first-party pre-authorization policy for Mail.* Graph scopes
# (AADSTS65002). The Graph CLI client is the recommended successor and works
# with delegated mail scopes out of the box on most tenants.
#
# If your organization blocks third-party public clients, register your own
# app (public client, device-code flow enabled, delegated Mail.Read +
# MailboxSettings.Read) and set OUTLOOK_MCP_CLIENT_ID.
DEFAULT_CLIENT_ID = "14d82eec-204b-4c2f-b7e8-296a70dab67e"

# Read-only by default. Write scopes are only requested when the user
# explicitly opts in with OUTLOOK_MCP_ENABLE_WRITE=1.
READ_SCOPES = ["Mail.Read", "MailboxSettings.Read", "User.Read"]
WRITE_SCOPES = ["Mail.ReadWrite", "MailboxSettings.ReadWrite", "User.Read"]


def _default_cache_dir() -> Path:
    """Token cache directory: $XDG_DATA_HOME/outlook-triage-mcp or ~/.local/share/outlook-triage-mcp."""
    xdg = os.environ.get("XDG_DATA_HOME")
    base = Path(xdg) if xdg else Path.home() / ".local" / "share"
    return base / "outlook-triage-mcp"


def _env_flag(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name, "").strip().lower()
    if not raw:
        return default
    return raw in {"1", "true", "yes", "on"}


@dataclass
class Settings:
    """Runtime settings resolved from the environment."""

    client_id: str = DEFAULT_CLIENT_ID
    tenant_id: str = "common"
    cache_dir: Path = field(default_factory=_default_cache_dir)
    write_enabled: bool = False
    user_email: str = ""
    max_attachment_bytes: int = 5 * 1024 * 1024  # attachments larger than this are listed, not parsed

    @property
    def scopes(self) -> list[str]:
        return WRITE_SCOPES if self.write_enabled else READ_SCOPES

    @property
    def token_cache_file(self) -> Path:
        return self.cache_dir / "token_cache.json"

    @classmethod
    def from_env(cls) -> "Settings":
        cache_dir = os.environ.get("OUTLOOK_MCP_CACHE_DIR")
        return cls(
            client_id=os.environ.get("OUTLOOK_MCP_CLIENT_ID", DEFAULT_CLIENT_ID),
            tenant_id=os.environ.get("OUTLOOK_MCP_TENANT_ID", "common"),
            cache_dir=Path(cache_dir) if cache_dir else _default_cache_dir(),
            write_enabled=_env_flag("OUTLOOK_MCP_ENABLE_WRITE"),
            user_email=os.environ.get("OUTLOOK_MCP_USER_EMAIL", "").strip().lower(),
            max_attachment_bytes=int(
                os.environ.get("OUTLOOK_MCP_MAX_ATTACHMENT_BYTES", 5 * 1024 * 1024)
            ),
        )
