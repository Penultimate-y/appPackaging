#!/usr/bin/env node
/*
================================================================================
Script Name:        proxy.mjs  (tanium-atlas-mcp-proxy)
Creation Date:      2026-10-23
Author:             Allen Johnson with Kiro
Script Function:    Local stdio <-> Streamable-HTTP proxy that lets an MCP
                    client which only speaks local stdio (e.g. Kiro) connect
                    to the remote Tanium Atlas MCP Server.

                    On start it performs an OAuth 2.0 client-credentials grant
                    against the Tanium token endpoint, caches the access token,
                    and transparently refreshes it before expiry. Every JSON-RPC
                    message from the client is forwarded to the remote /mcp
                    endpoint over HTTP POST with an Authorization: Bearer header;
                    responses (including text/event-stream) are streamed back to
                    the client over stdout.

                    Zero third-party dependencies - uses Node >= 18 built-ins
                    (global fetch, ReadableStream, process stdio).

Script Input:       All configuration comes from environment variables so no
                    secret or tenant-specific URL is ever hardcoded:

                      TANIUM_MCP_URL        Remote MCP endpoint.
                                            e.g. https://group1001-api.cloud.tanium.com/mcp
                      TANIUM_TOKEN_URL      OAuth 2.0 token endpoint (copy from
                                            the Atlas OAuth Clients registration
                                            screen).
                      TANIUM_CLIENT_ID      OAuth client id.
                      TANIUM_CLIENT_SECRET  OAuth client secret.
                      TANIUM_SCOPE          (optional) space-delimited scope(s)
                                            to request in the token call.
                      TANIUM_AUTH_STYLE     (optional) "basic" (default) sends
                                            client id/secret via HTTP Basic auth;
                                            "post" sends them in the form body.

Script Output:      MCP JSON-RPC traffic on stdout. Diagnostics on stderr only
                    (stdout is reserved for the protocol).

Permissions:        Runs as the invoking user. No elevation required.
================================================================================
*/

'use strict';

// ---------------------------------------------------------------------------
// DEFINE VARIABLES AND INPUTS AND OUTPUTS
// ---------------------------------------------------------------------------

const CONFIG = {
  mcpUrl: requireEnv('TANIUM_MCP_URL'),
  tokenUrl: requireEnv('TANIUM_TOKEN_URL'),
  clientId: requireEnv('TANIUM_CLIENT_ID'),
  clientSecret: requireEnv('TANIUM_CLIENT_SECRET'),
  scope: process.env.TANIUM_SCOPE || '',
  authStyle: (process.env.TANIUM_AUTH_STYLE || 'basic').toLowerCase(),
};

// Refresh the token this many seconds before it actually expires so an
// in-flight request never rides on a just-expired token.
const TOKEN_EXPIRY_SKEW_SECONDS = 60;

let cachedToken = null;      // { accessToken: string, expiresAtMs: number }
let sessionId = null;        // Mcp-Session-Id, if the server issues one.

// ---------------------------------------------------------------------------
// CODE AND SCRIPT LOGIC
// ---------------------------------------------------------------------------

function requireEnv(name) {
  const value = process.env[name];
  if (!value || !value.trim()) {
    log(`FATAL: required environment variable ${name} is not set.`);
    process.exit(1);
  }
  return value.trim();
}

// All human-readable output goes to stderr; stdout is the MCP channel only.
function log(message) {
  process.stderr.write(`[tanium-atlas-mcp-proxy] ${message}\n`);
}

// Obtain (and cache) an access token via the client-credentials grant.
async function getAccessToken() {
  const now = Date.now();
  if (cachedToken && cachedToken.expiresAtMs > now) {
    return cachedToken.accessToken;
  }

  const body = new URLSearchParams();
  body.set('grant_type', 'client_credentials');
  if (CONFIG.scope) body.set('scope', CONFIG.scope);

  const headers = {
    'Content-Type': 'application/x-www-form-urlencoded',
    Accept: 'application/json',
  };

  if (CONFIG.authStyle === 'post') {
    body.set('client_id', CONFIG.clientId);
    body.set('client_secret', CONFIG.clientSecret);
  } else {
    const basic = Buffer.from(`${CONFIG.clientId}:${CONFIG.clientSecret}`).toString('base64');
    headers.Authorization = `Basic ${basic}`;
  }

  const res = await fetch(CONFIG.tokenUrl, { method: 'POST', headers, body });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`token endpoint returned ${res.status} ${res.statusText}: ${text.slice(0, 500)}`);
  }

  const json = await res.json();
  if (!json.access_token) {
    throw new Error('token endpoint response did not include an access_token');
  }

  const expiresInSec = Number(json.expires_in) || 3600;
  cachedToken = {
    accessToken: json.access_token,
    expiresAtMs: now + Math.max(0, expiresInSec - TOKEN_EXPIRY_SKEW_SECONDS) * 1000,
  };
  log(`obtained access token, valid for ~${expiresInSec}s`);
  return cachedToken.accessToken;
}

