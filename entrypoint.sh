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

# --- computer_use / cua-driver setup ---
# Ensure ~/.hermes + minimal config exist and DISPLAY is wired for the agent
su - "$USER" -c 'mkdir -p ~/.hermes'
if [ ! -f /home/$USER/.hermes/config.yaml ]; then
  su - "$USER" -c 'cat > ~/.hermes/config.yaml <<YAML
computer_use:
  cua_telemetry: false
YAML'
fi
# Persist DISPLAY/XAUTHORITY for every login shell the agent uses
grep -q 'HERMES DESKTOP DISPLAY' /home/$USER/.bashrc 2>/dev/null || \
  printf '\n# HERMES DESKTOP DISPLAY\nexport DISPLAY=:1\nexport XAUTHORITY=/home/%s/.Xauthority\n' "$USER" \
  >> /home/$USER/.bashrc
chown -R $USER:$USER /home/$USER/.hermes /home/$USER/.bashrc

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
