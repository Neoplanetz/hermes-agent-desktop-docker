# Real-usage demo — screenshots + live agent-browse GIF (READMEs + Docker Hub)

- **Date:** 2026-07-01
- **Status:** Proposed (awaiting review)
- **Repo:** hermes-agent-desktop-docker

## 1. Context & decision

The public repo's docs are thorough (4-language READMEs, architecture SVGs, bundled-version
tables, beginner's guides) but carry **no visual proof the product actually works** — a
reader can't see the Hermes agent driving Chrome, the desktop, or the dashboard. For a
public image whose value is "secure zero-privilege CDP browser automation," a real-usage
demo is the most conspicuous remaining gap.

**Decision:** add a **hybrid** demo — a guaranteed set of **static screenshots** plus a
**best-effort live agent-browse GIF** — captured from the already-running, healthy
`hermes-desktop` container, and embedded in all four READMEs (en/ko/ja/zh) and the Docker
Hub Overview. The static screenshots are the guaranteed deliverable; the GIF is best-effort
and the demo ships static-only if the live capture can't be produced.

## 2. Goals (in scope)

- **Static screenshots (guaranteed):** 3–4 PNGs of the real running environment — the NoVNC
  XFCE desktop with Chrome + the Hermes trusted shortcuts, the Hermes dashboard (`:9119`),
  and the CDP-driven Chrome.
- **Live agent-browse GIF (best-effort):** one short animated GIF of the **real LLM agent**
  (free Nous `stepfun/step-3.7-flash:free`, vision+tools) driving Chrome via `/browser`,
  visible on the desktop.
- **Embed in all 4 READMEs + Docker Hub Overview**, reusing one shared set of asset files.
- **Capture from the live container** (no rebuild/reboot — it is up and healthy).

## 3. Non-goals (YAGNI)

- **Video/MP4/WebM.** Docker Hub markdown does not render video and GitHub README `<img>`
  can't embed it portably. GIF is the only format that renders via `![](…)` on both.
- **Per-language localized screenshots.** Captures show the (English) app UI and are reused
  across all four READMEs unchanged; only the surrounding section heading/prose is localized
  (screenshots are language-agnostic, unlike the architecture SVGs which carry translatable
  labels).
- **Image annotations / callouts / composited frames.** Ship raw captures; annotation can be
  a later polish pass.
- **A scripted model-less fallback capture.** If the live agent GIF can't be produced, the
  demo ships static-only rather than substituting a synthetic browser script.

## 4. Architecture / method

### 4.1 Capture from the live container (ffmpeg x11grab)

All capture is `ffmpeg` grabbing the X display `:1` **as the session user**, per the repo's
documented technique (`docker exec -u hermes -e DISPLAY=:1 … ffmpeg -f x11grab`). NoVNC
resizes `:1` dynamically, so each capture first reads the current geometry
(`xdpyinfo | awk '/dimensions/{print $2}'`) and passes it to `-video_size`.

- **Still:** `ffmpeg -y -f x11grab -video_size <WxH> -i :1 -frames:v 1 <out>.png`.
- **GIF (two-pass palette for quality, then shrink):**
  `ffmpeg -y -f x11grab -video_size <WxH> -framerate <fps> -t <dur> -i :1 -vf "fps=<fps>,scale=<w>:-1:flags=lanczos,palettegen" /tmp/pal.png`
  then `ffmpeg … -i :1 -i /tmp/pal.png -lavfi "fps=<fps>,scale=<w>:-1:flags=lanczos[x];[x][1:v]paletteuse" out.gif`,
  then `gifsicle -O3 --lossy=80 out.gif -o out.gif`. Target ≤ ~8 MB (fps 8–12, width
  ~960–1200, duration ~15–25 s).
- **Rejected alternative:** driving NoVNC via Playwright to screenshot — more moving parts
  and lower fidelity than grabbing `:1` directly with the tooling already present
  (ffmpeg + gifsicle).

### 4.2 Static screenshots (guaranteed) — `assets/`

- `demo-desktop.png` — NoVNC XFCE desktop: Chrome open + the Hermes Terminal/Setup/Dashboard
  trusted shortcuts.
