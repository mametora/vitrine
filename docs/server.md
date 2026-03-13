# バックエンドサーバー設計書

## 概要

Honoフレームワークを使用したNode.jsサーバー。REST API、WebSocketハンドラ、静的ファイル配信を単一プロセスで提供する。

## アプリケーション構造

```
packages/server/src/
├── index.ts              # エントリーポイント（サーバー起動）
├── app.ts                # Honoアプリ定義（ルーティング集約）
├── db/
│   ├── connection.ts     # SQLite接続・初期化
│   └── migrations.ts     # スキーママイグレーション
├── routes/
│   ├── vrm.ts            # VRM管理API
│   ├── poses.ts          # ポーズプリセットAPI
│   └── display.ts        # ディスプレイ状態API
├── ws/
│   └── handler.ts        # WebSocketハンドラ
└── services/
    └── display-service.ts # DisplayService（状態管理）
```

## エントリーポイント

### `index.ts`

```typescript
import { serve } from "@hono/node-server";
import { app } from "./app.js";
import { initDb } from "./db/connection.js";

const PORT = Number(process.env.PORT ?? 3000);

// DB初期化
initDb();

// サーバー起動
serve({ fetch: app.fetch, port: PORT }, (info) => {
  console.log(`Server running at http://localhost:${info.port}`);
});
```

## Honoアプリ定義

### `app.ts`

```typescript
import { Hono } from "hono";
import { serveStatic } from "@hono/node-server/serve-static";
import { vrmRoutes } from "./routes/vrm.js";
import { posesRoutes } from "./routes/poses.js";
import { displayRoutes } from "./routes/display.js";
import { wsHandler } from "./ws/handler.js";

const app = new Hono();

// REST API
app.route("/api/vrm", vrmRoutes);
app.route("/api/poses", posesRoutes);
app.route("/api/display", displayRoutes);

// WebSocket
app.get("/ws", wsHandler);

// 静的ファイル配信（ビルド済みフロントエンド）
app.use("/display/*", serveStatic({ root: "./public/display" }));
app.use("/control/*", serveStatic({ root: "./public/control" }));

// SPA フォールバック
app.get("/display/*", serveStatic({ path: "./public/display/index.html" }));
app.get("/control/*", serveStatic({ path: "./public/control/index.html" }));

export { app };
```

## ルーティング設計

### VRM管理 (`routes/vrm.ts`)

```typescript
import { Hono } from "hono";

const vrmRoutes = new Hono();

// VRM一覧取得
vrmRoutes.get("/", async (c) => {
  // db.prepare('SELECT ...').all()
  // return c.json({ vrms })
});

// VRMアップロード
vrmRoutes.post("/", async (c) => {
  // 1. multipart/form-data からファイル取得
  // 2. バリデーション（拡張子、サイズ）
  // 3. UUID v7生成
  // 4. data/vrm/{id}.vrm に保存
  // 5. DBにメタデータ登録
  // 6. WebSocketで vrmAdded イベント通知
  // 7. return c.json(vrm, 201)
});

// VRMファイル配信
vrmRoutes.get("/:id/file", async (c) => {
  // data/vrm/{id}.vrm を読み取ってレスポンス
});

// VRM削除
vrmRoutes.delete("/:id", async (c) => {
  // 1. DBからレコード削除
  // 2. data/vrm/{id}.vrm を削除
  // 3. WebSocketで vrmDeleted イベント通知
  // 4. return c.body(null, 204)
});
```

### ポーズプリセット (`routes/poses.ts`)

```typescript
const posesRoutes = new Hono();

// ポーズ一覧
posesRoutes.get("/", async (c) => { /* ... */ });

// ポーズ保存
posesRoutes.post("/", async (c) => { /* ... */ });

// ポーズ削除
posesRoutes.delete("/:id", async (c) => { /* ... */ });
```

### ディスプレイ状態 (`routes/display.ts`)

```typescript
const displayRoutes = new Hono();

