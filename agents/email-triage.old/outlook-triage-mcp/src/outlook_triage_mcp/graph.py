"""Thin Microsoft Graph client with retry/backoff.

Retries transient failures (429 and 5xx) honoring ``Retry-After`` when the
server sends one, with exponential backoff otherwise — the same discipline
used by the production automation this project was extracted from.
"""

from __future__ import annotations

import time
from typing import Any, Callable

import requests

from .config import GRAPH_BASE

RETRYABLE_STATUS = {429, 500, 502, 503, 504}


class GraphError(RuntimeError):
    """A non-retryable (or retry-exhausted) Graph API error."""

    def __init__(self, status_code: int, message: str):
        super().__init__(f"Graph API error {status_code}: {message}")
        self.status_code = status_code


class GraphClient:
    """Minimal Graph REST client.

    ``token_provider`` is called before every request so tokens are always
    fresh (MSAL renews them silently from cache). ``session`` and ``sleep``
    are injectable for tests.
    """

    def __init__(
        self,
        token_provider: Callable[[], str],
        base_url: str = GRAPH_BASE,
        max_retries: int = 4,
        backoff_base: float = 0.5,
        session: requests.Session | None = None,
        sleep: Callable[[float], None] = time.sleep,
        timeout: float = 30.0,
    ):
        self._token_provider = token_provider
        self.base_url = base_url.rstrip("/")
        self.max_retries = max_retries
        self.backoff_base = backoff_base
        self._session = session or requests.Session()
        self._sleep = sleep
        self._timeout = timeout

    # -- core ---------------------------------------------------------------

    def request(
        self,
        method: str,
        path: str,
        *,
        params: dict[str, Any] | None = None,
        json: dict[str, Any] | None = None,
        headers: dict[str, str] | None = None,
    ) -> dict[str, Any]:
        url = path if path.startswith("http") else f"{self.base_url}/{path.lstrip('/')}"
        last_status, last_detail = 0, ""

        for attempt in range(self.max_retries + 1):
            token = self._token_provider()
            request_headers = {"Authorization": f"Bearer {token}"}
            if headers:
                request_headers.update(headers)

            response = self._session.request(
                method,
                url,
                params=params,
                json=json,
                headers=request_headers,
                timeout=self._timeout,
            )

            if response.status_code in RETRYABLE_STATUS:
                last_status = response.status_code
                last_detail = _error_detail(response)
                if attempt < self.max_retries:
                    retry_after = response.headers.get("Retry-After")
                    delay = (
                        float(retry_after)
                        if retry_after
                        else self.backoff_base * (2**attempt)
                    )
                    self._sleep(delay)
                    continue
                raise GraphError(last_status, f"retries exhausted: {last_detail}")

            if response.status_code >= 400:
                raise GraphError(response.status_code, _error_detail(response))

            if response.status_code == 204 or not response.content:
                return {}
            return response.json()

        raise GraphError(last_status, last_detail)  # pragma: no cover — defensive

    # -- convenience -------------------------------------------------------

    def get(self, path: str, params: dict[str, Any] | None = None,
            headers: dict[str, str] | None = None) -> dict[str, Any]:
        return self.request("GET", path, params=params, headers=headers)

    def post(self, path: str, json: dict[str, Any] | None = None) -> dict[str, Any]:
        return self.request("POST", path, json=json)

    def patch(self, path: str, json: dict[str, Any] | None = None) -> dict[str, Any]:
        return self.request("PATCH", path, json=json)

    def get_paged(
        self,
        path: str,
        params: dict[str, Any] | None = None,
        headers: dict[str, str] | None = None,
        max_items: int = 200,
    ) -> list[dict[str, Any]]:
        """GET a collection, following @odata.nextLink up to ``max_items``."""
        items: list[dict[str, Any]] = []
        page = self.get(path, params=params, headers=headers)
        while True:
            items.extend(page.get("value", []))
            next_link = page.get("@odata.nextLink")
            if not next_link or len(items) >= max_items:
                break
            page = self.get(next_link, headers=headers)
        return items[:max_items]


def _error_detail(response: requests.Response) -> str:
    try:
        return response.json().get("error", {}).get("message", response.text[:500])
    except ValueError:
        return response.text[:500]
