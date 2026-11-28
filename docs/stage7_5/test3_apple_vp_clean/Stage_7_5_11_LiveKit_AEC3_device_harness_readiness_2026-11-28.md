# Stage 7.5.11 · LiveKitWebRTC AEC3 设备入口验收准备

独立设备入口在基线 `a524ee31d33c3862546952edd253d58a6b2e73d1` 上完成构建和离线验证，交独立审核。首次操作须取得单独设备授权。Apple VP 历史对照使用原冻结条件。[离线探针验收](Stage_7_5_11_LiveKit_AEC3_offline_probe_review_2026-11-28.md)

## 入口和资格

`tools/livekit_aec3_probe/run.sh` 默认走原 manual 验收。`--offline` 显式选择同一路径。`--device-self-test` 使用纯合成 PCM 和进程内测试替身。两条入口分别构建命令行程序，离线程序不链接设备入口或麦克风用途说明。设备入口要求 `--device --authorize-device --standard-mic-mode`、前台交互 Terminal、两个绝对路径和有效的 macOS 麦克风授权。仅在明确的设备命令、素材和输出路径预检、冻结路由预检都成立，且系统授权为未决定时，才可能显示系统麦克风权限面板。运行时从与 SDK 相同的 API 读回授权。权限拒绝或超时即退出。Terminal 的实际 TCC 归属与首次授权仍待该机器核验。[Apple 麦克风授权](https://developer.apple.com/documentation/bundleresources/requesting-authorization-for-media-capture-on-macos) · [SDK 授权检查](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/modules/audio_device/audio_engine_device.mm#L3304-L3310)

| 检查 | 实现 |
| --- | --- |
| 固定依赖和播放素材 | 校验 `LiveKitWebRTC 150.7871.08` 发布 ZIP 的 SHA-256 `008dbf8187843ab708afa44b65b8041d8ce8da99e530608cd85aa6ea3551529a`，仍核对实际映像路径。居民 WAV 从同一有界字节快照计算 SHA-256 并解码，要求 `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` 与单声道 24 kHz PCM16LE。历史台账记录 114,032 帧，约 4.75 秒。固定素材留在本机。 |
| 双向设备图 | 单一 Factory 将给定的原生 APM 和 AudioEngine ADM 连至同一 AudioTransport。软件 AEC 探针在 render-pre 按 SDK 回调初始化报告的处理率供给有界 PCM，校验单声道及 10 ms 帧。反向处理后的 PCM 由 SDK 原生 Source、mixer 和输出节点播放。采集经 SDK 输入、ADM、同一 APM 和 capture-post 进入单声道缓冲。输出 WAV 使用 capture-post 报告的采样率。 |
| 处理模式 | Factory 初始化后设置并读回原生 APM。启动前后核验 AEC 开，独立 NS、GC1、GC2 和额外 HPF 关。禁止 Apple 平台 VP，设备图启动前后读回两方向节点的 VP 状态。AEC3 关联 HPF 的源码默认仍启用。关联 PostFilter 取决于内部率及 field trial，未通过设备实测。 |
| 冻结路线 | 必须以 TinyUSB USB 输入和 Mac mini 内置扬声器为 macOS 默认设备。读取实际 Audio Unit 当前设备，输入使用 global element 1，输出使用 0。Mac mini 通过机型标识、内置传输和扬声器标签或终端类型验证。记录实际设备 ID、硬件采样率和通道数。输入读回须为 60.49%，输出为 59.86%，按百分比保留两位比较。拒绝已知的静音及可读性失败。量级、路由选择和 Mic Mode 均由操作者设定。 |
| 运行资格 | 设备图启动并再次通过 VP、路由和格式检查后，才准入探针的 PCM 回调。启动前后检查 Standard Mic Mode，运行中监听系统默认路由与引擎配置变动，并定期复核设备、格式、音量和模式。异常关闭供数和采集资格并停止，拒绝第二次创建或启动设备图。原生 SDK 或系统在路由异动期间能否产生瞬态流段仍须实机观察。 |
| 回听和文件 | 收齐 15 秒且通过数字见证及停止检查后，独占创建 `0600` PCM16 WAV。父目录必须已存在、为当前用户所有且只允许当前用户访问。失败或取消不给出有效录音。输出目录和文件请放在仓库之外。 |

[历史固定素材台账](Stage_7_5_11_split_AUHAL_P0_C_2_onset_history_device_runbook.md) · [固定构建器与源码锁](https://github.com/webrtc-sdk/webrtc-build/blob/0d1a5f8344c05bf0cf92efd313edcf3f4caf398c/VERSION#L1-L4) · [Factory 装配](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/sdk/objc/api/peerconnection/RTCPeerConnectionFactory.mm#L174-L189) · [原生反向处理](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/modules/audio_processing/audio_processing_impl.cc#L1571-L1623) · [Apple 活跃 Mic Mode](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activemicrophonemode)

## 播放见证和停止边界

设备模式只在 SDK 已连往输出节点的 main mixer 上用 `format:nil` 安装被动 tap。按实际回调格式读 PCM，汇总 render-pre 供帧、mixer 非零帧数、首末非零所在缓冲的有效 HostTime 和样本偏移。见证门要求至少约 100 ms 的非零帧总量及两个不同的缓冲 HostTime。该见证位于原生 APM 回写下游、硬件输出前。HostTime 和偏移属于 mixer 缓冲，末级 Source 消费时刻、逐样本传输同一性和实际空气声仍未取证。capture-post 的稳定格式和固定样本计数只见证本端收到的 SDK 块，公开钩子未附带硬件采样时标和源序号。[SDK 设备输出 Source 和 observer](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/modules/audio_device/audio_engine_device.mm#L2533-L2609) · [Apple Audio Node tap](https://developer.apple.com/documentation/avfaudio/avaudionode)

停止时先关闭探针的准入门，再同步请求 SDK 停止，核验 stop/release 事件、ADM 状态和监听器/tap 移除。关闭后拒绝新入场，并等待所有已准入的探针回调退出；回调持有缓冲直到退出。该计数只覆盖本探针的读写区。native observer 事件与计数稳定均无法证明整个设备 SDK 回调已退出，也不构成生产末级消费、插话或 `clear ACK ≤50 ms` 合同。manual 下行缓冲仍不可公开观察。[SDK manual loop](https://github.com/webrtc-sdk/webrtc/blob/7c1a802ab4e0d74f28ee997678346b3e753ef42a/modules/audio_device/audio_engine_device.mm#L3206-L3248)

## 离线工程验收

| 检查 | 结果 |
| --- | --- |
| 构建与库身份 | arm64 macOS 27.2.1、Apple Clang 21、C++17、ARC、优化和 `-Werror`。使用校验过的本地归档，实际加载 macOS framework SHA-256 `ec5bfaeb84447ae7556cd0614da9d94a3f109705b99d024db5a1464390d18085`。 |
| 参数及设备授权门 | 缺少显式设备授权参数时返回 64，未进入构建或设备代码。编译后的参数判定、自检和授权前置条件已检查，未请求系统权限。 |
| 设备入口合成自检 | `PASS`。测试供帧和格式适配、capture-post PCM 转换、合成 tap 非零位置和时标、启动失败与启动态失配后执行停止、关闭后拒绝新入场和已准入回调退出。实际设备图启动回滚仍待实测。 |
| WAV 验证 | `PASS`。合成文件检查 RIFF 解码限制、哈希不符拒绝、独占路径与权限，检查输出 PCM16LE、已有文件拒绝覆盖。另以临时合成测试模拟写入失败，确认部分文件清理。 |
| 固定 SDK manual 回归 | `PASS`。三个完整臂各收齐 302,400 帧，AEC 关闭逐样本误差为零。匹配与静音参考的尾段 RMS 分别为 15.010 与 1726.100（S16）。错配拒绝、图回滚和停止通过。manual 进程收到实际 SIGINT 后完成停止，退出 130 且无导出。 |
| 隔离回归 | Stage 7 禁止项检查和 Release Route Guard `PASS`。生产目录和工程相对基线无差异。既有 Native Voice Guard 在 `guard.py:48` 仍因同一旧路径白名单失败。 |

两种离线入口均可使用缓存的已校验 ZIP 禁网运行。此沙盒配置允许 AVAudioEngine 创建 manual 组件。

```bash
archive='/absolute/path/LiveKitWebRTC.xcframework.zip'

sandbox-exec -p '(version 1) (allow default) (deny network*)' /usr/bin/env \
  LIVEKIT_WEBRTC_ARCHIVE="$archive" tools/livekit_aec3_probe/run.sh --device-self-test

sandbox-exec -p '(version 1) (allow default) (deny network*)' /usr/bin/env \
  LIVEKIT_WEBRTC_ARCHIVE="$archive" tools/livekit_aec3_probe/run.sh --offline
```

## 首次真人双讲操作

仅在独立审核和单次设备授权后执行。使用 Mac mini 本机前台 Terminal。先在 macOS 设置中选 TinyUSB 为默认输入、Mac mini 内置扬声器为默认输出，分别确认 60.49% 和 59.86%、取消静音，并在控制中心确认当前麦克风模式为 Standard。准备经批准的固定原幅居民 WAV 与本地发布 ZIP。运行前关闭会占用音频设备或产生外放的其他程序。

在仓库根目录把下面两个路径替换为本机实际绝对路径，然后执行。输出目录自动设为私有，每次只运行一次。

```bash
archive='/absolute/path/LiveKitWebRTC.xcframework.zip'
resident='/absolute/path/to/fixed-resident.wav'
trial_dir="$(mktemp -d "$HOME/Library/Caches/aftelle-aec3-first.XXXXXX")"

LIVEKIT_WEBRTC_ARCHIVE="$archive" tools/livekit_aec3_probe/run.sh \
  --device --authorize-device --standard-mic-mode "$resident" "$trial_dir/double-talk.wav"
```

1. 看到开始提示便独自持续朗读。约第 3 秒居民开始播放，继续读，避免临时加大声音。
2. 居民播放结束后继续朗读一小段。恢复提示跟随 render-pre EOS，物理外放尾音以实际听到的为准。约第 11 秒看到停止提示，停讲并保持安静至结束。
3. 如出现实际设备、声音或模式失配，按 Ctrl-C 取消。留存脱敏错误，等待审核后决定是否补跑。
4. 成功结束才在本机回听 `double-talk.wav`。与冻结 Apple VP 证据对照，记录居民回声是否明显减少、人声是否仍压低或吞字、双讲及恢复是否自然三项。保留录音在本机。

## 交付状态

Stage 7 Forbidden Checklist `PASS`，触碰红线为零。变更集中于 `tools/livekit_aec3_probe/` 及两份 Test3 验收文档。新增独立命令行入口和测试。Runtime API、DR schema、平台 target 与 Stage 8 均未变更。

```ini
LIVEKIT_AEC3_DEVICE_HARNESS = READY_FOR_INDEPENDENT_REVIEW
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
