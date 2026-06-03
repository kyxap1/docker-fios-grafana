# Fios Firewall Logs → Grafana

Ships Verizon Fios (CR1000A) router logs into a self-hosted Grafana stack so you can search and visualize them.

## Why

The Fios router exposes firewall logs only through a clumsy web UI with no history or search. This pulls them out, keeps them, and makes them queryable in Grafana.

## How it works

Two sources feed the same pipeline:

```
CR1000A ──► syslog / UDP 514 ──────────────┐
                                           ├──► Alloy ──► Loki ──► Grafana
Fios web UI ──► cron (15m) ──► loggen ──────┘
```

- **CR1000A** — the router is configured to forward its own syslog straight to this host on UDP `514`.
- **cron** — Alpine + syslog-ng. Every 15 minutes `scripts/get_fw_log.sh` logs into the router web UI, downloads `messages_FW.log` (firewall events), drops already-sent lines (via `data/last_ts`), converts them to RFC3164 syslog, and forwards new lines to Alloy with `loggen`. It only runs when your public IP matches `HOME_IP`.
- **alloy** — receives syslog on UDP `514` from both sources, parses the timestamp, pushes to Loki.
- **loki** — stores logs on the filesystem (720h retention).
- **grafana** — http://localhost:3000, anonymous admin, with a pre-provisioned `firewall` dashboard.

The login flow in `get_fw_log.sh` is specific to the Fios CR1000A web UI.

## Usage

Create `.env` and a `router_pw` file (the router admin password), then:

```bash
echo 'ROUTER_IP=192.168.1.1' > .env
echo 'HOME_IP=<your-public-ip>' >> .env
printf '%s' 'your-router-password' > router_pw

docker compose up -d
```

Open Grafana at http://localhost:3000 and check the **firewall** dashboard.

## Enable router syslog forwarding

In the Fios UI: **Advanced → System → System Settings → Remote Administration**.

1. Turn **System Logging** on.
2. Set **Remote System Host IP Address** and **Remote Security Host IP Address** to the LAN IP of the host running this stack (e.g. `192.168.1.99`).
3. Leave the notify levels at `Information` (or raise as needed).
4. Click **Apply Changes**.

The router then streams its syslog to that host on UDP `514`, where Alloy is listening.

![Fios CR1000A — System Settings → Remote Administration: System Logging enabled with the Remote System/Security Host IP set to the stack host](https://github.com/kyxap1/docker-fios-grafana/releases/download/assets/router-syslog-setup.png)

## Config

| Var / file   | Purpose                                              |
|--------------|------------------------------------------------------|
| `ROUTER_IP`  | Router address (default `192.168.1.1`)               |
| `HOME_IP`    | Your home public IP; logs are only pulled when it matches |
| `router_pw`  | Router admin password (Docker secret, git-ignored)   |
