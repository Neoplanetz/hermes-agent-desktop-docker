# Real-usage demo — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Note on execution:** Tasks 1–2 (media capture) are controller/interactive — they drive the live `hermes-desktop` container and (Task 2) gate on a user-run login; they are NOT autonomous-subagent-friendly. Tasks 3–4 (doc edits) are subagent-friendly. Inline execution is the natural fit; the doc edits may be fanned to parallel subagents.

**Goal:** Add a real-usage demo — guaranteed static screenshots plus a best-effort live agent-browse GIF, captured from the running container — to all four READMEs and the Docker Hub Overview.

**Architecture:** Capture the X display `:1` of the already-running, healthy `hermes-desktop` container with `ffmpeg -f x11grab` (stills via `-frames:v 1`; GIF via two-pass palette + `gifsicle` shrink). Store PNG/GIF assets under `assets/`. Embed a "See it in action" section in `README.md`/`.ko`/`.ja`/`.zh` (relative paths) and `DOCKERHUB_OVERVIEW.md` (absolute raw URLs). The GIF is best-effort; the demo ships static-only if it can't be produced.

**Tech Stack:** ffmpeg (x11grab), gifsicle, Docker (`exec`/`cp` against the live container), Chrome DevTools Protocol (`:9222`), Hermes CLI, Markdown.

## Global Constraints

- **Capture source:** the running `hermes-desktop` container's display `:1`, as user `hermes`, via `docker exec -u hermes -e DISPLAY=:1 hermes-desktop … ffmpeg -f x11grab`. Read `:1` geometry first — `xdpyinfo | awk '/dimensions:/{print $2}'` (currently `1920x1080`; NoVNC may resize, so read it, don't hardcode). Copied from spec §4.1.
- **Guaranteed vs best-effort:** the static screenshots (desktop, dashboard, CDP Chrome) MUST ship; the live agent-browse GIF is best-effort → if it can't be produced, ship static-only (omit the GIF, do not block). Copied from spec §1/§2/§5.
- **GIF budget:** ≤ ~8 MB via ffmpeg two-pass palette (`palettegen`/`paletteuse`, `scale=…:flags=lanczos`) + `gifsicle -O3 --lossy=80`; fps 8–12, width ~960–1200, duration ~15–25 s. Copied from spec §4.1/§8.
- **Asset naming/paths:** under `assets/`, kebab-case `demo-*`. READMEs use **relative** `assets/demo-*` paths; `DOCKERHUB_OVERVIEW.md` uses **absolute raw URLs** `https://raw.githubusercontent.com/Neoplanetz/hermes-agent-desktop-docker/main/assets/demo-*`. Copied from spec §4.4/§6.
- **Language-agnostic captures:** the same PNG/GIF assets are reused across all four READMEs unchanged; only the section heading and one-line caption are localized. Section title "See it in action". Copied from spec §3/§8.
- **Live GIF prerequisite (interactive, USER-run):** `docker exec -it hermes-desktop bash -lc 'hermes auth add nous --type oauth'` (device-code login) + config `provider: nous`, `model: stepfun/step-3.7-flash:free`. Copied from spec §4.3.
- **No new build step, workflow, or dependency** — use the present ffmpeg + gifsicle and the running container. Copied from spec §6.
- **Insertion point:** the new `## See it in action` section goes immediately after the `## Architecture` block and before `## What's Included` in every README.

---

### Task 1: Capture the static screenshots → `assets/demo-*.png`

**Files:**
- Create: `assets/demo-desktop.png`, `assets/demo-dashboard.png`, `assets/demo-browser-cdp.png`

**Interfaces:**
- Consumes: the running `hermes-desktop` container (display `:1`, Chrome on CDP `:9222`, dashboard on `:9119`).
- Produces: three PNG files under `assets/`, each at the `:1` resolution, showing the intended UI. Tasks 3–4 embed them.

- [ ] **Step 1: Read the live `:1` geometry**

```bash
GEO=$(docker exec -u hermes -e DISPLAY=:1 hermes-desktop bash -lc 'xdpyinfo | awk "/dimensions:/{print \$2}"')
echo "GEO=$GEO"   # expect e.g. 1920x1080
```

- [ ] **Step 2: Stage the CDP Chrome on a real, content-rich page**

Open a real page via the CDP HTTP endpoint so the browser shot isn't `about:blank` (both verb forms — newer Chrome wants `PUT`, older accepts `GET`):

```bash
docker exec hermes-desktop bash -lc 'curl -s -X PUT "http://127.0.0.1:9222/json/new?https://news.ycombinator.com" >/dev/null || curl -s "http://127.0.0.1:9222/json/new?https://news.ycombinator.com" >/dev/null'
sleep 3
```

