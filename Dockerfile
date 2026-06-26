FROM ubuntu:24.04
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

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 6080 5901
ENTRYPOINT ["/entrypoint.sh"]
