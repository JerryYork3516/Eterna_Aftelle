# Test3/03 — 最新高通/关联/校准复审材料

**2026-10-04：Test3仍BLOCKED。本目录是后续只读复审材料，没有接入新的AEC或闸门修复。**

## 从指定提交的实际源码开始

产品源码快照为 `1dd85df6128510629a2fd3f608095d811ac96ce0`。它在此前远端 `bdd71e3cd7007346ed7ceab399fef7efea0b6195` 上只修改 Test3LocalAudioRunner 的测试根目录：temporaryDirectory → Application Support/Aftelle/test3-local-audio。该保存修复已构建与无声预检验证。Host/AEC/Gate/正式中断权限没有产品改动。

本目录由后续资料提交发布。请按发布该目录的精确提交读取，先核对[manifest.json](manifest.json)中的源码哈希；不要使用旧分支缓存，也不能声称远端文件包含本机未发布的音频或完整工作区。

## 最小阅读顺序

1. 本文件、[findings.md](findings.md)、[reference-result.json](reference-result.json)。
2. 实际Host的匹配、关联、校准、分类、确认窗与信号参考：`MacSpeechAcousticEchoHost.swift`。
3. Processor的72/144低频样本补偿、Bridge与RecordedAcousticReplay的输入/评价链路。
4. [calibration-witnesses.json](calibration-witnesses.json)、[reference-protocol.json](reference-protocol.json)、[readonly-review.md](readonly-review.md)。
5. 如需审核实验实现，再读[pinned-filter.cc](pinned-filter.cc)、[reference-domain-diagnostic.py.txt](reference-domain-diagnostic.py.txt)及[capture-hpf-candidate.diff](capture-hpf-candidate.diff)。差异只是已拒绝的隔离副本，不是产品补丁。

首读源码路径：

- `apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift`
- `apps/macos/Aftelle/MacSpeechWebRTCAECProcessor.swift`
- `tools/webrtc_aec3/bridge/AftelleAECBridge.mm`
- `tools/speech_aec_host_tests/RecordedAcousticReplay.swift`
- 需要时核对 `MacSpeechAudioCapture.swift`、`MacSpeechDeviceMonitor.swift`、`Test3LocalAudioRunner.swift`及AppController/Bridge的正式权限guard。

## 最新事实与更正

- 原固定capture HPF软件对照：normal转发341→98，325帧注入区间Gate158→68，因保留能力退化而拒绝。
- 最早观测的关联状态分歧在frame85。两路找到同一真实参考，raw相关0.946265、lag73.697167ms。baseline输出相关0.846431/0.625009满足两项≥0.55，HPF为0.097968/0.013116，关联候选1→0。
- frame87曾复位，不能把85当成226的唯一持续原因。baseline224–226连续3次关联支持后开始校准，随后累计6个基线样本；HPF注入前0个。
- frame346同参考raw相关0.159945低于当前源码 **minimumTimingCorrelation=0.35**。旧诊断文字误写0.65，本次已更正；源码门槛没有改变。HPF自适应分支因0<5返回，且frame450另被residual相关0.275953>0.25拒绝。
- 独立原窗口复算一致。固定frame85、固定lag、连续使用pinned48k HPF参照后：processed相关0.843428，但linear0.457918仍<0.55。因此按预登记STOP；未追加lag/窗长/滤波/阈值变体或新Gate。
- Host三点抽取不等于WebRTC band0；72/144补偿模型与固定源码相符。仅有变换差异不能自动判定Bug，也不能把替换splitter包装成保持原统计量的小修复。

## 证据边界

本目录只发布数值见证、哈希、源码和脱敏报告。不含PCM、手机文件、可恢复波形、真实DR、App binary、密钥或私人绝对路径。`${REPO}`/`${APP_CONTAINER}`是来源位置的占位符。诊断脚本作为文本快照供只读审核，不能在缺输入时生成替代真值。

`findings.md`保留本机实验完成时的叙述，其中“ignored目录”“未提交”等描述属于当时执行范围。发布行为未改变原实验结果。[validation.json](validation.json)保存无声检查摘要。

远端审查能检查代码、实验设计与数值见证；**没有本机PCM时不能声称独立复算了相关波形**。完整实体负控raw缺失；软件注入前房间背景缺独立静默标签。已存processed片段、零formal guard、1757项软件检查通过，都不能升级为实体声源归属PASS。

当前路由目标仍为Timesintelli USB麦克风＋Mac内置扬声器，禁止28U1。手机原件只作标签，不进入检测输入。正式cancel/clear/generation仍禁止。

## 本次需要的答案

请实际只读源码与上述见证，提出**一个有依据且可检验的最小修法**，使回声关联/校准与双讲资格不互相破坏。区分确定实现错误与判据适配假设。给准确函数/最小伪diff、因果输入、可复算预测、独立声源资格统计、长/短句保留约束、性能预算和停止条件。

如建议改变参考变换或聚合判据，必须承认统计量改变并说明验证方法。不能为达0.55换变换/选lag，不降低阈值、绕过校准、借用旧baseline或强制锁定。不重开D2、水印、AudioSeal、通用VAD或刚刚失败的简单HPF/HPF参照试验。

没有可支持的修法则明确NO_PATCH，并指出**一个会改变修复决策的精确缺口或只读检查**。不能泛称“继续测试”，也不能将单个候选失败当成WebRTC物理不可行。

Stage 7交付边界：**PASS**；仅保存路径修复和研究资料交付。Runtime API、DR schema、平台target、Stage8均未变；Test3仍BLOCKED。
