# Hermes Agent Desktop — 初心者ガイド

🇺🇸 [English](GUIDE_FOR_BEGINNERS.md) | 🇰🇷 [한국어](GUIDE_FOR_BEGINNERS.ko.md) | 🇨🇳 [中文](GUIDE_FOR_BEGINNERS.zh.md) | 🇯🇵 [日本語](GUIDE_FOR_BEGINNERS.ja.md)

技術にあまり詳しくなくても心配いりません。このガイドを上から順に進めていけば、
約15分で、AIエージェントがあなたの代わりにウェブを閲覧してくれるようになります —
しかも、その様子を自分の目で見られるデスクトップ上で動きます。

## これは何ですか？

Hermes Agent Desktop は、**Docker の中で動く完全な Ubuntu デスクトップ**で、
**Hermes AI エージェント**（Nous Research 製）があらかじめインストールされています。
エージェントはあなたの代わりに本物の Chrome ブラウザを操作し、その様子をあなたは
自分のウェブブラウザを通してリアルタイムで見守ります。あなたのコンピューターには
Docker 以外には何もインストールされません。

これは、**あなたのコンピューターの中に住むもう一台のコンピューター**だと考えてください。
そこでは、あなたが見守る間、AI がブラウザ内でクリックや入力を行ってくれます。

## 必要なもの

- **Windows、macOS、または Linux** が動作するコンピューター。
- 約 **8 GB の空きディスク容量**と **4 GB の空き RAM**。
- **AI モデルの API キー** — 無料の **Nous Portal** アカウントで大丈夫です（ステップ5で設定します）。
- 約 **15分**。

コードの書き方を知っている**必要はありません**。

## ステップ1：Docker Desktop をインストールする

Docker は仮想デスクトップを動かすためのプログラムです。一度だけインストールします。

### Windows
1. <https://www.docker.com/products/docker-desktop/> にアクセスして、**Download for Windows** をクリックします。
2. インストーラーを実行し、設定はそのままにして、求められたら再起動します。
3. **Docker Desktop** を開き、**「Engine running」**と表示されるまで待ちます。

### macOS
1. <https://www.docker.com/products/docker-desktop/> にアクセスして、**Download for Mac** をクリックします
   （M1/M2/M3/M4 なら **Apple Silicon**、それより古い Mac なら **Intel** を選びます）。
2. `.dmg` を開いて、**Docker** をアプリケーションフォルダにドラッグします。
3. Docker を起動して、**「Engine running」**と表示されるまで待ちます。

### Ubuntu / Linux
1. <https://docs.docker.com/engine/install/ubuntu/> に従って Docker Engine をインストールします。
2. ターミナルで `docker compose version` を実行し、バージョンが表示されることを確認します。

## ステップ2：プロジェクトファイルを作成する

新しいフォルダ（例えば `hermes-desktop`）を作り、その中に**2つのファイル**を入れます。

**ファイル1 — `compose.yaml`：**

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

**ファイル2 — `.env`**（自分でパスワードを決めてください！）：

```bash
HERMES_USER=hermes
HERMES_PASSWORD=change-this-password
```

## ステップ3：仮想コンピューターを起動する

そのフォルダの**中で**ターミナルを開き、次を実行します：

```bash
docker compose up -d
```

初回は、Docker がイメージをダウンロードします（数分かかります）。完了すると、
デスクトップはバックグラウンドで静かに動き続けます。

**フォルダ内でターミナルを開く方法：**
- **Windows**：エクスプローラーでフォルダを開き、アドレスバーに `cmd` と入力して Enter を押します。
- **macOS**：フォルダを右クリック →**「フォルダに新規ターミナル」**。
- **Ubuntu**：フォルダ内で右クリック →**「ターミナルで開く」**。

## ステップ4：デスクトップに接続する

ウェブブラウザを開いて、次にアクセスします：

**<http://localhost:6080/vnc.html>**

**Connect** をクリックし、`.env` で設定したパスワードを入力すると、完全な Ubuntu
デスクトップが表示されます。🎉

> リモートデスクトップアプリのほうが好みですか？ ユーザー名 `hermes` で `localhost:3390` に接続してください。
> VNC クライアントのほうが好みですか？ `localhost:5901` を使ってください。3つとも**同じ**デスクトップが表示されます。

## ステップ5：AI モデルを設定する（初回のみ）

エージェントが考えるためには AI モデルが必要です。一番簡単な無料の選択肢は **Nous Portal** です。

1. 2つ目のブラウザタブを開いて **<http://localhost:9119>** にアクセスします — これが**ダッシュボード**です。
2. ユーザー名 `hermes` と自分のパスワードでログインします。
3. **API Keys** タブを開きます。
4. プロバイダーとして **Nous** を選び、画面の指示に従ってログインします（無料アカウントで大丈夫です）。
5. **ビジョン + ツール**に対応したモデルを選びます（エージェントが見ることと操作することの両方をできるように）。
6. 保存します。

> ヒント：デスクトップ上の**「Hermes Setup」**アイコンをダブルクリックして、ガイド付きの
> ウィザードを実行する方法もあります。

## ステップ6：エージェントに代わりにブラウズしてもらう

ここが楽しいところです。

1. ダッシュボードで **Chat** タブを開きます。
2. ウェブ上で何かをするように頼んでみましょう。例えば：
   > 「example.com を開いて、メインの見出しを教えて。」
3. デスクトップのタブ（`localhost:6080`）に切り替えて**見守りましょう** — Chrome ウィンドウが
   開き、エージェントがあなたの代わりにページを読んでクリックします。

エージェントは、コンテナの**内部**にとどまる安全な接続（CDP）を通して Chrome を操作するので、
この自動操作がインターネットに公開されることは決してありません。

## ステップ7：ダッシュボードを使う

ダッシュボード（`localhost:9119`）には、あらゆる用途のタブがあります：

- **Status** — すべてが正常に動いていますか？
- **Chat** — エージェントと話します。
- **Config / API Keys** — モデルと認証情報。
- **Sessions / Skills / MCP** — 保存した作業、能力、ツール。
- **Channels** — Telegram などのチャットアプリと連携します。
- **Logs / Cron** — 何が起きたかを確認し、タスクをスケジュールします。

## ステップ8：アップデートする

新しいバージョンが公開されたら、プロジェクトフォルダで次を実行します：

```bash
docker compose pull
docker compose up -d
```

設定、API キー、セッションは `hermes-home` ボリュームに安全に保存されます。

## よくある質問

**私のデータは安全ですか？** すべてはあなた自身のマシン上の Docker ボリュームに保存されます。
あなたが選んだ AI モデル以外には、どこにも何も送信されません。

**`localhost:6080` のページが読み込まれません。** `docker compose up -d` の後、少し待ってください
— デスクトップの起動には約30〜60秒かかります。それから再読み込みしてください。

**パスワードを忘れました。** それは `.env` の中の `HERMES_PASSWORD` です。変更してから、もう一度
`docker compose up -d` を実行してください。

**エージェントは（ブラウザ以外の）通常のデスクトップアプリに入力できますか？** いいえ — このイメージは
**ブラウザ自動操作**専用に作られています。README の「Known limitations」を参照してください。

**どうやって停止しますか？** `docker compose down` を実行します（データは保持されます）。保存したデータも
含めてすべてを消去するには、`docker compose down -v` を実行します。

**Apple Silicon / arm64 で動作しますか？** はい — イメージはマルチアーキテクチャ対応なので、Docker が
あなたのコンピューターに合った正しいバージョンを自動的に取得します。
