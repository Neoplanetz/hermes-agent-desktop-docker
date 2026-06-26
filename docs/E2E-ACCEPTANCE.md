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
