# Tanium Atlas MCP — Kiro connection

Connects Kiro to the **Tanium Atlas MCP Server** on your Tanium Cloud instance
(`https://group1001-api.cloud.tanium.com/mcp`) using an OAuth 2.0
**client-credentials** grant.

## Why a proxy instead of a direct `url` server

Kiro can talk to remote MCP servers directly via a `url` entry, but:

- Tanium Atlas is a **confidential** OAuth client (client id **+ secret**). Kiro's
  IDE OAuth support is for **public** clients only (PKCE, no secret) — confidential
  clients work only in the Kiro CLI.
- Tanium access tokens are short-lived (~1 hour), so a static `Authorization: Bearer`
  header in `mcp.json` would expire and break.

`proxy.mjs` solves both: it runs as a local stdio MCP server, performs the
client-credentials token exchange, refreshes the token before expiry, and injects
`Authorization: Bearer <token>` on every call to the remote endpoint. Zero
third-party dependencies (Node 18+ built-ins only).

## One-time setup

### 1. Register an OAuth client in Tanium Atlas

1. In the Tanium console, open **Atlas → OAuth Clients**.
2. Register a new client:
   - **Grant type:** `Client Credentials` (machine-to-machine, no browser sign-in).
   - **Connects to:** the Model Context Protocol endpoint (Tanium Atlas MCP Server).
   - **Role:** assign **MCP User Read Only** (grants the read-only toolset).
3. After registering, copy these four values from the registration screen:
   - **Client ID**
   - **Client Secret** (shown once — store it safely)
   - **Token URL** (the OAuth 2.0 token endpoint)
   - **Scope** (if the screen specifies one; may be blank)

> Dynamic Client Registration (DCR) is not supported — this must be a statically
> registered client.

### 2. Set the environment variables (per user, persistent)

Run once in PowerShell. These persist for your Windows user account:

```powershell
# Paste the values from the Atlas OAuth Clients screen.
[Environment]::SetEnvironmentVariable('TANIUM_TOKEN_URL',     'https://group1001.cloud.tanium.com/oauth/token',     'User')
[Environment]::SetEnvironmentVariable('TANIUM_CLIENT_ID',     '<b0a5b925facdb00a9060ab7ed9007f76d56118d5fe89649a749275e5ca3555c1>',     'User')
[Environment]::SetEnvironmentVariable('TANIUM_CLIENT_SECRET', '<b27731ba6f29a93f43950071aedb983631929e0590d93347868e6f7078736eba>', 'User')
[Environment]::SetEnvironmentVariable('TANIUM_SCOPE',         '','User')
```

Keep the secret out of any file that gets committed. These live in your user
environment, not in the repo.

### 3. Approve the variables for expansion in Kiro

Kiro only expands env vars in `mcp.json` that you explicitly approve:

- Kiro **Settings** → search **"Mcp Approved Env Vars"** → add:
  `TANIUM_TOKEN_URL`, `TANIUM_CLIENT_ID`, `TANIUM_CLIENT_SECRET`, `TANIUM_SCOPE`.

### 4. Add the server to `mcp.json`

Add this block under `mcpServers` in either:

- workspace: `.kiro/settings/mcp.json`, or
- user-level: `~/.kiro/settings/mcp.json`

```json
"tanium-atlas": {
  "command": "node",
  "args": [
    "c:\\DWX_Dev_Sync\\dwx-automation-cli-scripts\\intune-apps\\tanium-atlas-mcp\\proxy.mjs"
  ],
  "env": {
    "TANIUM_MCP_URL": "https://group1001-api.cloud.tanium.com/mcp",
    "TANIUM_TOKEN_URL": "${TANIUM_TOKEN_URL}",
    "TANIUM_CLIENT_ID": "${TANIUM_CLIENT_ID}",
    "TANIUM_CLIENT_SECRET": "${TANIUM_CLIENT_SECRET}",
    "TANIUM_SCOPE": "${TANIUM_SCOPE}",
    "TANIUM_AUTH_STYLE": "basic"
  },
  "disabled": false,
  "autoApprove": []
}
```

Kiro hot-reloads `mcp.json` on save and reconnects just this server. The tools
from Tanium Atlas should appear in the MCP server list.

## Verifying it works

Run the proxy standalone with the env vars set — it should fetch a token and
wait on stdin (Ctrl+C to exit):

```powershell
node c:\DWX_Dev_Sync\dwx-automation-cli-scripts\intune-apps\tanium-atlas-mcp\proxy.mjs
```

Expected stderr: `obtained access token, valid for ~3600s`. If you instead see a
`FATAL` about a missing variable, that env var isn't set in this shell.

## Corporate TLS / Zscaler note

This machine has `NODE_EXTRA_CA_CERTS` pointing at
`C:\ProgramData\G1001\Certs\Zscaler.cacert.pem`, and Node warned that the file
could not be loaded. Against the real HTTPS Tanium endpoint through Zscaler TLS
inspection, Node may reject the certificate chain (`UNABLE_TO_GET_ISSUER_CERT` or
similar). If that happens:

1. Make sure the Zscaler root CA PEM actually exists at that path (or repoint
   `NODE_EXTRA_CA_CERTS` to the correct file), e.g.:
   ```powershell
   [Environment]::SetEnvironmentVariable('NODE_EXTRA_CA_CERTS','C:\path\to\Zscaler-root.pem','User')
   ```
2. Do **not** disable TLS verification (`NODE_TLS_REJECT_UNAUTHORIZED=0`) as a
   fix — that defeats certificate validation. Use the proper CA bundle instead.

## Environment variables reference

| Variable | Required | Purpose |
|---|---|---|
| `TANIUM_MCP_URL` | yes | Remote MCP endpoint (`https://group1001-api.cloud.tanium.com/mcp`). |
| `TANIUM_TOKEN_URL` | yes | OAuth 2.0 token endpoint from the Atlas OAuth Clients screen. |
| `TANIUM_CLIENT_ID` | yes | OAuth client id. |
| `TANIUM_CLIENT_SECRET` | yes | OAuth client secret. |
| `TANIUM_SCOPE` | no | Space-delimited scope(s), if Atlas specifies one. |
| `TANIUM_AUTH_STYLE` | no | `basic` (default) sends id/secret as HTTP Basic auth; `post` sends them in the form body. Try `post` if token calls 401 under `basic`. |

## Security

- The client secret lives only in your Windows user environment, never in the repo.
- The proxy writes all diagnostics to **stderr**; **stdout** carries only MCP
  protocol traffic, so the token is never printed to the protocol channel.
- Access is scoped to the **MCP User Read Only** role and your Tanium RBAC.
