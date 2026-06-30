# Codex Fix 3 Report

**Date:** 2026-06-30
**Branch:** main
**Prior defect commit:** 9e8521f (2nd Codex review fix)
**Fix commit:** see git log

---

## Edit 1 (CRITICAL) — entrypoint.sh: Surgical .xprofile line removal

### Exact old a11y lines (from commit 8586936)
Found in `entrypoint.sh` at the AT-SPI / accessibility block (lines written via `cat > /home/$USER/.xprofile <<'EOF'`):
```
export GTK_MODULES=atk-bridge
export QT_ACCESSIBILITY=1
export NO_AT_BRIDGE=0
export OOO_FORCE_DESKTOP=gnome
```

### Change made
Replaced the whole-file-delete:
```bash
su - "$USER" -c 'if [ -f ~/.xprofile ] && grep -qE "atk-bridge|NO_AT_BRIDGE|QT_ACCESSIBILITY" ~/.xprofile; then rm -f ~/.xprofile; fi'
```
With surgical per-line removal anchored to exact values:
```bash
su - "$USER" -c 'if [ -f ~/.xprofile ]; then
  sed -i -E "/^export GTK_MODULES=atk-bridge$/d; /^export QT_ACCESSIBILITY=1$/d; /^export NO_AT_BRIDGE=0$/d; /^export OOO_FORCE_DESKTOP=gnome$/d" ~/.xprofile
  grep -qE "[^[:space:]]" ~/.xprofile || rm -f ~/.xprofile
fi'
```
File is only deleted if nothing but whitespace remains after the surgical removal.

### Surgical-test result
Planted test file:
```
export GTK_MODULES=atk-bridge
export QT_ACCESSIBILITY=1
export NO_AT_BRIDGE=0
export OOO_FORCE_DESKTOP=gnome
export USER_CUSTOM=keepme
```

After `docker compose up -d --force-recreate` and healthy, `cat ~/.xprofile` returned:
```
export USER_CUSTOM=keepme
```
The 4 a11y lines were removed. `export USER_CUSTOM=keepme` SURVIVED. File was NOT deleted because a non-whitespace line remained. Test artifact then cleaned up with `rm -f ~/.xprofile`.

---

## Edit 2 (IMPORTANT) — scripts/verify-quiet-boot.sh: dpkg format false-green fix

### Problem
```bash
docker exec "$C" sh -c 'dpkg-query -W -f="${Status}" at-spi2-core 2>/dev/null | grep -q "install ok installed"'
```
The inner `sh -c` expanded `${Status}` (unset variable → empty string), so dpkg received an empty format and always reported the package absent — a permanent false-green.

### Fix
Dropped `sh -c` wrapper so single-quoted `${Status}` reaches dpkg literally:
```bash
docker exec "$C" dpkg-query -W -f='${Status}' at-spi2-core 2>/dev/null | grep -q "install ok installed" \
  && { echo "  FAIL at-spi2-core still installed"; exit 1; } || echo "  OK at-spi2-core absent"
```

### dpkg format evidence
```
$ docker exec hermes-desktop dpkg-query -W -f='${Status}' bash
install ok installed

$ docker exec hermes-desktop dpkg-query -W -f='${Status}' at-spi2-core 2>/dev/null
unknown ok not-installed
```
`bash` → `install ok installed` confirms the `${Status}` format directive is honored (not empty).  
`at-spi2-core` → `unknown ok not-installed` does NOT match `"install ok installed"`, so the gate correctly reports it absent.

---

## Edit 3 (MINOR) — scripts/verify-persistence.sh: Stronger seed assertion

### Change made
```bash
# Before:
echo "[verify-persistence] template-seeded files present on this volume?"
docker exec "$C" su - "$U" -c 'test -f ~/.vnc/xstartup' \
  && echo "  OK seeded" || { echo "  FAIL not seeded"; exit 1; }

# After:
echo "[verify-persistence] VNC startup + seeded ~/.hermes/config.yaml present?"
docker exec "$C" su - "$U" -c 'test -f ~/.vnc/xstartup && test -f ~/.hermes/config.yaml' \
  && echo "  OK seeded" || { echo "  FAIL not seeded"; exit 1; }
```
`xstartup` is rewritten every boot — weak evidence of a seeded volume. `~/.hermes/config.yaml` is seeded from `/opt/hermes-defaults` on first boot and persists, making this a genuine template-seed assertion.

---

## Verification Results

### bash -n syntax check
```
bash -n entrypoint.sh scripts/verify-quiet-boot.sh scripts/verify-persistence.sh
→ exit 0 (OK)
```

### docker build
```
→ success (hermes-desktop:latest built)
```

### docker compose up -d --force-recreate
```
→ Container hermes-desktop healthy
```

### Gate results (all 5 PASS)

| Gate | Result |
|------|--------|
| verify-quiet-boot.sh | PASS |
| verify-persistence.sh hermes-desktop | PASS |
| verify-config-seed.sh hermes-desktop | PASS |
| verify-gonogo.sh hermes-desktop | PASS |
| verify-cdp.sh hermes-desktop | PASS |

**verify-e2e.sh: NOT run (excluded per instructions)**