// 現在の状態取得
displayRoutes.get("/state", async (c) => {
  // DisplayService.getState() を返却
});
```

## DisplayService ステートマシン

### 責務

- ディスプレイ状態の一元管理（Single Source of Truth）
- コマンドの検証と状態更新
- 状態の永続化（SQLite display_state テーブル）
- WebSocket経由の状態同期

### 実装

```typescript
import type { DisplayState, WsCommand } from "@vitrine/shared";

class DisplayService {
  private state: DisplayState = {
    currentVrmId: null,
    rotation: { y: 0 },
    scale: 1.0,
    pose: null,
  };

  // 起動時にDBから状態復元
  restoreState(): void { /* ... */ }

  // 状態取得
  getState(): DisplayState {
    return structuredClone(this.state);
  }

  // コマンド処理
  handleCommand(command: WsCommand): DisplayState {
    switch (command.command) {
      case "selectVrm":
        this.state.currentVrmId = command.payload.vrmId;
        break;
      case "setPose":
        this.state.pose = command.payload;
        break;
      case "setRotation":
        this.state.rotation = command.payload;
        break;
      case "setScale":
        this.state.scale = command.payload.scale;
        break;
      case "resetPose":
        this.state.pose = null;
        break;
    }
    this.persistState();
    return this.getState();
  }

  // 状態をDBに永続化
  private persistState(): void { /* ... */ }
}

export const displayService = new DisplayService();
```

## WebSocketハンドラ

### ロール管理

```typescript
interface WsClient {
  ws: WSContext;
  role: "control" | "display";
}

const clients = new Set<WsClient>();
```

### ハンドラ実装

```typescript
import { createNodeWebSocket } from "@hono/node-ws";

const { injectWebSocket, upgradeWebSocket } = createNodeWebSocket({ app });

const wsHandler = upgradeWebSocket((c) => {
  const role = c.req.query("role") as "control" | "display";

  return {
    onOpen(evt, ws) {
      const client: WsClient = { ws, role };
      clients.add(client);

      // 接続確認 + 現在の状態を送信
      ws.send(JSON.stringify({
        type: "event",
        event: "connected",
        payload: {
          role,
          state: displayService.getState(),
        },
      }));
    },

    onMessage(evt, ws) {
      const msg = JSON.parse(evt.data as string);

      if (msg.type === "command") {
        // DisplayServiceでコマンド処理
        const newState = displayService.handleCommand(msg);

        // displayクライアントにコマンドを転送
        broadcastToRole("display", msg);

        // 全クライアントに状態同期
        broadcastAll({
          type: "stateSync",
          state: newState,
        });
      }
    },

    onClose(evt, ws) {
      // クライアントを削除
      for (const client of clients) {
        if (client.ws === ws) {
          clients.delete(client);
          break;
        }
      }
    },
  };
});
```

### ブロードキャスト関数

```typescript
function broadcastAll(msg: unknown): void {
  const data = JSON.stringify(msg);
  for (const client of clients) {
    client.ws.send(data);
  }
}

function broadcastToRole(role: string, msg: unknown): void {
  const data = JSON.stringify(msg);
  for (const client of clients) {
    if (client.role === role) {
      client.ws.send(data);
    }
  }
}
```

## 静的ファイル配信

ビルド時にフロントエンド（display / control）の成果物を `packages/server/public/` に配置する。

```
packages/server/public/
├── display/
│   ├── index.html
│   └── assets/
└── control/
    ├── index.html
    └── assets/
```

開発時は Vite の dev server を使用し、サーバーにはAPIとWebSocketのみを担当させる。

## 環境変数

```
PORT=3000          # サーバーポート
DATA_DIR=./data    # データディレクトリパス
```

## 依存パッケージ

```json
{
  "dependencies": {
    "hono": "^4.12.7",
    "@hono/node-server": "^1.x",
    "@hono/node-ws": "^1.x",
    "better-sqlite3": "^12.7.1",
    "@vitrine/shared": "workspace:*"
  },
  "devDependencies": {
    "@types/better-sqlite3": "^7.x",
    "typescript": "^5.9.0"
  }
}
```