The goal is a captured frame showing a real page, not `about:blank`. If the new tab doesn't come to the foreground on `:1`, activate it via the endpoint (`curl -s "http://127.0.0.1:9222/json/activate/<targetId>"`, id from `curl -s http://127.0.0.1:9222/json`) — or arrange the window by hand. This staging is hands-on; the Step 4 visual check is the gate.

- [ ] **Step 3: Capture the three stills**

```bash
# whole-desktop shot (Chrome + Hermes shortcuts visible)
docker exec -u hermes -e DISPLAY=:1 hermes-desktop bash -lc "ffmpeg -y -f x11grab -video_size $GEO -i :1 -frames:v 1 /tmp/demo-desktop.png"

# dashboard shot — point Chrome at the dashboard, then grab
docker exec hermes-desktop bash -lc 'curl -s "http://127.0.0.1:9222/json/new?http://127.0.0.1:9119" >/dev/null'; sleep 3
docker exec -u hermes -e DISPLAY=:1 hermes-desktop bash -lc "ffmpeg -y -f x11grab -video_size $GEO -i :1 -frames:v 1 /tmp/demo-dashboard.png"

# CDP-Chrome shot — re-stage the content page, then grab
docker exec hermes-desktop bash -lc 'curl -s "http://127.0.0.1:9222/json/new?https://news.ycombinator.com" >/dev/null'; sleep 3
docker exec -u hermes -e DISPLAY=:1 hermes-desktop bash -lc "ffmpeg -y -f x11grab -video_size $GEO -i :1 -frames:v 1 /tmp/demo-browser-cdp.png"

# copy out to assets/
for f in demo-desktop demo-dashboard demo-browser-cdp; do docker cp "hermes-desktop:/tmp/$f.png" "assets/$f.png"; done
```

- [ ] **Step 4: Verify each PNG (visual + structural)**

```bash
for f in demo-desktop demo-dashboard demo-browser-cdp; do
  ls -l "assets/$f.png"
  python3 -c "import struct;d=open('assets/$f.png','rb').read();print('$f', 'PNG' if d[:8]==b'\x89PNG\r\n\x1a\n' else 'NOT-PNG', struct.unpack('>II',d[16:24]))"
done
```
Expected: each file present, `PNG`, dimensions == `$GEO`, filesize non-trivial (tens–hundreds of KB). **Then open each PNG (Read the image) and confirm it visually shows the intended UI** — desktop with Chrome+shortcuts, the dashboard, and the CDP Chrome on a real page. Re-stage + re-grab any shot that looks wrong (e.g. `about:blank`, a dialog, wrong window focused).

- [ ] **Step 5: Commit**

```bash
git add assets/demo-desktop.png assets/demo-dashboard.png assets/demo-browser-cdp.png
git commit -m "docs(demo): add static screenshots (desktop, dashboard, CDP Chrome)"
```

---

### Task 2: Capture the live agent-browse GIF (BEST-EFFORT) → `assets/demo-agent-browse.gif`

**Files:**
- Create (best-effort): `assets/demo-agent-browse.gif`

**Interfaces:**
- Consumes: the running container + a user-authenticated Nous model.
- Produces: `assets/demo-agent-browse.gif` (≤ ~8 MB) **or** a recorded SKIP (then Tasks 3–4 omit the GIF).

- [ ] **Step 1: GATE — user authenticates the free Nous model (interactive)**

Hand this to the user (device-code login needs a real TTY; the `!`-prefix session shell works):

```
! docker exec -it hermes-desktop bash -lc 'hermes auth add nous --type oauth'
```
They visit the printed URL, enter the code, and confirm. Then set the model:
```bash
docker exec -u hermes hermes-desktop bash -lc "sed -i 's|^\(\s*model:\).*|\1 stepfun/step-3.7-flash:free|; s|^\(\s*provider:\).*|\1 nous|' ~/.hermes/config.yaml 2>/dev/null; grep -iE 'provider|model' ~/.hermes/config.yaml"
```
**If the user declines or login fails → SKIP to Step 5 (record skip; ship static-only).**

- [ ] **Step 2: Sanity-check the model answers (non-interactive)**

```bash
docker exec -u hermes hermes-desktop bash -lc 'timeout 60 hermes run "Reply with the single word: ready" 2>&1 | tail -3'
```
Expected: a short model reply (proves creds+model work). If it errors/times out → SKIP to Step 5.

- [ ] **Step 3: Record `:1` while the agent browses**

