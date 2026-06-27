# Hermes Agent Desktop — Access Model (Phase 2B)

## Shipped access model: CONVERGENCE

The agent acts on display `:1` (TigerVNC, `127.0.0.1:5901` inside the container).
Three access paths all reach **the same desktop**:

| Path | Address (host→container) | Notes |
|---|---|---|
| NoVNC (browser) | `http://localhost:6080/vnc.html` | Direct VNC over WebSocket |
| Raw VNC client | `localhost:5901` | Direct TigerVNC |
| RDP | `localhost:3390` → container `3389` | xrdp libvnc backend (see below) |

### RDP convergence detail

xrdp is configured with a `[Hermes-:1]` session that uses the `libvnc.so` backend,
pointing to `127.0.0.1:5901`. The `[Globals]` section sets `autorun=Hermes-:1`, so xrdp
**automatically connects** to that session after authentication — no session-type combo
selection is required. When an RDP client connects (e.g. Remmina, Windows RDC) and the
user enters credentials and presses Enter, xrdp proxies the connection directly to the
same TigerVNC display `:1` that `computer_use` acts on. There is no second X session —
all access paths share one desktop.

This means `computer_use` actions are observable in real time over RDP **by default**,
as well as over NoVNC or a raw VNC client.

## Security notes

- The runtime VNC password is written into `/etc/xrdp/xrdp.ini` inside the container
  at startup (mode 600, root-only). It is never baked into the image and never committed
  to version control.
- The password is injected at container startup via the `HERMES_PASSWORD` environment
  variable. No plaintext-password temp file is left on disk.
- `/etc/xrdp/xrdp.ini` (mode 600) is in-container only. Users who expose port 3389/3390
  beyond loopback should be aware the VNC password is stored there, and should treat
  that file accordingly (e.g. restrict container filesystem access).
- Default deployment binds RDP to `127.0.0.1:3390` (loopback only). Do not expose 3389
  to external networks without additional authentication.

## User-side acceptance step

After starting the container (`./scripts/spike-up.sh`), the manual acceptance check is:

1. Open `http://localhost:6080/vnc.html` — confirm the XFCE desktop is visible.
2. RDP to `localhost:3390`, enter credentials and press Enter — xrdp auto-connects to the converged `:1` session (no manual session selection required).
3. Confirm you see **the same desktop** as in step 1 (e.g. same open windows, same cursor position after a mouse move).

This confirms RDP is converged onto `:1` rather than spawning a new session.
