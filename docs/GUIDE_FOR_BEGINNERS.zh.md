# Hermes Agent Desktop —— 新手指南

🇺🇸 [English](GUIDE_FOR_BEGINNERS.md) | 🇰🇷 [한국어](GUIDE_FOR_BEGINNERS.ko.md) | 🇨🇳 [中文](GUIDE_FOR_BEGINNERS.zh.md) | 🇯🇵 [日本語](GUIDE_FOR_BEGINNERS.ja.md)

即使你不太懂技术也别担心。只要从头到尾跟着这份指南一步步操作，大约 15 分钟后，你就会拥有一个
替你上网浏览的 AI 智能体——而且你可以在一个亲眼看得见的桌面上，实时看着它工作。

## 这是什么？

Hermes Agent Desktop 是一个**运行在 Docker 内部的完整 Ubuntu 桌面**，并预装了
**Hermes AI 智能体**（由 Nous Research 开发）。这个智能体会替你操作一个真实的 Chrome
浏览器，而你可以通过自己的网页浏览器实时观看整个过程。除了 Docker 之外，你的电脑上不会安装
任何其他东西。

你可以把它想象成**住在你电脑里的第二台电脑**，由 AI 在浏览器里负责点击和输入，而你只需在一旁
监督。

## 你需要准备什么

- 一台运行 **Windows、macOS 或 Linux** 的电脑。
- 大约 **8 GB 的可用磁盘空间**和 **4 GB 的空闲内存**。
- 一个 **AI 模型 API 密钥**——一个免费的 **Nous Portal** 账户就够了（我们会在第 5 步设置）。
- 大约 **15 分钟**的时间。

你**不**需要懂编程。

## 第 1 步：安装 Docker Desktop

Docker 是运行虚拟桌面的程序。你只需安装一次。

### Windows
1. 前往 <https://www.docker.com/products/docker-desktop/>，点击 **Download for Windows**。
2. 运行安装程序，保持默认设置，如有提示就重启电脑。
3. 打开 **Docker Desktop**，等待它显示 **"Engine running"**（引擎运行中）。

### macOS
1. 前往 <https://www.docker.com/products/docker-desktop/>，点击 **Download for Mac**
   （M1/M2/M3/M4 芯片请选 **Apple Silicon**，较旧的 Mac 请选 **Intel**）。
2. 打开 `.dmg` 文件，把 **Docker** 拖入"应用程序"文件夹。
3. 启动 Docker，等待出现 **"Engine running"**。

### Ubuntu / Linux
1. 按照 <https://docs.docker.com/engine/install/ubuntu/> 的说明安装 Docker Engine。
2. 在终端里确认 `docker compose version` 能打印出版本号。

## 第 2 步：创建项目文件

新建一个文件夹（例如 `hermes-desktop`），并在里面放入**两个文件**。

**文件 1 —— `compose.yaml`：**

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

**文件 2 —— `.env`**（请自己选一个密码！）：

```bash
HERMES_USER=hermes
HERMES_PASSWORD=change-this-password
```

## 第 3 步：启动这台虚拟电脑

**在那个文件夹里**打开一个终端，然后运行：

```bash
docker compose up -d
```

第一次运行时，Docker 会下载镜像（需要几分钟）。下载完成后，桌面就会在后台悄悄地运行起来了。

**如何在文件夹里打开终端：**
- **Windows**：在文件资源管理器中打开该文件夹，在地址栏输入 `cmd`，然后按回车。
- **macOS**：右键点击该文件夹 → **New Terminal at Folder**（在文件夹位置新建终端）。
- **Ubuntu**：在文件夹内右键点击 → **Open in Terminal**（在终端中打开）。

## 第 4 步：连接到桌面

打开你的网页浏览器，访问：

**<http://localhost:6080/vnc.html>**

点击 **Connect**（连接），输入你 `.env` 文件里设置的密码，一个完整的 Ubuntu 桌面就会出现。🎉

> 更喜欢用远程桌面（Remote Desktop）应用？请用用户名 `hermes` 连接到 `localhost:3390`。
> 更喜欢用 VNC 客户端？请使用 `localhost:5901`。这三种方式显示的都是**同一个**桌面。

## 第 5 步：配置 AI 模型（仅首次需要）

智能体需要一个 AI 模型来"思考"。最简单的免费选择就是 **Nous Portal**。

1. 再打开一个浏览器标签页，访问 **<http://localhost:9119>**——也就是**控制台（dashboard）**。
2. 用用户名 `hermes` 和你的密码登录。
3. 打开 **API Keys** 标签页。
4. 选择 **Nous** 作为提供商，按照屏幕上的提示登录（免费账户即可）。
5. 挑选一个同时支持**视觉 + 工具（vision + tools）**的模型（这样智能体既能"看"又能"操作"）。
6. 保存。

> 小提示：你也可以双击桌面上的 **"Hermes Setup"** 图标，改用引导式向导来完成设置。

## 第 6 步：让智能体替你浏览网页

这是最有趣的部分。

1. 在控制台里，打开 **Chat** 标签页。
2. 让它在网上做点什么，例如：
   > "打开 example.com，告诉我页面的主标题是什么。"
3. 切换到桌面标签页（`localhost:6080`），然后**看着**——一个 Chrome 窗口会打开，
   智能体会替你阅读并点击页面。

智能体通过一个始终留在容器**内部**的安全连接（CDP）来控制 Chrome，因此整个自动化过程绝不会
暴露到互联网上。

## 第 7 步：使用控制台

控制台（`localhost:9119`）为每一项功能都准备了一个标签页：

- **Status**——一切运行是否正常？
- **Chat**——与智能体对话。
- **Config / API Keys**——模型和凭据。
- **Sessions / Skills / MCP**——保存的工作、能力和工具。
- **Channels**——连接 Telegram 和其他聊天应用。
- **Logs / Cron**——查看发生了什么，以及安排定时任务。

## 第 8 步：更新

当有新版本发布时，在你的项目文件夹里运行以下命令：

```bash
docker compose pull
docker compose up -d
```

你的设置、API 密钥和会话都会安全地保存在 `hermes-home` 数据卷里。

## 常见问题

**我的数据安全吗？** 所有东西都保存在你自己电脑上的一个 Docker 数据卷里。除了你选择的 AI
模型之外，不会有任何数据被发送到别处。

**`localhost:6080` 这个页面加载不出来。** 运行 `docker compose up -d` 之后请稍等一会儿
——桌面启动大约需要 30–60 秒。然后刷新页面即可。

**我忘记密码了。** 密码就是你 `.env` 文件里的 `HERMES_PASSWORD`。修改它，然后再次运行
`docker compose up -d`。

**智能体能在普通的桌面应用（而不是浏览器）里打字吗？** 不能——这个镜像只为**浏览器自动化**
而打造。详见 README 中的"Known limitations"（已知限制）一节。

**我该如何停止它？** 运行 `docker compose down`（你的数据会被保留）。如果想连同保存的数据
一起全部清除，请运行 `docker compose down -v`。

**它能在 Apple Silicon / arm64 上运行吗？** 可以——这个镜像是多架构的，所以 Docker 会自动
为你的电脑拉取正确的版本。