```bash
GEO=$(docker exec -u hermes -e DISPLAY=:1 hermes-desktop bash -lc 'xdpyinfo | awk "/dimensions:/{print \$2}"')
# start a ~22s screen recording in the background
docker exec -u hermes -e DISPLAY=:1 hermes-desktop bash -lc "ffmpeg -y -f x11grab -video_size $GEO -framerate 12 -t 22 -i :1 /tmp/demo.mp4" &
sleep 1
# issue a short, visually clear browse task so Chrome navigates on-screen
docker exec -u hermes -e DISPLAY=:1 hermes-desktop bash -lc 'timeout 90 hermes run "Use the browser to open https://news.ycombinator.com and tell me the current top story title." 2>&1 | tail -5'
wait
docker cp hermes-desktop:/tmp/demo.mp4 /tmp/demo.mp4
```

- [ ] **Step 4: Convert to an optimized GIF (two-pass palette + gifsicle)**

```bash
ffmpeg -y -i /tmp/demo.mp4 -vf "fps=10,scale=1000:-1:flags=lanczos,palettegen" /tmp/pal.png
ffmpeg -y -i /tmp/demo.mp4 -i /tmp/pal.png -lavfi "fps=10,scale=1000:-1:flags=lanczos[x];[x][1:v]paletteuse" /tmp/demo.gif
gifsicle -O3 --lossy=80 /tmp/demo.gif -o assets/demo-agent-browse.gif
ls -l assets/demo-agent-browse.gif
```
If > ~8 MB: re-run with lower `fps` (8), narrower `scale` (900), or shorter input (`-t 16`), and/or `--lossy=100`.

- [ ] **Step 5: Verify or record SKIP**

If produced:
```bash
python3 -c "d=open('assets/demo-agent-browse.gif','rb').read();print('GIF' if d[:6] in (b'GIF89a',b'GIF87a') else 'NOT-GIF', len(d),'bytes')"
ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 assets/demo-agent-browse.gif
```
Expected: `GIF`, ≤ ~8 MB, frames > 1. **Open the GIF (Read it) and confirm it shows Chrome navigating.**

If SKIPPED: note "live GIF skipped — <reason>; shipping static-only" in the task report/ledger. Tasks 3–4 then omit the GIF block.

- [ ] **Step 6: Commit (only if produced)**

```bash
git add assets/demo-agent-browse.gif
git commit -m "docs(demo): add live agent-browse GIF"
```

---

### Task 3: Add "See it in action" to the four READMEs (relative paths)

**Files:**
- Modify: `README.md`, `README.ko.md`, `README.ja.md`, `README.zh.md`

**Interfaces:**
- Consumes: the assets from Tasks 1–2 (`assets/demo-desktop.png`, `demo-dashboard.png`, `demo-browser-cdp.png`, and — if produced — `demo-agent-browse.gif`).
- Produces: a `## See it in action` section in each README, inserted after `## Architecture` and before `## What's Included`.

- [ ] **Step 1: Insert the section in `README.md` (English canonical), after the `## Architecture` block, before `## What's Included`**

```markdown
## See it in action

<p align="center">
  <img src="assets/demo-agent-browse.gif" width="800" alt="Hermes agent driving Chrome via the DevTools Protocol, watched over NoVNC" />
</p>

The Hermes agent drives a real Chrome over the Chrome DevTools Protocol (loopback-only), watched live over NoVNC — the same desktop you connect to.

<p align="center">
  <img src="assets/demo-desktop.png" width="32%" alt="XFCE desktop with Chrome and the Hermes trusted shortcuts" />
  <img src="assets/demo-dashboard.png" width="32%" alt="The Hermes dashboard" />
  <img src="assets/demo-browser-cdp.png" width="32%" alt="CDP-driven Chrome showing a live page" />
</p>
```

**If the GIF was SKIPPED in Task 2, omit the first `<p align="center">…gif…</p>` block and the sentence's "— the same desktop you connect to" stays; keep the three screenshots.**

- [ ] **Step 2: Replicate in `README.ko.md` / `.ja.md` / `.zh.md` with a localized heading + caption**

Same markdown and asset paths; translate only the heading and the one-line caption:

- `README.ko.md`: heading `## 실제 동작 보기`; caption `Hermes 에이전트가 Chrome DevTools Protocol(루프백 전용)로 실제 Chrome을 구동하며, 접속하는 바로 그 데스크톱을 NoVNC로 실시간 확인합니다.`
- `README.ja.md`: heading `## 実際の動作`; caption `Hermes エージェントが Chrome DevTools Protocol（ループバック専用）で実際の Chrome を操作し、接続するのと同じデスクトップを NoVNC でライブ表示します。`
- `README.zh.md`: heading `## 实际运行效果`; caption `Hermes 智能体通过 Chrome DevTools Protocol（仅回环）驱动真实的 Chrome，并通过 NoVNC 实时呈现你所连接的同一桌面。`

(These three files are independent — they may be edited by parallel subagents.)

- [ ] **Step 3: Verify all four READMEs**

