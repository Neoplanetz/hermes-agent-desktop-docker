#!/bin/bash
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
[ -r /etc/profile ] && . /etc/profile
[ -f "$HOME/.xprofile" ] && . "$HOME/.xprofile"
exec dbus-launch --exit-with-session startxfce4
