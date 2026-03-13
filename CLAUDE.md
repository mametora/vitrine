# Vitrine

VRM フィギュアを Pepper's Ghost 方式で表示するシステム。Raspberry Pi 5 + ハーフミラー構成。

## プロジェクト構成

pnpm workspaces によるモノレポ（未実装。設計書は `docs/` に格納済み）。

```
vitrine/
├── docs/               # 設計書
├── packages/
│   ├── shared/         # 共有型定義・プロトコル・定数
│   ├── server/         # Hono バックエンド
│   ├── display/        # Three.js ディスプレイレンダラー
│   └── control/        # SolidJS 操作UI
└── data/               # ランタイムデータ（gitignore）
```

## 開発ルール

### 設計書ファースト

- 新機能や大きな変更は、まず `docs/` に設計書を作成する
- 設計書はユーザーの確認・承認を得てから実装に着手する
- 各設計書は 1 つの LLM セッションで扱える粒度にする

### コーディング

- TypeScript を全パッケージで使用
- TypeScript Deep Dive のスタイルガイドに従う
- コード内コメントは英語
- ドキュメント・設計書は日本語

### 依存関係

- ライブラリ・ランタイムは最新安定版を使用する
- 主要バージョン: Node.js 24.x / pnpm 10.x / TypeScript 5.9.x / Vite 8.x

### コミット

- Conventional Commits に従う
- コミットメッセージは英語
