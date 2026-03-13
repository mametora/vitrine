# ディスプレイレンダラー設計書

## 概要

Three.jsと@pixiv/three-vrmを使用し、VRMモデルをリアルタイム描画するWebアプリケーション。Raspberry Pi 5のChromiumキオスクモードで全画面表示される。黒背景でハーフミラー越しのPepper's Ghost効果を実現する。

## Three.jsシーン構成

### シーン初期化

```typescript
// scene.ts
import * as THREE from "three";

interface SceneConfig {
  canvas: HTMLCanvasElement;
  width: number;
  height: number;
}

function createScene(config: SceneConfig) {
  // レンダラー
  const renderer = new THREE.WebGLRenderer({
    canvas: config.canvas,
    antialias: false,       // Pi 5ではアンチエイリアス無効でパフォーマンス優先
    alpha: false,           // 透過不要（黒背景）
    powerPreference: "low-power",
  });
  renderer.setSize(config.width, config.height);
  renderer.setPixelRatio(1);  // Pi 5ではdevicePixelRatio=1固定
  renderer.outputColorSpace = THREE.SRGBColorSpace;

  // シーン
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x000000);  // 黒背景

  // カメラ
  const camera = new THREE.PerspectiveCamera(
    30,                              // 狭いFOVでフィギュア感を出す
    config.width / config.height,
    0.1,
    20
  );
  camera.position.set(0, 0.8, 2.5);   // モデルの上半身〜全体が収まる位置
  camera.lookAt(0, 0.8, 0);

  // ライティング
  const ambientLight = new THREE.AmbientLight(0xffffff, 0.6);
  scene.add(ambientLight);

  const directionalLight = new THREE.DirectionalLight(0xffffff, 0.8);
  directionalLight.position.set(1, 2, 1);
  scene.add(directionalLight);

  // 下からのリムライト（フィギュア感の演出）
  const rimLight = new THREE.DirectionalLight(0x4488ff, 0.3);
  rimLight.position.set(0, -1, 0.5);
  scene.add(rimLight);

  return { renderer, scene, camera };
}
```

### 描画ループ

```typescript
const clock = new THREE.Clock();

function animate() {
  requestAnimationFrame(animate);

  const delta = clock.getDelta();

  // VRM SpringBone更新
  if (currentVrm) {
    currentVrm.update(delta);
  }

  // パフォーマンスモニタ更新
  performanceMonitor.update();

  renderer.render(scene, camera);
}
```

## VRM読み込みパイプライン

### ローダー設定

```typescript
// vrm-loader.ts
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { VRMLoaderPlugin, VRM } from "@pixiv/three-vrm";

const gltfLoader = new GLTFLoader();
gltfLoader.register((parser) => new VRMLoaderPlugin(parser));

async function loadVrm(url: string): Promise<VRM> {
  const gltf = await gltfLoader.loadAsync(url);
  const vrm = gltf.userData.vrm as VRM;

  // VRM 0.x互換: lookAtを無効化（フィギュアなので不要）
  if (vrm.lookAt) {
    vrm.lookAt.autoUpdate = false;
  }

  // T-poseからデフォルトポーズへの初期化
  vrm.humanoid.resetNormalizedPose();

  return vrm;
}
```

### VRM切り替え

```typescript
let currentVrm: VRM | null = null;

async function switchVrm(vrmId: string): Promise<void> {
  // 既存モデルを破棄
  if (currentVrm) {
    scene.remove(currentVrm.scene);
    currentVrm.scene.traverse((obj) => {
      if (obj instanceof THREE.Mesh) {
        obj.geometry.dispose();
        if (Array.isArray(obj.material)) {
          obj.material.forEach((m) => m.dispose());
        } else {
          obj.material.dispose();
        }
      }
    });
    currentVrm = null;
  }

  if (!vrmId) return;

  // 新しいモデルを読み込み
  const vrm = await loadVrm(`/api/vrm/${vrmId}/file`);
  currentVrm = vrm;
  scene.add(vrm.scene);
}
```

## SpringBone物理更新

`VRM.update(delta)` の呼び出しにより、SpringBoneが自動的に更新される。

```typescript
// 描画ループ内で毎フレーム呼び出す
if (currentVrm) {
  currentVrm.update(delta);
}
```

### 注意事項

- `delta` が大きすぎると物理が不安定になるため、上限を設ける
- Pi 5ではフレームレートが低下する場合があるので、deltaを `Math.min(delta, 0.05)` でクランプ

```typescript
const delta = Math.min(clock.getDelta(), 0.05); // 最大50ms = 20FPS相当
```

## ポーズ適用

### VRMHumanoid API

```typescript
import { VRMHumanBoneName } from "@pixiv/three-vrm";

interface BonePose {
  rotation: [number, number, number, number]; // quaternion [x, y, z, w]
}

function applyPose(vrm: VRM, bones: Record<string, BonePose>): void {
  // まずリセット
  vrm.humanoid.resetNormalizedPose();

  // 各ボーンにクォータニオンを適用
  for (const [boneName, pose] of Object.entries(bones)) {
    const node = vrm.humanoid.getNormalizedBoneNode(boneName as VRMHumanBoneName);
    if (node) {
      node.quaternion.set(
        pose.rotation[0],
        pose.rotation[1],
        pose.rotation[2],
        pose.rotation[3],
      );
    }
  }
}

function resetPose(vrm: VRM): void {
  vrm.humanoid.resetNormalizedPose();
}
```

