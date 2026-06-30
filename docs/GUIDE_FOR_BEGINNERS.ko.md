# Hermes Agent Desktop — 초보자 가이드

🇺🇸 [English](GUIDE_FOR_BEGINNERS.md) | 🇰🇷 [한국어](GUIDE_FOR_BEGINNERS.ko.md) | 🇨🇳 [中文](GUIDE_FOR_BEGINNERS.zh.md) | 🇯🇵 [日本語](GUIDE_FOR_BEGINNERS.ja.md)

기술에 익숙하지 않아도 걱정하지 마세요. 이 가이드를 위에서 아래로 차근차근 따라 하기만
하면, 약 15분 만에 AI 에이전트가 여러분을 대신해 웹을 탐색하게 됩니다 — 그것도 여러분이
직접 지켜볼 수 있는 데스크톱 위에서요.

## 이게 뭔가요?

Hermes Agent Desktop은 **Docker 안에서 실행되는 완전한 Ubuntu 데스크톱**으로,
**Hermes AI 에이전트**(Nous Research 제작)가 미리 설치되어 있습니다. 에이전트는 여러분을
대신해 진짜 Chrome 브라우저를 조작하고, 여러분은 자신의 웹 브라우저를 통해 그 과정을 실시간으로
지켜봅니다. 여러분의 컴퓨터에는 Docker 외에 아무것도 설치되지 않습니다.

**여러분의 컴퓨터 안에 사는 두 번째 컴퓨터**라고 생각하면 됩니다. 여러분이 지켜보는 동안
AI가 브라우저에서 클릭하고 타이핑을 대신해 줍니다.

## 필요한 것

- **Windows, macOS 또는 Linux**가 설치된 컴퓨터.
- 약 **8 GB의 여유 디스크 공간**과 **4 GB의 여유 RAM**.
- **AI 모델 API 키** — 무료 **Nous Portal** 계정이면 충분합니다(5단계에서 설정합니다).
- 약 **15분**.

코딩을 **할 줄 몰라도** 됩니다.

## 1단계: Docker Desktop 설치하기

Docker는 가상 데스크톱을 실행하는 프로그램입니다. 한 번만 설치하면 됩니다.

### Windows
1. <https://www.docker.com/products/docker-desktop/>로 이동해 **Download for Windows**를 클릭하세요.
2. 설치 프로그램을 실행하고 기본 설정을 그대로 둔 다음, 요청이 나오면 재시작하세요.
3. **Docker Desktop**을 열고 **"Engine running"**이 표시될 때까지 기다리세요.

### macOS
1. <https://www.docker.com/products/docker-desktop/>로 이동해 **Download for Mac**를 클릭하세요
   (M1/M2/M3/M4는 **Apple Silicon**을, 구형 Mac은 **Intel**을 선택하세요).
2. `.dmg`를 열고 **Docker**를 응용 프로그램 폴더로 드래그하세요.
3. Docker를 실행하고 **"Engine running"**이 나타날 때까지 기다리세요.

### Ubuntu / Linux
1. <https://docs.docker.com/engine/install/ubuntu/>를 따라 Docker Engine을 설치하세요.
2. 터미널에서 `docker compose version`이 버전을 출력하는지 확인하세요.

## 2단계: 프로젝트 파일 만들기

새 폴더(예: `hermes-desktop`)를 만들고 그 안에 **파일 두 개**를 넣으세요.

**파일 1 — `compose.yaml`:**

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

**파일 2 — `.env`**(비밀번호는 직접 정하세요!):

```bash
HERMES_USER=hermes
HERMES_PASSWORD=change-this-password
```

## 3단계: 가상 컴퓨터 시작하기

**그 폴더 안에서** 터미널을 열고 다음을 실행하세요:

```bash
docker compose up -d
```

처음 실행할 때는 Docker가 이미지를 내려받습니다(몇 분 정도 걸립니다). 다운로드가 끝나면
데스크톱이 백그라운드에서 조용히 실행됩니다.

**폴더에서 터미널을 여는 방법:**
- **Windows**: 파일 탐색기에서 폴더를 열고, 주소 표시줄에 `cmd`를 입력한 뒤 Enter를 누르세요.
- **macOS**: 폴더를 마우스 오른쪽 버튼으로 클릭 → **New Terminal at Folder**.
- **Ubuntu**: 폴더 안에서 마우스 오른쪽 버튼으로 클릭 → **Open in Terminal**.

## 4단계: 데스크톱에 연결하기

웹 브라우저를 열고 다음 주소로 이동하세요:

