#!/bin/bash
set -euo pipefail

USER="${HERMES_USER:-hermes}"
PASSWORD="${HERMES_PASSWORD:-hermes123}"
VNC_RESOLUTION="${VNC_RESOLUTION:-1920x1080}"
VNC_COL_DEPTH="${VNC_COL_DEPTH:-24}"

# ── Input validation (USER/PASSWORD are interpolated into su/chpasswd) ──
if ! [[ "$USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    echo "FATAL: invalid HERMES_USER '$USER' (must match ^[a-z_][a-z0-9_-]{0,31}$)"; exit 1
fi
case "$PASSWORD" in
    *[$'\n\r:']*) echo "FATAL: HERMES_PASSWORD contains newline, CR, or colon"; exit 1 ;;
esac

# Warn loudly when the published dev-default password is in use — it is PUBLICLY
# KNOWN and is the single credential for VNC, RDP, and the web dashboard.
if [ "$PASSWORD" = "hermes123" ]; then
    echo "WARNING: HERMES_PASSWORD is the default 'hermes123' (publicly known). Set a strong HERMES_PASSWORD in .env before exposing VNC/RDP/dashboard beyond 127.0.0.1." >&2
fi

# ── Dynamic user creation (so HERMES_USER from env takes effect) ──
# The image bakes 'hermes' (uid 1000) as the template account. If a different
# HERMES_USER is requested, create it at runtime and seed its home from the
# build-time template (Task 2 installs /opt/hermes-defaults).
if ! id "$USER" &>/dev/null; then
    echo ">> Creating user '$USER'..."
    useradd -m -s /bin/bash "$USER"
    usermod -aG sudo "$USER"
    SUDOERS_TMP=$(mktemp)
    echo "$USER ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_TMP"
    if visudo -c -f "$SUDOERS_TMP" >/dev/null; then
        mv "$SUDOERS_TMP" /etc/sudoers.d/"$USER"; chmod 0440 /etc/sudoers.d/"$USER"
    else
        rm -f "$SUDOERS_TMP"; echo "FATAL: sudoers entry failed visudo"; exit 1
    fi
fi
# Always sync password (handles password-only changes without rebuild)
echo "$USER:$PASSWORD" | chpasswd

# ── First-boot home seed (volume-shadow fix) ──
# A fresh named volume mounts empty over /home/$USER, shadowing image content.
# Seed from the build-time template only when the home looks empty.
if [ -d /opt/hermes-defaults ] && [ ! -e "/home/$USER/.seeded" ]; then
    cp -an /opt/hermes-defaults/. "/home/$USER/" 2>/dev/null || true
    cp -an /etc/skel/. "/home/$USER/" 2>/dev/null || true
    : > "/home/$USER/.seeded"
fi
chown -R "$USER:$USER" "/home/$USER"

# ── Desktop shortcuts — place + trust (only the known Hermes launchers; injection-safe) ──
DESKTOP_DIR="/home/$USER/Desktop"
mkdir -p "$DESKTOP_DIR"
for s in hermes-terminal.desktop hermes-setup.desktop hermes-dashboard.desktop; do
  f="$DESKTOP_DIR/$s"
  [ -f "$f" ] || cp "/opt/hermes-defaults/Desktop/$s" "$f" 2>/dev/null || true
  [ -f "$f" ] || continue
  chmod +x "$f"
  # XFCE 4.18 (Ubuntu 24.04) trusts a launcher only when it is executable AND has
  # metadata::xfce-exe-checksum == sha256(file contents) — exactly what the dialog's
  # "Mark Executable" button writes. metadata::trusted (old GNOME/Nautilus convention)
  # is IGNORED by XFCE, so setting only it left the "Untrusted application launcher"
  # dialog on EVERY icon launch. Set both inside one dbus session so gvfsd-metadata
  # persists them; path + checksum pass as positional args ($1/$2), never interpolated.
  sum="$(sha256sum "$f" | cut -d' ' -f1)"
  su - "$USER" -c 'dbus-launch sh -c '\''gio set "$1" metadata::trusted true; gio set "$1" metadata::xfce-exe-checksum "$2"'\'' _ "$1" "$2"' _ "$f" "$sum" 2>/dev/null || true
done
chown -R "$USER:$USER" "$DESKTOP_DIR"

# VNC password
mkdir -p /home/$USER/.vnc
echo "$PASSWORD" | vncpasswd -f > /home/$USER/.vnc/passwd
chmod 600 /home/$USER/.vnc/passwd
chown -R $USER:$USER /home/$USER/.vnc

# xstartup -> XFCE (sources .xprofile for a11y env vars, then starts AT-SPI bus within the dbus session)
cat > /home/$USER/.vnc/xstartup <<'EOF'
#!/bin/sh
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
[ -f "$HOME/.xprofile" ] && . "$HOME/.xprofile"
exec dbus-launch --exit-with-session sh -c '
  ATSPI=$(command -v at-spi-bus-launcher || echo /usr/libexec/at-spi-bus-launcher)
  "$ATSPI" --launch-immediately &
  sleep 0.5
  exec startxfce4
'
EOF
chmod +x /home/$USER/.vnc/xstartup
chown $USER:$USER /home/$USER/.vnc/xstartup

# AT-SPI / accessibility for computer_use
cat > /home/$USER/.xprofile <<'EOF'
export GTK_MODULES=atk-bridge
export QT_ACCESSIBILITY=1
export NO_AT_BRIDGE=0
export OOO_FORCE_DESKTOP=gnome
EOF
chown $USER:$USER /home/$USER/.xprofile

# clean stale + start Xvnc :1
su - "$USER" -c "vncserver -kill :1" 2>/dev/null || true
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
su - "$USER" -c "vncserver :1 -geometry ${VNC_RESOLUTION} -depth ${VNC_COL_DEPTH} \
  -localhost no -SecurityTypes VncAuth -passwd /home/$USER/.vnc/passwd"
sleep 3
# Turn on toolkit accessibility in xfconf settings (|| true — xfconfd may not be ready yet)
su - "$USER" -c "DISPLAY=:1 xfconf-query -c xsettings -p /Net/EnableAccessibility -n -t int -s 1" 2>/dev/null || true

# ── xRDP (RDP access on 3389) ──
echo "xfce4-session" > "/home/$USER/.xsession"
chown "$USER:$USER" "/home/$USER/.xsession"
[ -f /etc/xrdp/rsakeys.ini ] || xrdp-keygen xrdp /etc/xrdp/rsakeys.ini 2>/dev/null || true
if [ -f /etc/xrdp/key.pem ]; then
    chmod 640 /etc/xrdp/key.pem
    chgrp ssl-cert /etc/xrdp/key.pem 2>/dev/null || chmod 644 /etc/xrdp/key.pem
fi
# Converge RDP onto the existing :1 (TigerVNC on 5901) via libvnc, as the DEFAULT session.
# xrdp uses the FIRST session section by default, so insert the libvnc proxy BEFORE [Xorg]
# (and set autorun). Colon-free section name so autorun matches reliably.
if [ -f /usr/lib/xrdp/libvnc.so ] || [ -f /usr/lib/x86_64-linux-gnu/xrdp/libvnc.so ] || [ -f /usr/lib/aarch64-linux-gnu/xrdp/libvnc.so ]; then
  # Session block (unquoted heredoc expands ${PASSWORD}; only ever written via printf %s — literal-safe).
  BLOCK=$(cat <<RDPCONV
[Hermes]
name=Hermes Desktop (:1)
lib=libvnc.so
username=na
password=${PASSWORD}
ip=127.0.0.1
port=5901
RDPCONV
)
  ( umask 077
    # Drop any prior [Hermes] section (awk handles STRUCTURE only — no secret passes through it).
    awk '/^\[Hermes\]$/{h=1;next} h&&/^\[/{h=0} h{next} {print}' /etc/xrdp/xrdp.ini > /etc/xrdp/xrdp.ini.s1
    # Insert the block immediately BEFORE [Xorg] so it is the first/default session.
    xln=$(grep -n '^\[Xorg\]$' /etc/xrdp/xrdp.ini.s1 | head -1 | cut -d: -f1)
    if [ -n "$xln" ]; then
      head -n "$((xln-1))" /etc/xrdp/xrdp.ini.s1 > /etc/xrdp/xrdp.ini.s2
      printf '%s\n\n' "$BLOCK" >> /etc/xrdp/xrdp.ini.s2
      tail -n "+$xln" /etc/xrdp/xrdp.ini.s1 >> /etc/xrdp/xrdp.ini.s2
      mv /etc/xrdp/xrdp.ini.s2 /etc/xrdp/xrdp.ini
    else
      printf '\n%s\n' "$BLOCK" >> /etc/xrdp/xrdp.ini.s1
      mv /etc/xrdp/xrdp.ini.s1 /etc/xrdp/xrdp.ini
    fi
    rm -f /etc/xrdp/xrdp.ini.s1
  ) || true
  chmod 600 /etc/xrdp/xrdp.ini || true
  # autorun (skips the session combo on clients that honor it; colon-free name).
  if ! grep -q '^autorun=Hermes$' /etc/xrdp/xrdp.ini; then
    sed -i '0,/^\[Globals\]/ s//[Globals]\nautorun=Hermes/' /etc/xrdp/xrdp.ini || true
  fi
fi
# Clear stale xrdp PID files so xrdp re-starts cleanly on a container restart.
# The writable layer persists /run across restarts; a stale PID makes the init
# script (and start-stop-daemon) think xrdp is already up, so it never starts
# and the healthcheck's `pgrep -x xrdp` fails → container stuck unhealthy.
rm -f /var/run/xrdp/*.pid /run/xrdp/*.pid 2>/dev/null || true
/etc/init.d/xrdp start 2>/dev/null || { xrdp-sesman; xrdp; } || true

# --- config.yaml / SOUL.md seed (formerly also computer_use/cua-driver setup) ---
# Seed ~/.hermes/config.yaml + SOUL.md from build-time template if absent.
# (Task 2's first-boot cp -an already handles this on a truly fresh volume;
# this loop is a defensive net for partial-seed or custom-user scenarios.)
su - "$USER" -c 'mkdir -p ~/.hermes'
for f in config.yaml SOUL.md; do
  if [ ! -f "/home/$USER/.hermes/$f" ] && [ -f "/opt/hermes-defaults/.hermes/$f" ]; then
    cp "/opt/hermes-defaults/.hermes/$f" "/home/$USER/.hermes/$f"
  fi
done
chown -R "$USER:$USER" "/home/$USER/.hermes"

# ── Visible CDP browser for the computer_use browser leg ──
# Launch Chrome on :1 with remote debugging so Hermes `/browser connect` and
# cua-driver's `page` tool can attach over CDP (:9222). Chrome 136+ DISABLES
# --remote-debugging-port on the DEFAULT profile dir, so a DEDICATED --user-data-dir
# is mandatory (a default-profile launch silently brings up no CDP socket).
# Backgrounded and NOT supervised — if it dies the desktop stays up, and relaunch
# is idempotent (same profile dir → reuses the running instance, no port rebind).
CDP_PROFILE="/home/$USER/.config/google-chrome-cua"
su - "$USER" -c "mkdir -p '$CDP_PROFILE' && DISPLAY=:1 setsid google-chrome-stable \
  --remote-debugging-port=9222 --remote-allow-origins=* \
  --user-data-dir='$CDP_PROFILE' --no-first-run --no-default-browser-check \
  about:blank >/dev/null 2>&1 &" || true
echo "Visible CDP browser launching on :1 (CDP endpoint 127.0.0.1:9222)"

# ── Hermes web dashboard (9119, basic-auth = desktop credentials) ──
# Bind 0.0.0.0 so Docker's 127.0.0.1:9119:9119 host-map reaches it; a non-loopback
# bind forces an auth provider, so configure BasicAuthProvider from the desktop
# creds. No plaintext password at rest: compute a scrypt hash (password via env,
# never interpolated). The session-signing secret is DERIVED from the password
# (HMAC) so changing HERMES_PASSWORD invalidates old sessions, while a stable
# password keeps sessions valid across restarts — and no secret file sits at rest.
# The env file is user-owned, mode 600, and holds only the hash + secret + username.
DASH_DIR="/home/$USER/.hermes"
DASH_ENV_FILE="$DASH_DIR/dashboard.env"
su - "$USER" -c 'mkdir -p ~/.hermes/logs'
rm -f "$DASH_DIR/.dashboard-secret"   # legacy random secret — replaced by password-derived
PW_HASH="$(HPW="$PASSWORD" PYTHONPATH=/usr/local/lib/hermes-agent \
  /usr/local/lib/hermes-agent/venv/bin/python -c \
  'import os; from plugins.dashboard_auth.basic import hash_password; print(hash_password(os.environ["HPW"]))')"
DASH_SECRET="$(HPW="$PASSWORD" /usr/local/lib/hermes-agent/venv/bin/python -c \
  'import os,hmac,hashlib; print(hmac.new(b"hermes-dashboard-session-v1", os.environ["HPW"].encode(), hashlib.sha256).hexdigest())')"
( umask 077
  {
    printf "HERMES_DASHBOARD_BASIC_AUTH_USERNAME='%s'\n" "$USER"
    printf "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH='%s'\n" "$PW_HASH"
    printf "HERMES_DASHBOARD_BASIC_AUTH_SECRET='%s'\n" "$DASH_SECRET"
  } > "$DASH_ENV_FILE"
)
chown -R "$USER:$USER" "$DASH_DIR"
# Launch as the user (NOT setsid — we keep its PID to supervise it). Source the
# auth env (single-quoted values, safe to source).
su - "$USER" -c 'set -a; . ~/.hermes/dashboard.env; set +a; \
  exec hermes dashboard --host 0.0.0.0 --port 9119 --no-open --skip-build' \
  >> "$DASH_DIR/logs/dashboard.boot.log" 2>&1 &
DASH=$!
echo "Hermes dashboard starting on http://localhost:9119 (login: $USER / <desktop password>)"

# NoVNC
websockify --web=/usr/share/novnc 6080 localhost:5901 &
WS=$!
echo "Hermes desktop up: NoVNC http://localhost:6080/vnc.html  (vnc pw: set via HERMES_PASSWORD)"

# Supervise the two foreground-critical services: if EITHER the dashboard or
# websockify exits, stop the container (exit non-zero) so Docker's
# restart:unless-stopped recreates it — lightweight self-healing without s6.
wait -n "$WS" "$DASH" || true
echo "FATAL: a core service exited (websockify=$WS dashboard=$DASH) — stopping container for restart" >&2
exit 1
