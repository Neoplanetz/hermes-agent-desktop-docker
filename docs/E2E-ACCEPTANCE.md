# Computer-Use E2E Acceptance (manual, needs a model API key)

Validates the one thing the automated suite can't: a model driving `computer_use`
to actually operate the XFCE desktop, observed live over NoVNC.

## 1. Bring up + set a model key
```bash
HERMES_USER=hermes HERMES_PASSWORD=hermes123 docker compose up -d
# Set ONE provider key (example: Anthropic). Or use `hermes setup` in the terminal.
docker exec -it hermes-desktop su - hermes -c \
  'echo "ANTHROPIC_API_KEY=sk-ant-…" >> ~/.hermes/.env'
docker exec -it hermes-desktop su - hermes -c \
  'hermes config set model anthropic/claude-sonnet-4-6'   # or set in `hermes model`
```

## 2. Watch the desktop
Open http://localhost:6080/vnc.html (password `hermes123`). Leave a window
(e.g. Mousepad) focused on `:1`.

## 3. Drive computer_use
```bash
docker exec -it hermes-desktop su - hermes -c 'DISPLAY=:1 hermes -t computer_use chat'
# In the TUI, prompt: "Open Mousepad if it isn't open, then type 'hello from hermes' into it."
```

## 4. Acceptance criteria
- Over NoVNC you SEE Mousepad receive the typed text (AT-SPI/XSendEvent actuation).
- (Optional browser leg) prompt: "/browser connect, then open example.com and read the H1."
  Expect `/browser connect` to attach to the Chrome on `:9222` and the agent to read the page.
- `docker compose down && docker compose up -d` → the session/config persist (named volume).

Record PASS/FAIL + notes here. A PASS closes the spike's deferred "model-in-the-loop"
and "fresh named volume" gaps and clears Phase 2A.

---

## Result — 2026-06-29 (first model-in-the-loop run)

Model: **Nous Portal** free tier → `stepfun/step-3.7-flash:free` (the only free
Portal model with both vision and tool-calling; Claude/GPT/Gemini/Grok need credits).

**Mousepad typing: FAIL — and it is a driver/desktop issue, not a model one.**
Confirmed by driving cua-driver directly (no model in the loop):
- `type_text(window_id)` delivers **XSendEvent** synthetic key events, which **GTK
  ignores** → nothing lands in the editor.
- The AT-SPI path can't substitute: Mousepad's **GtkSourceView text widget is not
  exposed in the AT-SPI tree** (only the menubar/toolbar are), so there is no
  element to target.
- `xdotool type` (**XTest**) DOES land — but cua-driver 0.6.8 does not use XTest and
  exposes no input-method toggle. So no model can type into a GTK editor via this
  driver today. Tracked as a known limitation (see README).
- NOTE: the Phase-1 spike's "XTest input PASS" was raw xdotool/XTest, **not**
  cua-driver's actuation — which is why this model-in-the-loop gap survived until now.

**Browser leg: PASS — after a fix.** Did not work out of the box (nothing launched
Chrome with `--remote-debugging-port`; Chrome 136+ disables CDP on the default
profile; `CUA_DRIVER_CDP_PORT` unset). Fixed in `dd0e918`: entrypoint autostarts a
CDP Chrome on a dedicated `--user-data-dir` and exports `CUA_DRIVER_CDP_PORT=9222`.
Verified end-to-end on a clean rebuild cold boot — cua-driver `page`
`execute_javascript` read example.com's `<h1>` ("Example Domain") over CDP. Gate:
`scripts/verify-cdp.sh`.

Also fixed this session: "Untrusted application launcher" dialog on every icon
launch (`f182582` — set `metadata::xfce-exe-checksum`, which XFCE 4.18 actually
checks, not just the ignored `metadata::trusted`).

**Net:** the **browser-automation** path of `computer_use` works; **native GTK
desktop typing does not** (cua-driver XSendEvent/AT-SPI vs GtkSourceView) and needs
an upstream cua-driver input fix (XTest) or GTK AT-SPI text exposure.

---

## Correction — 2026-06-29 (driver-level reverse-engineering; supersedes the mechanism above)

Re-investigated by driving cua-driver 0.6.8 directly against a live Mousepad and
walking the AT-SPI tree. The earlier "GtkSourceView text widget is not exposed in the
AT-SPI tree" claim is **wrong** — the widget *is* exposed. Verified facts:

- A raw AT-SPI walk of a focused Mousepad finds the editor as a `text` accessible
  implementing **both `Text` and `EditableText`** (depth 6, under
  `page tab list → page tab → scroll pane`).
