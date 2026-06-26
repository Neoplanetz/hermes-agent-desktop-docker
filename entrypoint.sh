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

# xstartup -> XFCE
cat > /home/$USER/.vnc/xstartup <<'EOF'
#!/bin/sh
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
exec dbus-launch --exit-with-session startxfce4
EOF
chmod +x /home/$USER/.vnc/xstartup
chown $USER:$USER /home/$USER/.vnc/xstartup

# clean stale + start Xvnc :1
su - "$USER" -c "vncserver -kill :1" 2>/dev/null || true
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
su - "$USER" -c "vncserver :1 -geometry ${VNC_RESOLUTION} -depth ${VNC_COL_DEPTH} \
  -localhost no -SecurityTypes VncAuth -passwd /home/$USER/.vnc/passwd"
sleep 2

# NoVNC
websockify --web=/usr/share/novnc 6080 localhost:5901 &
WS=$!
echo "Spike desktop up: NoVNC http://localhost:6080/vnc.html  (vnc pw: $PASSWORD)"
wait $WS
