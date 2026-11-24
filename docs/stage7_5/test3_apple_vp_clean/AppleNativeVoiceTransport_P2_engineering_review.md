# AppleNativeVoiceTransport · P2 工程报告

2026-11-24（Asia/Shanghai）。P1 已获主控 PASS，P2 工程交主控审核。授权基线 `5ef549f634a0cb75eaca6e49c0a903214261119a`，受测源码 `25c50bf5e6d89d3e2e3bc602894c838d7a9846ef`，原运行源码 `574fc735ca239c9b334029debbdee546cda18d49`。

## 音频图

```text
VP Input 客户端 Float32 → Sink → C 选取配置声道 → 采集环
采集环 → P1 串行 Worker，原生采集率到 24 kHz → PCM16LE 480 samples / 960 bytes
24 kHz PCM16LE → 同一 Worker，24 kHz 到 VP 播放率 → 播放环
播放环 → 单声道 Float32 Source → MainMixer → VP Output
```

每张活动图只有一台 AVAudioEngine。停止状态配置 Voice Processing，要求两端启用 VP，AGC ON，bypass=false，inputMuted=false。应用软件每方向只使用 P1 的一次 SRC。Sink 使用实际输入节点客户端格式，Source 使用实际播放率，并以 mono 接入 MainMixer。输出连接和协商格式在启动读回中核对。Apple 内部转换、声学参考和滤波状态仍待设备验收。参考 [WWDC19 510](https://developer.apple.com/videos/play/wwdc2019/510/)、[WWDC23 Voice Processing](https://developer.apple.com/videos/play/wwdc2023/10235/) 和 [Apple 配置变更通知约束](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/avaudioengineconfigurationchange)。

## 实时边界和身份

- Objective-C++ 节点 block 在安装和销毁阶段持有上下文 lease。回调只借用 C 指针。C11 环、交错拆声道区在控制侧预分配，回调路径无锁、堆分配、日志、文件 I/O、Swift Actor 和 SRC。采集支持 negotiated Float32 平面与交错布局，按 AudioBufferList 实际容量验证。超出有界分配的捕获帧报告丢失，输出在容量有效时填静音。
- 每张图绑定不可变的 capture token 和 configurationID。保留回调原始 SampleTime、HostTime ticks 与有效性 flags，再以已知 Mach timebase 转为 P1 时间坐标。畸形和溢出丢帧在下一块提交处标明。P1 遇真实内容缺口断段，缺失或无效的时钟没有 freshness，采集不补零。
- Source 在入口取得本次 playback token，环只消费该 token。回调提交前检查 active token 与图状态，旧回调可完成清空确认，不能读取新 token 的 PCM。已有输出遇中途失效清零。Worker 的待提交块保留原身份，C 写入检查 active token 和 ack。回调级界限不能撤销已提交硬件的帧。
- EOS 与最后一段 PCM 一起发布。空闲、未开始交付前的预备静音、取消及开始交付后的真实欠载有明确分类；EOS 自然尾部填静音。环清空 ack、EOS Source handoff 与物理播放完成分别处理。物理完成为 UNKNOWN。

## 会话和设备

串行非实时 transport actor 持有图、P1 Worker 和待提交块。控制者提供 Runtime generation、routeEpoch、captureGeneration、configurationID 和播放身份。P2 只镜像。正常多轮及取消只推进播放侧，保留采集 SRC、时钟和帧环。上一正常 EOS 有 Source handoff 后可开下一轮。Worker 背压只保留一个转换块，一次最多接受 48,000 bytes PCM，未接纳的调用由上层重试。上层驱动 service，无自动重试循环。

启动需要当前授权，采集与播放在启动读回前保持关闭。权限撤回、会话 close 或明确配置失效先关 C 图，再撤监听并停止 Engine。宽松枚举或改名需等价路由快照才保持运行。绑定设备、默认可用端、名义采样率、stream 布局或 Aggregate 活动成员变动会失效。Engine 配置通知本身失效，图释放由控制侧异步完成。故障后仅显式 rebuild 接受新的配置身份及两侧 token。部分启动失败在同一清理路径关闭，旧图 block 保留旧上下文并从此不重新激活。

## 验收和范围

- P1 Normal、Release、TSan、ASan/UBSan 四组通过。各 1,770 项 Swift 检查、100 万帧 SPSC、30,000 次失效和 2 个受控竞态。
- P2 同四组通过。各 4 套 C 回调测试、4 个受控提交竞态和 62 项 Fake 会话检查。覆盖回压、正常 EOS、并发取消、方向采样率不同、可变回调大小、异常戳、真实丢帧标记、Aggregate 重建、权限、部分启动失败和重复关闭。TSan、ASan、C/C++ UBSan 无报告。
- Clang 未插桩 IR 递归调用审计通过，O0 22 个可达函数，O2 9 个可达函数。SwiftFormat、严格 SwiftLint、Architecture/Secret/Release Route 及扩展 P1 隔离 Guard 通过。

`FULL_CURRENT` 本轮 21/21 实际执行，通过全部子项。21 份日志与 `25c50bf` 的源码身份和 SHA-256 一致。离线 Test3 候选 7/7 子项、11/11 不变量通过。Debug 和 Release 均编译了新 Engine、C 回调与 Objective-C++ 桥并构建成功。产物核对确认 Debug 有旧 timing 符号，Release 无该符号，`application_launched=false`。

矩阵路径为 `.build/t3_2_a_validation/full_current-lyaw43ii/results.json`，SHA-256 `db379d1f49cc5a184b57ce7c3a91417fd5b08aeaca1b4492b719fe40e60a1f8f`。

## 交付与停止

| 范围 | 文件与证据 |
|---|---|
| 独立图和控制 | AppleNativeVoiceTransport、NativeVoiceGraph、NativeVoiceSessionGraph、NativeVoiceSystemEngine、NativeVoiceHALRoute |
| 回调和兼容 | NativeVoiceRealtime C/Header/Lease、NativeVoiceRing C/Header、P1 Worker 的方向采样率和捕获丢帧输入 |
| 构建与验证 | 原 App 的 7 个 P2 Sources 成员及一行桥接头，P2 Fake/C/IR 验收，扩展 P1 隔离 Guard |

Stage 7 Forbidden Checklist A–I 为 PASS。64 份冻结的旧 App 文件逐字节相等，项目声明只增加已列 P2 编译成员。生产路径切换 0，现有 Bridge、Cascaded、RuntimeCore、DR、Provider、原安全阈值和平台 target 保持。两棵受保护树原索引、7 项冲突、14 份未跟踪证据及三份 fixture 的字节与登记元数据核对一致。历史 P1 34 项、收口 29 项证据与旧矩阵的失败及通过收据摘要一致。新收据保存在 `.build/apple_native_voice_transport_p2_20261124/evidence/`。

待实机验收的项目包括实际 VP 协商、默认与实际 Aggregate 设备的兼容、真实回调预算、实际权限事件传递、物理输出延迟及声学效果。现有默认设备监控接口没有注册回执，默认通知覆盖也在实机验收范围内。C/Swift 工程证据采用 Fake、纯内存 PCM 和编译后的调用图。

```text
P1 = PASS
P2 = REVIEW_PENDING
P3 = NOT_STARTED
DEVICE_RUNS = 0
AEC_ROOT_CAUSE = UNKNOWN
CLOCK_ROOT_CAUSE = UNKNOWN
SQ_M1 = OPEN
T3_2_A = BLOCKED
Formal_Test3 = BLOCKED
Test3.execution_authorized = false
```

P2 交付后停止，等待主控审核。P1–P4 完成后再交 Gemini 统一架构审核，真实实验另待明确授权。
