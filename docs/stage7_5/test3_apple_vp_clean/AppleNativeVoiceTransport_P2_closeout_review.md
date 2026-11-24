# AppleNativeVoiceTransport · P2 收口报告

2026-11-24（Asia/Shanghai）。主控已接受 P2 核心架构，本轮提交收口复核。基线 `2c961b14cdec55b27447ab473b49a92ad4f51164`，验收源码 `ece9e1f907fabc6ded60839bc79330f2c9a22995`。

## Apple VP I/O 协商

本机 SDK `AVAudioIONode.h` 的 `setVoiceProcessingEnabled:error:` 要求在停止状态改格式，且启用 VP 时 Input.outputFormat 与 Output.inputFormat 一致。冻结源码 `574fc735` 的 `configureVoiceProcessingIO` 按输入客户端实际格式配置 Mixer→Output。历史 D2-F1 记录了 48 kHz 输入 3ch、输出协商前 2ch，协商后两端为 3ch。在后续无声记录中也有 16 kHz 的同类读回。历史证据仅作为格式合同的依据。参见 [D2-F1](T3_2_A_D2_F1_root_cause_and_silent_dry_run.md) 与 [D2-F1 R1](T3_2_A_D2_F1_R1_target_route_silent_validation.md)。

P2 在 stopped 状态开启 VP，读回双端启用、AGC ON、bypass=false、inputMuted=false。Mixer→Output 使用输入端实际的 `AVAudioFormat`，随后重新读取两端，拒绝格式不一致或协商中输入变化。节点安装后及启动前复核格式，运行中的配置读回仍核对 pin。Sink 接协商后实际输入格式，Source 在协商率下保持 mono 接入 Mixer。P1 两方向独立 SRC 能力保留，Fake 的独立采样率只是通用转换回归。

## 设备与监听

- 独立 P2 HAL 统一注册系统默认输入、默认输出和设备清单通知。设备快照包括默认端、两 AudioUnit 的 Global CurrentDevice ID、可获得的 Aggregate 活动成员及其流。相同设备 ID 去重。Global ID 可能指同一 Aggregate，不提供物理麦克风或扬声器绑定证明。
- 核查被监控设备可用性、名义采样率、输入输出流及声道布局。普通 Aggregate 维持活动／完整成员核验。自动 Aggregate 依据 SDK 的独立 transport type 分别核查公开属性，活动成员可读时一并展开并监听，即使完整成员表不可读。未公开的成员信息保持 UNKNOWN。流快照纳入 virtual 与 physical ASBD，采样率及声道数相同也能发现编码变化。
- 必要属性缺失、读回失败或监听注册非成功时事务回滚，撤销已注册项，引擎停止且回调 gate 未激活。无关设备枚举经相同快照核验可维持当前图。真实变化使旧图失效，明确重建需要新配置身份和两侧 token。原生产设备监控保持原样。

## 保留给 P3 的接口事实

- **实际 Source Render 时间**　使用真实 Source 回调的 SampleTime、HostTime、有效性 flags 和 frameCount。当前 C++ Source block 未向上层交付该时间戳，缺失维持 UNKNOWN。
- **播放身份**　记录回调入口及最终提交核对的播放 epoch/token，并绑定 Runtime generation、routeEpoch、configurationID。迟到或被失效的回调不能充当新身份的事实。
- **真实非零提交**　标明最终身份检查之后真正交给 Source 返回缓冲的非零区域及有效帧范围，区别空闲、欠载、取消清零和自然结束。队列非空没有这个含义。
- **清空确认**　分别记录逻辑失效的 token 和 Source 消费侧确认的 token，交付边界之前的清零与已经提交给系统的帧分别处理。EOS handoff 只表示回调处理了终止标记，物理完成仍 UNKNOWN。

以上为待接入合同。播放队列状态、EOS handoff 和已启用 Apple VP 都不授予声学资格。P2 收口不增加 Runtime 插话决策或额外诊断系统。

## 工程改动