// Forward a single JSON-RPC message (already parsed) to the remote MCP server
// and stream any response back to the client over stdout.
async function forward(message) {
  const token = await getAccessToken();

  const headers = {
    'Content-Type': 'application/json',
    Accept: 'application/json, text/event-stream',
    Authorization: `Bearer ${token}`,
  };
  if (sessionId) headers['Mcp-Session-Id'] = sessionId;

  const res = await fetch(CONFIG.mcpUrl, {
    method: 'POST',
    headers,
    body: JSON.stringify(message),
  });

  // Capture a server-minted session id so subsequent calls stay on the
  // same logical session.
  const returnedSession = res.headers.get('mcp-session-id');
  if (returnedSession) sessionId = returnedSession;

  if (!res.ok) {
    const text = await res.text().catch(() => '');
    // Surface the error back to the client as a JSON-RPC error when possible.
    if (message && message.id !== undefined && message.id !== null) {
      writeToClient({
        jsonrpc: '2.0',
        id: message.id,
        error: {
          code: -32000,
          message: `Tanium MCP HTTP ${res.status}: ${text.slice(0, 300)}`,
        },
      });
    }
    log(`remote returned ${res.status} ${res.statusText}: ${text.slice(0, 300)}`);
    return;
  }

  // 202 Accepted with no body: a notification/response the server ack'd.
  if (res.status === 202) return;

  const contentType = res.headers.get('content-type') || '';

  if (contentType.includes('text/event-stream')) {
    await pipeEventStream(res);
  } else if (contentType.includes('application/json')) {
    const json = await res.json();
    writeToClient(json);
  } else {
    const text = await res.text().catch(() => '');
    if (text.trim()) log(`unexpected content-type "${contentType}": ${text.slice(0, 200)}`);
  }
}

// Parse a Server-Sent Events stream and emit each `data:` JSON payload to the
// client as a framed JSON-RPC message.
async function pipeEventStream(res) {
  const decoder = new TextDecoder();
  let buffer = '';

  for await (const chunk of res.body) {
    buffer += decoder.decode(chunk, { stream: true });
    let sepIndex;
    // SSE events are separated by a blank line.
    while ((sepIndex = buffer.indexOf('\n\n')) !== -1) {
      const rawEvent = buffer.slice(0, sepIndex);
      buffer = buffer.slice(sepIndex + 2);
      emitSseEvent(rawEvent);
    }
  }
  if (buffer.trim()) emitSseEvent(buffer);
}

function emitSseEvent(rawEvent) {
  const dataLines = rawEvent
    .split('\n')
    .filter((line) => line.startsWith('data:'))
    .map((line) => line.slice(5).trimStart());
  if (dataLines.length === 0) return;
  const payload = dataLines.join('\n');
  try {
    writeToClient(JSON.parse(payload));
  } catch {
    log(`could not parse SSE data payload: ${payload.slice(0, 200)}`);
  }
}

// Write a JSON-RPC message to the client, newline-delimited on stdout.
function writeToClient(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

// Read newline-delimited JSON-RPC messages from stdin and forward each one.
function startStdinLoop() {
  let buffer = '';
  process.stdin.setEncoding('utf8');

  process.stdin.on('data', (chunk) => {
    buffer += chunk;
    let newlineIndex;
    while ((newlineIndex = buffer.indexOf('\n')) !== -1) {
      const line = buffer.slice(0, newlineIndex).trim();
      buffer = buffer.slice(newlineIndex + 1);
      if (!line) continue;
      let message;
      try {
        message = JSON.parse(line);
      } catch {
        log(`ignoring non-JSON line from client: ${line.slice(0, 200)}`);
        continue;
      }
      forward(message).catch((err) => {
        log(`forward error: ${err.message}`);
        if (message && message.id !== undefined && message.id !== null) {
          writeToClient({
            jsonrpc: '2.0',
            id: message.id,
            error: { code: -32001, message: `proxy error: ${err.message}` },
          });
        }
      });
    }
  });

  process.stdin.on('end', () => process.exit(0));
}

async function main() {
  log(`starting; remote MCP endpoint = ${CONFIG.mcpUrl}`);
  // Fail fast if credentials are wrong, before the client sends anything.
  try {
    await getAccessToken();
  } catch (err) {
    log(`FATAL: initial token exchange failed: ${err.message}`);
    process.exit(1);
  }
  startStdinLoop();
}

main();

// ---------------------------------------------------------------------------
// CODE COMPLETE
// ---------------------------------------------------------------------------
