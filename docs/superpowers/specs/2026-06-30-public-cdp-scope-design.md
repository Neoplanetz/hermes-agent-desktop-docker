# Public Scope — Secure CDP Browser Automation (drop native computer_use desktop input)

- **Date:** 2026-06-30
- **Status:** Proposed (awaiting review)
- **Repo:** hermes-agent-desktop-docker

## 1. Context & decision

This image is being **published publicly**, so it must be safe to `docker compose up`
without granting dangerous host access. The original ambition was full `computer_use`
desktop control (the agent typing/clicking native GUI apps). Investigation this session
**proved that cannot be delivered securely** in a containerized VNC desktop:

- cua-driver's Linux input is a **`uinput` virtual device**; on this VNC server
  (`Xvnc`) it can't attach (no `/dev/input` nodes, read-only `/sys`), so it falls back
  to **XSendEvent**, which GTK ignores → native typing/clicking fails.
- The only way to make the uinput path work is a real **`Xorg` + `--privileged`** (or
  `/dev/uinput` + host `/dev/input`), which **bleeds host input both ways**: the agent
  can inject keystrokes into the host's real desktop, and the container reads the host's
  physical keyboard. Linux input devices aren't namespaced, so there's no clean middle.
  Unacceptable for a public image.

Full analysis and evidence: `docs/E2E-ACCEPTANCE.md`.

**Decision:** scope the public project to what works **securely with zero privilege** —
**CDP browser automation** — and explicitly drop native desktop control.

## 2. Goals (in scope)

- **Secure CDP browser automation.** A CDP-enabled Chrome autostarts on `:1`
  (loopback `127.0.0.1:9222`, never host-published). Hermes' built-in **`/browser`**
  attaches over CDP; the agent navigates / reads / drives the page.
- **Observable, operable desktop.** NoVNC (6080), VNC (5901), RDP (3390→3389), Hermes
  dashboard (9119) — all bound to host loopback — so a human can watch the agent's
  browser work and intervene.
- **Persistence & turnkey.** Named-volume home, default-credential warning, healthcheck.
- **Zero extra privilege.** No `--privileged`, no `--device`, no host-input access.

## 3. Non-goals (explicit)

- **Native `computer_use` desktop input** (typing/clicking/dragging native GUI apps via
  cua-driver). Documented as an unsupported limitation of this VNC/container model — not
  a regression (it never worked securely).
- **Xorg/x11vnc migration** and the **focus-assist** workaround: both dropped. The spike
  proved the migration needs privileged host-input bleed; focus-assist only rescued
  GUI-editor typing, which is now out of scope. Their analysis stays as rationale.

## 4. Key change — remove cua-driver

Verified this session: Hermes' `/browser` is **independent of cua-driver** — a
standalone CDP client (`agent/browser_provider.py`, `hermes_cli/browser_connect.py`,
`websockets`) attaching to `127.0.0.1:9222`. cua-driver is only the (now out-of-scope)
`computer_use` toolset. Therefore:

- **Remove** the `hermes computer-use install` step, the `/opt/hermes-noop` shim, and
  the `CUA_DRIVER_CDP_PORT` env from Dockerfile/entrypoint.
- **Keep** the CDP Chrome autostart on `:1` (this is what `/browser` attaches to).
- **Verify** Hermes runs cleanly with the `computer_use` toolset absent (it's optional;
  confirm no startup error and it's simply not offered).

Result: smaller image, no broken/confusing native-input surface, cleaner security story.

## 5. Architecture after the change

- **Unchanged:** Ubuntu 24.04 + XFCE on `Xvnc :1`; NoVNC/VNC/RDP/dashboard (loopback);
  named-volume persistence; desktop-trust; tini PID1; healthcheck.
- **Changed:** cua-driver removed. CDP Chrome autostart kept. Agent browser control =
  Hermes `/browser` (CDP → `127.0.0.1:9222`).

## 6. Security posture (public)

- ✅ All host-published ports bound to `127.0.0.1` (6080 / 5901 / 3390 / 9119).
- ✅ CDP `9222` is **not** host-published (internal only).
- ✅ Default-password boot warning; the non-loopback dashboard bind forces basic-auth.
- ⚠️ `security_opt: [seccomp=unconfined]` in compose loosens syscall filtering — review
  whether it's actually needed (likely for Chrome's sandbox). Prefer a least-privilege
  alternative (Chrome run with a proper sandbox, or a tailored seccomp profile) or
  document the justification for a public image.
- Confirm removing cua-driver also removes its background/telemetry surface.

## 7. Verification

- `/browser connect` attaches to `:9222`; the agent reads example.com `<h1>` on a clean
  rebuild + cold boot. Update `scripts/verify-cdp.sh` to exercise **`/browser`** rather
  than cua-driver's `page` tool.
- Hermes starts cleanly without cua-driver; `hermes` CLI usable; dashboard healthy.
- Image size drops (cua-driver removed); all existing `verify-*.sh` gates stay green.

## 8. Documentation

- **README / DOCKERHUB_OVERVIEW:** reframe the headline as **secure CDP browser
  automation + an observable VNC/RDP desktop**; remove or scope down `computer_use`
  claims; keep the native-input limitation note linking `docs/E2E-ACCEPTANCE.md`.

## 9. Open question for review

- Drop cua-driver entirely (this spec, Option A) **vs.** keep it but document
  native input as unsupported (Option B). Recommendation: **Option A** — leaner and a
  cleaner security story for a public image, with no loss of the in-scope CDP capability.