| 文件 | 职责 |
| --- | --- |
| `NativeVoiceSystemEngine.swift`、`NativeVoiceRealtime.h`、`NativeVoiceRealtimeLease.mm` | 停止状态下的 VP 格式协商和安全连接。 |
| `NativeVoiceHALRoute.swift`、`NativeVoiceGraph.swift` | 默认设备、实际 AU 设备、活动成员与流的快照及监听事务。 |
| `AppleNativeVoiceTransport.swift`、`NativeVoiceSessionGraph.swift` | 接通注册失败回滚、激活前读回及旧图失效。 |
| `CloseoutContractTests.swift`、`FakeVoiceEngine.swift`、`SessionTests.swift` | 协商、注册及会话失效的合成回归。 |
| `tools/native_voice_transport_p2_tests/check.sh`、`tools/native_voice_transport_tests/guard.py` | 收口测试入口及冻结路径检查。 |

## 本轮验收

### P1／P2 回归

- P1 四配置各通过 1,770 项 Swift 检查、100 万帧 SPSC、30,000 次清空和 2 个受控竞态。P2 四配置各通过 114 项 Fake/合成检查、4 套 C 回调测试、4 个受控提交竞态。四配置为 Normal、Release、TSan、ASan/UBSan。
- 新回归包含 3ch／2ch、不同采样率、交错布局、连接失败、协商中输入变化、注册缺失和失败后的回滚。自动 Aggregate 回归覆盖仅公开活动成员、成员信息不可用及活动成员监听缺失。Fake 覆盖激活前快照变化、活动成员变化、同率同声道数的物理流格式变化、设备不可用及旧图隔离。
- 首轮三声道测试夹具缺显式声道布局，配置无效。已使用 MPEG 3.0 布局复验，系统适配器仍使用 input 节点读回的实际格式。

### TSan 与 ASan／UBSan

TSan、ASan（Swift 及 C/C++）与 UBSan（C/C++）均无报告。

### Guard

- Clang 回调调用图审计通过。O0 22 个可达函数，O2 9 个。SwiftFormat、严格 SwiftLint、Architecture/Secret/Release Route Guard 和 P1/P2 隔离 Guard 通过。

### FULL_CURRENT

最终矩阵 21/21 实际执行并通过，复用 0。Test3 离线候选 7/7，11 条不变量通过。父子收据、各日志及源码身份均经核对。回执 `.build/t3_2_a_validation/full_current-we1aewcz/results.json`，SHA-256 `3401b4ab3059cda10d252579dc01eeb943515cfdb3c0def6c21ad8a3fd76176e`。

为补齐 SDK 中自动 Aggregate 的覆盖，首轮矩阵在第 17 项主动结束。原收据保留 16 PASS、1 中断（exit 130）、4 NOT_RUN。最终矩阵在独立源码提交上从头执行。

### Debug／Release

Debug、Release 与产物隔离通过。两个构建均编译 P2 原生适配器和回调桥。Debug 时序符号存在，Release 时序符号缺失。应用启动 0。

## Stage 7 Forbidden Checklist

结论 **PASS**，触碰红线 0。

- A、C。仅 macOS 独立 P2 图及主机会话测试，保留现有 Host 边界。
- B、D、E。RuntimeCore、Runtime API、DR、fixture、Provider 契约和密钥路径均保持原样。
- F、G、H。保留 Memory、Trace、LiveState、调度、UI、Cascaded、插话权威与安全阈值。
- I。工程与测试改动见文件表。文档更新本报告、正式入口及 DEVLOG。新增平台 target 0，Stage 8 工作 0。收口提交后按停止线等待主控复核。

## 生产路径与保护工作区

P1/P2 隔离 Guard 复核 64 份冻结旧 App 文件。相对基线，生产 App、RuntimeCore、原 Bridge、项目定义、P1 内核和 C 实时回调的差异为 0。有 7 项冲突的受保护工作树，其索引、冲突记录和 14 份证据核对一致。3 份 fixture 与三轮历史收据相符。另一个干净的主工作树 HEAD、暂存树和 Git 状态一致，其 `.git/index` 文件 SHA-256 发生变化，字节级核验未通过，写入来源 UNKNOWN。前后摘要见本轮保护回执。工程日志位于 `.build/apple_native_voice_transport_p2_closeout_20261124/evidence/`。

## 停止线

实际 VP 协商和 HAL 设备兼容性仍待实机验收。设备运行 0，生产路径切换 0，真实 Provider 请求与私人音频分析均为 0。P1 为 PASS，P2 收口为 REVIEW_PENDING，P3 为 NOT_STARTED。AEC/CLOCK 根因 UNKNOWN，SQ-M1 OPEN，T3.2-A 和 Formal Test3 BLOCKED，`Test3.execution_authorized=false`。本轮交付后停止等待主控。