```bash
for f in README.md README.ko.md README.ja.md README.zh.md; do
  echo "== $f =="
  grep -c 'assets/demo-desktop.png\|assets/demo-dashboard.png\|assets/demo-browser-cdp.png' "$f"   # expect 3 (or the count matching present assets)
  grep -nE 'See it in action|실제 동작 보기|実際の動作|实际运行效果' "$f"   # expect exactly 1 heading
done
```
Expected: each README has exactly one demo heading and references all three screenshots (plus the GIF if produced). Confirm the section sits between `## Architecture` and `## What's Included`.

- [ ] **Step 4: Commit**

```bash
git add README.md README.ko.md README.ja.md README.zh.md
git commit -m "docs(demo): add 'See it in action' section to all 4 READMEs"
```

---

### Task 4: Add "See it in action" to `DOCKERHUB_OVERVIEW.md` (raw URLs) + push acceptance

**Files:**
- Modify: `DOCKERHUB_OVERVIEW.md`

**Interfaces:**
- Consumes: the same assets, referenced by absolute raw URL.
- Produces: the demo section in the Hub Overview; after push to `main` the `dockerhub-description.yml` Action syncs it live.

- [ ] **Step 1: Insert the section with ABSOLUTE raw URLs**

Place it in the same relative position the READMEs use (after the architecture diagram). Use the exact raw-URL base `https://raw.githubusercontent.com/Neoplanetz/hermes-agent-desktop-docker/main/assets/`:

```markdown
## See it in action

<p align="center">
  <img src="https://raw.githubusercontent.com/Neoplanetz/hermes-agent-desktop-docker/main/assets/demo-agent-browse.gif" width="800" alt="Hermes agent driving Chrome via the DevTools Protocol, watched over NoVNC" />
</p>

The Hermes agent drives a real Chrome over the Chrome DevTools Protocol (loopback-only), watched live over NoVNC — the same desktop you connect to.

<p align="center">
  <img src="https://raw.githubusercontent.com/Neoplanetz/hermes-agent-desktop-docker/main/assets/demo-desktop.png" width="32%" alt="XFCE desktop with Chrome and the Hermes trusted shortcuts" />
  <img src="https://raw.githubusercontent.com/Neoplanetz/hermes-agent-desktop-docker/main/assets/demo-dashboard.png" width="32%" alt="The Hermes dashboard" />
  <img src="https://raw.githubusercontent.com/Neoplanetz/hermes-agent-desktop-docker/main/assets/demo-browser-cdp.png" width="32%" alt="CDP-driven Chrome showing a live page" />
</p>
```

**If the GIF was SKIPPED, omit its `<p>` block (keep the three screenshots).**

- [ ] **Step 2: Verify**

```bash
grep -c 'raw.githubusercontent.com/Neoplanetz/hermes-agent-desktop-docker/main/assets/demo-' DOCKERHUB_OVERVIEW.md   # expect 3 or 4
grep -n 'See it in action' DOCKERHUB_OVERVIEW.md   # expect 1
```

- [ ] **Step 3: Commit**

```bash
git add DOCKERHUB_OVERVIEW.md
git commit -m "docs(demo): add 'See it in action' to Docker Hub overview (raw URLs)"
```

- [ ] **Step 4: Acceptance — after the branch is merged/pushed to `main`**

The raw URLs resolve only once the assets are on `main`. After merge/push:
```bash
for a in demo-desktop.png demo-dashboard.png demo-browser-cdp.png demo-agent-browse.gif; do
  code=$(curl -s -o /dev/null -w '%{http_code} %{content_type}' "https://raw.githubusercontent.com/Neoplanetz/hermes-agent-desktop-docker/main/assets/$a"); echo "$a -> $code"
done
gh run list --workflow="Sync Docker Hub description" --branch main --limit 1
```
Expected: each present asset returns `200 image/png` (or `image/gif`); the Sync Action run is green; the live Hub Overview `full_description` contains "See it in action" (check `gh api repos/Neoplanetz/hermes-agent-desktop-docker` → Docker Hub API, or the Hub page). A SKIPPED GIF simply 404s and isn't referenced.

---

## Notes / assumptions

- **Screenshot staging is hands-on.** Getting Chrome to foreground a real page for the stills may need manual adjustment (activate the right tab/window); the commands above are the mechanism, not a guarantee. The verification step (open the PNG) is the gate.
- **The GIF is best-effort and gated on a user login.** Do not block the demo on it — Tasks 3–4 are written to degrade to static-only.
- **NoVNC dynamic resize:** always read `$GEO` immediately before a capture; do not hardcode `1920x1080`.
- **Chrome `/json/new?<url>` behavior varies by version.** If the HTTP endpoint won't navigate the visible tab, drive `Page.navigate` over the target's `webSocketDebuggerUrl` with a short Node script, or arrange the page by hand — the only requirement is that the captured frame shows a real page.
