"""Retry/backoff behavior of the Graph client, with a fake HTTP session."""

from __future__ import annotations

import json as jsonlib

import pytest

from outlook_triage_mcp.graph import GraphClient, GraphError


class FakeResponse:
    def __init__(self, status_code: int, body: dict | None = None,
                 headers: dict | None = None):
        self.status_code = status_code
        self.headers = headers or {}
        self._body = body if body is not None else {}
        self.content = jsonlib.dumps(self._body).encode() if body is not None else b""
        self.text = jsonlib.dumps(self._body) if body is not None else ""

    def json(self):
        if not self.content:
            raise ValueError("no content")
        return self._body


class FakeSession:
    def __init__(self, responses: list[FakeResponse]):
        self._responses = list(responses)
        self.requests: list[tuple[str, str]] = []

    def request(self, method, url, **kwargs):
        self.requests.append((method, url))
        return self._responses.pop(0)


def make_client(responses, sleeps):
    session = FakeSession(responses)
    client = GraphClient(
        token_provider=lambda: "fake-token",
        session=session,
        sleep=sleeps.append,
        max_retries=3,
        backoff_base=0.5,
    )
    return client, session


def test_retries_429_honoring_retry_after():
    sleeps: list[float] = []
    client, session = make_client(
        [
            FakeResponse(429, {"error": {"message": "throttled"}},
                         headers={"Retry-After": "2"}),
            FakeResponse(200, {"value": [{"id": "1"}]}),
        ],
        sleeps,
    )
    result = client.get("me/messages")
    assert result["value"] == [{"id": "1"}]
    assert sleeps == [2.0]
    assert len(session.requests) == 2


def test_exponential_backoff_without_retry_after():
    sleeps: list[float] = []
    client, _ = make_client(
        [
            FakeResponse(503, {"error": {"message": "unavailable"}}),
            FakeResponse(503, {"error": {"message": "unavailable"}}),
            FakeResponse(200, {"ok": True}),
        ],
        sleeps,
    )
    assert client.get("me/messages") == {"ok": True}
    assert sleeps == [0.5, 1.0]  # 0.5 * 2**attempt


def test_gives_up_after_max_retries():
    sleeps: list[float] = []
    client, session = make_client(
        [FakeResponse(503, {"error": {"message": "down"}})] * 4,
        sleeps,
    )
    with pytest.raises(GraphError) as excinfo:
        client.get("me/messages")
    assert excinfo.value.status_code == 503
    assert len(session.requests) == 4  # initial + 3 retries


def test_non_retryable_error_raises_immediately():
    sleeps: list[float] = []
    client, session = make_client(
        [FakeResponse(403, {"error": {"message": "forbidden"}})],
        sleeps,
    )
    with pytest.raises(GraphError) as excinfo:
        client.get("me/messages")
    assert excinfo.value.status_code == 403
    assert sleeps == []
    assert len(session.requests) == 1
