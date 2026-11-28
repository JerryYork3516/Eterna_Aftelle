# Stage 7.5.11 · LiveKitWebRTC 软件 AEC3 离线验收

2026-11-28。交接基线 `55be8d1a5b9e05f8601a57a59c93b3ae0552b8fe`。离线探针独立构建。已观察到合成参考经 render-pre 进入 AEC3，改变同一 APM 的 capture-post 输出。SDK 无设备模式丢弃下行回写缓冲，公开接口无法核对其中的实际 PCM。P0-C.3 的起音结论仍为 `INCONCLUSIVE`，Apple VP 保留为后续对照。[P0-C.3 证据报告](Stage_7_5_11_split_AUHAL_P0_C_3_final_onset_evidence_review_2026-11-28.md) · [固定版本可行性报告](Stage_7_5_11_LiveKit_Swift_local_audio_feasibility.md)

## 复现与依赖核验

在 macOS 上安装 Xcode 命令行工具后，从仓库根目录运行。默认下载固定发布 ZIP，先核验全包 SHA-256，再解出 universal macOS framework。仅构建命令行程序。使用已下载的 ZIP 时设置 `LIVEKIT_WEBRTC_ARCHIVE`，该路径仍执行同一校验。可选的 `PROBE_CAPTURE_FILE` 指向仓库外尚不存在的文件。成功时才导出匹配参考臂的 48 kHz 单声道 PCM16LE，无容器头。

```bash
tools/livekit_aec3_probe/run.sh

LIVEKIT_WEBRTC_ARCHIVE=/absolute/path/LiveKitWebRTC.xcframework.zip \
PROBE_CAPTURE_FILE=/private/tmp/aec3-synthetic-capture.pcm \
tools/livekit_aec3_probe/run.sh
```

| 核验对象 | 本轮证据 |
| --- | --- |
| 官方二进制版本 | `LiveKitWebRTC 150.7871.08`，包装提交 `b34647c69f8f048d5ed1df3ddcb478f346621653` |
| WebRTC 源码对应关系 | 官方构建器 `0d1a5f8344c05bf0cf92efd313edcf3f4caf398c` 将 `WEBRTC_COMMIT` 锁到 `7c1a802ab4e0d74f28ee997678346b3e753ef42a` |
| ZIP | 687,287,540 字节，下载字节实算 SHA-256 `008dbf8187843ab708afa44b65b8041d8ce8da99e530608cd85aa6ea3551529a`，与官方包清单一致。空文件负控在解包前拒绝，退出 1。 |
| 实际链接 | universal macOS Mach-O SHA-256 `ec5bfaeb84447ae7556cd0614da9d94a3f109705b99d024db5a1464390d18085`。进程用 `dladdr` 核对 APM `config` 方法实际加载的映像与校验 ZIP 解出的 framework 一致。 |
| 执行环境 | arm64，macOS 27.2.1，Xcode 27.0，Apple Clang 21。C++17、ARC、优化编译及 `-Werror` 通过。 |

