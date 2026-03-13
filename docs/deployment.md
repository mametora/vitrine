# デプロイ・運用設計書

## 概要

Raspberry Pi 5にHolo Figureシステムをデプロイし、Chromiumキオスクモードでディスプレイレンダラーを自動起動する手順を定義する。

## Raspberry Pi 5 セットアップ

### 必要なハードウェア

- Raspberry Pi 5（4GB以上推奨）
- microSDカード（32GB以上）
- 小型ディスプレイ（HDMI接続、5〜7インチ推奨）
- ハーフミラー + フレーム（Pepper's Ghost構成用）
- 電源アダプタ（USB-C 5V/5A）

### OS

Raspberry Pi OS Lite (64-bit) + 必要なGUIパッケージのみインストール。

```bash
# Raspberry Pi Imager で Raspberry Pi OS Lite (64-bit) を書き込み
# 初期設定（SSH有効化、Wi-Fi設定）はImagerのAdvanced Optionsで実施
```

### 基本セットアップ

```bash
# パッケージ更新
sudo apt update && sudo apt upgrade -y

# GUI関連（Chromium表示に必要な最小限）
sudo apt install -y \
  chromium-browser \
  xserver-xorg \
  xinit \
  x11-xserver-utils \
  unclutter

# Node.js 24.x (fnm経由)
curl -fsSL https://fnm.vercel.app/install | bash
fnm install 24
fnm default 24

# pnpm
corepack enable
corepack prepare pnpm@latest --activate

# GPU メモリ割り当て増加
echo "gpu_mem=256" | sudo tee -a /boot/firmware/config.txt
```

## ビルド & デプロイ

### ビルドスクリプト

開発マシンまたはPi上でビルドし、成果物を配置する。

```bash
#!/bin/bash
# scripts/build.sh

set -e

# 依存インストール
pnpm install

# 共有パッケージビルド
pnpm -F @holo-figure/shared build

# フロントエンドビルド
pnpm -F @holo-figure/display build
pnpm -F @holo-figure/control build

# サーバーにフロントエンド成果物を配置
mkdir -p packages/server/public
cp -r packages/display/dist packages/server/public/display
cp -r packages/control/dist packages/server/public/control

# サーバービルド
pnpm -F @holo-figure/server build

echo "Build complete!"
```

### デプロイスクリプト

開発マシンからPiへデプロイする。

```bash
#!/bin/bash
# scripts/deploy.sh

PI_HOST="${PI_HOST:-pi@raspberrypi.local}"
DEPLOY_DIR="/opt/holo-figure"

set -e

# ビルド
./scripts/build.sh

# rsyncで転送
rsync -avz --delete \
  --exclude=node_modules \
  --exclude=.git \
  --exclude=data \
  packages/server/dist/ \
  packages/server/public/ \
  packages/server/package.json \
  "${PI_HOST}:${DEPLOY_DIR}/"

# Pi上で依存インストール & サービス再起動
ssh "${PI_HOST}" << 'EOF'
  cd /opt/holo-figure
  pnpm install --prod
  sudo systemctl restart holo-figure
EOF

echo "Deploy complete!"
```

## Chromiumキオスクモード

### 起動スクリプト

```bash
#!/bin/bash
# scripts/kiosk.sh

# 画面の電源管理を無効化
xset s off
xset -dpms
xset s noblank

# カーソルを非表示
unclutter -idle 0.1 -root &

# Chromiumをキオスクモードで起動
chromium-browser \
  --kiosk \
  --no-first-run \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-translate \
  --noerrdialogs \
  --incognito \
  --disable-gpu-compositing \
  --enable-features=Vulkan \
  "http://localhost:3000/display/"
```

### X11自動起動

```bash
# ~/.xinitrc
exec /opt/holo-figure/scripts/kiosk.sh
```

```bash
# ~/.bash_profile に追加（自動ログイン + X起動）
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  startx
fi
```

### 自動ログイン設定

```bash
sudo raspi-config
# System Options → Boot / Auto Login → Console Autologin
```

## systemdサービス

### Holo Figureサーバー

```ini
# /etc/systemd/system/holo-figure.service
[Unit]
Description=Holo Figure Server
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/opt/holo-figure
ExecStart=/home/pi/.local/share/fnm/aliases/default/bin/node dist/index.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production
Environment=PORT=3000
Environment=DATA_DIR=/opt/holo-figure/data

[Install]
WantedBy=multi-user.target
```

### サービス登録

```bash
sudo systemctl daemon-reload
sudo systemctl enable holo-figure
sudo systemctl start holo-figure
```

### 動作確認

```bash
# サービス状態確認
sudo systemctl status holo-figure

# ログ確認
sudo journalctl -u holo-figure -f
```

## ハーフミラーディスプレイの物理構成

### Pepper's Ghost方式

```
       ┌─────────────────┐
       │  ハーフミラー    │  45°で設置
       │  (アクリル板)    │
       └────────┬────────┘
                │ ↗ 反射像（浮遊するフィギュア）
                │
   ┌────────────┴────────────┐
   │     小型ディスプレイ     │  上向きに設置
   │     (黒背景 + VRM描画)  │
   └─────────────────────────┘
   │         筐体             │
   └─────────────────────────┘
```

### 構成のポイント

1. **ディスプレイ**: 上向き（画面が天井方向）に設置
2. **ハーフミラー**: ディスプレイの上に45°の角度で設置
3. **黒背景**: 描画領域以外は完全な黒（`#000000`）。ハーフミラーが黒を透過し、明るい部分のみ反射
4. **筐体**: 外光を遮断するケース。黒い内装で反射を防止
5. **視点**: ハーフミラーの正面から観察

### 推奨パーツ

| パーツ | 仕様 |
|--------|------|
| ディスプレイ | 5〜7インチ HDMI IPS液晶 |
| ハーフミラー | アクリル製ハーフミラー板（透過率50%程度） |
| 筐体 | 3Dプリント or 木製フレーム |
| 固定 | アクリル板用スタンド or 3Dプリントブラケット |

## トラブルシューティング

### よくある問題

| 症状 | 対処 |
|------|------|
| Chromiumが起動しない | `gpu_mem=256` を確認、`--disable-gpu-compositing` オプション追加 |
| FPSが極端に低い | 適応的品質調整が動作しているか確認。ブラウザのdev toolsでパフォーマンス計測 |
| WebSocket接続が切れる | ネットワーク状態確認。自動再接続が動作しているか確認 |
| VRMが表示されない | コンソールエラー確認。VRMファイルの破損チェック |
| 画面がスリープする | `xset` 設定確認。`/etc/lightdm/lightdm.conf` のスリープ設定確認 |
