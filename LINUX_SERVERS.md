# Linux Servers Module

This fork keeps the normal local macOS Stats modules and replaces the hosted
`Remote` module with a self-hosted `Linux Servers` module.

## Mac app

Open Stats settings, enable `Linux Servers`, then add each server with:

- Name
- Tailscale URL, for example `http://nas.tailnet-name.ts.net:9783`
- Bearer token
- Enabled state and ordering

Each enabled server gets its own macOS menu bar item. Clicking that item opens a
server-specific popup with CPU, memory, disk, network, temperature, GPU, and top
process data. Tokens are stored in macOS Keychain.

Fresh installs default update checks to `Never` so the custom fork does not
silently replace itself with upstream Stats.

## Linux agent

The agent lives in `server-stats-agent/`.

```sh
cd server-stats-agent
go build ./cmd/server-stats-agent
SERVER_STATS_TOKEN="replace-me" ./server-stats-agent
```

Default port: `9783`

Endpoints:

- `GET /v1/health`
- `GET /v1/snapshot`
- `GET /v1/stream`

All endpoints require:

```http
Authorization: Bearer <token>
```

The intended network boundary is Tailscale plus the bearer token.
