# 通信プロトコル設計書

## 概要

サーバー・操作UI・ディスプレイレンダラー間の通信仕様を定義する。REST APIはCRUD操作に、WebSocketはリアルタイム操作と状態同期に使用する。

## REST API

### ベースURL

```
http://<host>:3000/api
```

### VRM管理

#### `GET /api/vrm`

アップロード済みVRM一覧を取得。

**レスポンス:**

```typescript
{
  vrms: Array<{
    id: string;           // UUID
    filename: string;     // 元のファイル名
    title: string;        // VRMメタデータから抽出 or ファイル名
    fileSize: number;     // バイト数
    createdAt: string;    // ISO 8601
  }>;
}
```

#### `POST /api/vrm`

VRMファイルをアップロード。

**リクエスト:** `multipart/form-data`

| フィールド | 型 | 必須 | 説明 |
|-----------|-----|------|------|
| file | File | Yes | .vrmファイル |

**レスポンス:** `201 Created`

```typescript
{
  id: string;
  filename: string;
  title: string;
  fileSize: number;
  createdAt: string;
}
```

**エラー:**

| ステータス | 条件 |
|-----------|------|
| 400 | ファイルなし、または.vrm以外 |
| 413 | ファイルサイズ超過（上限: 100MB） |

#### `DELETE /api/vrm/:id`

VRMファイルを削除。

**レスポンス:** `204 No Content`

**エラー:**

| ステータス | 条件 |
|-----------|------|
| 404 | 指定IDのVRMが存在しない |

### ポーズプリセット管理

#### `GET /api/poses`

ポーズプリセット一覧を取得。

**レスポンス:**

```typescript
{
  poses: Array<{
    id: string;
    name: string;
    bones: Record<string, { rotation: [number, number, number, number] }>;
    createdAt: string;
  }>;
}
```

#### `POST /api/poses`

ポーズプリセットを保存。

**リクエスト:**

```typescript
{
  name: string;
  bones: Record<string, { rotation: [number, number, number, number] }>;
}
```

**レスポンス:** `201 Created`

```typescript
{
  id: string;
  name: string;
  bones: Record<string, { rotation: [number, number, number, number] }>;
  createdAt: string;
}
```

#### `DELETE /api/poses/:id`

ポーズプリセットを削除。

**レスポンス:** `204 No Content`

### ディスプレイ状態

#### `GET /api/display/state`

現在のディスプレイ状態を取得。初回接続時の状態復元に使用。

**レスポンス:**

```typescript
{
  currentVrmId: string | null;
  rotation: { y: number };
  scale: number;
  pose: {
    presetId: string | null;
    bones: Record<string, { rotation: [number, number, number, number] }>;
  } | null;
}
```

## WebSocketプロトコル

### 接続

```
ws://<host>:3000/ws?role=control
ws://<host>:3000/ws?role=display
```

`role` クエリパラメータでクライアントの役割を指定する。

- `control`: 操作UIクライアント（複数接続可）
- `display`: ディスプレイレンダラー（通常1台）

### メッセージ形式

すべてのメッセージはJSONで、以下の共通構造を持つ。

```typescript
type WsMessage =
  | WsCommand
  | WsStateSync
  | WsEvent
  | WsError;
```

### コマンド（control → サーバー → display）

操作UIから送信され、サーバーが検証・状態更新後にディスプレイに転送する。

```typescript
interface WsCommand {
  type: "command";
  command: string;
  payload: unknown;
}
```

#### `selectVrm` - VRM選択

```typescript
{
  type: "command",
  command: "selectVrm",
  payload: {
    vrmId: string;  // VRM ID。null で選択解除
  }
}
```

#### `setPose` - ポーズ設定

```typescript
{
  type: "command",
  command: "setPose",
  payload: {
    presetId: string | null;  // プリセットID（カスタムの場合null）
    bones: Record<string, {
      rotation: [number, number, number, number];  // クォータニオン [x, y, z, w]
    }>;
  }
}
```

#### `setRotation` - Y軸回転

```typescript
{
  type: "command",
  command: "setRotation",
  payload: {
    y: number;  // ラジアン
  }
}
```

#### `setScale` - スケール変更

```typescript
{
  type: "command",
  command: "setScale",
  payload: {
    scale: number;  // 0.1 〜 3.0
  }
}
```

#### `resetPose` - ポーズリセット

```typescript
{
  type: "command",
  command: "resetPose",
  payload: {}
}
```

### 状態同期（サーバー → 全クライアント）

サーバーの状態が変化したとき、全クライアントにブロードキャストされる。

```typescript
interface WsStateSync {
  type: "stateSync";
  state: {
    currentVrmId: string | null;
    rotation: { y: number };
    scale: number;
    pose: {
      presetId: string | null;
      bones: Record<string, { rotation: [number, number, number, number] }>;
    } | null;
  };
}
```

### イベント（サーバー → クライアント）

サーバーから通知されるイベント。

```typescript
interface WsEvent {
  type: "event";
  event: string;
  payload: unknown;
}
```

#### `vrmAdded` - VRM追加通知

```typescript
{
  type: "event",
  event: "vrmAdded",
  payload: {
    id: string;
    filename: string;
    title: string;
    fileSize: number;
    createdAt: string;
  }
}
```

#### `vrmDeleted` - VRM削除通知

```typescript
{
  type: "event",
  event: "vrmDeleted",
  payload: {
    id: string;
  }
}
```

#### `connected` - 接続確認

接続成功時にサーバーから送信。現在の状態を含む。

```typescript
{
  type: "event",
  event: "connected",
  payload: {
    role: "control" | "display";
    state: { /* DisplayState */ };
  }
}
```

### エラー（サーバー → クライアント）

```typescript
interface WsError {
  type: "error";
  code: string;
  message: string;
}
```

#### エラーコード一覧

| コード | 説明 |
|--------|------|
| `INVALID_MESSAGE` | メッセージのパースに失敗 |
| `INVALID_COMMAND` | 不明なコマンド |
| `INVALID_PAYLOAD` | ペイロードの検証に失敗 |
| `VRM_NOT_FOUND` | 指定VRMが存在しない |
| `INTERNAL_ERROR` | サーバー内部エラー |

## 状態同期の仕組み

### 状態管理

サーバーの `DisplayService` が正規の状態（Single Source of Truth）を保持する。

```typescript
interface DisplayState {
  currentVrmId: string | null;
  rotation: { y: number };
  scale: number;
  pose: {
    presetId: string | null;
    bones: Record<string, { rotation: [number, number, number, number] }>;
  } | null;
}
```

### 同期フロー

1. クライアント接続時: `connected` イベントで現在の状態を送信
2. コマンド受信時: サーバーが状態を更新し、`stateSync` を全クライアントにブロードキャスト
3. displayクライアントが切断・再接続しても、`connected` イベントで状態を復元

### 再接続

WebSocketクライアントは自動再接続を実装する。

- 切断検知後、1秒後に再接続を試行
- 再接続間隔は指数バックオフ（最大30秒）
- 再接続成功時、`connected` イベントで状態を復元

## エラーハンドリング方針

### REST API

- 標準的なHTTPステータスコードを使用
- エラーレスポンスは `{ error: string; details?: string }` 形式
- 入力バリデーションエラーは 400
- 存在しないリソースは 404
- サーバーエラーは 500

### WebSocket

- 不正なメッセージには `WsError` を返却（接続は維持）
- 致命的なエラーの場合のみ接続を切断
- クライアント側は `WsError` を受け取ったらUIにエラー表示
