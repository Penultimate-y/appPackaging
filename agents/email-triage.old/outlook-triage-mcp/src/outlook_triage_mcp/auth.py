"""MSAL device-code authentication with a persistent local token cache.

Design notes (inherited from the production system this was extracted from):

- Public client + device-code flow: no client secret anywhere. The user signs
  in on any browser with a short code; the server never sees the password.
- Persistent ``SerializableTokenCache`` on disk (0600 permissions) so the
  login survives restarts. MSAL refreshes tokens silently from the cache.
- Because an MCP server has no interactive console, the device flow is
  surfaced through the ``auth_status`` tool: calling it starts the flow and
  returns the verification URL + user code, while a background thread waits
  for the user to complete sign-in.
"""

from __future__ import annotations

import logging
import threading
import time
from typing import Any

import msal

from .config import Settings

log = logging.getLogger(__name__)


class AuthRequiredError(RuntimeError):
    """Raised when a Graph call is attempted without a valid cached token."""


class AuthManager:
    """Owns the MSAL app, the token cache, and the pending device-code flow."""

    def __init__(self, settings: Settings):
        self._settings = settings
        self._cache = msal.SerializableTokenCache()
        self._app: msal.PublicClientApplication | None = None
        self._lock = threading.Lock()
        self._pending_flow: dict[str, Any] | None = None
        self._flow_started_at: float = 0.0
        self._last_flow_result: dict[str, Any] | None = None
        self._load_cache()

    # -- cache persistence ----------------------------------------------

    def _load_cache(self) -> None:
        path = self._settings.token_cache_file
        if path.exists():
            try:
                self._cache.deserialize(path.read_text(encoding="utf-8"))
            except (ValueError, OSError) as exc:
                log.warning("Could not load token cache (%s); starting fresh.", exc)

    def _persist_cache(self) -> None:
        if not self._cache.has_state_changed:
            return
        path = self._settings.token_cache_file
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(self._cache.serialize(), encoding="utf-8")
        try:
            path.chmod(0o600)
        except OSError:
            pass

    # -- MSAL app ---------------------------------------------------------

    def _get_app(self) -> msal.PublicClientApplication:
        if self._app is None:
            self._app = msal.PublicClientApplication(
                self._settings.client_id,
                authority=f"https://login.microsoftonline.com/{self._settings.tenant_id}",
                token_cache=self._cache,
            )
        return self._app

    # -- token acquisition -------------------------------------------------

    def _acquire_silent(self) -> dict[str, Any] | None:
        app = self._get_app()
        accounts = app.get_accounts(username=self._settings.user_email or None)
        if not accounts:
            accounts = app.get_accounts()
        for account in accounts:
            result = app.acquire_token_silent(self._settings.scopes, account=account)
            if result and "access_token" in result:
                self._persist_cache()
                return result
        return None

    def get_token(self) -> str:
        """Return a valid access token from cache, or raise AuthRequiredError.

        This never blocks on user interaction: interactive sign-in is only
        started by the ``auth_status`` tool via :meth:`begin_device_flow`.
        """
        result = self._acquire_silent()
        if result:
            return result["access_token"]
        raise AuthRequiredError(
            "Not authenticated with Microsoft 365. "
            "Call the auth_status tool to start device-code sign-in."
        )

    # -- device-code flow --------------------------------------------------

    def begin_device_flow(self) -> dict[str, Any]:
        """Start (or reuse) a device-code flow and return its public details."""
        with self._lock:
            if self._pending_flow is not None:
                flow = self._pending_flow
                expires_in = int(flow.get("expires_in", 900))
                if time.monotonic() - self._flow_started_at < expires_in:
                    return self._flow_public_view(flow)
                self._pending_flow = None  # expired — start over

            app = self._get_app()
            flow = app.initiate_device_flow(scopes=self._settings.scopes)
            if "user_code" not in flow:
                raise RuntimeError(
                    f"Failed to initiate device-code flow: "
                    f"{flow.get('error_description', flow.get('error', 'unknown error'))}"
                )
            self._pending_flow = flow
            self._flow_started_at = time.monotonic()
            self._last_flow_result = None

        thread = threading.Thread(target=self._wait_for_flow, args=(flow,), daemon=True)
        thread.start()
        return self._flow_public_view(flow)

    def _wait_for_flow(self, flow: dict[str, Any]) -> None:
        """Blocks in a background thread until the user completes sign-in."""
        try:
            result = self._get_app().acquire_token_by_device_flow(flow)
        except Exception as exc:  # network or MSAL failure — surface via status
            result = {"error": "device_flow_failed", "error_description": str(exc)}
        with self._lock:
            self._last_flow_result = result
            self._pending_flow = None
        if "access_token" in result:
            self._persist_cache()
            log.info("Device-code sign-in completed.")

    @staticmethod
    def _flow_public_view(flow: dict[str, Any]) -> dict[str, Any]:
        return {
            "verification_uri": flow.get("verification_uri"),
            "user_code": flow.get("user_code"),
            "expires_in_seconds": flow.get("expires_in"),
            "message": flow.get("message"),
        }

    # -- status --------------------------------------------------------------

    def status(self) -> dict[str, Any]:
        """Current auth state, safe to expose as a tool result."""
        result = self._acquire_silent()
        if result:
            app = self._get_app()
            accounts = app.get_accounts()
            return {
                "authenticated": True,
                "account": accounts[0].get("username") if accounts else None,
                "scopes": self._settings.scopes,
                "write_enabled": self._settings.write_enabled,
            }

        with self._lock:
            pending = self._pending_flow
            last = self._last_flow_result

        if pending is not None:
            view = self._flow_public_view(pending)
            view.update(
                {
                    "authenticated": False,
                    "state": "awaiting_sign_in",
                    "instructions": (
                        f"Open {view['verification_uri']} and enter code "
                        f"{view['user_code']}. Then call auth_status again to confirm."
                    ),
                }
            )
            return view

        state: dict[str, Any] = {"authenticated": False, "state": "not_authenticated"}
        if last and "access_token" not in last:
            state["last_error"] = last.get("error_description") or last.get("error")
        return state
