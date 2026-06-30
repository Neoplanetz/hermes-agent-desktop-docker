# Hermes Agent Desktop Docker

A turnkey Ubuntu 24.04 + XFCE4 desktop with **Hermes Agent** (Nous Research)
pre-installed for **secure browser automation**: a CDP-enabled Chrome runs on
the `:1` display and Hermes' `/browser` drives it, while you watch and steer over
the web (NoVNC), VNC, or RDP. Runs with **no extra privilege** (`docker compose up`).

## Architecture

<p align="center">
  <img src="assets/architecture_en.svg" width="720" alt="Hermes Agent Desktop architecture" />
</p>

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
agent's browser actions are visible no matter how you connect
(see `docs/ACCESS-MODEL.md`). Default credentials are `hermes` / `hermes123` —
**change them before exposing any port beyond loopback.**

## What the agent can do

- **Browser automation (CDP)** — a CDP-enabled Chrome autostarts on `:1`; Hermes
  `/browser` attaches over CDP (`127.0.0.1:9222`, never exposed to the host) so the
  agent can read and drive web pages while you watch over NoVNC/RDP.
- **Observable desktop** — NoVNC / VNC / RDP all show the same `:1` session, so you
  can watch the automation live and intervene by hand.
- **Dashboard** — Status, Chat (embedded TUI), Config, API Keys, Sessions,
  Skills, MCP, Logs, Cron, Channels.

## Known limitations

- **Keyboard input into native GTK apps via `computer_use` is not supported (out of scope for this image)** under
  this VNC desktop. **Root cause is the X server**, not GTK: this image runs TigerVNC
  `Xvnc`, which exposes only its built-in VNC/XTEST input and **does not accept
  `uinput`/`libinput` virtual input devices**. cua-driver's native Linux real-input
  path is a `uinput` virtual device — under `Xvnc` it can't attach ("`uinput/libinput
  pointers cannot become real X input devices`", per cua-driver's own diagnostic), so
  it silently falls back to **XSendEvent** (synthetic events), which GTK ignores for
  **both clicks and keystrokes**. On a normal Xorg session those uinput devices
  register as real input and typing works — which is why upstream docs say it works,
  and why trycua flags Linux as a *pre-release* backend. Verified corollaries: the
  text widget *is* exposed in AT-SPI (a `text` accessible with `Text`+`EditableText`);
  cua-driver's `get_window_state` doesn't enumerate it; and if the widget is focused
  out-of-band via a real XTest click, cua-driver then types fine (`"path": "ax"`).
  The **browser-automation path (CDP) works.** Full analysis + the Xvnc/uinput root
  cause in `docs/E2E-ACCEPTANCE.md`.

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
