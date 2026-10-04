# Test3/03 — 最新声源资格修法复审

**2026-10-04：Test3/03 仍 BLOCKED。没有新的 Host/AEC/Gate 产品补丁。**

本目录发布最新有标签实体负控的脱敏数值证据、计算方法及隔离对照。请按发布本目录的精确提交读取。正式产品源码基线为 `85db493c95fd3e1864296038209317e1cf4409be`；本次发布没有修改产品源码。Runner 保存修复以工作区补丁快照提供，其 SHA-256 见 manifest；它尚未成为产品提交。

## 复审目的

在 Timesintelli USB 麦克风＋Mac 内置扬声器、WebRTC AEC3 路线上，提出一份有代码及反例依据的最小隔离修法：居民纯回声零错误声源资格/确认，真人双讲和约400ms短句有覆盖，起音和有效PCM不退化。不能改成手动暂停，不放宽阈值，不接未经声源验证的正式 Runtime 中断。

当前确定的反例是：实体原运行有42个错误资格帧、4条错误确认链、48个Gate开启帧、56个按源身份去重的非零转发帧；正式 interrupt/cancel/clear/new generation 均为0。用户在运行后独立确认全程静默、其他设备无外放，且听到Mac居民声音。正式权限0不能掩盖声源判据失败。

资格数值的独立标量复算与原实现一致。AEC3实际环形槽身份也已核对。仅禁用旧lock资格臂、仅消除参考批次重置均未形成充分修法。请聚焦当前三类资格臂与参考/基线状态的证据可靠性，提供可证伪的修复设计。

## 阅读顺序

先读本页、[findings.md](findings.md)、[manifest.json](manifest.json)，再读取下列数字见证。方法源码按具体疑点阅读，不一次加载全部代码。

|材料|用途|
|---|---|
|[physical-negative.json](physical-negative.json)|独立静默标签、实际路由、42/4/48/56、正式权限0、保存/性能边界|
|[confirmation-witnesses.json](confirmation-witnesses.json)|四条确认链实际Host字段，资格计数及原始源身份|
|[qualification-result.json](qualification-result.json)、[qualification-witnesses.json](qualification-witnesses.json)|17帧标量复算，12个确认帧的主窗口及alternative完整合法域统计|
|[baseline-witnesses.json](baseline-witnesses.json)|五个基线来源、冻结事件、三类资格分支见证|
|[locked-arm-ablation.json](locked-arm-ablation.json)、[诊断diff](locked-arm-diagnostic.diff)|第一臂消融仍失败且软件49→48，未接产品|
|[aec-original-replay.json](aec-original-replay.json)|未改AEC的完整clean/linear逐位复现与内部状态|
|[ring-identity-result.json](ring-identity-result.json)、[31块身份](ring-selected-identities.json)|实际环形写读位置、已到达样本、锚点时间；不是完整FIR声学对齐证明|
|[reset-cause-result.json](reset-cause-result.json)、[callback-order-result.json](callback-order-result.json)|5572事件算术一致、批次到达/重置及未证明的阻塞因果|
|[paired-scheduling-protocol.json](paired-scheduling-protocol.json)、[paired-scheduling-result.json](paired-scheduling-result.json)、[观察不扰动证明](paired-stats-observer.json)|一次冻结排程对照、原Host时序事后41/3/104/110，停止扩大|
|[publication-provenance.json](publication-provenance.json)|本地原件哈希及每份发布材料的转换说明|
|[Runner工作区补丁](runner-retention-working-tree.diff)|尚未产品提交的保存修复；请基于产品基线核对diff，不能称已在正式源码生效|

方法快照：`qualification-scalar-audit.py.txt`、`ring-identity-audit.py.txt`、`reset-cause-audit.py.txt`、`ring-logger.diff`、`paired-scheduling.py.txt`、`paired-assessment.py.txt`。它们保留运算/插桩逻辑，路径替换为匿名占位符，仅供审核；远端没有所需PCM，不能用它们冒充已运行样本复算。`ring-logger.diff`基于固定上游，不是产品改动。`findings.md`保留的本地资产名应按本表找对应发布件，不代表远端存在同名本地目录。

## 源码首读范围与修复要求

实际阅读 `MacSpeechAcousticEchoHost.swift` 的 classifyCapture、timingMatchSupportsEchoAssociation、updateTimingLock、updateResidualEchoBaseline、adaptive/immediate double-talk、alternative、三帧确认和pre-roll/span源身份。再核对 `MacSpeechAudioCapture.swift` 的tap尺寸与两路送入顺序、`MacSpeechWebRTCAECProcessor.swift`、`AftelleAECBridge.mm`的输出/延迟契约，以及 `RecordedAcousticReplay.swift` 的评价归账。

希望复审者输出一份函数级最小伪diff、因果输入、状态生命周期、独立人声保护与可证伪反例。没有足够支持时输出NO_PATCH并指定一个最小无声实验。不要把“索引计算一致”扩大为“方案不可行”，也不要把单项改善扩大为“整体必然可行”。

最低保护：实体负控错误near/double资格与确认均0，分别统计Gate/源span，不用HAL或正式权限guard掩盖；软件固定源mask raw[164779,320779)、clean[165211,321211)，保持原49资格/165转发并检查起音/有效PCM。后续候选需要因果可用时间和目标Mac性能检查；软件通过后仍需要真人长句/约400ms短句关键验收。本轮排程对照触发负控停止条件，未扩大到软件正控。

不重开D2、水印、AudioSeal、通用VAD、HPF变体、固定110ms提示；不调阈值、不用手机评价真值当运行时输入。保持现有WebRTC路线，不直接切Apple。

## 发布验证

- 本次只新增文档、脱敏JSON和诊断方法/工作区diff快照；正式产品源码没有修改。
- 原实体包27个文件及归档原件均重核哈希一致；新材料的数值与本地来源一致，清单逐文件SHA-256见manifest。
- Runner补丁的旧文件hash、工作区hash与diff已绑定；工作区仍保留该修改。当前缺SwiftFormat/SwiftLint，未将该产品修改提交。完整App构建和Host回归本次NOT_RUN（文档发布）；以前的实际构建/实体保存见运行身份，不能冒充本次重测。
- 不上传PCM、私人人声、真实DR、binary、secret或用户绝对路径；本地原资产保留。

## 审查边界

- 本目录不包含私人录音、PCM、真实居民文件、二进制或密钥。没有上传波形，远端复审者不能声称独立复算了未提供的样本。
- 排程对照的Host结果是保持原Host时序的事后诊断，真实新决策可用时间未重建；不能称新实时因果链验收。
- 软件49资格/165转发是固定软件源区间的最低保护，不能替代真人短句验收。
- 没有本次实体真人正控，不把Candidate/软件回归升级为Decision。
- 只读审核，不运行设备、不改代码、不切路由、不调阈值、不提交推送。

Stage7边界检查PASS：只发布审查材料；Runtime API、DR schema、平台target和Stage8均未改变。Test3/03保持BLOCKED。
