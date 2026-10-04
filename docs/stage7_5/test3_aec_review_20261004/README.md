# Stage 7.5 / Test3 / 03 — Apple 与 WebRTC 只读选型及修复审查

**2026-10-04：Test3/03 仍为 BLOCKED。本目录是研究快照，不是功能完成、路线验收或 Runtime 中断接入。**

**最新后续入口：[高通/关联/校准复审材料](hpf-followup/README.md)。** 后续产品快照 `1dd85df6128510629a2fd3f608095d811ac96ce0` 仅修复Test3资产保存目录；该子目录补齐frame85/224–226/346实际见证、固定HPF参照失败结果及门槛文字勘误。请优先读此入口，再按需要查本页保留的较早路线审查。

## 1. 审查任务

请 Aftelle 主控 / GPT Pro 实际读取当前提交的源码和本目录报告，独立比较：继续修 WebRTC AEC3，还是恢复 Apple Voice Processing AEC。给出一个有代码依据的最小修法，或一个能够决定修复方向的最小无声实验。不要仅根据摘要、模型印象或一次零 Gate 选择路线。

审查只读：不改代码、不切路由、不调阈值、不录音、不外放、不提交推送。当前没有要求用户重录。缺实体真人 WebRTC 正控限制最终验收，但现有实体负控已经足以证明当前实现存在问题；不能把缺正控当作无法继续诊断的唯一理由。

## 2. 版本和材料边界

- 仓库 `JerryYork3516/Eterna_Aftelle`，分支 `7.5.11`。
- 当前源码快照提交：`1163a887e6820cdd4c70ee58ba71b4b66aea66fc`。本目录由后续文档提交发布；该文档提交未继续修改产品源码。
- 优化 WebRTC 实体运行身份：原 HEAD `fbe7b77ec663832954d428bac90694447cecfba7` 加 tracked diff SHA-256 `8ba526b0f6a6f93401318919ab4b28465852e94bbe48ea9fc1248fbdac0ce47b`。本次提交前核对 diff 完全一致。原 frozen App SHA-256 为 `f4577deb09095ae4c567e617f2d22e73d4647d55930679e732416e21ddb3c24e`。
- Apple 报告使用历史代码/二进制身份；不能称为刚切回 Apple 的新测试，也不能直接与 WebRTC 做同版本同声场性能排名。
- WebRTC 固定上游：`9f30e83c018647b05804571699cf22b1f0f3409e`，见 `tools/webrtc_aec3/sync.sh` 和 `gclient.template`。实际封装、配置、patch 仍须一起读取。
- [manifest.json](manifest.json) 保存源码 SHA-256、报告原件/发布件 SHA-256 及本轮无声验证信息。
- 原始 PCM、手机录音、真实 DR、App 二进制、完整逐帧波形与本地 trace **未上传**。本目录只含技术报告与哈希/数值元数据。报告中的 `.build` 路径是本地来源，不是远端可读取文件。
- 远端审查者可以审核源码与报告推理，但不能宣称已独立复算未提供的 PCM。历史软件报告中的 `pre-injection pure-echo` 表示注入前预期工况，不会把缺少用户静默标签的房间录音升级为有标签实体负控。
- 所有报告按原实验时间保留。历史的“未提交/未推送/下一步”叙述不代表本次发布状态。原准备 manifest 的 `physical_runs_started=false` 是开测前快照；已有实体运行由后续报告和 capsule 证明，不可用旧字段否认运行发生。
- 历史提交 `1d3cfcb` 标题中的 “Complete Test3 Tier 1 fallback” **不代表 Test3/03 PASS**。

## 3. 目标与硬边界

设备组合是 Timesintelli USB 麦克风＋Mac 内置扬声器；禁止使用 28U1。目标是自动插话：居民纯回声零错误正式资格；真人双讲和约 400 ms 短句能及时取得资格，保留起音与有效 PCM。不能改成手动暂停，也不把要求改成 600 ms。

截至本次源码提交：

- `AppController.formalSpeechSourceAttributionVerified = false`，正式声学插话入口受该 guard 约束。
- `MacSpeechRealtimeBrainInputBridge` 的正式声源确认仍为 false，Runtime 还要求确认才能授予正式声学资格。
- WebRTC 软件测试成功最多为 `CANDIDATE_ONLY`，`test3_acceptance = NOT_ESTABLISHED`。
- 历史 Debug 显式插话及 provisional 测试设施仍存在；不要误称所有历史设施已删除。本文的锁定结论特指未验证的自动声源不能获得正式中断权限。