- cua-driver's own `get_window_state` walker, however, **never enumerates that node**.
  Its `elements` array (and `tree_markdown`) contain only the menubar (221 menu items
  + 20 menus) and 15 toolbar buttons — so the model is never handed an
  `element_index`/`element_token` for the text area. (`query` doesn't surface it either.)
- All cua-driver actuation on Linux is **XSendEvent** (synthetic, `send_event=true`,
  "no focus steal") — for clicks *and* keys. GTK ignores these. Confirmed A/B at
  identical window-local coordinates: a cua-driver `click` (XSendEvent) does **not**
  focus the GtkSourceView (the lazily-created `text` accessible never appears); an
  `xdotool` click (XTest) at the same point **does** (the node appears).
  `GDK_CORE_DEVICE_EVENTS=1` does not change this.
- The `text` accessible is created **lazily** — it doesn't exist until the widget gets
  real (XTest) focus. Hence a deadlock: cua-driver can't focus the editor (its click is
  ignored), and without focus there's no AT-SPI element to type into, so `type_text`
  falls back to `"path": "key_events"` (XSendEvent) → nothing lands.
- **Once the widget is focused out-of-band (an XTest click), it works**: `type_text`
  (no element) reports `"path": "ax"` and the text actually lands — verified by reading
  the widget's content back over AT-SPI (`EditableText`).
- The binary contains a `platform_linux::input::send_type_text_xtest` symbol, but it's
  reserved (terminal emulators use pty/XTest) and there is no config/env toggle
  (`cua-driver config` exposes only capture_mode/pip/image; no input-strategy
  `CUA_DRIVER_RS_*` var) to force it for GTK editors.

**Net (corrected):** native GTK typing fails because of **two cua-driver gaps** — its
AT-SPI walker doesn't surface the editor element in `get_window_state`, and its
XSendEvent-only input is ignored by GTK (so it can neither focus nor type into the
editor). The AT-SPI typing path itself is sound once focus exists. Fix is upstream:
surface the text element in `get_window_state`, and/or route GTK editors through the
existing `send_type_text_xtest` path (or expose an XTest toggle). Repro scripts used
for this correction live in the session scratchpad (AT-SPI walk + cua-driver A/B).

---

## Deeper root cause — 2026-06-30 (it's the X server: Xvnc rejects uinput)

The proximate cause above ("cua-driver uses XSendEvent, which GTK ignores") is real,
but the *reason* cua-driver uses XSendEvent here is **environmental — the X server.**
cua-driver's own diagnostic string (extracted from the 0.6.8 binary) says it outright:

> `server is Xtigervnc. Xtigervnc exposes only its built-in VNC/XTEST devices, so`
> `Linux uinput/libinput pointers cannot become real X input devices in this`
> `environment.` (and: `parallel_mouse_drag is not supported on this server`)

cua-driver's native Linux input path is a **`uinput` virtual input device** (it links
`evdev::uinput::VirtualDevice`). On a standard Xorg session, libinput/evdev picks up
that uinput device as a **real X input device** → events look real → GTK accepts them
→ typing/clicks work (this is what upstream docs mean by Linux = "XTest (X11)"). But
**TigerVNC's `Xvnc` does not read `/dev/uinput` devices** — it only has its own
built-in VNC/XTEST input — so cua-driver's uinput device "cannot become a real X input
device," and it falls back to **XSendEvent**, which GTK ignores. That is the whole bug.

Evidence gathered this session:
- `xdpyinfo` on `:1` lists the **XTEST** extension, and `xdotool` (which uses XTest)
  *does* focus + type here — so XTEST works on Xvnc. cua-driver simply does **not** use
  XTEST as its input fallback (uinput → XSendEvent, never XTEST).
- cua-driver `doctor` reports `display server: X11`, `AT-SPI reachable`, and its X11
  input plan is self-described as **"AT-SPI + XSendEvent input will work"** — i.e. it
  never intended XTest on this server.

**Implication / fix direction:** the clean fix is to **replace the X server** — run a
real `Xorg` (headless via the `dummy` video driver) with `libinput`, served over VNC
by `x11vnc`/`x0vncserver`, instead of TigerVNC's `Xvnc`. Then cua-driver's uinput path
attaches as real input and typing/dragging work natively (no focus-assist hack).
Requirements/caveats: the container needs **`/dev/uinput`** access (`--device
/dev/uinput`, host `uinput` module loaded, write permission for the session user), and
the RDP→`:1`/dashboard/persistence topology has to be re-wired off `Xvnc`. The
lighter alternative is the verified **focus-assist** workaround (XTest click to focus,
which works because XTEST is present on Xvnc) — narrower (GUI editors only), no
`/dev/uinput` needed.
