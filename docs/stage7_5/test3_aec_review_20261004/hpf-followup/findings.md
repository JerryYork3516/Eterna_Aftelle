# Stage 7.5 / Test3 / 03 — 高通后的关联/校准因果链

## 当前裁定

**本轮无声定位与自动检查完成；没有获得可批准的闸门修复。Test3/03：BLOCKED。**

固定高通参照的单一诊断触发预登记停止条件。它证明现有相关量对前处理敏感，但不足以恢复当前回声关联条件；未向 Gate 或正式 Runtime 接入。不能由此判定整个 WebRTC 路线不可行。

## 身份与范围

- 仓库 `${REPO}`，分支 `7.5.11`，HEAD `bdd71e3cd7007346ed7ceab399fef7efea0b6195`。
- pinned WebRTC `9f30e83c018647b05804571699cf22b1f0f3409e`。
- Host SHA256 `51cbfbb9f6b2aefedc8af37c74b8892a68d2919bf260fcc082a07ca287a1df85`。
- 使用既有 normal 软件注入对照的完整事件及 PCM，手机资料没有进入检测输入。
- 本轮新增文件均在本 ignored 目录；三个旧诊断文件仅更正文字中的门槛值，原副本/哈希保存在 `pre-errata/`。
- 版本管理下仍仅有上轮 `Test3LocalAudioRunner.swift` 的保存目录改动，两个既有未跟踪 PCM 保留。AEC/Host/Gate/Provider/Runtime 代码未新增改动；未 reset/clean/commit/push。

## 已解释的因果链

### 最早观测分歧：frame85

两路实际分类窗口身份相同：capture `71157241272958ns`；render frame `71157159429958ns`；offset391；窗口起点 `71157167575791ns`；lag73.697167ms；raw相关0.9462654107；origin `historical_discovery`。

| 既有指标 | baseline | capture HPF |
|---|---:|---:|
| processed↔原render相关 | 0.846431 | 0.097968 |
| linear↔原render相关 | 0.625009 | 0.013116 |
| 两个输出都低于既有能量门槛 | 否 | 否 |
| 两个输出都满足相关≥0.55 | 是 | 否 |
| timing关联候选计数 | 1 | 0 |

`timingMatchSupportsEchoAssociation`（Host:2713）因此对HPF返回false，`updateTimingLock`不取得该候选。原窗口确实找到；HPF `timingMatchAvailable=false` 是 historical 匹配在 reported diagnostics 被隐藏，`classificationMatchAvailable=true`。

frame87两路曾重新归零，所以85只代表最早分歧，不冒称226的唯一持续原因。

### 建立基线的直接链：224–226

baseline224→225→226连续通过相关条件，关联候选1→2→3，在226锁定并取得第一个resident-only基线。随后252–255、258累计到6。

HPF同阶段没有取得锁定，注入前基线一直为0；695/811才累计至1/2。226两路选择不同参考是状态反馈后的结果，不能单独用来指认索引错误。

### 资格丢失的具体帧：346与450

- frame346两路使用同参考，raw相关0.159945低于**当前源码0.35**，即时双讲分支均失败。baseline自适应分支有6个基线样本而通过；HPF在0<5处返回，未计算excess power。HPF processed RMS0.070570高于原0.037820，不是此处能量不足。
- frame450 baseline即时双讲通过；HPF residual相关0.275953超过既有0.25，即时分支被拒绝，自适应基线仍不足。

基线缺失解释了部分资格损失，不能解释全部341→98，也不能据此借用旧基线、强制锁定或绕过校准。

## 本轮唯一数值诊断与停止条件

`protocol.json`在计算前冻结frame85身份、源码门槛、输入哈希、公式及数值容差1e-6。使用固定版官方HighPassFilter(48000,1)连续处理真实render完整帧；不按窗口重置、不改变lag，不补造缺样。显式重建FIFO和playback start丢弃的120样本，处理/linear参考分别按432/216个48k样本补偿。

先独立标量复算原render三项相关，与实际trace一致，再只替换诊断参照；没有重跑AEC或运行新Gate。

| capture HPF第85帧 | 原render参照 | 固定HPF参照 |
|---|---:|---:|
| processed相关 | 0.097968 | **0.843428** |
| linear相关 | 0.013116 | **0.457918** |
| 两项均≥现有0.55 | 否 | **否** |

因此状态为 `REJECTED_AS_SUFFICIENT_REPAIR_FOR_WITNESS`。按协议STOP，未追加滤波器、窗长、lag或门槛试验。processed一项恢复不能包装成关联/Gate成功。该结果是软件见证诊断，不是实体验收。

## 独立只读源码复审

两个审查子任务均只读，本轮仅root写审计文件：

1. 关联/基线审查独立确认上述分支及实际门槛，未发现已证实的索引、归一化或更新错误。
2. pinned信号链审查确认fullband HPF→AnalyzeCapture→Split→ProcessCapture与完整APM顺序一致；Configure/Reset状态合理。APM render自身不要求相同HPF，不能把“render未高通”直接定为接入Bug。
3. Host三点平均抽取不等于WebRTC带状态的ThreeBandFilterBank band0。72/144低频样本延迟与分析/分块/抑制/合成模型相符，未发现单位或乘3错误。替换参考构造会改变统计量、状态及延迟，需要独立论证；不能按本帧缺少0.092的相关量去挑新变换。

两项复审均未批准产品patch。详见 `readonly-review.md`。

## 自动检查及环境

- `bash tools/speech_aec_host_tests/check.sh` exit0：Host检查1757项；timing controls13组、failed0；Apple non-user hangover16项；recorded/live fixture replay及源码边界检查PASS。输出摘要见 `host-check-summary.json`。这些是软件/假后端检查，未升级实体结果。
- 上轮保存路径修复的Debug构建成功。本轮源码未新增变化，复用该构建执行实际preflight：exit0，Timesintelli UID与BuiltInSpeakerDevice正确，持久根目录正确，permission_requested=false，qwen_calls=0。
- 输入及涉及源码哈希前后不变，实际输出窗口复算通过，git diff --check通过。
- 两份完整实体负控原件仍缺失；现存处理片段不能支持新AEC实体重跑。WebRTC同版本、同路由真人400ms/长句正控仍未验收。
- 本轮没有录音/外放。processed格式、实时回调积压、实际播放与捕获生命周期等在线声学指标本轮NOT_RUN，不能从preflight或fixture推定已通过。

## 完成与未完成

完成：保存风险修复已有构建证据；基线失败已追到关联条件；原匹配见证独立复算；一个固定信号口径假设验证并按条件停止；当前软件自动检查与无声路由预检通过。

未完成：可接入的声源判据/闸门修复、实体纯回声零误资格、真人约400ms与长句覆盖、实时性能及正式中断链路验收。Formal guard继续false，Bridge的sourceAttributionConfirmed继续false。

**唯一下一步：用本机源码和本轮见证做判据适配性的只读联合复审，要求下一项建议明确给出实现位置、可复算预测、正负控与停止条件。** 复审材料已准备为 `handoff.md`，不需要用户再录音来重现同一问题；没有新的受证据支持修法前，不启动下一轮实体录音。这个停止不代表WebRTC整体被否证。

## Stage 7检查

结论：**PASS（本轮边界）**。触碰红线无；修改文件为ignored诊断/报告及旧报告文字勘误；本轮产品代码、Runtime API、DR schema、平台target、Stage8均未改变。Test3仍BLOCKED。后续若需录音/播放或接正式中断，按既有授权边界先停下来。
