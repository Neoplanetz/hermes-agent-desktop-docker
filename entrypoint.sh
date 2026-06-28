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
  # Pass the path as a positional arg ($1) — never interpolate it into the shell string.
  su - "$USER" -c 'dbus-launch gio set "$1" metadata::trusted true' _ "$f" 2>/dev/null || true
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
export GTK_MODULES=gail:atk-bridge
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
if [ -f /usr/lib/xrdp/libvnc.so ] || [ -f /usr/lib/x86_64-linux-gnu/xrdp/libvnc.so ]; then
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
/etc/init.d/xrdp start 2>/dev/null || { xrdp-sesman; xrdp; } || true

# --- computer_use / cua-driver setup ---
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
# Persist DISPLAY/XAUTHORITY for every login shell the agent uses
grep -q 'HERMES DESKTOP DISPLAY' /home/$USER/.bashrc 2>/dev/null || \
  printf '\n# HERMES DESKTOP DISPLAY\nexport DISPLAY=:1\nexport XAUTHORITY=/home/%s/.Xauthority\n' "$USER" \
  >> /home/$USER/.bashrc
chown "$USER:$USER" "/home/$USER/.bashrc"

# Install cua-driver once (needs network on first boot)
if [ ! -f /home/$USER/.hermes/.cua-installed ]; then
  if su - "$USER" -c 'DISPLAY=:1 hermes computer-use install'; then
    su - "$USER" -c 'touch ~/.hermes/.cua-installed'
  else
    echo "WARN: hermes computer-use install failed (see logs)"
  fi
fi

# ── Hermes web dashboard (9119, basic-auth = desktop credentials) ──
# Bind 0.0.0.0 so Docker's 127.0.0.1:9119:9119 host-map reaches it; a non-loopback
# bind forces an auth provider, so configure BasicAuthProvider from the desktop
# creds. No plaintext password at rest: compute a scrypt hash (password via env,
# never interpolated) and persist a random signing secret. The env file is
# user-owned, mode 600, and holds only the hash + secret + username.
DASH_DIR="/home/$USER/.hermes"
DASH_SECRET_FILE="$DASH_DIR/.dashboard-secret"
DASH_ENV_FILE="$DASH_DIR/dashboard.env"
su - "$USER" -c 'mkdir -p ~/.hermes/logs'
PW_HASH="$(HPW="$PASSWORD" PYTHONPATH=/usr/local/lib/hermes-agent \
  /usr/local/lib/hermes-agent/venv/bin/python -c \
  'import os; from plugins.dashboard_auth.basic import hash_password; print(hash_password(os.environ["HPW"]))')"
if [ ! -s "$DASH_SECRET_FILE" ]; then
  ( umask 077; /usr/local/lib/hermes-agent/venv/bin/python -c 'import secrets; print(secrets.token_hex(32))' > "$DASH_SECRET_FILE" )
fi
DASH_SECRET="$(cat "$DASH_SECRET_FILE")"
( umask 077
  {
    printf "HERMES_DASHBOARD_BASIC_AUTH_USERNAME='%s'\n" "$USER"
    printf "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH='%s'\n" "$PW_HASH"
    printf "HERMES_DASHBOARD_BASIC_AUTH_SECRET='%s'\n" "$DASH_SECRET"
  } > "$DASH_ENV_FILE"
)
chown -R "$USER:$USER" "$DASH_DIR"
# Launch detached as the user; source the auth env (single-quoted values, safe to source).
setsid su - "$USER" -c 'set -a; . ~/.hermes/dashboard.env; set +a; \
  exec hermes dashboard --host 0.0.0.0 --port 9119 --no-open --skip-build' \
  >> "$DASH_DIR/logs/dashboard.boot.log" 2>&1 &
echo "Hermes dashboard starting on http://localhost:9119 (login: $USER / <desktop password>)"

# NoVNC
websockify --web=/usr/share/novnc 6080 localhost:5901 &
WS=$!
echo "Hermes desktop up: NoVNC http://localhost:6080/vnc.html  (vnc pw: $PASSWORD)"
wait $WS
