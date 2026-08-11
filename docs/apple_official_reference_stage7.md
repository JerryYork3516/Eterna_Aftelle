# Stage 7 Apple Official Reference

> 用途:给 Stage 7 macOS 单机 Runtime Host 提供最小 Apple 官方文档入口。
> 性质:实现参考索引,不是 Aftelle 架构事实源,也不是新阶段计划。

## 用途

当 Stage 7 任务涉及 SwiftUI、Metal、FileManager、Keychain、Human Interface Guidelines 或 Accessibility 时,只按当前节点读取最小相关 Apple 官方文档。不要为了"系统学习 Apple 平台"一次性扩展阅读范围。

本文档只回答"当前 macOS 节点该参考哪类 Apple 官方资料",不改变:

- `docs/02_architecture.md`
- `docs/aftelle_runtime_boundary.md`
- `docs/03_dev_plan.md`
- `docs/runtime_api_contract.md`
- `docs/dr_contract_v0_3.md`
- `docs/provider_profile_contract.md`

如果 Apple 官方文档与 Stage 7 项目文档冲突,必须停止并报告冲突点,不得自行修改架构、Runtime API、DR schema 或阶段范围。

## 允许参考范围

只允许按当前任务需要参考以下 Apple 官方类别:

- SwiftUI / Scene / macOS Window
  - https://developer.apple.com/documentation/swiftui
- Metal
  - https://developer.apple.com/documentation/metal
- FileManager / Application Support
  - https://developer.apple.com/documentation/foundation/filemanager
- Keychain
  - https://developer.apple.com/documentation/security/keychain-services
- Human Interface Guidelines / macOS / Motion / Materials
  - https://developer.apple.com/design/human-interface-guidelines/macos
  - https://developer.apple.com/design/human-interface-guidelines/motion
  - https://developer.apple.com/design/human-interface-guidelines/materials
- Accessibility / Reduce Motion
  - https://developer.apple.com/design/human-interface-guidelines/accessibility

## 禁止扩展范围

Stage 7 不因 Apple 官方文档参考而进入以下范围:

- iOS / iPadOS / visionOS 正式适配
- ARKit / RealityKit 正式功能
- WatchKit / TVUIKit
- CloudKit / iCloud Sync
- Push Notification
- App Store 完整审核规划
- 多平台 target

以上内容即使出现在 Apple 官方文档导航中,Stage 7 也只视为后续阶段背景,不得作为当前实现依据。

## 使用规则

1. 先读 Aftelle 项目文档,再按当前节点打开最小 Apple 官方文档。
2. Apple 官方文档只用于实现语义、平台 API 约束、系统交互习惯、视觉/动效可访问性参考。
3. 不复制 Apple 官方文档全文;只记录必要链接、结论和项目内决策。
4. 不把 Apple 文档中的平台能力自动升级为 Stage 7 功能。
5. 不因 Apple 文档新增 Swift / Xcode / project target / entitlement / capability。
6. 涉及 secret 时,仍以项目边界为准:Provider secret 只经 `key_ref` 引用,真实值由 Apple Keychain 持有,RuntimeCore 通过 ProviderRouter / ProviderAdapter 使用。
7. 涉及视觉或动效时,仍以 Stage 7 粒子生命体和 `visual_state` / `resident_state` 输入为准;Aftelle 只渲染,不推理人格或情绪。

## Stage 7 节点映射

| Stage 7 节点 | 可参考 Apple 官方文档类别 | 用途 | 禁止扩展 |
|---|---|---|---|
| 7.1 技术底座 / Shell / Provider 配置 | SwiftUI / Scene / macOS Window; Keychain | App shell、窗口生命周期、`key_ref` 配置入口 | 不新增平台 target;不接真实 Provider;不改 Runtime API |
| 7.2 会话与展示缓存 | FileManager / Application Support | 本地 session/display cache 文件位置与目录语义 | 不做 iCloud / CloudKit sync;不写回 DR |
| 7.3 粒子生命体视觉底座 + 字幕 | Metal; HIG Motion; Accessibility / Reduce Motion | 粒子渲染、降频动效、可访问性动效边界 | 不做 ARKit / RealityKit;不做 3D 数字人;不进入 Stage 8 |
| 7.4 人文共情居民打磨 | HIG macOS / Motion / Materials | 视觉克制、材料感、动效节奏参考 | 不改变居民人格来源;不让 Aftelle 推理人格或情绪 |
| 7.5 前台原生实时语音 / 级联降级 / 字幕 | AVFoundation; Keychain; Accessibility / Reduce Motion | 麦克风与播放平台资源、Provider secret 引用边界、字幕与动效可访问性 | RuntimeCore 拥有会话与 Provider 路由;Host / UI / Adapter 不直连 Provider,不引入 always-on 或后台监听 |
| 7.9 屏幕捕获指导原型 | Accessibility | Aftelle 内部指导原型的可访问性语义参考 | 不做通用电脑控制;不跨 App 操作 |
| 7.10 Windows / AR 适配隔离验证 | Accessibility; HIG Motion | 只做隔离验证和未来 Host 预留 | 不引入 ARKit / RealityKit 正式功能;不新增多平台 target |

## 冲突处理

若出现以下情况,结论必须是 REWORK 或停止:

- Apple 官方文档建议与 `aftelle_runtime_boundary.md` 冲突。
- Apple 官方文档会导致新增平台 target、Runtime API 字段、DR schema 字段或 Provider Profile 字段。
- Apple 官方文档诱导实现 iOS / visionOS / ARKit / RealityKit / CloudKit / Push Notification。
- Apple 官方文档要求复制 RuntimeCore 职责到 Host。

处理方式:记录冲突点、引用相关 Apple 官方入口、引用冲突的 Aftelle 文档位置,交给人工评审。
