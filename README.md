# Hermes Agent Desktop Docker

A turnkey Ubuntu 24.04 + XFCE4 desktop with **Hermes Agent** (Nous Research)
pre-installed and its **`computer_use`** toolset wired to the desktop's `:1`
display — so the agent can drive a real GUI and a visible browser while you
watch and steer over the web, VNC, or RDP.

## Quick start

```bash
cp .env.example .env        # then edit HERMES_USER / HERMES_PASSWORD
docker compose up -d
```

Then open the **dashboard** at <http://localhost:9119> and set a model + API key
(Nous Portal recommended) in the API Keys tab, or run `hermes setup` from the
"Hermes Setup" desktop shortcut.

## Access

| Surface | Address | Login |
|---|---|---|
| Web desktop (NoVNC) | <http://localhost:6080/vnc.html> | VNC password = `HERMES_PASSWORD` |
| Raw VNC client | `localhost:5901` | `HERMES_PASSWORD` |
| RDP client | `localhost:3390` | `HERMES_USER` / `HERMES_PASSWORD` |
| Web dashboard | <http://localhost:9119> | `HERMES_USER` / `HERMES_PASSWORD` |

All three remote-desktop paths converge on the **same** `:1` desktop, so the
agent's `computer_use` actions are visible no matter how you connect
(see `docs/ACCESS-MODEL.md`). Default credentials are `hermes` / `hermes123` —
**change them before exposing any port beyond loopback.**

## What the agent can do

- **`computer_use`** — reads the desktop's window list + AT-SPI accessibility tree
  on `:1` and drives apps via cua-driver (`hermes computer-use doctor` to check).
  ⚠️ Keyboard input into native GTK apps does not work yet — see **Known limitations**.
- **Visible browser** — a CDP-enabled Chrome autostarts on `:1`; `/browser connect`
  and the agent's `page` tool attach over CDP (`:9222`) so the agent can read/drive
  the page while you watch.
- **Dashboard** — Status, Chat (embedded TUI), Config, API Keys, Sessions,
  Skills, MCP, Logs, Cron, Channels.

## Known limitations

- **Keyboard input into native GTK apps via `computer_use` does not work yet.**
  cua-driver injects keystrokes via XSendEvent (synthetic X events, which GTK
  ignores) and via AT-SPI element targeting (but GTK editors like Mousepad don't
  expose their text widget in the AT-SPI tree). Raw XTest input works, but
  cua-driver 0.6.8 doesn't use it. The **browser-automation path (CDP) works.**
  Needs an upstream cua-driver input fix — details in `docs/E2E-ACCEPTANCE.md`.

## Configuration

- `HERMES_USER` / `HERMES_PASSWORD` — desktop account, used for VNC/RDP and the
  dashboard login. Set in `.env`.
- Per-user state persists in the `hermes-home` Docker volume (`~/.hermes`).
- Model/provider are unset by default — configure at runtime in the dashboard.

## Security

- The dashboard binds `0.0.0.0` inside the container but is host-published to
  `127.0.0.1:9119` only, and **always requires login** (scrypt-hashed password
  auth; no plaintext stored). LAN exposure is opt-in — edit the port mappings in
  `docker-compose.yml` and use a strong `HERMES_PASSWORD`.
- The VNC password and dashboard auth material are generated at container start
  (mode 600, in-container only) — never baked into the image or committed.

## Ports

`6080` NoVNC · `5901` VNC · `3390→3389` RDP · `9119` dashboard · `9222` CDP (in-container).
