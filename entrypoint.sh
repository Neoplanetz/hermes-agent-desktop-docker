#!/bin/bash
set -euo pipefail
USER=hermes
PASSWORD=hermes123
VNC_RESOLUTION="${VNC_RESOLUTION:-1920x1080}"
VNC_COL_DEPTH="${VNC_COL_DEPTH:-24}"

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
grep -q 'HERMES SPIKE DISPLAY' /home/$USER/.bashrc 2>/dev/null || \
  printf '\n# HERMES SPIKE DISPLAY\nexport DISPLAY=:1\nexport XAUTHORITY=/home/%s/.Xauthority\n' "$USER" \
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
echo "Spike desktop up: NoVNC http://localhost:6080/vnc.html  (vnc pw: $PASSWORD)"
wait $WS
