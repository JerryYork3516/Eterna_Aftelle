# T3.2-A / R5-M20 — 2026-10-29 续作审核

本次按用户“明天8:00继续，修复后重新执行三轮”的新授权续作。本文先登记离线修复，设备批次结果在同一报告追加。当前尚未运行本次设备批次，不代表声学验收通过。

## 1. Git、候选和范围

- 起始 HEAD = upstream = 实时远端：`6cddef00910fdaddd22135ebfff169f980614cc2`。
- 修改前本地回滚提交：`5f11c1882cf8e4351c2e44abcd15b2f4dedb9d4f`；只使用登记的隔离工作区。
- 原工作区7个冲突、原索引和14项未跟踪证据保留。旧 D43CA586 与 1D11273F 批次及其消耗标记不复用、不修改。
- 新 Debug launcher SHA256：`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`（未变）。
- 新 Debug dylib SHA256：`4de26c8850e670dd6be73b03ce60b29c8404b2791d154276087d34295d32433e`（本次必要 DEBUG 修改后真实重建）；仅更新 M20 身份登记。
- 居民素材 SHA256：`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`。
- `m20_echo.py` SHA256：`f9363dd62100563fe80c5693b4889dea65e60f7c99c2a36715feb8f4c46b49ae`，检测器与阈值未改。

本次代码文件：`AppController.swift`、`MacSpeechAudioCapture.swift`、`MacSpeechAudioHost.swift`、`RealtimeInterruptionEvidenceTests.swift`、`WarmupWindowStatsTests.swift`、`m20_batch.py`、`test_m20.py`、`integration.py`。没有音频素材、设备标识、私人 Manifest 或日志提交。

## 2. 已证实的故障与最小修复

**CONFIRMED_ENGINEERING_DEFECT — 最终 FIFO 收尾。** 旧控制器正常封存前没有末次 drain；普通 `MacSpeechAudioFrameBuffer.end(generation:)` 会清空 FIFO。因此不能先调用普通 Stop 再凭 queued=0 宣称完整。上一轮949包生成、944包 drain、5包 queued 与此机制相容；该历史事实不等于实际 Native 丢帧。

M20 正常完成路径新增 `finishMacAECBatchCapture` → `MacSpeechAudioHost.finishDebugCapture` → `stopAndSealNativeVoiceDebug`：沿原生命周期锁和 capture-processing 边界停止生产资格、封存 Native、移除原 Tap，随后有界 drain 已生成包，验证生成量不变、实际队列包数等于返回包数且队列归零，才调用原 `end`。返回真实包继续经过原 generation/sequence/content-time/score-window/720KB 检查，不补零、不存预热 PCM。增加 `mac_aec_final_drain` 回执，并要求 generated=drained、generation 相同；不删除 queued==0 门禁。普通 Stop、历史 C、Converter reset/EOF 未修改。

**CONFIRMED_ENGINEERING_DEFECT — DEBUG 观察排他区过长。** `MacSpeechNativeVoiceTiming.render/scheduled` 原先在共享 try-acquire 标志内逐样本扫描非零区间。确定性交错 Fixture 证明扫描期间到来的合法 Input 元数据会被记为 skipped，制造观察缺口。将现有扫描移到该标志之外，仅让有界元数据更新占用标志；PCM 值不变，没有新 Engine/Tap/观察系统。真正竞争、stale、invalid 和时钟缺口仍记录并拒绝技术资格。历史 skipped=6 是否全部由这一路造成仍为 HYPOTHESIS，不能把观察遗漏称为真实音频丢帧。

M20 审核器同时要求 final-drain 回执、包守恒、Input/Render 观察与时钟计数完整。观察异常会停止余下轮次，不能被 `ECHO_NOT_DETECTED` 掩盖。

## 3. 离线 RED / GREEN 与检查

