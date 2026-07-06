# server-stats-agent

Lightweight Linux metrics agent for the Stats macOS tray app.

## Build

```sh
go build ./cmd/server-stats-agent
```

## Run

```sh
SERVER_STATS_TOKEN="replace-me" ./server-stats-agent
```

The agent listens on `:9783` by default and exposes:

- `GET /v1/health`
- `GET /v1/snapshot`
- `GET /v1/stream`

All endpoints require:

```http
Authorization: Bearer <token>
```

Tailscale is the intended network boundary for v1; keep the listener bound to a
Tailnet-reachable interface or firewall it to your Tailnet.

## systemd

Copy `packaging/systemd/server-stats-agent.service` to
`/etc/systemd/system/server-stats-agent.service`, then create
`/etc/server-stats-agent.env`:

```sh
SERVER_STATS_TOKEN=replace-me
SERVER_STATS_LISTEN=:9783
```

Then enable it:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now server-stats-agent
```