### 回転・スケール適用

```typescript
function setModelRotation(vrm: VRM, y: number): void {
  vrm.scene.rotation.y = y;
}

function setModelScale(vrm: VRM, scale: number): void {
  vrm.scene.scale.setScalar(scale);
}
```

## パフォーマンス最適化戦略

### Pi 5のGPU特性

- VideoCore VII GPU（Vulkan 1.2対応）
- 共有メモリ（専用VRAMなし）
- WebGLで利用可能な性能は限定的

### 最適化設定

| 項目 | 設定 | 理由 |
|------|------|------|
| `antialias` | `false` | GPU負荷を大幅に削減 |
| `pixelRatio` | `1` | 高DPIスケーリング無効 |
| `shadowMap` | 無効 | シャドウマップ計算を省略 |
| FOV | `30` | 描画範囲を狭くしてフィルレート削減 |
| テクスチャ | 必要に応じてリサイズ | VRAM節約 |

### 適応的品質調整

FPS監視に基づく自動品質調整システム。

```typescript
// performance.ts

interface QualityLevel {
  name: string;
  pixelRatio: number;
  springBoneEnabled: boolean;
}

const QUALITY_LEVELS: QualityLevel[] = [
  { name: "high",   pixelRatio: 1.0, springBoneEnabled: true },
  { name: "medium", pixelRatio: 0.75, springBoneEnabled: true },
  { name: "low",    pixelRatio: 0.5,  springBoneEnabled: false },
];

class PerformanceMonitor {
  private frames = 0;
  private lastTime = performance.now();
  private currentFps = 60;
  private qualityIndex = 0;
  private readonly targetFps = 20;
  private readonly checkInterval = 3000; // 3秒ごとに評価

  update(): void {
    this.frames++;
    const now = performance.now();
    const elapsed = now - this.lastTime;

    if (elapsed >= this.checkInterval) {
      this.currentFps = (this.frames * 1000) / elapsed;
      this.frames = 0;
      this.lastTime = now;
      this.adjustQuality();
    }
  }

  private adjustQuality(): void {
    if (this.currentFps < this.targetFps && this.qualityIndex < QUALITY_LEVELS.length - 1) {
      this.qualityIndex++;
      this.applyQuality();
    } else if (this.currentFps > this.targetFps * 1.5 && this.qualityIndex > 0) {
      this.qualityIndex--;
      this.applyQuality();
    }
  }

  private applyQuality(): void {
    const level = QUALITY_LEVELS[this.qualityIndex];
    renderer.setPixelRatio(level.pixelRatio);
    // SpringBone有効/無効はVRM updateの呼び出し制御で対応
  }

  getFps(): number {
    return this.currentFps;
  }

  getQualityLevel(): string {
    return QUALITY_LEVELS[this.qualityIndex].name;
  }
}
```

## WebSocketクライアント

```typescript
// ws-client.ts
import type { WsMessage, WsCommand, WsStateSync } from "@vitrine/shared";

type CommandHandler = (command: WsCommand) => void;
type StateSyncHandler = (state: WsStateSync["state"]) => void;

class DisplayWsClient {
  private ws: WebSocket | null = null;
  private reconnectDelay = 1000;
  private onCommand: CommandHandler;
  private onStateSync: StateSyncHandler;

  constructor(onCommand: CommandHandler, onStateSync: StateSyncHandler) {
    this.onCommand = onCommand;
    this.onStateSync = onStateSync;
    this.connect();
  }

  private connect(): void {
    const protocol = location.protocol === "https:" ? "wss:" : "ws:";
    this.ws = new WebSocket(`${protocol}//${location.host}/ws?role=display`);

    this.ws.onopen = () => {
      this.reconnectDelay = 1000;
    };

    this.ws.onmessage = (evt) => {
      const msg: WsMessage = JSON.parse(evt.data);
      switch (msg.type) {
        case "command":
          this.onCommand(msg);
          break;
        case "stateSync":
          this.onStateSync(msg.state);
          break;
        case "event":
          if (msg.event === "connected") {
            this.onStateSync(msg.payload.state);
          }
          break;
      }
    };

    this.ws.onclose = () => {
      setTimeout(() => {
        this.reconnectDelay = Math.min(this.reconnectDelay * 2, 30000);
        this.connect();
      }, this.reconnectDelay);
    };
  }
}
```

## 画面構成

```html
<!-- index.html -->
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Vitrine Display</title>
  <style>
    * { margin: 0; padding: 0; }
    body { overflow: hidden; background: #000; }
    canvas { display: block; width: 100vw; height: 100vh; }
  </style>
</head>
<body>
  <canvas id="display-canvas"></canvas>
  <script type="module" src="/src/main.ts"></script>
</body>
</html>
```

## 依存パッケージ

```json
{
  "dependencies": {
    "three": "^0.183.2",
    "@pixiv/three-vrm": "^3.4.5",
    "@vitrine/shared": "workspace:*"
  },
  "devDependencies": {
    "@types/three": "^0.183.0",
    "vite": "^8.0.0",
    "typescript": "^5.9.0"
  }
}
```
