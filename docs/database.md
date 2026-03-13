# データベース・ストレージ設計書

## 概要

SQLiteを使用した軽量なデータ永続化と、ローカルファイルシステムによるVRMファイル管理を定義する。

## SQLiteデータベース

### ファイル配置

```
data/vitrine.db
```

`data/` ディレクトリはアプリケーション起動時に自動作成される。

### スキーマ定義

#### `vrm_files` テーブル

アップロードされたVRMファイルのメタデータを管理する。

```sql
CREATE TABLE IF NOT EXISTS vrm_files (
  id TEXT PRIMARY KEY,          -- UUID v7
  filename TEXT NOT NULL,       -- 元のファイル名
  title TEXT NOT NULL,          -- 表示名（VRMメタデータ or ファイル名）
  stored_path TEXT NOT NULL,    -- data/vrm/ 以下の保存パス
  file_size INTEGER NOT NULL,   -- バイト数
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
```

#### `pose_presets` テーブル

ポーズプリセットを管理する。

```sql
CREATE TABLE IF NOT EXISTS pose_presets (
  id TEXT PRIMARY KEY,          -- UUID v7
  name TEXT NOT NULL,           -- プリセット名
  bones_json TEXT NOT NULL,     -- ボーンデータ（JSON文字列）
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
```

`bones_json` の構造:

```json
{
  "hips": { "rotation": [0, 0, 0, 1] },
  "spine": { "rotation": [0, 0, 0, 1] },
  "leftUpperArm": { "rotation": [0, 0, 0.3, 0.95] }
}
```

キーはVRM HumanoidボーンのcamelCase名。値はクォータニオン `[x, y, z, w]`。

#### `display_state` テーブル

ディスプレイの永続化状態。サーバー再起動時の状態復元に使用。

```sql
CREATE TABLE IF NOT EXISTS display_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
```

保存するキーと値:

| key | value | 説明 |
|-----|-------|------|
| `currentVrmId` | `string \| null` | 現在選択中のVRM ID |
| `rotation` | `{"y": 0}` | 回転状態（JSON） |
| `scale` | `1.0` | スケール値 |
| `posePresetId` | `string \| null` | 適用中のプリセットID |
| `poseBones` | `{...}` | 適用中のボーンデータ（JSON） |

## VRMファイルストレージ

### ファイル配置

```
data/vrm/
├── 01961234-5678-7abc-def0-123456789abc.vrm
├── 01961234-5678-7abd-def0-123456789abd.vrm
└── ...
```

### 保存ルール

- ファイル名は `{uuid}.vrm` 形式（UUIDはDBのidと一致）
- 元のファイル名はDBの `filename` カラムに保持
- UUID v7を使用（タイムスタンプ順でソート可能）

### 配信

VRMファイルはREST API経由で配信する。

```
GET /api/vrm/:id/file
```

サーバーが `data/vrm/{id}.vrm` を読み取りレスポンスとして返す。`Content-Type: application/octet-stream`。

## マイグレーション方針

### 初期化

アプリケーション起動時に `CREATE TABLE IF NOT EXISTS` でテーブルを作成する。マイグレーションツールは使用せず、シンプルに保つ。

### スキーマバージョン管理

```sql
CREATE TABLE IF NOT EXISTS schema_version (
  version INTEGER PRIMARY KEY
);
```

起動時にバージョンを確認し、必要なマイグレーションを順次適用する。

```typescript
const MIGRATIONS: Array<{ version: number; sql: string }> = [
  {
    version: 1,
    sql: `
      CREATE TABLE vrm_files (...);
      CREATE TABLE pose_presets (...);
      CREATE TABLE display_state (...);
    `,
  },
  // 将来のマイグレーションはここに追加
];
```

### バックアップ

SQLiteは単一ファイルのため、`data/vitrine.db` をコピーするだけでバックアップ可能。

## データアクセスパターン

### VRM操作

```typescript
// 一覧取得
db.prepare('SELECT id, filename, title, file_size, created_at FROM vrm_files ORDER BY created_at DESC').all();

// 登録
db.prepare('INSERT INTO vrm_files (id, filename, title, stored_path, file_size) VALUES (?, ?, ?, ?, ?)').run(...);

// 削除（DBレコード + ファイル）
db.prepare('DELETE FROM vrm_files WHERE id = ?').run(id);
// + fs.unlinkSync(`data/vrm/${id}.vrm`)
```

### ポーズプリセット操作

```typescript
// 一覧取得
db.prepare('SELECT * FROM pose_presets ORDER BY created_at DESC').all();

// 保存
db.prepare('INSERT INTO pose_presets (id, name, bones_json) VALUES (?, ?, ?)').run(id, name, JSON.stringify(bones));

// 削除
db.prepare('DELETE FROM pose_presets WHERE id = ?').run(id);
```

### ディスプレイ状態操作

```typescript
// 状態読み込み（起動時）
const rows = db.prepare('SELECT key, value FROM display_state').all();

// 状態保存（変更時）
db.prepare('INSERT OR REPLACE INTO display_state (key, value) VALUES (?, ?)').run(key, value);
```