[官方发布](https://github.com/livekit/webrtc-xcframework/releases/tag/150.7871.08) · [包清单](https://github.com/livekit/webrtc-xcframework/blob/b34647c69f8f048d5ed1df3ddcb478f346621653/Package.swift#L13-L24) · [构建版本锁](https://github.com/webrtc-sdk/webrtc-build/blob/0d1a5f8344c05bf0cf92efd313edcf3f4caf398c/VERSION#L1-L4)

本轮验收从本地 ZIP 构建，并在进程出站网络禁用的沙盒中运行。Codex 默认沙盒的一次尝试在创建 AVAudioEngine 的 manual I/O 组件时由 AVFAudio 拒绝。使用允许该组件、继续禁网的沙盒后，完整验收通过。探针只允许 SDK manual rendering 图，采集端验收要求创建时已处于 manual 模式、无输入 Source、无 VP，设备模式的输出配置入口被拒绝。Factory 可以注册 Core Audio 设备变化监听，本轮未打开设备采放流。[手动引擎初始化与设备观察](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/modules/audio_device/audio_engine_device.mm#L354-L422) · [manual 图](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/modules/audio_device/audio_engine_device.mm#L1880-L1940)

## 配置与数据路径

每个测试臂有一个 Factory，各自持有同一双向链所用的 AudioEngine ADM、AudioTransport 和原生 APM。测试臂之间销毁整个 Factory，以隔离 AEC3 自适应历史。探针在 Factory 初始化后重新应用五个开关。启动前后分别从注入实例的原生 `GetConfig()` 和 Factory 的逐项 `softwareActive` 读回交叉校验。软件 AEC 臂读回 AEC 开、独立 NS／GC1／GC2／HPF 关。ADM 平台 VP 策略与 requested 均为关，manual 图报告无 active VP、AEC、NS 或 AGC。这些 active 值来自无设备状态，实机状态待实机核验。[Factory 原生装配](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/sdk/objc/api/peerconnection/RTCPeerConnectionFactory.mm#L174-L189) · [启动时默认配置](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/media/engine/webrtc_voice_engine.cc#L529-L554) · [原生配置读回](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/sdk/objc/components/audio/RTCDefaultAudioProcessingModule.mm#L89-L99) · [VP 状态来源](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/modules/audio_device/audio_engine_device.mm#L1177-L1225)

固定版委托构造参数没有安装委托，探针通过公开 setter 显式接好并核对身份。AEC3 关联的 `enforce_high_pass_filtering` 默认开启，公开 APM wrapper 只读回额外 HPF 开关。固定源码会按此关联请求建立 APM HPF。AEC3 关联 PostFilter 的构造需要 48 kHz 内部处理率，本轮 AEC 臂观测到 32 kHz 的反向处理率。两项内部关联处理的取值均来自固定源码分支，探针没有专门的内部开关读回。[委托适配器](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/sdk/objc/components/audio/RTCAudioCustomProcessingAdapter.mm#L111-L132) · [AEC 默认配置](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/api/audio/audio_processing.h#L194-L204) · [HPF 构造](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/modules/audio_processing/audio_processing_impl.cc#L1827-L1848) · [PostFilter 构造](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/modules/audio_processing/post_filter.cc#L44-L51)

| 位置 | 离线可见证据 | 固定源码和观测边界 |
| --- | --- | --- |
| 合成 PCM 到反向处理 | 实际库调用 render-pre。缓冲是单声道 FloatS16，AEC 开启时稳定于 32 kHz／320 帧，关闭时为 48 kHz／480 帧。匹配参考和静音参考两臂使用相同 capture 输入与软件配置，capture-post 明确区分两臂。 | render-pre 先于 AEC3 `AnalyzeRender`。对照结果见证参考确实影响采集输出。公开 API 无 `AnalyzeRender` 逐帧 counter。 |
| APM 回写到 ADM | `manual_playout_pcm=NOT_EXPOSED`。下行末端实际帧数、幅值、SRC 输出与连续性未直接取证。 | `ProcessReverseStream` 将处理缓冲复制回 AudioFrame，Native AudioTransport 执行输出 SRC。manual loop 以 `GetPlayoutData` 拉入私有 `read_buffer_` 后丢弃。该处无公开 callback。公开 AEC dump 的反向事件在 render-pre 之前采样。 |
| 采集到本地导出 | synthetic Source 接到 SDK manual 图给定的主 mixer，SDK 拉取该输入并经自己的 ADM 与 AudioTransport 投递。关闭 AEC 的 capture-post 逐样本与 synthetic 输入一致。开启后从同一 capture-post 收到处理输出。 | 采集采用 SDK 的 48 kHz 单声道 S16 输入格式。公开 capture-post 是 APM 输出见证，允许回调外导出。 |

[反向处理与回写](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/modules/audio_processing/audio_processing_impl.cc#L1571-L1623) · [AudioFrame 原位回写](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/modules/audio_processing/include/audio_frame_proxies.cc#L47-L69) · [AudioTransport](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/audio/audio_transport_impl.cc#L150-L230) · [manual 合成输入接点](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/modules/audio_device/audio_engine_device.mm#L1979-L2008) · [manual 私有缓冲与采集投递](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/modules/audio_device/audio_engine_device.mm#L3206-L3248)

## 无设备验收

固定种子的 24 kHz PCM 夹具在进入回调前以线性插值适配 SDK 报出的比率。小向量核验 16／32／48 kHz 的逐点结果，长夹具核验有效供数和部分末帧的补零。16 kHz 可用于初始化阶段，本轮稳态实际使用 32 和 48 kHz。每段开始空跑 150 ms 再送入夹具。合成采集由同一夹具的两个固定延迟分量组成，延迟为 70 ms 和约 92.85 ms。缓冲和 10 ms 帧均固定上限，资料只含合成信号。运行中的回调校验通道、帧数和 FloatS16 幅值，文件写入在停止后进行。

| 实际臂 | render-pre 10 ms 块 | 夹具推进帧 | 首次补零 / 总补零 | capture-post 帧 | 第 5–6 秒 RMS（S16） |
| --- | ---: | ---: | ---: | ---: | ---: |
| AEC 开，匹配参考 | 630 | 191,911 | 89 / 4,889 | 302,400 | 15.010 |
| AEC 开，静音参考 | 630 | 191,911 | 89 / 4,889 | 302,400 | 1,726.100 |
| AEC 关，匹配参考 | 630 | 287,866 | 134 / 7,334 | 302,400 | 1,847.815 |

静音臂推进同样的时间轴，向反向帧写入全零。AEC 关闭臂对全部 302,400 个样本逐点检查，最大绝对误差 0 S16 LSB。匹配参考臂导出 604,800 字节，本次文件 SHA-256 为 `59cb2e4d4dc96b0b42b111eda6bb23065217e016172f75c79308a05bfa2c081f`。以可复核的逐点、帧数和 RMS 断言判断。该夹具只确认软件反向参考的作用，TinyUSB＋Mac mini 回声量、双讲保真、真实 SRC 及长期时钟对齐均待实机测量。

- **结束供数。** 三个完整臂均出现部分供数补零、完整静音块和同一 ADM 双向停止。SDK 回报 `didStopEngine` 和 `willReleaseEngine`，随后 render 与 capture 计数稳定。
- **取消。** 内建用例在 30 块处停止，已捕获 14,400 帧，尚未到 EOS。另向匹配参考臂的运行中进程发送 SIGINT，观测停止与退出码 130，无导出。
- **配置失败和释放。** 错配在启动前被拒绝。主动拒绝 manual 图输入配置时，原生启动返回 `-7701`，图创建和释放各一次，无 PCM 回调。正常停止后解除 observer 和 APM 委托，Factory 作用域覆盖停止和解绑。
- **生产隔离。** 相对交接基线，`apps/`、`platform-macos/`、`brain/`、`shared-protocol/` 无差异。没有生产工程或包清单引用探针。Release Route Guard `PASS`。已有 Native Voice Guard 在基线和交付树同样在 `tools/native_voice_transport_tests/guard.py:48` 失败，原因是 P4 冻结路径白名单与基线中既有的后续 Native Voice 资产不一致。白名单未改。仅执行相关 Guard 与探针回归。

这两种停止见证限定在探针自身生命周期。生产级打断、声源门、末级代际隔离和 `clear ACK ≤50 ms` 仍是接入门槛。SDK 的设备端实际 PCM、时标、路由和清空回执尚未取证。

## 后续实机操作

1. 取得单独的设备试验授权。先为独立候选增加同图 Source 的最后数字消费见证，并固定执行文件、合成或获批素材摘要与录证保留方式。
2. 在 TinyUSB 输入、Mac mini 内置扬声器和 Standard Mic Mode 下固定输入输出音量。软件臂启用前后分别读回原生 APM 五个开关，采放后读取实际两端设备身份、VP 状态、非零 PCM 和数字时标。用冻结 Apple VP 路线作同条件对照。路由或模式失配时停止该臂。
3. 按单讲、回声、双讲和恢复窗记录实际听感与数字时标。每臂独立核验停止和释放。时钟、声学及生产取消合同分别验收，再决定是否申请接入评审。

## 结论

Stage 7 Forbidden Checklist `PASS`。修改仅限 `tools/livekit_aec3_probe/Probe.mm`、`tools/livekit_aec3_probe/run.sh` 和本报告。触碰红线为零。新增独立工具代码。Runtime API、DR schema、平台 target、Stage 8 均无变更。设备试验需要新的授权。

```ini
LIVEKIT_AEC3_PROBE_ENGINEERING = PASS
LIVEKIT_AEC3_OFFLINE_DATAFLOW = PASS_LIMITED
LIVEKIT_AEC3_HARDWARE = NOT_RUN
LIVEKIT_AEC3_ACOUSTIC = NOT_RUN
LIVEKIT_AFTELLE_ADOPTION = BLOCKED
AEC_ROOT_CAUSE = UNKNOWN
CLOCK_ROOT_CAUSE = UNKNOWN
SQ_M1 = OPEN
Formal_Test3 = BLOCKED
Test3.execution_authorized = false
DEVICE_RUNS_THIS_TASK = 0
```