| 命令/检查 | 实际结果 |
| --- | --- |
| `M20_RESIDENT_WAV=<登记素材> bash tools/realtime_interruption_evidence_tests/check.sh m20-only`，旧实现+5包尾部 RED | exit 133，评分保留量断言失败；没有设备运行 |
| `bash tools/speech_aec_host_tests/check.sh d1-stats-only`，扫描交错 RED | exit 133，Input 观察丢失断言失败 |
| 首次末次-drain GREEN 编译 | exit 1，Optional generation 未解包；已用显式 RunID/generation 绑定修正，未给默认值 |
| 最终 `m20-only` | exit 0，396 checks；覆盖0/5包尾部、实际回执、720KB合成字节一致及历史 C 的原 queued-tail 行为 |
| 最终 `d1-stats-only` | exit 0；profile 19 cases/51 checks，Native 16/77，warmup 26/92；含扫描交错和真正观察竞争负控 |
| `check.sh m19-only`（现有导出回归） | exit 0，device_access=ZERO |
| Python：`test_m20_identity,test_m20,test_m20_fixture,test_m20_control,test_m07,test_failure_evidence,test_original_ui,test_integration` | 最终97 tests，0 failure，0 error，exit 0；全部 Fake，无 App/设备启动 |
| Debug / Release `xcodebuild ... -scheme Aftelle -configuration Debug或Release -destination platform=macOS -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build` | 各1次，均 exit 0；独立 DerivedData，不覆盖旧候选 |
| Release `nm`/`strings` | 新停止/drain接口、DEBUG timing类型和回执键均不存在 |
| `tools/realtime_release_route_guard/check.sh`、`tools/architecture_guard/check.sh`、`tools/secret_guard/check.sh` | 三项 exit 0 / PASS |
| SwiftFormat 0.63.1 / SwiftLint 0.65.1 增量检查 | 22处修改范围通过；只在隔离目录使用固定版本，未改全局或项目依赖。Format 使用 `--disable wrapMultilineStatementBraces --commas inline` 与现行 Lint 同行花括号/无尾逗号规则一致；历史 Lint 105项保留，新增0 |
| Python AST、`git diff --check`、文件白名单及文档隐私检查 | PASS |

Python 旧 profile 的测试身份仅在 Fake 进程内绑定当前 Fixture；正式 M20 入口仍验证真实 PID、路径、映射 dylib 和完整 SHA。未删除任何真实身份检查。未执行 FULL_CURRENT、ASR、设备测试或历史音频读取。

## 4. 并发、安全与剩余边界

新增停止/drain 仅在 DEBUG 非实时控制路径使用，原音频 callback 的处理算法不变。停止资格与 Native seal 共用既有 capture-processing 排他边界；末次真实包 drain 在 FIFO end 之前。扫描本来已有、仍有界，移出观察临界区不改变音频；后续真正观察竞争仍可能发生，出现即停止，不能承诺任意负载下零缺口。

保持 AEC/AGC/NS、AudioGraph、采样率、channelMap、Converter、时钟容差、RuntimeCore、Provider、正式 Gate 和 M18-E01 原状。Native 已经经过 Apple VP，不是 ADC Raw。尾部跨边界包与 Converter partial tail 仍不能靠补零宣称完整。没有物理扬声器独立见证时，低相关性也只能是 ECHO_NOT_DETECTED / UNVERIFIED。

Stage7 Forbidden Checklist：PASS。五维 SELF_REVIEW：范围=PASS；因果证据=仅确认工程缺陷；生命周期/并发=定点验证PASS、实机待证；隐私/Git=PASS；声学真实性=UNVERIFIED。新增 CRITICAL=0、MAJOR=0、规范 B 类=0；现有声学/时钟根因及 M18-E01 不因此关闭。

## 5. 本次新批次（修复推送后填写）

`DEVICE_RUNS=0`。只有新 plan、独立授权消耗记录、设备只读预检和实际 SHA 全部通过，才按此次新授权使用现有 `m20_batch.py` 正式入口执行最多3轮。旧批次不复用；不自动调整系统设置，不重试，不加第4轮。任何安全/身份/时钟/观察/导出/退出异常均立即停止余下轮次。

## 6. 保持状态

```ini
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=DEFERRED
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
