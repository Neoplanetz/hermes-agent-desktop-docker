# Hermes Agent Desktop
FROM ubuntu:24.04
LABEL org.opencontainers.image.title="Hermes Agent Desktop"
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Seoul \
    DISPLAY=:1 \
    VNC_RESOLUTION=1920x1080 \
    VNC_COL_DEPTH=24
RUN apt-get update && apt-get install -y --no-install-recommends \
      xfce4 xfce4-terminal dbus-x11 \
      tigervnc-standalone-server tigervnc-common tigervnc-tools \
      novnc websockify \
      sudo curl wget ca-certificates net-tools iproute2 lsof procps \
      x11-utils xauth \
      fonts-noto-cjk fonts-noto-color-emoji \
      at-spi2-core gir1.2-atspi-2.0 python3-gi \
      libglib2.0-bin gvfs gvfs-daemons \
      mousepad xdotool \
    && ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN userdel -r ubuntu 2>/dev/null || true \
    && useradd -m -s /bin/bash -u 1000 hermes \
    && adduser hermes sudo \
    && echo 'hermes ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/hermes \
    && chmod 0440 /etc/sudoers.d/hermes
# Hermes runtime deps (installer declines these under --non-interactive)
RUN apt-get update && apt-get install -y --no-install-recommends \
      git ripgrep ffmpeg \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Hermes Agent — root FHS install (/usr/local/bin/hermes), pinned, non-interactive.
# Build deps live ONLY in this layer: installed, used for the install + web build,
# then purged so they never reach the final image.
ARG HERMES_BRANCH=main
ARG HERMES_COMMIT=dd0e4ab81abccf7df5b11c6c16853d5e5de9db69
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential python3-dev pkg-config libffi-dev \
    && curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- \
         --non-interactive --skip-setup --skip-browser --no-skills \
         --branch "${HERMES_BRANCH}" --commit "${HERMES_COMMIT}" \
    && /usr/local/bin/hermes --version \
    && cd /usr/local/lib/hermes-agent/web && npm run build \
    && test -d /usr/local/lib/hermes-agent/hermes_cli/web_dist \
    && rm -rf /usr/local/lib/hermes-agent/web/node_modules \
    && npm cache clean --force \
    && apt-get purge -y build-essential python3-dev pkg-config libffi-dev \
    && apt-get autoremove -y \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Browser with a --no-sandbox `google-chrome-stable` wrapper (CDP/computer-use).
# amd64: Google Chrome (.deb). arm64: Chromium from the xtradeb PPA — Google
# Chrome ships no arm64 Linux build and Ubuntu 24.04's `chromium` is a snap
# (unusable in a container). The wrapper name is identical on both arches, so
# the entrypoint, desktop shortcuts, and verify-gonogo work unchanged.
ARG TARGETARCH
RUN set -eux; \
    if [ "${TARGETARCH}" = "arm64" ]; then \
      apt-get update; \
      apt-get install -y --no-install-recommends software-properties-common; \
      add-apt-repository -y ppa:xtradeb/apps; \
      apt-get update; \
      apt-get install -y --no-install-recommends chromium; \
      apt-get purge -y software-properties-common; apt-get autoremove -y; \
      CHROME_REAL="$(command -v chromium)"; \
    else \
      wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb; \
      { apt-get update && apt-get install -y /tmp/chrome.deb; } || { apt-get -f install -y && apt-get install -y /tmp/chrome.deb; }; \
      rm -f /tmp/chrome.deb; \
      mv /usr/bin/google-chrome-stable /usr/bin/google-chrome-stable-real; \
      CHROME_REAL=/usr/bin/google-chrome-stable-real; \
    fi; \
    printf '#!/bin/bash\nexec %s --no-sandbox "$@"\n' "$CHROME_REAL" > /usr/bin/google-chrome-stable; \
    chmod +x /usr/bin/google-chrome-stable; \
    apt-get clean; rm -rf /var/lib/apt/lists/*

# Home template seeded onto the (volume-shadowed) home on first boot
RUN mkdir -p /opt/hermes-defaults/.vnc /opt/hermes-defaults/Desktop \
      /opt/hermes-defaults/.hermes \
    && cp /home/hermes/.bashrc /opt/hermes-defaults/ 2>/dev/null || true
COPY configs/config.yaml /opt/hermes-defaults/.hermes/config.yaml
COPY configs/desktop/hermes-terminal.desktop configs/desktop/hermes-setup.desktop configs/desktop/hermes-dashboard.desktop /opt/hermes-defaults/Desktop/
RUN printf '# SOUL.md — Hermes persona\nYou are a helpful assistant running on a Linux desktop. Be concise.\n' \
      > /opt/hermes-defaults/.hermes/SOUL.md

RUN apt-get update && apt-get install -y --no-install-recommends \
      xrdp xorgxrdp \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
# Session hook (separate XFCE session; Task 3 converges onto :1 via libvnc)
COPY configs/xrdp/startwm.sh /etc/xrdp/startwm.sh
RUN chmod +x /etc/xrdp/startwm.sh \
    && sed -i 's/^#xserverbpp=24/xserverbpp=24/' /etc/xrdp/xrdp.ini || true

# Ensure DISPLAY/XAUTHORITY are set in every login shell; expose the live
# XFCE session D-Bus address with a socket-liveness check so `gio info` can
# reach gvfsd-metadata to read metadata::trusted in non-interactive su - calls.
# Both files are rootfs (not volume) — image-upgradeable, never volume-locked.
RUN printf 'export DISPLAY="${DISPLAY:-:1}"\nexport XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"\n' \
      > /etc/profile.d/hermes-display.sh \
    && chmod 0644 /etc/profile.d/hermes-display.sh \
    && cat > /etc/profile.d/hermes-dbus.sh << 'EOSH'
# Expose live XFCE session D-Bus address to login shells (e.g. su - for gio info).
# Rootfs file — image-upgradeable, NOT on the user-home volume.
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  _mach=$(cat /etc/machine-id 2>/dev/null)
  _sess="${HOME}/.dbus/session-bus/${_mach}-1"
  if [ -f "$_sess" ]; then
    . "$_sess" 2>/dev/null || true
    # Liveness check: only export if the socket file is live
    _sock="${DBUS_SESSION_BUS_ADDRESS#unix:path=}"
    _sock="${_sock%%,*}"
    if [ -n "${_sock}" ] && [ -S "${_sock}" ]; then
      export DBUS_SESSION_BUS_ADDRESS
    else
      unset DBUS_SESSION_BUS_ADDRESS 2>/dev/null || true
    fi
  fi
fi
EOSH
RUN chmod 0644 /etc/profile.d/hermes-dbus.sh



COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 6080 5901 9222 3389 9119
ENTRYPOINT ["/entrypoint.sh"]
