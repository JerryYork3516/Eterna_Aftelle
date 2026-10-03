> Published historical report. Source: `.build/test3-apple-graph-audit-20261003/report.md`.
> Local home/device identifiers are redacted; relative artifact links are rendered as text.
> Read [README](README.md) for chronology and corrections. Referenced PCM, traces and binaries remain local and are not part of this publication.
> Statements such as "no commit/push" describe the original experiment, not this later publication.

# Test3/03 · Apple VP 接线与环境只读复审 · 2026-10-03

**裁定：未发现可归因于独立播放引擎、设备错绑或采集转换的具体缺陷；Test3/03 仍 `BLOCKED`。** 这不证明 Apple 单麦路线不可行，也不证明实际 Apple AEC 已充分消除实体回声。未改变产品判据或正式 Runtime 中断。

## 固定身份与范围

- 仓库 `<LOCAL_WORKSPACE>`，分支 `7.5.11`，HEAD `01728b34c539c71cceeb63cd0721269580b2fad9`；原有未提交修改与测试资产保留。未 reset、clean、commit、push。
- 当前源码的正式 `AppController` 两个初始化均把同一 `SystemMacSpeechVoiceProcessingEngine` 实例传给捕获和播放（`AppController.swift:775–790, 826–841`）；实体 `Test3LocalAudioRunner` 也共享一个实例（`:401–411`）。引擎内部将 `playerNode` 接入 `mainMixerNode`，启用 VoiceProcessing 并检查输入／输出两个标志（`MacSpeechAudioCapture.swift:1268–1304`）。输入 tap 来自该引擎的 `inputNode`，居民块由同一引擎的 `playerNode` 排程播放。
- 软件 render reference tap 在 `playerNode` 的 bus 0、主混音器之前（`MacSpeechAudioCapture.swift:1929–1948`）。它能记录预混音播放样本；不能单独证明物理扬声器后的参考已经被 Apple AEC 有效使用。Apple 的 [AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioengine) 文档说明 player → mixer → outputNode 链路；[AVAudioIONode](https://developer.apple.com/documentation/avfaudio/avaudioionode) 文档说明 macOS 输入／输出使用系统默认设备。这里的官方描述与当前代码拓扑一致。
- 本机本轮无声 `system_profiler SPAudioDataType` 显示默认输入仍是 Timesintelli `TinyUSB DFU runtime`、默认输出仍是 Mac mini 内置扬声器；当前输出采样率显示 48 kHz。10 月 1 日实体 render tap 为 44.1 kHz；跨日采样率已变化，不能把当前环境冒充当时逐字节相同。两次 10 月 1 日实体录音自身的设备 UID、binary、1050 个 render 帧和供音节律配对一致，详见各自 `assessment.md`。

## 对现有漏检的解释边界

- 同构真人轮 (local-only artifact: `../test3-native-positive-20261001/trial-bb65665cda534210a3398bcbcb625dbc/assessment.md`)的短句 808–858 共 51 帧：HAL 缓存 `true` 0/51、音量合格 14/51、分离合格 1/51，且唯一分离合格帧音量不合格；Gate 0。14 个音量合格帧的最大 render 相关为 0.311–0.699，超过既有 0.25。高相关只能说明有可匹配成分，不能证明没有真人。长句本轮 Gate 也为 0。
- 同 binary 纯回声轮 (local-only artifact: `../test3-native-negative-20261001/trial-40e1aa79ab1c44fb9cec8622c760df3c/assessment.md`)在 1050 个播放帧内 Gate 0，但 HAL `true` 239 帧；一次负控的零 Gate 不是长期零误报认证。14 个真人音量合格帧被分离挡下，与真人段 HAL 缓存一直 `false` 是两个独立阻断。
- 已有原生转换逐样本复算 (local-only artifact: `../test3-apple-native-converter-replay-20261002/report.md`)在正负控各 1079 个 Host 帧上均为 0 不符，排除了当前 16→48 kHz 转换在标注短句处改坏波形的解释。此次额外读取原生 Apple tap PCM 的短句 808–858：峰值 0.151744、RMS 0.016339、`abs(sample)≥0.99` 为 0；没有该短句片段削波的迹象。这只检查 Apple tap，不代表 USB ADC 的独立测量。
- 正控 VAD 事件只记录到短句前约 1.77 秒的 `false`，短句之后没有新的 `true` 通知；改成回调进入时间也不能从现有事件重获 `true`。现有日志无法判断 HAL 物理状态是否曾短暂翻转、通知是否漏发或被合并。状态变化通知的时间间隔没有固定上限；不能用两个通知之间的长间隔证明丢事件。
- 同路由固定暂停实体试验 (local-only artifact: `../test3-controlled-yield-20261002/pair-outcome.md`)在暂停后约 +264 ms 内容时间仍有超门槛 processed 回声，首个完整低能量采集回调约 +435.4 ms 才到达；已触发预登记的 400 ms 时间停止条件，不重试该策略。

## 下一条件

本轮独立代码审查及 Cursor Opus 5.5 本地只读复审都未指出能同时解释真人漏检并守住纯回声的可复现接线／实现缺陷。Opus 的“用通知间隔验证漏事件”建议没有可预登记的通知频率界，不作为新实验。现有证据也没有可直接接入的同路由新声源资格规则；不因 Gate 失败而调阈值、绕过 HAL、改成手动暂停或让用户重复录音。

下一项修复工作须先提出**判决时可取得、预先固定规则**的原 Apple 路线声源观察，并在现有完整有标签负控上取得 source-only 3/5 错误确认 0，在真人长句与约 400 ms 短句内有及时覆盖；同时单独解释 HAL 阻断。未满足前，正式 Provider cancel／playback clear 保持禁止。若要验证新的物理运行状态，必须在规则离线成立后才安排用户关键实体验收。

Stage 7 forbidden checklist：`PASS`；触碰红线无；本轮仅新增本地 ignored `.build/` 报告，未改代码、Runtime API、DR schema、平台 target，未进入 Stage 8；无需请求用户确认。没有发声或录音。