**<http://localhost:6080/vnc.html>**

**Connect**를 클릭하고 `.env`에 적은 비밀번호를 입력하면, 완전한 Ubuntu 데스크톱이
나타납니다. 🎉

> 원격 데스크톱(RDP) 앱을 더 선호하시나요? 사용자 이름 `hermes`로 `localhost:3390`에 연결하세요.
> VNC 클라이언트를 더 선호하시나요? `localhost:5901`을 사용하세요. 세 가지 모두 **같은** 데스크톱을 보여줍니다.

## 5단계: AI 모델 설정하기 (최초 1회만)

에이전트가 생각하려면 AI 모델이 필요합니다. 가장 쉬운 무료 옵션은 **Nous Portal**입니다.

1. 두 번째 브라우저 탭을 열고 **<http://localhost:9119>** — 즉 **대시보드**로 이동하세요.
2. 사용자 이름 `hermes`와 비밀번호로 로그인하세요.
3. **API Keys** 탭을 여세요.
4. 공급자로 **Nous**를 선택하고 화면에 표시되는 로그인 안내를 따르세요(무료 계정이면 충분합니다).
5. **비전(vision) + 도구(tools)**를 지원하는 모델을 선택하세요(그래야 에이전트가 보면서 동시에 행동할 수 있습니다).
6. 저장하세요.

> 팁: 대신 데스크톱에 있는 **"Hermes Setup"** 아이콘을 더블클릭하면 안내 마법사를 실행할
> 수도 있습니다.

## 6단계: 에이전트가 대신 웹을 탐색하게 하기

여기서부터가 재미있는 부분입니다.

1. 대시보드에서 **Chat** 탭을 여세요.
2. 웹에서 무언가를 해달라고 요청하세요. 예를 들면:
   > "example.com을 열어서 메인 제목을 알려줘."
3. 데스크톱 탭(`localhost:6080`)으로 전환해 **지켜보세요** — Chrome 창이 열리고
   에이전트가 여러분을 대신해 페이지를 읽고 클릭합니다.

에이전트는 컨테이너 **내부**에 머무는 보안 연결(CDP)을 통해 Chrome을 제어하므로,
이 자동화는 절대 인터넷에 노출되지 않습니다.

## 7단계: 대시보드 사용하기

대시보드(`localhost:9119`)에는 모든 기능을 위한 탭이 마련되어 있습니다:

- **Status** — 모든 것이 정상인가요?
- **Chat** — 에이전트와 대화합니다.
- **Config / API Keys** — 모델과 자격 증명.
- **Sessions / Skills / MCP** — 저장된 작업, 능력, 도구.
- **Channels** — Telegram 및 기타 채팅 앱을 연결합니다.
- **Logs / Cron** — 무슨 일이 있었는지 확인하고 작업을 예약합니다.

## 8단계: 업데이트하기

새 버전이 나오면 프로젝트 폴더에서 다음을 실행하세요:

```bash
docker compose pull
docker compose up -d
```

여러분의 설정, API 키, 세션은 `hermes-home` 볼륨에 안전하게 보관됩니다.

## 자주 묻는 질문

**제 데이터는 안전한가요?** 모든 것이 여러분 자신의 컴퓨터에 있는 Docker 볼륨에 저장됩니다.
여러분이 선택한 AI 모델 외에는 그 어디로도 전송되지 않습니다.

**`localhost:6080` 페이지가 열리지 않아요.** `docker compose up -d` 이후 잠시 기다려 주세요
— 데스크톱이 부팅되는 데 약 30~60초가 걸립니다. 그런 다음 새로고침하세요.

**비밀번호를 잊어버렸어요.** 비밀번호는 `.env`에 있는 `HERMES_PASSWORD`입니다. 그 값을 바꾼 뒤
`docker compose up -d`를 다시 실행하세요.

**에이전트가 (브라우저가 아닌) 일반 데스크톱 앱에 입력할 수 있나요?** 아니요 — 이 이미지는
**브라우저 자동화** 전용으로 만들어졌습니다. README의 "Known limitations"를 참고하세요.

**어떻게 중지하나요?** `docker compose down`을 실행하세요(데이터는 그대로 유지됩니다). 저장된
데이터까지 포함해 모든 것을 지우려면 `docker compose down -v`를 실행하세요.

**Apple Silicon / arm64에서도 작동하나요?** 네 — 이 이미지는 멀티 아키텍처(multi-arch)이므로,
Docker가 여러분의 컴퓨터에 맞는 버전을 자동으로 내려받습니다.
