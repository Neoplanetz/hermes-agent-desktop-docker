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
      libglib2.0-bin gvfs \
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
      build-essential python3-dev pkg-config libffi-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Hermes Agent — root FHS install (/usr/local/bin/hermes), pinned, non-interactive.
ARG HERMES_BRANCH=main
ENV HERMES_HOME=/root/.hermes
RUN curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- \
      --non-interactive --skip-setup --skip-browser --no-skills \
      --branch "${HERMES_BRANCH}" \
    && /usr/local/bin/hermes --version

# Google Chrome (amd64) with --no-sandbox wrapper for CDP/computer-use
RUN wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && (apt-get update && apt-get install -y /tmp/chrome.deb || (apt-get -f install -y && apt-get install -y /tmp/chrome.deb)) \
    && rm -f /tmp/chrome.deb \
    && mv /usr/bin/google-chrome-stable /usr/bin/google-chrome-stable-real \
    && printf '#!/bin/bash\nexec /usr/bin/google-chrome-stable-real --no-sandbox "$@"\n' > /usr/bin/google-chrome-stable \
    && chmod +x /usr/bin/google-chrome-stable \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Home template seeded onto the (volume-shadowed) home on first boot
RUN mkdir -p /opt/hermes-defaults/.vnc /opt/hermes-defaults/Desktop \
      /opt/hermes-defaults/.hermes \
    && cp /home/hermes/.bashrc /opt/hermes-defaults/ 2>/dev/null || true
COPY configs/config.yaml /opt/hermes-defaults/.hermes/config.yaml
COPY configs/desktop/hermes-terminal.desktop configs/desktop/hermes-setup.desktop /opt/hermes-defaults/Desktop/
RUN printf '# SOUL.md — Hermes persona\nYou are a helpful assistant running on a Linux desktop. Be concise.\n' \
      > /opt/hermes-defaults/.hermes/SOUL.md

RUN apt-get update && apt-get install -y --no-install-recommends \
      xrdp xorgxrdp \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
# Session hook (separate XFCE session; Task 3 converges onto :1 via libvnc)
COPY configs/xrdp/startwm.sh /etc/xrdp/startwm.sh
RUN chmod +x /etc/xrdp/startwm.sh \
    && sed -i 's/^#xserverbpp=24/xserverbpp=24/' /etc/xrdp/xrdp.ini || true

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 6080 5901 9222 3389
ENTRYPOINT ["/entrypoint.sh"]
