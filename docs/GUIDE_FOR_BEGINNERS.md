# Hermes Agent Desktop — Beginner's Guide

🇺🇸 [English](GUIDE_FOR_BEGINNERS.md) | 🇰🇷 [한국어](GUIDE_FOR_BEGINNERS.ko.md) | 🇨🇳 [中文](GUIDE_FOR_BEGINNERS.zh.md) | 🇯🇵 [日本語](GUIDE_FOR_BEGINNERS.ja.md)

Don't worry if you're not very tech-savvy. Follow this guide from top to bottom and
you'll have an AI agent browsing the web for you — on a desktop you can watch — in
about 15 minutes.

## What is this?

Hermes Agent Desktop is a **full Ubuntu desktop that runs inside Docker**, with the
**Hermes AI agent** (by Nous Research) pre-installed. The agent drives a real Chrome
browser for you, and you watch it happen live through your own web browser. Nothing is
installed on your computer except Docker.

Think of it as **a second computer, living inside your computer**, where an AI does the
clicking and typing in the browser while you supervise.

## What you need

- A computer running **Windows, macOS, or Linux**.
- About **8 GB of free disk space** and **4 GB of spare RAM**.
- An **AI model API key** — a free **Nous Portal** account works (we set it up in Step 5).
- About **15 minutes**.

You do **not** need to know how to code.

## Step 1: Install Docker Desktop

Docker is the program that runs the virtual desktop. You install it once.

### Windows
1. Go to <https://www.docker.com/products/docker-desktop/> and click **Download for Windows**.
2. Run the installer, keep the defaults, and restart if asked.
3. Open **Docker Desktop** and wait until it shows **"Engine running"**.

### macOS
1. Go to <https://www.docker.com/products/docker-desktop/> and click **Download for Mac**
   (pick **Apple Silicon** for M1/M2/M3/M4, or **Intel** for older Macs).
2. Open the `.dmg` and drag **Docker** into Applications.
3. Launch Docker and wait for **"Engine running"**.

### Ubuntu / Linux
1. Install Docker Engine by following <https://docs.docker.com/engine/install/ubuntu/>.
2. Confirm `docker compose version` prints a version in a terminal.

## Step 2: Create the project files

Make a new folder (for example `hermes-desktop`) and put **two files** inside it.

**File 1 — `compose.yaml`:**

```yaml
services:
  hermes-desktop:
    image: neoplanetz/hermes-desktop-docker:latest
    container_name: hermes-desktop
    environment:
      - HERMES_USER=${HERMES_USER:-hermes}
      - HERMES_PASSWORD=${HERMES_PASSWORD:-hermes123}
    ports:
      - "127.0.0.1:6080:6080"
      - "127.0.0.1:5901:5901"
      - "127.0.0.1:3390:3389"
      - "127.0.0.1:9119:9119"
    volumes:
      - hermes-home:/home/${HERMES_USER:-hermes}
    shm_size: "2gb"
    restart: unless-stopped
    init: true

volumes:
  hermes-home:
    name: hermes-home
```

**File 2 — `.env`** (choose your own password!):

```bash
HERMES_USER=hermes
HERMES_PASSWORD=change-this-password
```

## Step 3: Start the virtual computer

Open a terminal **inside that folder** and run:

```bash
docker compose up -d
```

The first time, Docker downloads the image (a few minutes). When it finishes, the
desktop is running quietly in the background.

**How to open a terminal in the folder:**
- **Windows**: open the folder in File Explorer, type `cmd` in the address bar, press Enter.
- **macOS**: right-click the folder → **New Terminal at Folder**.
- **Ubuntu**: right-click inside the folder → **Open in Terminal**.

## Step 4: Connect to the desktop

Open your web browser and go to:

**<http://localhost:6080/vnc.html>**

Click **Connect**, enter the password from your `.env`, and a full Ubuntu desktop
appears. 🎉

> Prefer a Remote Desktop app? Connect to `localhost:3390` with username `hermes`.
> Prefer a VNC client? Use `localhost:5901`. All three show the **same** desktop.

## Step 5: Configure the AI model (first time only)

The agent needs an AI model to think. The easiest free option is **Nous Portal**.

1. Open a second browser tab and go to **<http://localhost:9119>** — the **dashboard**.
2. Log in with username `hermes` and your password.
3. Open the **API Keys** tab.
4. Choose **Nous** as the provider and follow the on-screen login (a free account works).
5. Pick a model that supports **vision + tools** (so the agent can both see and act).
6. Save.

> Tip: you can also double-click the **"Hermes Setup"** icon on the desktop to run a
> guided wizard instead.

## Step 6: Let the agent browse for you

This is the fun part.

1. In the dashboard, open the **Chat** tab.
2. Ask it to do something on the web, for example:
   > "Open example.com and tell me the main heading."
3. Switch to the desktop tab (`localhost:6080`) and **watch** — a Chrome window opens
   and the agent reads and clicks the page for you.

The agent controls Chrome through a secure connection (CDP) that stays **inside** the
container, so the automation is never exposed to the internet.

## Step 7: Using the dashboard

The dashboard (`localhost:9119`) has a tab for everything:

- **Status** — is everything healthy?
- **Chat** — talk to the agent.
- **Config / API Keys** — models and credentials.
- **Sessions / Skills / MCP** — saved work, abilities, and tools.
- **Channels** — connect Telegram and other chat apps.
- **Logs / Cron** — see what happened, and schedule tasks.

## Step 8: Updating

When a new version ships, run these in your project folder:

```bash
docker compose pull
docker compose up -d
```

Your settings, API keys, and sessions are kept safely in the `hermes-home` volume.

## Frequently Asked Questions

**Is my data safe?** Everything lives in a Docker volume on your own machine. Nothing is
sent anywhere except to the AI model you choose.

**The page at `localhost:6080` won't load.** Give it a minute after `docker compose up -d`
— the desktop takes about 30–60 seconds to boot. Then refresh.

**I forgot my password.** It's the `HERMES_PASSWORD` in your `.env`. Change it and run
`docker compose up -d` again.

**Can the agent type into normal desktop apps (not the browser)?** No — this image is
built for **browser automation** only. See the README's "Known limitations".

**How do I stop it?** Run `docker compose down` (your data is kept). To erase everything
including the saved data, run `docker compose down -v`.

**Does it work on Apple Silicon / arm64?** Yes — the image is multi-arch, so Docker pulls
the right version for your computer automatically.
