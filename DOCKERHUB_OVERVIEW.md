# Hermes Agent Desktop

A turnkey Ubuntu 24.04 + XFCE4 desktop with **Hermes Agent** (Nous Research)
pre-installed for **secure browser automation**: a CDP-enabled Chrome runs on
the `:1` display and Hermes' `/browser` drives it, while you watch and steer over
the web (NoVNC), VNC, or RDP. Runs with **no extra privilege** (`docker compose up`).

## Quick start

```bash
# 1. Pull the image
docker pull neoplanetz/hermes-desktop-docker

# 2. Create your env file
cat > .env <<'EOF'
HERMES_USER=hermes
HERMES_PASSWORD=hermes123
EOF

# 3. Start
docker run -d \
  --env-file .env \
  -p 127.0.0.1:6080:6080 \
  -p 127.0.0.1:5901:5901 \
  -p 127.0.0.1:3390:3389 \
  -p 127.0.0.1:9119:9119 \
  -v hermes-home:/home/hermes \
  neoplanetz/hermes-desktop-docker
```

> The volume mounts `/home/hermes` because the example sets `HERMES_USER=hermes`.
> If you change `HERMES_USER`, mount `/home/<user>` instead.

Then open the **dashboard** at http://localhost:9119 and set a model + API key
in the API Keys tab, or run `hermes setup` from the "Hermes Setup" desktop
shortcut.

## Access

| Surface | Address | Login |
|---|---|---|
| Web desktop (NoVNC) | http://localhost:6080/vnc.html | VNC password = `HERMES_PASSWORD` |
| Raw VNC client | `localhost:5901` | `HERMES_PASSWORD` |
| RDP client | `localhost:3390` | `HERMES_USER` / `HERMES_PASSWORD` |
| Web dashboard | http://localhost:9119 | `HERMES_USER` / `HERMES_PASSWORD` |

All three remote-desktop paths converge on the **same** `:1` desktop, so the
agent's browser actions are visible no matter how you connect.
Default credentials are `hermes` / `hermes123` —
**change them before exposing any port beyond loopback.**

## What the agent can do

- **Browser automation (CDP)** — a CDP-enabled Chrome autostarts on `:1`; Hermes
  `/browser` attaches over CDP (`127.0.0.1:9222`) so the agent reads and drives web
  pages while you watch. (Native `computer_use` desktop input is not supported under
  this VNC desktop — see the project README / `docs/E2E-ACCEPTANCE.md`.)
- **Dashboard** — Status, Chat (embedded TUI), Config, API Keys, Sessions,
  Skills, MCP, Logs, Cron, Channels.

## Configuration

- `HERMES_USER` / `HERMES_PASSWORD` — desktop account, used for VNC/RDP and the
  dashboard login.
- Per-user state persists in the `hermes-home` Docker volume (mounted at the
  user's home; `~/.hermes` holds config, sessions, skills).
- Model/provider are unset by default — configure at runtime in the dashboard.

## Security

- The dashboard binds `0.0.0.0` inside the container but should be published to
  `127.0.0.1:9119` only (as shown above), and **always requires login**
  (scrypt-hashed password auth; no plaintext stored). LAN exposure is opt-in —
  change the port binding and use a strong `HERMES_PASSWORD`.
- The VNC password and dashboard auth material are generated at container start
  (mode 600, in-container only) — never baked into the image.

## Ports

`6080` NoVNC · `5901` VNC · `3390→3389` RDP · `9119` dashboard · `9222` CDP (in-container).
