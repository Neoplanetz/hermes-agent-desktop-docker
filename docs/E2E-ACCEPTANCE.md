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