- `demo-dashboard.png` — the Hermes dashboard at `127.0.0.1:9119`.
- `demo-browser-cdp.png` — the CDP-driven Chrome showing a real page.
- `demo-terminal.png` *(optional)* — a Hermes CLI session.

Each is grabbed after arranging the desktop (launch Chrome / open the dashboard / focus the
target window) so the frame shows the intended UI.

### 4.3 Live agent-browse GIF (best-effort) — `assets/demo-agent-browse.gif`

Prerequisite (interactive, user-run): the maintainer authenticates the free Nous model
inside the container — `hermes auth add nous --type oauth` (device-code: visit URL + enter
code) — and the config is set to `provider: nous`, `model: stepfun/step-3.7-flash:free`. The
implementer pauses and hands this step to the user (the plan makes this an explicit gate).

Scenario: issue one short, visually clear browse task (e.g. "open a specific page and
summarize its top item") so Chrome visibly navigates on `:1`; capture ~15–25 s; convert to
an optimized GIF per §4.1.

### 4.4 Assets + doc placement

- Files live under `assets/`: `demo-desktop.png`, `demo-dashboard.png`,
  `demo-browser-cdp.png`, optional `demo-terminal.png`, `demo-agent-browse.gif`.
- A new **"See it in action"** section is added near the top of each README (after the intro/
  badges, around the existing architecture-diagram area), heading localized per language,
  using **relative** asset paths (`assets/demo-*.png|gif`) so GitHub renders them.
- The same section is added to `DOCKERHUB_OVERVIEW.md` using **raw GitHub URLs**
  (`https://raw.githubusercontent.com/Neoplanetz/hermes-agent-desktop-docker/main/assets/demo-*`)
  — identical to the architecture-SVG embed pattern; renders on Docker Hub because the repo
  is public. The `dockerhub-description.yml` Action auto-syncs the Overview on push.

## 5. Graceful degradation / risks

- **Live GIF fails** (login declined, model latency/flakiness, capture timing) → **ship
  static-only**: the "See it in action" section renders the screenshots; the GIF line is
  simply omitted. The hybrid is designed to degrade to the guaranteed stills.
- **NoVNC dynamic resolution** → read `:1` geometry immediately before each grab.
- **GIF too large for comfortable README/Hub load** → lower fps/width/duration and re-run
  `gifsicle --lossy`; keep ≤ ~8 MB.
- **Raw URLs 404 on Docker Hub** → only a risk if the repo were private; it is public and
  raw serves `image/svg+xml`/`image/png`/`image/gif` (verified pattern from the SVGs). The
  raw URLs resolve only after the assets are pushed to `main`.

## 6. Conventions / guardrails

- Assets in `assets/` alongside the architecture SVGs; kebab-case `demo-*` names.
- READMEs: relative paths (GitHub-native). Docker Hub Overview: absolute raw URLs (Hub can't
  resolve relative paths) — matches the established SVG/guide-link pattern.
- No new build step, workflow, or dependency; capture uses the already-present
  ffmpeg + gifsicle and the already-running container.

## 7. Verification (how we know it works)

- **Each PNG:** open/inspect it — non-empty, correct resolution, shows the intended UI
  (desktop/dashboard/Chrome).
- **GIF (if produced):** plays, shows Chrome navigating, ≤ ~8 MB.
- **READMEs:** the "See it in action" section is present in all four with the correct
  (relative) asset references; structure stays consistent with the other sections.
- **Docker Hub:** after push to `main`, the Action run is green and the live Overview
  (`hub.docker.com/v2/repositories/neoplanetz/hermes-desktop-docker/`) `full_description`
  contains the demo section; the raw asset URLs return 200 with an image content-type.

## 8. Defaults (adjustable in the plan)

- **Screenshot set:** the three core stills (desktop, dashboard, Chrome); `demo-terminal.png`
  optional.
- **GIF budget:** fps 8–12, width ~960–1200, duration ~15–25 s, ≤ ~8 MB.
- **README section title:** "See it in action" (localized per language).