不重开已否证的 D2、水印、AudioSeal 或通用 VAD 路线，不用软件注入冒充实体人声，不把手机评价真值接成运行时检测输入。不用调阈值或选片段制造 PASS。高回声相关说明存在回声成分，不能证明真人不存在；低 processed 能量也可能是人声被误抑制。

## 4. 两条路线目前的证据

| 路线 / 样本 | 已有结果 | 解释边界 |
| --- | --- | --- |
| Apple，历史同构实体纯回声 | 1050 个播放帧 Gate 0 | 单次零 Gate 不等于零残留回声或长期可靠性 |
| Apple，后续历史同构真人长/短句 | 长句 Gate 0；约 510 ms 短句 51 帧 HAL true 0、音量合格 14、分离合格 1，且唯一分离帧音量不合格；Gate 0 | 早期另一次长句曾有局部开闸，不能据此称当前长句已解决。HAL 与 separation 是两个独立阻断 |
| Apple，处理效果 | 一些片段大幅压低回声，另一些仍有明显居民波形 | 能量比还包含 AGC/其他处理影响，不能唯一归因于 AEC，也未证明跨轮稳定 |
| WebRTC，优化实体纯回声 | Gate 64 / forwarded 68，首次开闸 652、694 | 有用户静默标签；确定失败。Gate 帧数不是独立试验次数，正式 cancel/clear/generation 仍为 0 |
| WebRTC，较旧实体纯回声 | Gate 250 / forwarded 258 | 不同构建身份，只能作为另一个反例 |
| WebRTC，优化普通/较高音量软件注入 | 注入前 Gate 20/18；注入后 forwarded 341/352 | 机械回归；周围房间声无独立真人标签，不能升级为有标签实体负控/正控 |
| WebRTC，隔离 main-lag 替换候选 | 优化实体负控 0/0；普通软件覆盖 351；较高软件覆盖 0，且注入前 Gate 38 | **REJECTED**，不可只取改善的一行。不是产品已修复 |

Apple 接线和转换审查未发现可复现的独立播放引擎、设备错绑或短句转换损坏；这不证明所有实现都正确。Apple 的短窗最大相关与事后 250 ms 相关不是同一统计量。其专用资格路径不能用 WebRTC 的主匹配/alternative 分支替代解释。

WebRTC 有两层问题：部分窗口的延迟历史偏向旧短峰、导致残留回声；Host 又可能将残留回声当成真人。用当前 main lag 直接替换历史结果时，新 lag 借用了另一个历史峰的质量位，较高音量案例出现缺乏持续支持的长延迟跳变并抑制软件人声。但更早的误开闸并非这些跳变单独造成，不能声称一个 lag 字段修改就解决全部。

## 5. 阅读顺序

先读本文件与以下路线报告；再按具体假设查深层见证，不要一次读取全部项目文档。

| 材料 | 用途 |
| --- | --- |
| [Apple 接线复审](apple-graph-audit.md) | 实际执行路径、真人漏检和环境排除范围 |
| [Apple 处理效果](apple-acoustic-effect.md) | 回声抑制波动及不可唯一归因的边界 |
| [Apple 历史状态](apple-status.md) | 早期构建、转换与运行状态；其中蓝牙默认路由为历史快照，非当前目标设备 |
| [WebRTC 实体负控](webrtc-negative.md) | 64/68 失败、冻结身份、Host 分支、参考及环境检查 |
| [WebRTC 软件回归](webrtc-software-suite.md) | 修正供音节律后的结果与软件/实体边界 |
| [WebRTC 修法可行性复审](webrtc-feasibility.md) | 已拒绝方向及当前未找到可支持候选；是可质疑的审查结论，不是数学不可能证明 |
| [main-lag 候选结果](rejected-main-lag-result.md) | 负控改善和较高音量人声丢失必须同时解释 |
| [main-lag Host 分歧](rejected-main-lag-host-divergence.md) | 早期误开闸、校准历史、后续信号损失 |
| [内部逐样本身份见证](webrtc-internal-divergence.md) | 补充上一报告当时尚缺的 AEC 内部见证 |
| [延迟历史支持审计](webrtc-temporal-support.md) | 精确直方图复算、新峰支持与长时间沿用 |
| [ERLE 提案筛查](rejected-erle-screen.md) | 前置条件不成立，不能按原提案生效 |
| [新鲜 AEC 指标](fresh-aec-metrics.md) | 排除关键失败帧仅因 Host 缓存滞后造成 ERLE 判断错误 |

