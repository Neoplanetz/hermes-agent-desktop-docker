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

# ── Desktop shortcuts — place + trust (defensive: works on fresh AND existing volumes) ──
DESKTOP_DIR="/home/$USER/Desktop"
mkdir -p "$DESKTOP_DIR"
for s in hermes-terminal.desktop hermes-setup.desktop; do
  [ -f "$DESKTOP_DIR/$s" ] || cp "/opt/hermes-defaults/Desktop/$s" "$DESKTOP_DIR/$s" 2>/dev/null || true
done
for f in "$DESKTOP_DIR"/*.desktop; do
  [ -f "$f" ] || continue
  chmod +x "$f"
  su - "$USER" -c "dbus-launch gio set '$f' metadata::trusted true" 2>/dev/null || true
done
chown -R "$USER:$USER" "$DESKTOP_DIR"
# Ensure subsequent login shells (including non-interactive su -) can reach the
# XFCE session's dbus bus so `gio info` sees metadata::trusted without dbus-launch.
grep -q 'HERMES_DBUS_PROFILE' "/home/$USER/.profile" 2>/dev/null || \
  cat >> "/home/$USER/.profile" << 'PROFILE_DBUS'
# HERMES_DBUS_PROFILE: expose the running XFCE session bus to gio (metadata::trusted)
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  _mach=$(cat /etc/machine-id 2>/dev/null)
  _sess="$HOME/.dbus/session-bus/${_mach}-1"
  if [ -f "$_sess" ]; then
    . "$_sess" 2>/dev/null || true
    export DBUS_SESSION_BUS_ADDRESS
  fi
fi
PROFILE_DBUS
chown "$USER:$USER" "/home/$USER/.profile"

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
# Converge RDP onto the existing :1 (TigerVNC on 5901) via libvnc.
# Replaces the default Xorg session so an RDP login lands on :1.
if [ -f /usr/lib/xrdp/libvnc.so ] || [ -f /usr/lib/x86_64-linux-gnu/xrdp/libvnc.so ]; then
  # Build the session block in a variable (unquoted heredoc expands ${PASSWORD}).
  # No temp file is written — avoids leaving a plaintext password on disk.
  BLOCK=$(cat <<RDPCONV
[Hermes-:1]
name=Hermes Desktop (:1)
lib=libvnc.so
username=na
password=${PASSWORD}
ip=127.0.0.1
port=5901
RDPCONV
)
  # Append the session block to xrdp.ini (idempotent). Session appears last in
  # the RDP session dropdown (appended, not spliced to the top).
  if ! grep -q '^\[Hermes-:1\]' /etc/xrdp/xrdp.ini; then
    printf '\n%s\n' "$BLOCK" >> /etc/xrdp/xrdp.ini || true
  fi
  chmod 600 /etc/xrdp/xrdp.ini || true
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

# NoVNC
websockify --web=/usr/share/novnc 6080 localhost:5901 &
WS=$!
echo "Hermes desktop up: NoVNC http://localhost:6080/vnc.html  (vnc pw: $PASSWORD)"
wait $WS