源码首读范围（都在此仓库）：

1. `apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift`：Apple 资格、WebRTC 分类、alternative、确认窗、DEBUG 实际见证。
2. `apps/macos/Aftelle/MacSpeechAudioCapture.swift`：路由、Voice Processing、转换、capture/render 送入顺序。
3. `apps/macos/Aftelle/MacSpeechWebRTCAECProcessor.swift` 与 `tools/webrtc_aec3/bridge/AftelleAECBridge.mm`：实际配置、样本单位、延迟和调用契约。
4. `apps/macos/Aftelle/MacSpeechDeviceMonitor.swift`：HAL 缓存的生命周期和读取语义。
5. `apps/macos/Aftelle/Test3LocalAudioRunner.swift` 与 `tools/speech_aec_host_tests/RecordedAcousticReplay.swift`：测试路由、软件注入、证据消费与评价边界。
6. 必要时核对 `AppController.swift`、`MacSpeechRealtimeBrainInputBridge.swift` 的正式权限 guard；不扩大为 Runtime 重构。

上游延迟实现可从固定修订读取：[matched_filter_lag_aggregator.cc](https://webrtc.googlesource.com/src/+/9f30e83c018647b05804571699cf22b1f0f3409e/modules/audio_processing/aec3/matched_filter_lag_aggregator.cc)、[render_delay_controller.cc](https://webrtc.googlesource.com/src/+/9f30e83c018647b05804571699cf22b1f0f3409e/modules/audio_processing/aec3/render_delay_controller.cc)。如果查新版修复，须说明具体提交及是否适用于固定版本，不能泛称升级即可解决。

## 6. 希望主控回答什么

1. 用源码位置把 CONFIRMED、HYPOTHESIS、UNSUPPORTED 分开。当前有哪些接入/状态机/判据问题？哪些只是没有足够证据归因？
2. 独立推荐继续 WebRTC 或恢复 Apple，解释对现有反例的覆盖及预期工作量。若证据不足以选择，明确说明缺哪一个会改变选择的事实；不要强行二选一。
3. 只给一个最有依据的最小修法：函数、旧逻辑的问题、伪代码/最小 diff、因果输入、为何有机会保留长句与短句。若推荐 Apple，必须分别处理 HAL=false 和 separation=false；若推荐 WebRTC，必须处理残留回声误开及较高音量覆盖丢失。
4. 如果确实没有可支持的代码修法，给一个最小无声判别实验，明确每种结果将怎样改变修复决策。不要要求用户先重录来代替技术判断。
5. 可质疑已有诊断/验收统计是否适用，但不得降低“实体回声零错误正式确认＋真人短句覆盖”的产品目标。某次修复改善不证明整套方案必然成功；一个候选失败也不证明整条路线不可能。

最低离线验证约束：两份已有有标签实体负控分别零错误资格；软件注入前活动单独报告；既有软件近端覆盖和起音不退化；参考完整、因果、连续；PCM 完整；P99/最大耗时和积压不退化。通过后仍需必要的同路由实体长句/约 400 ms 短句验收。不能绕过 HAL 制造 Gate PASS，也不能用 HAL=false 隐藏独立声源判据误放行。

## 7. 本次交付检查

- `bash tools/speech_aec_host_tests/check.sh`：exit 0，Host、hangover、replay self-check 与静态契约检查通过。
- 优化 Debug `xcodebuild`：exit 0，`BUILD SUCCEEDED`。完整命令、日志哈希见 manifest。
- 当前六文件快照与优化 frozen run 的 tracked diff 一致；此次发布未实现新的 AEC 修法。
- 本轮没有新的实体录放音，构建和无声测试不改变 Test3 BLOCKED。
- Stage 7 checklist：**PASS**；触碰红线无。提交文件是既有六文件实现快照及本目录报告/元数据。未新增 Runtime API、DR schema、平台 target，未进入 Stage 8。用户已授权提交推送与扩展读取，无需再请求确认。
