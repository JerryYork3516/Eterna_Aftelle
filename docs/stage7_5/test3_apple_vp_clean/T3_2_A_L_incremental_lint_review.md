# Eterna Aftelle · T3.2-A-L-R2 · Final Submission与治理决定

日期：2026-10-16（Asia/Shanghai）。主控已正式批准 **T3.2-A-L-R2离线功能安全部分**，并为当前已验证的17文件交付单独授予**一次性lint提交例外**。本次不是沿用e0旧豁免，不改变工具FAIL、04规范或未来强制门槛。

当前工程状态：**ENGINEERING = REWORK / DEBT_DEFERRED**。Release Guard、Debug / 未签名Release、受影响安全回归保持真实PASS；SwiftFormat **FAIL / 18286 / exit1**，SwiftLint strict **FAIL / 312 / exit2**；B=0，C=23（21项文件／类型长度、2项函数长度）。C23仍是有归责的增长，不改写为“历史未恶化”，仅由主控决定统一延期至Stage7.5结束后治理。本次不继续重构。

## FS.1 提交授权、内容和证据一致性

- Git起点HEAD、upstream、实时远端均为 `e0b4f686d8b872ffac4fb9abfa9dadb7f0377e9a`；`Test3-AppleVP-Clean`追踪origin同名分支。开始时staging为空，原17项未提交修改完整保留，无未知文件改动。
- 本轮仅更新本报告、README与DEVLOG的治理记录；不再修改源码／测试／脚本。16项源码／脚本与最近R2验证manifest逐字节匹配，所以沿用对应的真实build／回归／工具证据，**本次没有重复运行测试、build或lint**。
- 累计提交文件仍为R2.7所列17项：5生产Swift、7测试Swift、2直接相关静态检查脚本、3文档。未加入DR、PCM、WAV、密钥、本机私人SHA、原始日志或额外文件。
- 主启动函数内直接请求权限一次；权限与三拒绝分支先于Apple backend、Capture prepare和Provider start。唯一共享Engine、Realtime Apple VP、Cascaded原AEC3、Test2原Runtime授权／取消／恢复链保持；没有新Runtime授权Owner。
- 7份测试原断言调用数量和负控／身份／watchdog／旧代保护保持，不删用例或降低数值门槛。Release Guard脚本与HEAD原字节相同。辅助Host静态提取范围发现的MINOR另列FS.3，不将其写成精确范围验证。
- 首轮暂存后 `git diff --cached --check` 为exit2，仅因本报告diff展示的3条空白上下文行尾空格（当时156/178/242行）；限定清除这3个文档空格后重新核验。原始R2报告原字节仍保留在Git外preflight；提交版只归一化这3条空白展示，不改任何历史事实、源码或测试。此前工作区diff检查未包含这份新增报告，本次不将首轮失败隐藏为PASS。
- 使用指定提交信息 `[7.5][T3.2-A-L] finalize incremental lint remediation with recorded debt`；只显式暂存白名单文件，正常push，无强推。最终交付以提交后HEAD=upstream=实时远端且工作区干净为完成条件；实际40位SHA由Git回执和最终汇报提供，不在提交内容中自引用。

## FS.2 主控工程治理决定

1. 本次单独的一次性lint提交例外，只允许提交当前已验证修改，不产生永久例外；不修改 `docs/04_code_standards.md`，不取消工具，不把FAIL改判PASS。
2. C23规范债务：21项文件／类型长度＋2项函数长度，完整逐项清单仍见R2.4；统一登记为Stage7.5结束后的治理债务，本次不再拆分或清理。
3. 后续Stage7.5新增代码严格执行规范，新增违规必须为零；已有结构债务单独登记。
4. 功能、安全、Release Guard零豁免；本次lint例外不得延伸到这些检查。
5. Stage7.5结束后集中治理历史债务。本段只记录主控决定，不新增CI、lint配置、阈值或后续节点代码。
6. SQ-M1仍OPEN；Qwen严格overlap仍0/3；真实设备、T3.2-B、T3.3及正式Test3均未获执行授权。

## FS.3 五维最终核验与实际审核来源

本次完整累计diff再复核来源：

- `/root/lint_capture`：对AppController、AudioHost、OutputHost独立只读累计复核；另跨审AEC中首次L由另一作者抽取的Apple／fallback helper及调用方。自己的Capture或R2 AEC作者部分不冒称独立。
- `/root/lint_hosts`：对Capture完整累计diff和直接上下文独立复核；AEC首次L本人作者块标SELF_REVIEW，其他作者的Apple／R2去重交叉复核。
- `/root/final_submission_tests`：本次新独立AI reviewer，未参与7测试／2脚本的修改；完整累计diff和既有R2摘要只读核对，未执行测试／build／lint。
- `/root`：文档与交付核验SELF_REVIEW，核验原始证据摘要、16项验证身份、白名单、隐私、Git与授权范围。本次代码内容未改变。

| 维度 | 最终结论 | 范围／限制 |
| --- | --- | --- |
| TECHNICAL | PASS；离线安全已获主控APPROVED | 权限先行、Stop／await／旧代保护、唯一Engine、路线隔离及Test2原Owner保持；不含实机／声学验收 |
| ENGINEERING | REWORK / DEBT_DEFERRED | 保留全量严格工具FAIL；C23延期治理；仅当前提交一次性例外，无永久豁免 |
| EVIDENCE | PASS | 当前验证源码完全匹配；实际命令／exit／计数、首次失败、Fake与物理界线均保留 |
| CONSISTENCY | PASS | 当前主控决定与以下R2／L历史快照分开，README／DEVLOG同口径；授权不扩展 |
| Stage7 Forbidden Checklist | PASS | 六红线均未触碰；无新平台、DR/API/Store/Runtime Owner、Provider／设备执行 |

新增CRITICAL=0；新增功能安全MAJOR=0。既有工程规范MAJOR1 OPEN和两个函数规范MINOR OPEN继续登记；本次另发现**MINOR静态检查范围问题1项**：`tools/speech_audio_host_tests/check.sh:99`的awk仍以已删除的 `acceptRealtimeMicrophoneAuthorization` 为结束标记，会扫描到EOF。当前目标helper内确实有Apple选择，R81/R853实际后端断言存在；没有当前功能错误或失败，不构成功能安全MAJOR。但不能声称此辅助awk严格限定helper范围。该问题独立于C23的lint债务，保持OPEN，不凭lint例外将它关闭；本次按“仅提交已验证内容”边界不修改脚本，后续有限检查器维护需另行授权。

六红线最终核验：大脑无平台依赖新增；Store/schema不变；三层与Runtime授权不黏连；DR只读与revision不变；逻辑／画法分离不变；Intent边界不变。范围检查PASS不覆盖工程工具FAIL。

## FS.4 最终状态及停止边界

下列Submission完成状态**仅在本次正常commit/push后Git一致性与clean检查全部成立时生效**；失败必须保留实际失败，不能提前报告完成。Git回执保留在忽略证据目录，由最终回复给出真实SHA。

```text
T3.2-A-L Offline Safety = APPROVED
T3.2-A-L Submission = COMPLETED
ENGINEERING = REWORK / DEBT_DEFERRED
T3.2-A Device = NOT_AUTHORIZED
T3.2-B = NOT_AUTHORIZED
T3.3 = NOT_STARTED
SQ-M1 = OPEN
Qwen Strict Overlap = 0/3
Formal Test3 = BLOCKED
Test3.execution_authorized = false
```

提交推送完成后立即停止，不自动进入设备、T3.2-B、T3.3、Human Gate或真实Qwen。本轮未改变ACE3及VP研究worktree。

---

# 历史快照 · R2本地审核（以下完整保留）

下文“尚未批准／LOCAL_ONLY／未获提交例外／未提交”等均指Final Submission主控决定前的R2审核快照；当前授权以FS.1–FS.4为准。原失败和未验证条件不追溯改判。

# Eterna Aftelle · T3.2-A-L-R2 · Release Guard修复与本地工程复核

日期：2026-10-16（Asia/Shanghai）。当前状态：**T3.2-A-L = REVIEW_PENDING / LOCAL_ONLY；ENGINEERING = REWORK**。

**建议本轮离线功能安全部分收口；不建议全局工程规范收口。** Release Guard、Debug / 未签名 Release、受影响离线回归均真实 PASS；新增 B＝0。C＝23：21项文件／类型结构债务、2项保留函数长度债务。SwiftFormat 18,286 / exit 1、SwiftLint strict 312 / exit 2，仍为 **FAIL**；没有提交豁免沿用、没有 commit / push。主控仍是批准者，本结论不是节点 APPROVED。

本轮更新采用“当前 R2 结果＋下方首次 L 交付历史全文”的结构。下方原 18,285 / 312、B1 / C24、Release guard FAIL、构建 NOT_RUN 均为首次 L 候选的真实历史，不追溯改判，也不是当前 R2 状态。T3.2-A 历史报告及其他验收文件保持原样。

## R2.1 起点与保留范围

- 任务开始时 Clean HEAD、upstream、实时远端均为 `e0b4f686d8b872ffac4fb9abfa9dadb7f0377e9a`；分支 `Test3-AppleVP-Clean`，追踪 `origin/Test3-AppleVP-Clean`，远端 `JerryYork3516/Eterna_Aftelle`。
- 初始 17 个未提交文件与前次交付一致，staging 为空；前次验证的 13 Swift + 2 脚本字节身份全部匹配。
- 在 Git 忽略目录 `.build/t3_2_a_l_r2/incoming/` 保存全部 17 文件原字节与 `incoming.diff` / `incoming-manifest.json`。未 reset / clean / stash / checkout / 切换 worktree，未覆盖或丢弃首次 L 变更。
- 本轮相对 incoming 仅再修改 **2个生产 Swift、1个测试 Swift、3份既有本地文档**；累计仍是原 17 文件，没有新增白名单外文件、测试标准、lint配置或生产组件。
- 用户明确本轮不自动 commit / push，故不执行规则中的跨文件 checkpoint commit；使用既有 e0 加本地忽略快照保留恢复证据。e0 的一次 lint 提交豁免不延续，不改代码规范。
- 权威计划仍为 [README v2](README.md) / [T3.1-R2](T3_1_R2_native_voice_experience_plan.md)。Stage7任务前检查 PASS；任务后六条红线见 R2.8。

## R2.2 Release Guard根因与定点修复

首次 L 的真实失败为 `start_permission_helper expected=1 actual=0`：权限调用和权限错误 switch 被抽离主启动函数，旧 guard 在单函数片段内无法证明权限→身份 fence→prepare→Provider 的顺序。R2 **不改 guard**，直接修复 AppController 局部重构：

1. `startRealtimeResidentBrainRoute()` 内直接 `await ensureRealtimeMicrophoneAuthorization()` 恰好一次。
2. await 后立即检查同一 attempt、shutdown operation / completion；失败时只执行原条件式 shutdown→snapshot，随后返回。
3. 原 `required` / `denied` / `unavailable` 三个错误分支回到该启动函数；授权失败不会到后端选择、prepare 或 Provider。
4. `.appleVoiceProcessing` backend helper 仅做后端选择及错误关闭，无重复权限调用；删除无消费者的 `acceptRealtimeMicrophoneAuthorization`。
5. 保留 `selectSpeechAudioProcessingMode` 前后 stop-generation / shutdown fence、backend await 后 attempt fence、prepare await 后取消旧准备代、Provider await 后 abandoned-start处理；无第二 Engine、Provider取消或Session / Runtime机制改动。

最终顺序：**Microphone Authorization → attempt/shutdown身份检查 → Apple VP backend selection → prepareCaptureGeneration → Provider Session Start**。

`settleAbandonedRealtimeAuthorization()` 只承接原 guard 失败分支的条件式 shutdown 清理，继承现有 MainActor。helper 仅含原有 shutdown 和 currentSnapshot 两条 await 操作；没有新 Task / Actor、其他异步调用或状态 owner。静态审核不推断运行时实际挂起次数。无 shutdown 的失效 attempt 仍不做额外清理，父函数仍立即 return。此小函数使权限安全链直接可审计，同时避免启动函数重新超过基线复杂度／长度。

相关函数仍在 Release 可见区；DEBUG 只包原诊断。`tools/realtime_release_route_guard/check.sh` 与 HEAD 原字节相同，无删减、放宽或伪造断言。

| 候选／运行 | 命令 | exit / 结果 |
| --- | --- | --- |
| 首次 L（历史） | `bash tools/realtime_release_route_guard/check.sh` | 1 / FAIL，expected=1 actual=0 |
| R2首次定点修复 | 同上 | 0 / PASS |
| R2局部清理函数完成 | 同上 | 0 / PASS |
| 最终格式候选／验证前 | 同上 | 0 / PASS |

重跑仅对应后续实际源码变化，用于确认最终候选；没有失败后反复调参或改 guard。R2没有 Release Guard / 构建 / 安全回归失败，旧 L 失败完整保留。

## R2.3 具体源码diff与函数长度取舍

相对本轮 incoming 的完整源码diff（仅3文件）如下，非 ab11→e0→L 的累计diff；累计清单见 R2.7。

```diff
--- incoming-L/apps/macos/Aftelle/AppController.swift
+++ R2/apps/macos/Aftelle/AppController.swift
@@ -3127,4 +3127,34 @@
             lastErrorCode: nil
         )
+        let microphoneAuthorization =
+            await ensureRealtimeMicrophoneAuthorization()
+        guard realtimeBrainRouteAttemptID == attemptID,
+              speechAudioHostShutdownOperation == nil,
+              !speechAudioHostShutdownCompleted else {
+            await settleAbandonedRealtimeAuthorization()
+            return
+        }
+        switch microphoneAuthorization {
+        case .authorized:
+            break
+        case .notDetermined:
+            realtimeBrainRouteAttemptID = nil
+            publishRealtimeResidentBrainRouteFailure(
+                "microphone_permission_required"
+            )
+            return
+        case .denied:
+            realtimeBrainRouteAttemptID = nil
+            publishRealtimeResidentBrainRouteFailure(
+                "microphone_permission_denied"
+            )
+            return
+        case .restricted, .failed:
+            realtimeBrainRouteAttemptID = nil
+            publishRealtimeResidentBrainRouteFailure(
+                "microphone_permission_unavailable"
+            )
+            return
+        }
         guard await prepareRealtimeSpeechAudioBackend(attemptID: attemptID) else {
             return
@@ -3261,20 +3291,4 @@

     private func prepareRealtimeSpeechAudioBackend(attemptID: UUID) async -> Bool {
-        let microphoneAuthorization =
-            await ensureRealtimeMicrophoneAuthorization()
-        guard realtimeBrainRouteAttemptID == attemptID,
-              speechAudioHostShutdownOperation == nil,
-              !speechAudioHostShutdownCompleted
-        else {
-            if speechAudioHostShutdownOperation != nil || speechAudioHostShutdownCompleted {
-                await speechAudioHost.shutdown()
-                speechAudioHostSnapshot =
-                    await speechAudioHost.currentSnapshot()
-            }
-            return false
-        }
-        guard acceptRealtimeMicrophoneAuthorization(microphoneAuthorization) else {
-            return false
-        }
         do {
             try await selectSpeechAudioProcessingMode(
@@ -3295,28 +3309,9 @@
     }

-    private func acceptRealtimeMicrophoneAuthorization(
-        _ microphoneAuthorization: MicrophoneAuthorizationState
-    ) -> Bool {
-        switch microphoneAuthorization {
-        case .authorized:
-            return true
-        case .notDetermined:
-            realtimeBrainRouteAttemptID = nil
-            publishRealtimeResidentBrainRouteFailure(
-                "microphone_permission_required"
-            )
-            return false
-        case .denied:
-            realtimeBrainRouteAttemptID = nil
-            publishRealtimeResidentBrainRouteFailure(
-                "microphone_permission_denied"
-            )
-            return false
-        case .restricted, .failed:
-            realtimeBrainRouteAttemptID = nil
-            publishRealtimeResidentBrainRouteFailure(
-                "microphone_permission_unavailable"
-            )
-            return false
+    private func settleAbandonedRealtimeAuthorization() async {
+        if speechAudioHostShutdownOperation != nil || speechAudioHostShutdownCompleted {
+            await speechAudioHost.shutdown()
+            speechAudioHostSnapshot =
+                await speechAudioHost.currentSnapshot()
         }
     }
--- incoming-L/apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift
+++ R2/apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift
@@ -1082,9 +1082,5 @@
             }
             guard mode == .webRTCAEC3, let backend else {
-                recordUnavailableCaptureObservation(
-                    samples,
-                    hostTimeNanoseconds: hostTimeNanoseconds
-                )
-                return [captureSpan(samples: samples)]
+                return makeUnavailableCaptureSpans(samples, hostTimeNanoseconds: hostTimeNanoseconds)
             }
             #if DEBUG
@@ -1189,4 +1185,11 @@
         guard mode == .appleVoiceProcessing,
               !isRouteRebuilding else { return [] }
+        return makeUnavailableCaptureSpans(samples, hostTimeNanoseconds: hostTimeNanoseconds)
+    }
+
+    private func makeUnavailableCaptureSpans(
+        _ samples: [Float],
+        hostTimeNanoseconds: UInt64?
+    ) -> [MacSpeechAcousticCaptureSpan] {
         recordUnavailableCaptureObservation(
             samples,
--- incoming-L/tools/realtime_resident_only_zero_self_interrupt_tests/RealtimeResidentOnlyZeroSelfInterruptTests.swift
+++ R2/tools/realtime_resident_only_zero_self_interrupt_tests/RealtimeResidentOnlyZeroSelfInterruptTests.swift
@@ -11532,5 +11532,5 @@
             expect(capture.processingMode == .appleVoiceProcessing,
                    "R8.5.3 mechanical fake records the Realtime Apple backend request")
-    }
+        }

     private static func emitR853QwenListeningNearEnd(
```

- R853 B1仅把新 helper 结束括号从4改为8空格；等待、backend断言及全部测试内容不变。
- AEC重复的 `recordUnavailableCaptureObservation → captureSpan → 数组返回` 合并为一个同步 helper，两个真实消费者是有效 Apple capture 和原 non-AEC / backend缺失分支；均仍处在原 `queue.sync` 下。无新锁／await／状态，未增加PCM复制或重采样；fallback的条件式构造、FIFO、WebRTC处理与catch原样。
- `consumeFormalSpeechPlaybackEvent` 不再拆：77相对76仅多必需的 output close；它必须位于 stopCapture 后、Runtime commit 前。为1行搬动整个历史完成阶段会增加异步 helper 边界及回归范围，且没有重复逻辑可去除。
- `makeSnapshot` 不再拆：92相对90仅增加两个有消费者的真实观测实参。它是无分支字段投影；拆分需要不必要的部分DTO／初始化协议或包装层，不能带来实际复杂度收益。

本轮没有将保留理由当作规则豁免：后两项仍记录 C OPEN。21项文件／类型增长依主控要求单独列债，不大规模拆文件。

| 函数／指标 | ab11 | e0 | 首次L | R2 | 结论 |
| --- | --- | --- | --- | --- | --- |
| Realtime start 函数长度 | 209 | 224 | 177 | 207 | 未超过基线；历史超阈值仍在 |
| Realtime start 复杂度 | 23 | 26 | 18 | 23 | 等于基线；历史超阈值仍在 |
| processCaptureSpans 函数长度 | 111 | 120 | 114 | 110 | C关闭；仍有原超阈值历史诊断 |
| consumeFormalSpeechPlaybackEvent 长度 | 76 | 77 | 77 | 77 | C保留；必要close顺序 |
| makeSnapshot 长度 | 90 | 92 | 92 | 92 | C保留；必要实参 |

## R2.4 严格工具与真实增量

沿用 SwiftFormat **0.63.1**、SwiftLint **0.65.1**，本轮实际 `--version` 核验一致。基线 ab11／e0／首次 L 的原始报告保持原字节，不无目的重跑。最终检查使用同一显式13 Swift文件并集、同一规则与参数；新增Converter测试按全文件检查，最终0诊断，因此JSON只有12文件含诊断，但实际输入仍13文件。

```sh
<SwiftFormat-0.63.1> --lint --reporter json --report <ignored>/format_r2_verified.json <13 explicit Swift files>
<SwiftLint-0.65.1> lint --strict --quiet --reporter json --cache-path <ignored>/lint-cache-r2_verified <13 explicit Swift files>
```

| 工具 | ab11 | e0 | 首次L | R2最终 | 最终exit / 结果 |
| --- | --- | --- | --- | --- | --- |
| SwiftFormat | 18408 | 18697 | 18285 | 18286 | 1 / FAIL |
| SwiftLint strict | 317 | 341 | 312 | 312 | 2 / FAIL |

格式计数比L多1，不代表新增问题：恢复原权限分支带回历史诊断，B1缩进已关闭。相对L规则变化仅 `elseOnSameLine` 145→146、`indent` 17025→17024、`wrapMultilineStatementBraces` 338→339；其余规则条数不变。不能用总数差推导增量。

保留中间工具结果：R2首次检查18,287 / 312；随后局部 brace 换行出现 SwiftLint `opening_brace` 新诊断（18,286 / 313），已用该既有条件的自然单行写法解决（不足120字符），最终18,286 / 312。未禁用规则或改配置，没有把中间新增诊断藏为历史；全局工具三次均FAIL，最终B0不改变全局结果。

继续使用首次L的Git变更区间／函数身份／邻接token审计方法；Host第39／187行两项仍按已核验的基线单行if/property前置源码归D，不因报告后继token变化列B。最终可复算证据：`.build/t3_2_a_l_r2/attribution-final-r2.json`、`remaining-c-r2.json`、`rule-counts-l-to-r2.json`、`tool-results-verified.json`、`format_r2_verified.json` / `lint_r2_verified.json`。机器未校正初稿仍另保留为 `classification-post.json`，不与最终canonical混淆。

| 工具／候选 | A | B | C | D | 总数 |
| --- | --- | --- | --- | --- | --- |
| Format 首次L | 717 | 1 | 0 | 17567 | 18285 |
| Format R2 | 717 | 0 | 0 | 17569 | 18286 |
| Lint 首次L | 17 | 0 | 24 | 271 | 312 |
| Lint R2 | 17 | 0 | 23 | 272 | 312 |

R2剩余：**B0；C23＝file_length 11＋type_body_length 10＋function_body_length 2**。历史未恶化A+D：Format18,286；Lint289。C23不并入“纯历史未恶化”，也不声称增量全部清零。

以下列出全部23项剩余C（文件名与下方完整清单一一对应）：

| 文件 | 规则／scope | ab11 | 首次L | R2 | 类别 |
| --- | --- | --- | --- | --- | --- |
| AppController.swift | file_length / `<file>` | 6943 | 7140 | 7135 | 结构债务 |
| AppController.swift | function_body_length / `func:consumeFormalSpeechPlaybackEvent` | 76 | 77 | 77 | 函数债务 |
| AppController.swift | type_body_length / `type:AppController` | 6313 | 6502 | 6497 | 结构债务 |
| MacSpeechAcousticEchoHost.swift | file_length / `<file>` | 3390 | 3470 | 3473 | 结构债务 |
| MacSpeechAcousticEchoHost.swift | function_body_length / `func:makeSnapshot` | 90 | 92 | 92 | 函数债务 |
| MacSpeechAcousticEchoHost.swift | type_body_length / `type:MacSpeechAcousticEchoHost` | 2569 | 2638 | 2640 | 结构债务 |
| MacSpeechAudioCapture.swift | file_length / `<file>` | 1404 | 1814 | 1814 | 结构债务 |
| MacSpeechAudioCapture.swift | type_body_length / `type:SystemMacSpeechVoiceProcessingEngine` | 630 | 690 | 690 | 结构债务 |
| MacSpeechAudioHost.swift | file_length / `<file>` | 498 | 520 | 520 | 结构债务 |
| MacSpeechAudioHost.swift | type_body_length / `type:MacSpeechAudioHost` | 370 | 390 | 390 | 结构债务 |
| MacSpeechAudioOutputHost.swift | file_length / `<file>` | 811 | 839 | 839 | 结构债务 |
| MacSpeechAudioOutputHost.swift | type_body_length / `type:MacSpeechAudioOutputHost` | 670 | 696 | 696 | 结构债务 |
| MacSpeechAudioOutputPlayer.swift | file_length / `<file>` | 461 | 465 | 465 | 结构债务 |
| RealtimeInterruptionEvidenceTests.swift | file_length / `<file>` | 2396 | 2659 | 2659 | 结构债务 |
| RealtimeInterruptionEvidenceTests.swift | type_body_length / `type:RealtimeInterruptionEvidenceTests` | 1829 | 1965 | 1965 | 结构债务 |
| RealtimeResidentOnlyZeroSelfInterruptTests.swift | file_length / `<file>` | 12203 | 12226 | 12226 | 结构债务 |
| RealtimeResidentOnlyZeroSelfInterruptTests.swift | type_body_length / `type:RealtimeResidentOnlyZeroSelfInterruptTests` | 11271 | 11278 | 11278 | 结构债务 |
| MacSpeechAcousticEchoHostTests.swift | file_length / `<file>` | 2057 | 2219 | 2219 | 结构债务 |
| MacSpeechAcousticEchoHostTests.swift | type_body_length / `type:MacSpeechAcousticEchoHostTests` | 1842 | 2000 | 2000 | 结构债务 |
| MacSpeechAudioHostTests.swift | file_length / `<file>` | 711 | 982 | 982 | 结构债务 |
| MacSpeechAudioHostTests.swift | type_body_length / `type:MacSpeechAudioHostTests` | 492 | 703 | 703 | 结构债务 |
| MacSpeechAudioOutputHostTests.swift | file_length / `<file>` | 1054 | 1379 | 1379 | 结构债务 |
| MacSpeechAudioOutputHostTests.swift | type_body_length / `type:MacSpeechAudioOutputHostTests` | 992 | 1306 | 1306 | 结构债务 |

## R2.5 实际构建与安全回归

最终候选 Release Guard PASS 后，顺序执行 Debug→Release，两者均为同一显式 Aftelle project/scheme、独立 R2 DerivedData、禁用签名；没有运行App或设备。随后按受影响范围运行以下离线入口各一次。AEC入口已包含Converter及合成Replay；R853 suite已包含三个子模式；confirmed/latency分别包装r832/r833，不额外重复子入口。未重跑完整Qwen Adapter / Session-Memory等未受影响历史套件。

Host、AEC、Input与Runtime集成覆盖受改权限／捕获链；Playback按本轮明确列项作一次传递编译依赖回归（脚本编译AECHost），其238 checks不冒充新capture helper的运行覆盖。与新helper直接相关的行为证据来自AEC/Converter及路线集成。

| 实际命令 | exit | 结果 | cases/checks／限制 |
| --- | --- | --- | --- |
| xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug -destination platform=macOS -derivedDataPath .build/t3_2_a_l_r2/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build | 0 | PASS | —；BUILD SUCCEEDED |
| xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Release -destination platform=macOS -derivedDataPath .build/t3_2_a_l_r2/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build | 0 | PASS | —；BUILD SUCCEEDED；unsigned |
| bash tools/speech_audio_host_tests/check.sh | 0 | PASS | 178 checks；不编造runtime cases |
| bash tools/speech_audio_output_tests/check.sh | 0 | PASS | 238 checks；传递编译依赖 |
| bash tools/speech_aec_host_tests/check.sh | 0 | PASS | AEC1165 checks；Converter25 cases / 221 checks；synthetic Replay |
| bash tools/mac_speech_realtime_brain_input_tests/check.sh | 0 | PASS | 32 cases / 210 checks |
| bash tools/realtime_interruption_evidence_tests/check.sh | 0 | PASS | 28 cases / 239 checks；权限6、准备Stop3为子集，不另加总 |
| bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r823-full | 0 | PASS | 12 cases / 126 checks |
| bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r853-qwen-suite | 0 | PASS | 15 cases / 223 checks＝10/120＋1/59＋4/44 |
| bash tools/realtime_confirmed_interruption_tests/check.sh | 0 | PASS | 1 case / 62 checks |
| bash tools/realtime_barge_in_latency_stale_audio_tests/check.sh | 0 | PASS | 1 case / 68 checks |

本轮两build及所有离线入口首次执行即exit0，没有隐藏失败后重试；完整命令／elapsed／exit在 `verification-results.json`，原始日志位于同一Git忽略目录。Release guard的三次PASS与源码修改顺序另列R2.2；本轮中间lint诊断另列R2.4。首次L的失败／NOT_RUN完整保留在下方历史。

验证开始前冻结16项源码／脚本（13 Swift＋原2个局部同步脚本＋未改Release guard）身份；全部验证结束后逐字节一致。构建与测试间未改源码、测试、README或报告，未触发resident脚本的工作区变更；后续仅更新三份授权文档。

所有音频数据来自既有Fake／合成PCM，R853为真实Adapter接内存Fake WebSocket，没有真实Provider请求或费用，没有mic／speaker Engine或设备实验。固定fixture只由已批准离线脚本加载，无内容打印／导出／修改。DEBUG Controller仍可能执行既有属性级Keychain `exists`查询，不宣称零Keychain API或临时HOME隔离系统Keychain；本轮无secret获取。真实Apple AEC / NS / AGC音质、削波／路由、持续双讲及Human Gate全部NOT_RUN / NOT_AUTHORIZED。

## R2.6 五维审核、问题登记与收口建议

实际审核来源：

- `/root`：AppController、R853B1及文档作者；这些部分标SELF_REVIEW；实际工具／build／回归由root执行并保存日志。
- `/root/lint_capture`：仅AEC helper作者（本文件SELF_REVIEW）；对跨作者AppController和R853进行独立只读审核，确认权限调用、MainActor/原await、Stop fence、Release可见性与无Runtime／Provider／Session旁路。
- `/root/lint_hosts`：本轮没有编辑；独立只读审查AppController最终cleanup helper及另一作者AEC去重的两消费者、队列／fallback／PCM构造顺序。其在首次L的作者身份已在历史登记，R2审查不冒充盲审。
- `/root/lint_tests`：本轮没有编辑或运行测试；独立复算最终raw/canonical多重集、基线引用、B/C、cases/checks、exit、时间顺序及16项manifest；并复核offline Fake依赖。首次L测试作者身份保留；R2证据审核不是代替root执行。

独立审查未发现本轮新CRITICAL或功能安全MAJOR；没有把各reviewer的只读判断写成其亲自运行测试。报告一致性再按最终文本只读复核。

| 维度 | 结论 | 边界 |
| --- | --- | --- |
| TECHNICAL_REVIEW | PASS（离线功能安全范围；建议） | 原Releaseguard、两build及受影响安全回归均PASS；状态／权限／generation所有权保持；不含设备／声学验收 |
| ENGINEERING_REVIEW | REWORK | 全局强制工具仍FAIL，C23尚未规范收口；B0及函数处理理由不构成提交豁免 |
| EVIDENCE_REVIEW | PASS | 独立原始诊断逐条覆盖／基线无过量复用；实际命令exit、首次失败与NOT_RUN边界准确 |
| CONSISTENCY_REVIEW | PASS（授权与状态一致） | R2新旧状态分开；最终README/DEVLOG与报告同口径；原合同/研究/Test2/Qwen0/3不改 |
| Stage7 Forbidden Checklist | PASS（范围／六条红线） | 无新增平台／Owner／DR/API／Provider旁路／设备执行；不覆盖lint FAIL |

| 问题／级别 | 当前状态 | 实际处置 |
| --- | --- | --- |
| L-M2 / 原MAJOR | CLOSED（R2离线验证） | 直接权限链恢复，guard及Debug/Release/受影响安全套件通过；不改测试器 |
| L-m1 / 原MINOR | CLOSED | R853缩进B1修复，最终B0 |
| R2中间brace诊断 / MINOR | CLOSED | 保留313项中间FAIL，最终无该新增诊断 |
| R2-review措辞 / MINOR | CLOSED | 按独立审核改为“两条原有await操作”，不从静态源码推断实际挂起次数；没有代码变更 |
| E-1 / 工程规范MAJOR | OPEN（继承L-M1） | 全局SwiftFormat/SwiftLint仍FAIL；21结构C＋2函数C登记；无豁免、不能提交 |
| F-1 / MINOR规范债务 | OPEN（保留理由） | consumer76→77；必要close在stopCapture与commit之间，不拆异步阶段 |
| F-2 / MINOR规范债务 | OPEN（保留理由） | snapshot90→92；两个必要观测实参，不增部分DTO/初始化协议 |
| SQ-M1 / 历史安全问题 | OPEN（独立边界） | 不是本轮lint新增，未验声学/资格兼容，不因工具或Fake PASS关闭 |

本轮最终：CRITICAL0；新增功能安全MAJOR0；**工程规范MAJOR1 OPEN、MINOR规范债务2 OPEN**。已关闭的Release / B1 / 中间brace问题单独保留，不与剩余lint observation数混算。SQ-M1是历史独立OPEN问题，不计入本次规范新增。

收口建议：**离线功能安全部分 PASS_RECOMMENDED；全局ENGINEERING仍REWORK。** 两个函数已给出具体不宜继续拆分理由，满足本轮有限技术安全收口条件；21结构债务保留。由于代码规范的强制工具仍FAIL，若主控希望提交当前候选，仍需要其另行明确给予本次提交例外；本轮不请求大范围重构、不自动请求／授予豁免、不commit/push。不是T3.2-A整体APPROVED，也不是设备或下一节点准入。

## R2.7 累计文件清单与状态

| 累计未提交文件 | 本轮R2 |
| --- | --- |
| DEVLOG.md | 本轮文档更新 |
| apps/macos/Aftelle/AppController.swift | 本轮源码局部修复 |
| apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift | 本轮源码局部修复 |
| apps/macos/Aftelle/MacSpeechAudioCapture.swift | 保留首次L原字节 |
| apps/macos/Aftelle/MacSpeechAudioHost.swift | 保留首次L原字节 |
| apps/macos/Aftelle/MacSpeechAudioOutputHost.swift | 保留首次L原字节 |
| docs/stage7_5/test3_apple_vp_clean/README.md | 本轮文档更新 |
| docs/stage7_5/test3_apple_vp_clean/T3_2_A_L_incremental_lint_review.md | 本轮文档更新 |
| tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift | 保留首次L原字节 |
| tools/realtime_resident_only_zero_self_interrupt_tests/RealtimeResidentOnlyZeroSelfInterruptTests.swift | 本轮源码局部修复 |
| tools/speech_aec_host_tests/ConverterTimelineTests.swift | 保留首次L原字节 |
| tools/speech_aec_host_tests/MacSpeechAcousticEchoHostTests.swift | 保留首次L原字节 |
| tools/speech_aec_host_tests/check.sh | 保留首次L原字节 |
| tools/speech_audio_host_tests/MacSpeechAudioHostTests.swift | 保留首次L原字节 |
| tools/speech_audio_host_tests/check.sh | 保留首次L原字节 |
| tools/speech_audio_output_tests/FakeMacSpeechAudioOutputPlayer.swift | 保留首次L原字节 |
| tools/speech_audio_output_tests/MacSpeechAudioOutputHostTests.swift | 保留首次L原字节 |

```text
T3.2-A = REVIEW_PENDING
T3.2-A-L = REVIEW_PENDING / LOCAL_ONLY
TECHNICAL_SAFETY = PASS_RECOMMENDED (OFFLINE_ONLY)
ENGINEERING = REWORK
T3.2-A Device = NOT_AUTHORIZED
T3.2-B = NOT_AUTHORIZED
T3.3–T3.6 = NOT_STARTED
SQ-M1 = OPEN
Qwen Strict Overlap = 0/3
Formal Test3 = BLOCKED
Test3.execution_authorized = false
```

## R2.8 Stage7六条红线与停止边界

| 红线 | R2证据 | 结论 |
| --- | --- | --- |
| 大脑不碰平台 | RuntimeCore/brain无变化，仅原macOS Host局部函数 | PASS |
| Store带版本 | 无Store/schema改动 | PASS |
| 三层不黏连 | 无Runtime授权、Provider取消、Session机制、Bridge/Qwen Adapter修改；权限仍原Controller→Host | PASS |
| DR只读+revision | 无DR/schema/fixture/revision修改或资产进Git | PASS |
| 逻辑/画法分层 | 无粒子/Metal改动 | PASS |
| 交互按意图 | 无坐标式业务逻辑或新交互能力 | PASS |

Stage7其他范围项亦PASS：无新target/Stage8/调度/Memory owner/第二Engine/常驻监听；未新增Source Gate或把sourceAttributionConfirmed写成true。Apple VP完整处理路径保持原实现（input/output VP、bypass、unmuted、实际AGC状态、格式/Converter/packetization）；R2未改Capture字节，Cascaded继续真实AEC3、不双重AEC。机械build/Fake回归不能证实真实Apple声学质量。

本轮不碰AGENTS、04规范、旧Test3合同、01–24研究报告、Test2/T3.0-F/T3.2-A历史验收。最终检查完成后停止，交由主控审核；未进入T3.2-B/T3.3或设备/Provider。

## R2.9 最终只读本地核验

最终只读核验已完成，实际记录位于 Git 忽略目录 `.build/t3_2_a_l_r2/final-local-checks.json`：

| 核验项 | 实际结果 |
| --- | --- |
| HEAD / upstream / 实时远端 | 均为 `e0b4f686d8b872ffac4fb9abfa9dadb7f0377e9a`；实时远端读取 exit0 |
| 本地变更保留 | 累计原17文件；无白名单外项；相对incoming仅3源码＋3文档变化，其余11文件原字节保留 |
| 验证源码身份 | 16项源码／脚本全部匹配验证manifest，无验证后代码补丁 |
| Release guard | 文件与HEAD原字节相同 |
| `git diff --check` | exit0；不替代严格lint结果 |
| staging / commit / push | staging为空；均未执行提交或推送，没有新SHA |
| ACE3 / VP研究worktree | HEAD、diff和status任务前后指纹全部一致；未改变原worktree |
| 交付资产／隐私 | 无DR/PCM/WAV/key/raw日志文件进入改动清单；新增文本无私人绝对路径／secret字面值候选 |
| 禁用／配置 | R2无新增lint:disable；无lint配置／阈值／AGENTS／04规范／历史合同／验收改动 |
| 文档链接 | 当前README及报告所有本地链接目标存在 |

报告R2.1–R2.8和README/DEVLOG已由独立只读reviewer复核：证据／一致性PASS；技术建议仅限离线安全，ENGINEERING仍REWORK。独立审核提出的一处await／实际挂起措辞已修正，未改源码。随后只补本节真实Git结果，不重跑测试或构建。

完成后停止。主控尚未批准节点或新提交例外；T3.2-A-L保持REVIEW_PENDING / LOCAL_ONLY。

---

# 历史快照 · T3.2-A-L 首次本地交付（以下保持原结果）

下文为R2开始时17文件快照中的首次报告正文；其“当前／停止／未构建”均指首次L候选。R2当前状态以本文R2.1–R2.9为准，不覆盖原失败。

# Eterna Aftelle · T3.2-A-L · 增量规范修复实际审核

日期：2026-10-16（Asia/Shanghai）。状态：**LOCAL_PARTIAL / STOPPED；ENGINEERING = REWORK；未提交、未推送。**

本轮没有达到“本次引入的可归责问题归零”。修复后 SwiftFormat 仍 FAIL（exit 1，18,285 项）；SwiftLint strict 仍 FAIL（exit 2，312 项）。准确归因后仍有 **B 类 1 项、C 类 24 项**。受影响离线运行套件全部通过，但 **Release route guard 实际 FAIL（exit 1）**；按停止条件，后续 Debug / Release 构建 NOT_RUN，未修改该 guard 后重跑。不能建议 T3.2-A 工程收口。

本报告是当前本地候选的证据，不改变 [T3.2-A 历史报告](T3_2_A_implementation_and_review.md) 的当时结果。e0b4f686 的单次 lint 提交豁免不延续至本轮。主控未批准本候选、设备实验或下一节点。

## 1. Git、范围与证据身份

- Repository：`JerryYork3516/Eterna_Aftelle`；Branch：`Test3-AppleVP-Clean`；upstream：`origin/Test3-AppleVP-Clean`。
- 任务开始时 HEAD、upstream、实时远端同为 `e0b4f686d8b872ffac4fb9abfa9dadb7f0377e9a`，工作区干净。该既有提交是回滚点，本轮未创建新提交。
- 固定比较基线：`ab11ca11f405e5b11a6f48ef1b595a3be4f1127d`；修复前：`e0b4f686d8b872ffac4fb9abfa9dadb7f0377e9a`；修复后：当前未提交工作区。
- 白名单为 T3.2-A 改动的 13 个 Swift 文件（6 生产、7 测试），不全库搜索或格式化。基线中实际存在 12 个；新增 `ConverterTimelineTests.swift` 无基线文件，按全文件检查，不能把其问题归历史。
- 实际修改 12 个 Swift 文件（5 生产、7 测试）、2 个直接受 helper 抽取影响的静态检查脚本；另外仅本报告、README、DEVLOG。`MacSpeechAudioOutputPlayer.swift` 已审查，无需局部修复，保持 e0 原字节。
- 未改 RuntimeCore、Qwen Adapter、Input Bridge、DR、Store、公开 Runtime API、lint 配置、Xcode 工程或旧合同。没有 cherry-pick、lint:disable、删除测试断言或新 State Owner。
- 原始工具 JSON、命令、日志、逐条归因及源码身份保存在 Git 忽略目录 `.build/t3_2_a_l/`；不将私人 Fixture、原始日志或本机私人摘要写入 Git。本报告仅使用仓库相对路径和脱敏计数。
- `validation-source-manifest.json` 登记 13 个 Swift 文件和 2 个脚本在验证前的字节身份；验证停止后复核这些文件未再改变。原 ACE3 / VP 研究 worktree 只读，最终检查记录在第 10 节。

依据：[正式计划 v2](T3_1_R2_native_voice_experience_plan.md)、[代码规范](../../04_code_standards.md)、[Stage7 Checklist](../../stage7_forbidden_checklist.md)。本轮按用户指定范围执行；规则、阈值、工具版本和参数均不降低。

## 2. 同口径工具结果与归因方法

工具固定为 SwiftFormat **0.63.1**、SwiftLint **0.65.1**。基线和修复前文件均由上述精确 Git 对象导出至忽略快照目录；修复后检查同一文件并集。没有额外规则覆盖。命令中的 `<files>` 是本报告第 4 节的显式 13 文件并集，基线只传入其中实际存在的 12 个；`<evidence>` 为上述忽略目录，绝非更大目录递归检查。

```sh
<SwiftFormat-0.63.1> --lint --reporter json --report <evidence>/format_<phase>.json <files>
<SwiftLint-0.65.1> lint --strict --quiet --reporter json --cache-path <evidence>/lint-cache-<phase> <files>
```

三阶段工具各执行一次最终同口径审计；期间局部修改的检查日志另外保留，不替换最终结果。工具报告的 observation 是规则诊断条目，**不是独立缺陷、测试 case 或物理声学证据**。未使用“修复前后总数差”代替归因。

| 工具 / 阶段 | 基线 ab11 | 修复前 e0 | 本地修复后 | 结果 / exit |
| --- | --- | --- | --- | --- |
| SwiftFormat | 18,408 | 18,697 | 18,285 | 三阶段 FAIL / 1 |
| SwiftLint strict | 317 | 341 | 312 | 三阶段 FAIL / 2 |

分类定义：A＝原有、对应源码位置未移动且未恶化；B＝新增，基线无对应诊断；C＝原有超标指标因 T3.2-A 及本轮修改而继续增长；D＝同一历史规则／源码诊断的行号移动、函数迁移或报告邻接 token 变化，未恶化。A 与 D 都是历史残余，但 D 不代表已修复。

使用 `git diff --unified=0 ab11…e0` 和当前 diff 将诊断关联到变更区间；精确行映射优先，移动代码以同文件、规则、实际源码、函数身份和基线诊断计数匹配。长度／复杂度按对应函数与类型实际测值比较；新增测试文件全部为新增范围。对报告指向下一 token 的特殊情况人工回看前置源码，不能只按行文本相似度归 D。

| 工具 / 阶段 | A | B | C | D | 合计 |
| --- | --- | --- | --- | --- | --- |
| Format 修复前 | 717 | 365 | 0 | 17615 | 18697 |
| Format 修复后 | 717 | 1 | 0 | 17567 | 18285 |
| Lint 修复前 | 12 | 28 | 32 | 269 | 341 |
| Lint 修复后 | 17 | 0 | 24 | 271 | 312 |

修复后历史未恶化残余：Format A+D＝18,284；Lint A+D＝288。另有 C＝24，必须独立保留，不能合并为“全是历史”。B＝1 与 C＝24 合计为 25 项仍可归责观察，并非 25 个独立行为缺陷。

最终可复算归因文件为 `.build/t3_2_a_l/attribution-final-pre.json`、`attribution-final-post.json`，按规则汇总为 `rule-attribution-pre.json` / `rule-attribution-post.json`，增量表为 `incremental-problem-matrix.csv`，三阶段原始规则计数为 `all-rule-counts.json`。这些派生文件保留逐条人工校正后的 B365 / B1。`classification-*.json` / `classification-summary-*.json` 是未做邻接 token 人工校正的机器初稿（原 B369 / B3），保留作过程记录，**不是最终归因**；原工具 JSON 未修改。

人工修正与防误判：

- Host 修复前第 39 行 `wrapIfStatementBodies`、第 179 行 `wrapPropertyBodies`（修复后第 39 / 187 行）实际指向旧 `queryFails` / `isStarted` 前置单行体的后续 token；基线对应 33 / 140 行，属于 D。
- R81 修复前第 301 行的空行／property 诊断来自原 `stopCount` scope 结束位置（基线 205 行），属于 D。
- AEC `testAppleModeDoesNotUseWebRTC` 在 ab11 仅 10 行、没有函数长度警告；e0 扩展后 71 行的警告属于 **B**，不能写成 C。最终矩阵已更正早期工作笔记中的误分类。
- R853 新 helper `waitForR853StartAndVerifyBackend` 第 11534 行结束括号为 4 空格，声明／正文为 8 / 12 空格。它是本轮新增 helper 的真实 `indent` **B1**，不能借旧相似括号洗成 D。因后续 Release guard 失败，已停止修改，保留未关闭。
- 早期 Capture 中间笔记的 1811 行不是最终候选；最终实际为 1814 行，以下统一以最终同口径报告为准。

### 2.1 各文件原始计数

以下每格为 `ab11 / e0 / 本地修复后`，用于复算总数，不单独据此判归属。短文件名的完整目录见第 4 节。

| 文件 | SwiftFormat | SwiftLint |
| --- | --- | --- |
| AppController.swift | 4454 / 4559 / 4394 | 83 / 85 / 83 |
| MacSpeechAcousticEchoHost.swift | 1203 / 1208 / 1203 | 37 / 37 / 37 |
| MacSpeechAudioCapture.swift | 169 / 179 / 114 | 15 / 23 / 10 |
| MacSpeechAudioHost.swift | 27 / 28 / 25 | 3 / 3 / 3 |
| MacSpeechAudioOutputHost.swift | 86 / 89 / 80 | 8 / 8 / 8 |
| MacSpeechAudioOutputPlayer.swift | 19 / 19 / 19 | 3 / 3 / 3 |
| RealtimeInterruptionEvidenceTests.swift | 128 / 161 / 128 | 11 / 12 / 11 |
| RealtimeResidentOnlyZeroSelfInterruptTests.swift | 11767 / 11782 / 11767 | 122 / 122 / 122 |
| ConverterTimelineTests.swift | 0 / 57 / 0 | 0 / 7 / 0 |
| MacSpeechAcousticEchoHostTests.swift | 412 / 453 / 412 | 15 / 16 / 15 |
| MacSpeechAudioHostTests.swift | 57 / 68 / 57 | 13 / 14 / 13 |
| FakeMacSpeechAudioOutputPlayer.swift | 30 / 32 / 30 | 2 / 2 / 2 |
| MacSpeechAudioOutputHostTests.swift | 56 / 62 / 56 | 5 / 9 / 5 |

### 2.2 规则变化

仅列三阶段计数有变化的规则；其余规则数量不变，其历史诊断仍保留在最终总数中。完整规则计数及 A/B/C/D 逐条映射在忽略证据目录。

| 工具 | 规则 | ab11 | e0 | 本地 |
| --- | --- | --- | --- | --- |
| format | andOperator | 3 | 4 | 3 |
| format | blankLinesBetweenScopes | 49 | 57 | 49 |
| format | docComments | 0 | 1 | 0 |
| format | elseOnSameLine | 159 | 162 | 145 |
| format | hoistPatternLet | 62 | 64 | 60 |
| format | hoistTry | 11 | 7 | 7 |
| format | indent | 17105 | 17258 | 17025 |
| format | numberFormatting | 187 | 208 | 185 |
| format | redundantParens | 7 | 8 | 7 |
| format | redundantSelf | 5 | 4 | 4 |
| format | spaceAroundOperators | 2 | 10 | 2 |
| format | trailingCommas | 45 | 47 | 45 |
| format | unusedArguments | 14 | 21 | 14 |
| format | wrapArguments | 240 | 256 | 240 |
| format | wrapFunctionBodies | 46 | 67 | 46 |
| format | wrapIfStatementBodies | 51 | 90 | 51 |
| format | wrapMultilineStatementBraces | 358 | 365 | 338 |
| format | wrapPropertyBodies | 41 | 45 | 41 |
| lint | closure_parameter_position | 17 | 15 | 15 |
| lint | control_statement | 4 | 5 | 4 |
| lint | cyclomatic_complexity | 22 | 27 | 22 |
| lint | function_body_length | 141 | 151 | 140 |
| lint | function_parameter_count | 12 | 13 | 12 |
| lint | identifier_name | 26 | 27 | 26 |
| lint | implicit_optional_initialization | 0 | 1 | 0 |
| lint | large_tuple | 6 | 9 | 6 |
| lint | line_length | 46 | 50 | 44 |

## 3. 准确增量矩阵与剩余问题

### 3.1 SwiftFormat B 类：按文件／规则／函数／变更位置

下表为 e0 修复前的 365 项真实新增，按文件和规则合并计数；`scope` 与行号来自 e0 对应 Git 变更和诊断。函数迁移／报告邻接 token 已按上文排除。函数列表包含相应新增代码所属类型 scope；逐条诊断位置保留在 Git 外 CSV / JSON。本地最终仅 R853 的 B1 未关闭，其余本表原 B 诊断已关闭；原 B 关闭不抵销本轮新增 B1。

| 文件 | 规则 | scope | e0 诊断行 | 数 |
| --- | --- | --- | --- | --- |
| AppController.swift | elseOnSameLine | AppController.selectSpeechAudioProcessingMode(_:stopGeneration:) | 3317, 3323 | 2 |
| AppController.swift | hoistPatternLet | AppController | 4534, 5294 | 2 |
| AppController.swift | indent | AppController | 2924–2927, 2929, 2932–2945, 2947–2950, 2965, 4489, 4502–4525, 4533–4539, 4573, 4576, 5041, 5152, 5241, 5244–5270, 5293–5299, 5304–5307, 5316–5319, 5323–5326, 5329–5332, 5357 | 112 |
| AppController.swift | wrapMultilineStatementBraces | AppController.selectSpeechAudioProcessingMode(_:stopGeneration:) | 3317, 3323 | 2 |
| MacSpeechAcousticEchoHost.swift | docComments | MacSpeechAcousticEchoSnapshot | 102 | 1 |
| MacSpeechAcousticEchoHost.swift | wrapIfStatementBodies | MacSpeechAcousticEchoHost.recordUnavailableCaptureObservation(_:hostTimeNanoseconds:) | 1229–1230 | 2 |
| MacSpeechAcousticEchoHost.swift | wrapPropertyBodies | MacSpeechAcousticEchoSnapshot | 103–104 | 2 |
| MacSpeechAudioCapture.swift | blankLinesBetweenScopes | .selectProcessingMode(_:) | 496 | 1 |
| MacSpeechAudioCapture.swift | elseOnSameLine | MacSpeechAudioConverter.convert(_:activityEvidenceKind:acousticSnapshot:contentTimestampNanoseconds:requireContentTime:); MacSpeechFloatMono48kConverter.anchoredInputHostTime(sampleTime:hostTimeNanoseconds:inputFrameCount:); MacSpeechFloatMono48kConverter.convert(_:hostTimeNanoseconds:sampleTime:); MacSpeechFloatMono48kConverter.outputHostTime(sampleCount:); SystemMacSpeechVoiceProcessingEngine.configureIfNeeded(); SystemMacSpeechVoiceProcessingEngine.scheduleOutput(_:completion:); SystemMacSpeechVoiceProcessingEngine.selectProcessingMode(_:); SystemMacSpeechVoiceProcessingEngine.startCapture(generation:frameBuffer:); SystemMacSpeechVoiceProcessingEngine.updateVoiceProcessingSnapshot(engine:requireUnmuted:) | 553, 609, 756, 818, 822, 904, 1013, 1044, 1148, 1248, 1253, 1307 | 12 |
| MacSpeechAudioCapture.swift | indent | MacSpeechAudioConverter.convert(_:activityEvidenceKind:acousticSnapshot:contentTimestampNanoseconds:requireContentTime:); MacSpeechFloatMono48kConverter.anchoredInputHostTime(sampleTime:hostTimeNanoseconds:inputFrameCount:); SystemMacSpeechVoiceProcessingEngine; SystemMacSpeechVoiceProcessingEngine.makeAcousticEchoHost(mode:); SystemMacSpeechVoiceProcessingEngine.processCapture(_:hostTimeNanoseconds:nativeSampleTime:configurationID:generation:frameBuffer:) | 609, 864, 904, 979, 1000–1003, 1005, 1412, 1422, 1430, 1434, 1458, 1462, 1471 | 16 |
| MacSpeechAudioCapture.swift | numberFormatting | MacSpeechAudioConverter.convert(_:activityEvidenceKind:acousticSnapshot:contentTimestampNanoseconds:requireContentTime:); MacSpeechFloatMono48kConverter.convert(_:hostTimeNanoseconds:sampleTime:) | 569, 755 | 2 |
| MacSpeechAudioCapture.swift | redundantParens | SystemMacSpeechVoiceProcessingEngine.updateVoiceProcessingSnapshot(engine:requireUnmuted:) | 1301 | 1 |
| MacSpeechAudioCapture.swift | wrapFunctionBodies | .discardPendingAudioForGenerationTransition(); .voiceProcessingSnapshot() | 497–498 | 2 |
| MacSpeechAudioCapture.swift | wrapIfStatementBodies | MacSpeechAudioConverter.convert(_:activityEvidenceKind:acousticSnapshot:contentTimestampNanoseconds:requireContentTime:); MacSpeechFloatMono48kConverter.anchoredInputHostTime(sampleTime:hostTimeNanoseconds:inputFrameCount:); MacSpeechPCM16Packetizer.append(samples:activityEvidenceKind:acousticSnapshot:contentTimestampNanoseconds:); SystemMacSpeechVoiceProcessingEngine.routeWillRebuild(); SystemMacSpeechVoiceProcessingEngine.startCapture(generation:frameBuffer:); SystemMacSpeechVoiceProcessingEngine.startOutput(); SystemMacSpeechVoiceProcessingEngine.tearDownGraph(outputAlreadyStopped:) | 375–376, 558–559, 889–890, 1054–1055, 1173–1174, 1346–1348, 1369–1370 | 15 |
| MacSpeechAudioCapture.swift | wrapMultilineStatementBraces | MacSpeechAudioConverter.convert(_:activityEvidenceKind:acousticSnapshot:contentTimestampNanoseconds:requireContentTime:); MacSpeechFloatMono48kConverter.anchoredInputHostTime(sampleTime:hostTimeNanoseconds:inputFrameCount:); MacSpeechFloatMono48kConverter.convert(_:hostTimeNanoseconds:sampleTime:); MacSpeechFloatMono48kConverter.outputHostTime(sampleCount:); SystemMacSpeechVoiceProcessingEngine; SystemMacSpeechVoiceProcessingEngine.configureIfNeeded(); SystemMacSpeechVoiceProcessingEngine.scheduleOutput(_:completion:); SystemMacSpeechVoiceProcessingEngine.selectProcessingMode(_:); SystemMacSpeechVoiceProcessingEngine.startCapture(generation:frameBuffer:); SystemMacSpeechVoiceProcessingEngine.updateVoiceProcessingSnapshot(engine:requireUnmuted:) | 553, 609, 756, 812, 818, 822, 868, 904, 1013, 1044, 1148, 1248, 1253, 1301, 1307, 1430 | 16 |
| MacSpeechAudioHost.swift | elseOnSameLine | MacSpeechAudioHost.selectProcessingMode(_:) | 142 | 1 |
| MacSpeechAudioHost.swift | wrapMultilineStatementBraces | MacSpeechAudioHost.currentVoiceProcessingSnapshot(); MacSpeechAudioHost.selectProcessingMode(_:) | 142, 227 | 2 |
| MacSpeechAudioOutputHost.swift | andOperator | MacSpeechAudioOutputHost.handleDeviceRouteChange() | 698 | 1 |
| MacSpeechAudioOutputHost.swift | elseOnSameLine | MacSpeechAudioOutputHost.handleDeviceRouteChange() | 692 | 1 |
| MacSpeechAudioOutputHost.swift | indent | MacSpeechAudioOutputHost.handleDeviceRouteChange(); MacSpeechAudioOutputHost.init(player:deviceMonitor:configuration:sleepForConsumerTimeout:) | 155–157, 690–692 | 6 |
| MacSpeechAudioOutputHost.swift | wrapMultilineStatementBraces | MacSpeechAudioOutputHost.handleDeviceRouteChange() | 692 | 1 |
| RealtimeInterruptionEvidenceTests.swift | blankLinesBetweenScopes | T32CascadedASRProvider; T32CascadedASRProvider.cancel(generation:); T32CascadedASRProvider.receive(generation:); T32CascadedASRProvider.send(_:); T32CascadedTTSProvider.receive(generation:); T32CascadedTTSProvider.start(request:); T32CascadedTTSProvider.startCount() | 33, 39, 44, 48, 65, 69, 72 | 7 |
| RealtimeInterruptionEvidenceTests.swift | indent | RealtimeInterruptionEvidenceTests.testStopDuringCapturePreparation(fixture:) | 1414–1415 | 2 |
| RealtimeInterruptionEvidenceTests.swift | numberFormatting | T32CascadedTTSProvider.start(request:) | 61 | 1 |
| RealtimeInterruptionEvidenceTests.swift | trailingCommas | T32CascadedTTSProvider.start(request:); T32CascadedTextTransport.data(for:) | 15, 63 | 2 |
| RealtimeInterruptionEvidenceTests.swift | unusedArguments | T32CascadedASRProvider.cancel(generation:); T32CascadedASRProvider.close(generation:); T32CascadedASRProvider.start(request:); T32CascadedCredentialReader.readCredential(for:); T32CascadedTTSProvider.cancel(generation:); T32CascadedTTSProvider.close(generation:); T32CascadedTTSProvider.receive(generation:) | 8, 27, 40, 45, 66, 70–71 | 7 |
| RealtimeInterruptionEvidenceTests.swift | wrapArguments | RealtimeInterruptionEvidenceTests.testStopDuringCapturePreparation(fixture:) | 1415 | 1 |
| RealtimeInterruptionEvidenceTests.swift | wrapFunctionBodies | R855MicrophoneAuthorizationProvider; R855MicrophoneAuthorizationProvider.isQueryPending(); T32CascadedASRProvider; T32CascadedASRProvider.send(_:); T32CascadedASRProvider.sources(); T32CascadedASRProvider.start(request:); T32CascadedASRProvider.startCount(); T32CascadedCredentialReader; T32CascadedCredentialReader.readCredential(for:); T32CascadedTTSProvider; T32CascadedTTSProvider.cancel(generation:); T32CascadedTTSProvider.close(generation:); T32CascadedTTSProvider.startCount() | 8–9, 27–28, 46–48, 70–73, 118–119 | 13 |
| RealtimeResidentOnlyZeroSelfInterruptTests.swift | indent | <file> | 328, 343–351, 353–355, 11481–11482 | 15 |
| ConverterTimelineTests.swift | indent | ConverterTimelineTests.buffer(_:rate:); ConverterTimelineTests.clockBoundary(rate:scenario:); ConverterTimelineTests.reference(_:from:to:); ConverterTimelineTests.streaming(rate:) | 47, 66, 79, 100, 110, 127–130, 135, 138 | 11 |
| ConverterTimelineTests.swift | numberFormatting | ConverterTimelineTests.capacity(); ConverterTimelineTests.delivery(rate:); ConverterTimelineTests.gatedSpanCompatibility(); ConverterTimelineTests.invalidTimestamp(); ConverterTimelineTests.main(); ConverterTimelineTests.packetTimeAndReset(); ConverterTimelineTests.processingState(); ConverterTimelineTests.reference(_:from:to:); ConverterTimelineTests.streaming(rate:) | 17, 66, 98, 105, 148, 179–180, 193–194, 210–211, 217, 229, 247–248, 251, 258, 260 | 18 |
| ConverterTimelineTests.swift | spaceAroundOperators | ConverterTimelineTests.capacity(); ConverterTimelineTests.clockBoundary(rate:scenario:); ConverterTimelineTests.delivery(rate:); ConverterTimelineTests.gatedSpanCompatibility(); ConverterTimelineTests.processingState(); ConverterTimelineTests.streaming(rate:); ConverterTimelineTests.waveform(_:) | 58, 92, 122, 156, 158, 215, 230, 267 | 8 |
| ConverterTimelineTests.swift | wrapArguments | ConverterTimelineTests.delivery(rate:); ConverterTimelineTests.processingState(); ConverterTimelineTests.streaming(rate:) | 100, 159, 235 | 3 |
| ConverterTimelineTests.swift | wrapFunctionBodies | ReferenceInput; ReferenceInput.init(_:) | 6–7 | 2 |
| ConverterTimelineTests.swift | wrapIfStatementBodies | ConverterTimelineTests.clockBoundary(rate:scenario:); ConverterTimelineTests.expect(_:_:); ConverterTimelineTests.gatedSpanCompatibility() | 37–38, 126–130, 133–135, 220–223 | 14 |
| ConverterTimelineTests.swift | wrapMultilineStatementBraces | ConverterTimelineTests.main() | 20 | 1 |
| MacSpeechAcousticEchoHostTests.swift | indent | MacSpeechAcousticEchoHostTests.testAppleFullScaleObservation(); MacSpeechAcousticEchoHostTests.testAppleModeDoesNotUseWebRTC(); MacSpeechAcousticEchoHostTests.testAppleRouteRebuildAndFailureStayClosed() | 1934–1935, 1940–1942, 1944–1946, 1948–1951, 1953–1955, 1974–1975, 1995–1996, 1999–2000, 2004–2005, 2010–2011, 2040–2041, 2055–2056 | 29 |
| MacSpeechAcousticEchoHostTests.swift | wrapArguments | MacSpeechAcousticEchoHostTests.testAppleFullScaleObservation(); MacSpeechAcousticEchoHostTests.testAppleModeDoesNotUseWebRTC(); MacSpeechAcousticEchoHostTests.testAppleRouteRebuildAndFailureStayClosed() | 1935, 1942, 1946, 1951, 1955, 1975, 1996, 2000, 2005, 2011, 2041, 2056 | 12 |
| MacSpeechAudioHostTests.swift | numberFormatting | MacSpeechAudioHostTests.waitForQuery(_:number:) | 685 | 1 |
| MacSpeechAudioHostTests.swift | wrapFunctionBodies | FakeMicrophoneAuthorizationProvider; FakeMicrophoneAuthorizationProvider.holdNextQuery(); FakeMicrophoneAuthorizationProvider.isQueryPending(_:) | 49–52 | 4 |
| MacSpeechAudioHostTests.swift | wrapIfStatementBodies | FakeMacSpeechAudioCapture.selectProcessingMode(_:); FakeMicrophoneAuthorizationProvider.releaseQuery(_:fails:); MacSpeechAudioHostTests.waitForQuery(_:number:) | 54–55, 93–94, 686–687 | 6 |
| FakeMacSpeechAudioOutputPlayer.swift | wrapPropertyBodies | FakeMacSpeechConsumerWatchdogSleeper | 6–7 | 2 |
| MacSpeechAudioOutputHostTests.swift | numberFormatting | MacSpeechAudioOutputHostTests.testInputRouteChangeInvalidatesOutputAndCanRecover() | 1109 | 1 |
| MacSpeechAudioOutputHostTests.swift | wrapIfStatementBodies | MacSpeechAudioOutputHostTests.testInputRouteChangeInvalidatesOutputAndCanRecover() | 1106–1107 | 2 |
| MacSpeechAudioOutputHostTests.swift | wrapMultilineStatementBraces | MacSpeechAudioOutputHostTests.testInputRouteChangeInvalidatesOutputAndCanRecover(); MacSpeechAudioOutputHostTests.testRetiredWatchdogCannotFailSameGenerationPlayback(); MacSpeechAudioOutputHostTests.testSameDeviceAvailabilityChangesInvalidateOutputOnce() | 733, 1092, 1166 | 3 |

### 3.2 SwiftLint B 类：新增函数／规则

以下 28 项（按相同函数／规则合并）在最终候选中均不再报新增 B 警告。新增 Converter 测试按全文件计入，未排除其中任何规则。

| 文件 | 规则 / scope | e0 诊断行 | 数 | 本地残余 B |
| --- | --- | --- | --- | --- |
| AppController.swift | cyclomatic_complexity / startFormalSpeechRoute | 4473 | 1 | 0 |
| AppController.swift | cyclomatic_complexity / startNativeSpeechInputBridge | 5226 | 1 | 0 |
| MacSpeechAudioCapture.swift | control_statement / SystemMacSpeechVoiceProcessingEngine.updateVoiceProcessingSnapshot(engine:requireUnmuted:) | 1299 | 1 | 0 |
| MacSpeechAudioCapture.swift | cyclomatic_complexity / anchoredInputHostTime | 848 | 1 | 0 |
| MacSpeechAudioCapture.swift | cyclomatic_complexity / convert | 543 | 1 | 0 |
| MacSpeechAudioCapture.swift | function_body_length / anchoredInputHostTime | 848 | 1 | 0 |
| MacSpeechAudioCapture.swift | function_body_length / convert | 543, 746 | 2 | 0 |
| MacSpeechAudioCapture.swift | function_parameter_count / processCapture | 1440 | 1 | 0 |
| MacSpeechAudioCapture.swift | large_tuple / SystemMacSpeechVoiceProcessingEngine.processCapture(_:hostTimeNanoseconds:nativeSampleTime:configurationID:generation:frameBuffer:) | 1450 | 1 | 0 |
| MacSpeechAudioCapture.swift | large_tuple / SystemMacSpeechVoiceProcessingEngine.startCapture(generation:frameBuffer:) | 1038 | 1 | 0 |
| MacSpeechAudioCapture.swift | large_tuple / SystemMacSpeechVoiceProcessingEngine.tearDownGraph(outputAlreadyStopped:) | 1326 | 1 | 0 |
| MacSpeechAudioCapture.swift | line_length / SystemMacSpeechVoiceProcessingEngine.processCapture(_:hostTimeNanoseconds:nativeSampleTime:configurationID:generation:frameBuffer:) | 1450, 1481 | 2 | 0 |
| RealtimeInterruptionEvidenceTests.swift | function_body_length / testConsecutiveCascadedTurnsReleaseBackend | 1322 | 1 | 0 |
| ConverterTimelineTests.swift | cyclomatic_complexity / clockBoundary | 114 | 1 | 0 |
| ConverterTimelineTests.swift | identifier_name / ConverterTimelineTests.reference(_:from:to:) | 61 | 1 | 0 |
| ConverterTimelineTests.swift | implicit_optional_initialization / ConverterTimelineTests.clockBoundary(rate:scenario:) | 124 | 1 | 0 |
| ConverterTimelineTests.swift | line_length / ConverterTimelineTests.packetTimeAndReset() | 201, 204 | 2 | 0 |
| ConverterTimelineTests.swift | line_length / ConverterTimelineTests.processingState() | 240 | 1 | 0 |
| ConverterTimelineTests.swift | line_length / ConverterTimelineTests.streaming(rate:) | 107 | 1 | 0 |
| MacSpeechAcousticEchoHostTests.swift | function_body_length / testAppleModeDoesNotUseWebRTC | 1904 | 1 | 0 |
| MacSpeechAudioHostTests.swift | function_body_length / testPendingPreparationRejectsSelectionAndCannotResumeAfterRetirement | 582 | 1 | 0 |
| MacSpeechAudioOutputHostTests.swift | function_body_length / testInputRouteChangeInvalidatesOutputAndCanRecover | 1091 | 1 | 0 |
| MacSpeechAudioOutputHostTests.swift | function_body_length / testRetiredWatchdogCannotFailSameGenerationPlayback | 732 | 1 | 0 |
| MacSpeechAudioOutputHostTests.swift | function_body_length / testSameDeviceAvailabilityChangesInvalidateOutputOnce | 1165 | 1 | 0 |
| MacSpeechAudioOutputHostTests.swift | function_body_length / testWatchdogInvalidatedByClearAndClose | 791 | 1 | 0 |

### 3.3 C 类：历史阈值已超标且继续增长

下表覆盖修复前全部 32 项 C，按同一文件／规则／函数身份关联三阶段测值。修复后仍超出基线的 24 项保留 C；不是单纯行号移动。其中 21 项是文件／类型聚合大小增长、3 项为函数长度增长。测值使用工具的规则口径（函数／类型排除空行和注释，文件按该规则原口径），不与物理文件总行数混算。

| 文件 | 规则 / scope | ab11 | e0 | 本地 | 归属 |
| --- | --- | --- | --- | --- | --- |
| AppController.swift | cyclomatic_complexity / startRealtimeResidentBrainRoute | 23 | 26 | 18 | 未恶化／改善 |
| AppController.swift | file_length / `<file>` | 6943 | 7086 | 7140 | C OPEN |
| AppController.swift | function_body_length / consumeFormalSpeechPlaybackEvent | 76 | 77 | 77 | C OPEN |
| AppController.swift | function_body_length / startFormalSpeechRoute | 99 | 131 | 90 | 未恶化／改善 |
| AppController.swift | function_body_length / startNativeSpeechInputBridge | 116 | 166 | 111 | 未恶化／改善 |
| AppController.swift | function_body_length / startRealtimeResidentBrainRoute | 209 | 224 | 177 | 未恶化／改善 |
| AppController.swift | type_body_length / AppController | 6313 | 6455 | 6502 | C OPEN |
| MacSpeechAcousticEchoHost.swift | file_length / `<file>` | 3390 | 3445 | 3470 | C OPEN |
| MacSpeechAcousticEchoHost.swift | function_body_length / makeSnapshot | 90 | 92 | 92 | C OPEN |
| MacSpeechAcousticEchoHost.swift | function_body_length / processCaptureSpans | 111 | 120 | 114 | C OPEN |
| MacSpeechAcousticEchoHost.swift | type_body_length / MacSpeechAcousticEchoHost | 2569 | 2618 | 2638 | C OPEN |
| MacSpeechAudioCapture.swift | file_length / `<file>` | 1404 | 1691 | 1814 | C OPEN |
| MacSpeechAudioCapture.swift | function_body_length / startCapture | 52 | 57 | 不再报该阈值警告 | 未恶化／改善 |
| MacSpeechAudioCapture.swift | type_body_length / SystemMacSpeechVoiceProcessingEngine | 630 | 641 | 690 | C OPEN |
| MacSpeechAudioHost.swift | file_length / `<file>` | 498 | 520 | 520 | C OPEN |
| MacSpeechAudioHost.swift | type_body_length / MacSpeechAudioHost | 370 | 390 | 390 | C OPEN |
| MacSpeechAudioOutputHost.swift | file_length / `<file>` | 811 | 838 | 839 | C OPEN |
| MacSpeechAudioOutputHost.swift | type_body_length / MacSpeechAudioOutputHost | 670 | 695 | 696 | C OPEN |
| MacSpeechAudioOutputPlayer.swift | file_length / `<file>` | 461 | 465 | 465 | C OPEN |
| RealtimeInterruptionEvidenceTests.swift | file_length / `<file>` | 2396 | 2612 | 2659 | C OPEN |
| RealtimeInterruptionEvidenceTests.swift | function_body_length / main | 679 | 681 | 679 | 未恶化／改善 |
| RealtimeInterruptionEvidenceTests.swift | function_body_length / makePermissionControllerStack | 68 | 69 | 63 | 未恶化／改善 |
| RealtimeInterruptionEvidenceTests.swift | type_body_length / RealtimeInterruptionEvidenceTests | 1829 | 1944 | 1965 | C OPEN |
| RealtimeResidentOnlyZeroSelfInterruptTests.swift | file_length / `<file>` | 12203 | 12220 | 12226 | C OPEN |
| RealtimeResidentOnlyZeroSelfInterruptTests.swift | function_body_length / makeR853QwenControllerStack | 125 | 127 | 125 | 未恶化／改善 |
| RealtimeResidentOnlyZeroSelfInterruptTests.swift | type_body_length / RealtimeResidentOnlyZeroSelfInterruptTests | 11271 | 11273 | 11278 | C OPEN |
| MacSpeechAcousticEchoHostTests.swift | file_length / `<file>` | 2057 | 2208 | 2219 | C OPEN |
| MacSpeechAcousticEchoHostTests.swift | type_body_length / MacSpeechAcousticEchoHostTests | 1842 | 1991 | 2000 | C OPEN |
| MacSpeechAudioHostTests.swift | file_length / `<file>` | 711 | 963 | 982 | C OPEN |
| MacSpeechAudioHostTests.swift | type_body_length / MacSpeechAudioHostTests | 492 | 694 | 703 | C OPEN |
| MacSpeechAudioOutputHostTests.swift | file_length / `<file>` | 1054 | 1344 | 1379 | C OPEN |
| MacSpeechAudioOutputHostTests.swift | type_body_length / MacSpeechAudioOutputHostTests | 992 | 1275 | 1306 | C OPEN |

剩余 3 个函数 C：`consumeFormalSpeechPlaybackEvent` 76→77→77，`processCaptureSpans` 111→120→114，`makeSnapshot` 90→92→92。它们未在本轮完全回到基线。没有用空洞 helper、压缩可读代码或新 Owner 来抹平数字。

重要函数改善：Realtime start 函数长度 209→224→177、复杂度 23→26→18；Formal start 长度 99→131→90、复杂度无诊断→16→无诊断；Native start 长度 116→166→111、复杂度无诊断→16→无诊断。仍有既存阈值警告，不声称这些函数全部 lint PASS。

**工程停止边界：** 继续消除所有聚合 C 将涉及旧大文件／类型的更广重组；本轮没有据此扩大任务，也不把必要 Apple 分支或新增测试量解释成“不计 C”。本轮本地 helper 抽取本身亦增加聚合行数，这是尚未收口的维护成本。Release guard 失败后不再修补 B1 或继续拆分。

## 4. 实际修复范围与语义保护

生产路径前缀均为 `apps/macos/Aftelle/`：

| 文件 | 本轮局部内容 | 关键约束 |
| --- | --- | --- |
| MacSpeechAudioCapture.swift | Converter / capture lifecycle 局部 helper；临时 immutable context 替换超大 tuple；新增区间格式／命名 | 原锁内顺序、PCM 内容时间、cursor、generation / callback fence；原 AVAudioTime 直接传递，不以到达时间替代内容时间 |
| AppController.swift | Realtime / Formal / Native 启动中的后端、权限、准备阶段局部 helper；新增段格式 | 原 MainActor、await 后 attempt / shutdown / stop fence、错误／取消／close 顺序；无新增 Task |
| MacSpeechAcousticEchoHost.swift | 新 Apple / fallback 分支同步 helper；新增快照属性格式 | 原处理队列／锁、真实 backend 及 fail-closed；不叠加 AEC |
| MacSpeechAudioHost.swift | 新增 backend 相关局部格式 | 原 actor 和 route 状态 owner |
| MacSpeechAudioOutputHost.swift | 新增生命周期段局部格式 | 原 Playback owner、prepared / queued / in-flight 拒绝条件 |
| MacSpeechAudioOutputPlayer.swift | 只读，无修改 | e0 原字节保留；原 T3.2-A file_length C 仍计入 |

Capture 的三个临时值对象仅封装调用当次上下文，不保存新生命周期状态，不增加锁、Actor、Engine、Controller 或 Manager。converter 输出 Float 指针跨 helper 使用的 owner 由 `withExtendedLifetime(outputBuffer)` 保持有效；未新增重采样或 PCM 复制。原执行顺序、错误类型／传播、锁范围、原始内容时间、route / generation reset 不改。静态交叉审核未发现新的运行时 CRITICAL / MAJOR，但不替代未完成的 Release 构建与实机验证。

测试文件均保留原断言、用例注册顺序及计数；只对新增／被本轮扩展的长函数做 phase helper，及局部命名／格式修正：

| 完整测试路径 | 内容 | 静态 expect 调用点（修复前→后） |
| --- | --- | --- |
| tools/speech_aec_host_tests/ConverterTimelineTests.swift | clock timestamp helper、命名、格式；全文件检查 | 33→33 |
| tools/speech_aec_host_tests/MacSpeechAcousticEchoHostTests.swift | Apple 测试 phase helper／格式 | 275→275 |
| tools/speech_audio_host_tests/MacSpeechAudioHostTests.swift | backend / busy lifecycle 测试 phase helper | 134→134 |
| tools/speech_audio_output_tests/FakeMacSpeechAudioOutputPlayer.swift | 新增 fake 局部格式 | 0→0 |
| tools/speech_audio_output_tests/MacSpeechAudioOutputHostTests.swift | 新 backend 生命周期测试 phase helper | 207→207 |
| tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift | 共用 fixture helper（两个消费者），启动准备测试 phase helper | 112→112 |
| tools/realtime_resident_only_zero_self_interrupt_tests/RealtimeResidentOnlyZeroSelfInterruptTests.swift | R853 既有 100ms 等待和新增 backend 断言移入 helper | 503→503 |

`expect` 源码调用点不是运行检查总数；异步／循环运行数以第 5 节真实日志为准，没有通过减少调用来获得 PASS。

两个受影响脚本的最小同步（在验证前完成）：

- `tools/speech_audio_host_tests/check.sh`：保留 Realtime 后端选择断言，启动函数调用 helper、helper 内选择 `.appleVoiceProcessing` 均需存在；不再错误要求选择表达式必须直接在旧函数体。
- `tools/speech_aec_host_tests/check.sh`：原 capture 回调改传原 `AVAudioTime at: when` 后，检查实际 capture 原时间字段提取及两处 host-time 换算，保留 render / sample / 时序要求。

`tools/realtime_release_route_guard/check.sh` **没有修改**；其后真实失败触发停止。不能把前两个已同步脚本的 PASS 外推到 Release guard。

## 5. 实际离线回归与构建

仅调用预先审查的 Fake / fixture 入口，无真实 Provider、麦克风、扬声器或音频实验。原 fixture 只用于已批准离线加载，未修改、导出或打印内容。沿用既有脚本中的临时隔离路径；没有把临时 HOME 称为系统 Keychain 隔离，也没有读取 secret。源码允许的既有无密钥状态检查不构成真实 Provider 实验。raw 输出保留在 Git 外，不逐字复制潜在本机路径。

以下是本轮实际命令，未用上一节点的 PASS 填充：

| 实际命令 / 项目 | exit | 结果 | cases / checks / 限制 |
| --- | --- | --- | --- |
| bash tools/speech_audio_host_tests/check.sh | 0 | PASS | 178 checks；未独立输出 cases |
| bash tools/speech_audio_output_tests/check.sh | 0 | PASS | 238 checks；未独立输出 cases |
| bash tools/speech_aec_host_tests/check.sh | 0 | PASS | AEC 1165 checks；Converter 25 cases / 221 checks；合成 replay 自检 |
| bash tools/mac_speech_realtime_brain_input_tests/check.sh | 0 | PASS | 32 cases / 210 checks |
| bash tools/realtime_interruption_evidence_tests/check.sh | 0 | PASS | 28 cases / 239 checks |
| bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r823-full | 0 | PASS | 12 cases / 126 checks |
| bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r853-qwen-suite | 0 | PASS | 15 cases / 223 checks＝10/120＋1/59＋4/44 |
| bash tools/realtime_confirmed_interruption_tests/check.sh | 0 | PASS | 1 case / 62 checks |
| bash tools/realtime_barge_in_latency_stale_audio_tests/check.sh | 0 | PASS | 1 case / 68 checks |
| bash tools/realtime_release_route_guard/check.sh | 1 | FAIL | 首个静态断言失败；没有完整 guard PASS |
| build_debug | — | NOT_RUN_AFTER_FAILURE | 无执行，无 exit code |
| build_release | — | NOT_RUN_AFTER_FAILURE | 无执行，无 exit code |

上述运行套件与 e0 节点对应计数一致，无删断言、降门槛或重复跑到绿灯。R853 的 Qwen 是离线 Fake Wire / fixture，不是真实 Qwen overlap。`live_replay=PASS` 是既有脚本合成回放标签，不是真实音频回放。

### Release guard 第一失败与停止

```text
realtime_release_route_guard_count=start_permission_helper expected=1 actual=0
```

`tools/realtime_release_route_guard/check.sh:267–268` 仅截取 `startRealtimeResidentBrainRoute()` 函数体，要求 `ensureRealtimeMicrophoneAuthorization()` 直接出现恰好一次。抽取 helper 后启动函数改调用 `prepareRealtimeSpeechAudioBackend()`，实际权限调用在后者；旧文本断言得到 0。

只读源码／独立复核确认权限调用及 attempt / shutdown / stop-generation fence 仍在 Release 可见源码，未证实权限绕过。**这是已确认的静态检查断言失败，不等于已确认的运行时退化，也不等于 Release 安全已证实。** 同脚本 282–318 行还要求权限→fence→capture prepare→Provider 的顺序及错误分支位置；不能只把计数改绿或删除这些要求。

按照用户“重构引起功能或安全回归失败即停止”的保守边界，失败后不再改源码／测试／guard、不重跑；排队中的 Debug 和未签名 Release 构建均 `NOT_RUN_AFTER_FAILURE`。之前 T3.2-A 的 Debug / Release PASS 仅属于 e0，不能替代本地重构候选。局部 Swift parse 的 exit 0 亦不替代构建。

未重复运行未受影响的完整 Qwen Adapter / Session-Memory 历史套件，也未将其登记为当前 PASS。真实物理 AEC / NS / AGC、音质、路由设备、削波、人类双讲、正式 Human Gate 全部 NOT_RUN / NOT_AUTHORIZED。

## 6. 五维审核与实际来源

本轮采用三个 Codex 协作子代理加主代理；不是三名外部人工审核者，也不宣称盲审。代码作者只对自己修改部分做 SELF_REVIEW，交叉审查范围分别记录：

- `/root/lint_capture`：作者仅 Capture；另独立只读审查 AppController / AEC Host / Audio Host / Output Host 的执行顺序、Actor / 锁 / await、权限 fence、Cascaded 隔离及实际 Release guard 失败定位。未修改对方文件。
- `/root/lint_hosts`：作者为上述四个 Host / Controller；另独立只读审查 Capture 锁、AVAudioTime、buffer owner、converter 连续性及七个测试的用例／断言保存，并复核最终逐条分类和原始工具证据；发现 R853 B1、修正 AEC B/C 误分类及 Capture 中间测值。未修改对方文件。
- `/root/lint_tests`：作者七个测试；本文件涉及其自身修改时明确按 SELF_REVIEW，不冒充独立结论。
- 主代理 `/root`：工具／Git／全量归因／脚本修改／报告与状态审计为 SELF_REVIEW；原始工具运行、归因矩阵由 `/root/lint_hosts` 交叉复核。未能启动的其他 reviewer 不计入审核来源。

每名作者负责不同文件，没有多个 AI 同时群改一个 bug；所有独立审核均只读。

| 维度 | 结论 | 范围 / 依据 / 限制 |
| --- | --- | --- |
| TECHNICAL_REVIEW | REWORK | 交叉源码审核与运行套件未发现新 CRITICAL / MAJOR 运行语义缺陷；Release guard FAIL、Debug / Release 未执行，不能给技术收口 PASS |
| ENGINEERING_REVIEW | REWORK | B1 / C24 未关闭；两严格工具 FAIL；没有全库格式化或新状态 Owner；聚合维护成本未回到基线 |
| EVIDENCE_REVIEW | PASS（证据呈现） | 原始工具计数、分类、命令 exit、第一失败及 NOT_RUN 明列；工作笔记误分类已更正；不把 mock / 历史 PASS 当本候选验收 |
| CONSISTENCY_REVIEW | REWORK | 阶段／授权／Qwen / SQ-M1 边界保持；但 helper 抽取与现有 Release guard 的检查合同未闭合，不建议节点批准 |
| Stage7 Forbidden Checklist | PASS（范围／红线） | 六条红线及当前批准的 Realtime / Cascaded ownership 均保持；不等于 lint、Release 或 Human Gate PASS |

EVIDENCE 的 PASS 仅代表报告忠实记录，不消除实际检查失败。最终工程结论 REWORK，主控没有 APPROVED；本轮不请求自动延续旧例外。

## 7. 问题登记

| ID / 级别 | 状态 | 事实与后果 | 后续边界 |
| --- | --- | --- | --- |
| CRITICAL | 0 已确认项 | 交叉源码与已运行离线结果未确认 CRITICAL；Release / 实机仍未验证 | 不能由 0 推断所有安全条件已证实 |
| L-M1 / MAJOR | OPEN | C24 未回到 ab11 基线，含 21 聚合与 3 函数增长；严格工具仍 FAIL，本轮增量归零目标未达成 | 先由主控决定最小后续范围；不得为长度拆巨型历史文件或虚报历史无恶化 |
| L-M2 / MAJOR | OPEN | Release route guard exit 1；后续构建 NOT_RUN，权限→fence→prepare→Provider 检查合同尚未覆盖新 helper 调用链 | 若另行授权修复 guard，必须保留等价 Release 调用链／错误分支／顺序负控，再执行受影响验证；本轮失败后不继续 |
| L-m1 / MINOR | OPEN | R853 新 helper 第 11534 行 indent B1，真实新增，停止后未修 | 后续明确授权范围内局部改正并验证；不能归 D 或凭旧豁免提交 |
| L-m2 / MINOR | CLOSED（报告纠正） | AEC 新增长测试长度误列 C、Capture 中间 1811 行混作最终值 | 最终原始证据／矩阵已分别修正 B 和 1814；保留历史工作笔记不改原失败 |
| SQ-M1 / 历史安全问题 | OPEN（非本轮） | Apple PCM 与既有声学活动／资格接口的安全兼容未验证 | 本轮 lint 不关闭，不新增 Gate、不硬编码 sourceAttributionConfirmed=true |

本轮新增审核登记：CRITICAL 0；MAJOR 2 OPEN；MINOR 1 OPEN、1 CLOSED（证据纠正归为一条）。SQ-M1 单独列历史 OPEN，不将其冒充本轮已修复或再次验收。

## 8. 工程收口建议与后续工作

**NOT_RECOMMENDED_FOR_ENGINEERING_CLOSE。** 保留当前本地修改与全部失败；不 commit / push、不强推、不覆盖其他 worktree。全局 strict lint 仍失败，且增量目标和 Release 验证都未完成。旧 e0 单次 lint 豁免不覆盖本轮；不得自动给予新提交豁免。

最小后续决策仅供主控另行审议：先明确 helper 调用链 Release guard 的等价验证方案，及是否继续本轮局部重构／回退受影响抽取；随后在限定授权下处理 B1 与可局部消除的函数 C。聚合 C 需要明确保留债务或另立范围，不能通过本轮全库拆分解决。任何后续功能／安全失败仍立即停止；在所有适用强制检查通过前，本报告不能授权提交。

保持 [README v2](README.md) 状态：

```text
T3.2-A = REVIEW_PENDING
T3.2-A-L = LOCAL_PARTIAL / STOPPED
ENGINEERING = REWORK
T3.2-A Device Validation = NOT_AUTHORIZED
T3.2-B = NOT_AUTHORIZED
T3.3–T3.6 = NOT_STARTED
SQ-M1 = OPEN
Qwen Strict Overlap = 0/3
Formal Test3 = BLOCKED
Test3.execution_authorized = false
```

没有启动任何真实麦克风／扬声器／Provider 或下个节点。测试中的机械 PCM 与 Fake 输出不能证明 Apple 真实 AEC / NS / AGC 声学验收。

## 9. Stage7 Forbidden Checklist

任务前／后结论：**PASS（范围／红线）**。工程和 Release 检查失败另列，未用此 PASS 覆盖。

| 六条红线 | 本轮证据 | 结论 |
| --- | --- | --- |
| 1 大脑不碰平台 | 无 brain / RuntimeCore 修改，平台代码留在原 Host | PASS |
| 2 Store 带版本 | 无 Store / schema 修改 | PASS |
| 3 三层不黏连 | 未改 Runtime 授权、Qwen Adapter、Provider cancel / clear owner；Host 仅原局部函数抽取 | PASS |
| 4 DR 只读 + revision | 无 DR / fixture / revision 修改、无 DR 入 Git | PASS |
| 5 逻辑／画法分层 | 无 Metal / 粒子 / 画法改动 | PASS |
| 6 交互按意图 | 无坐标驱动逻辑或交互路由新增 | PASS |

- A Stage：仅 macOS Stage7 原节点，没有新平台 target / Stage8。
- B / C Runtime / Host：唯一 Engine、Playback、Activity / Runtime owner 保留；无 Controller / Manager / State Owner 新增。Cascaded 原 AEC3 路线及 PCM 来源保持；RuntimeCore 最终授权、exactly-once、generation / stale fence 未改。
- D DR / API：无 schema、fixture、公开 Runtime API 变化；没有状态写回 DR。
- E Provider / Secret：没有真实 Provider 请求、secret 读取／输出、新 Keychain 实现或 UI 直连；本报告无密钥／私人路径／DR 摘要。
- F Memory / Trace：未改 Session / Memory / Trace owner 和持久化规则。
- G Scheduler：无新调度／后台任务／多居民／跨 App 行动。
- H UI / Rendering：没有新 UI／渲染能力、always-on、声纹或未经授权设备活动。Realtime 依用户已批准 T3.1-R2 / T3.2-A 范围，不能以旧 Checklist 的“未提前实现”文字否定已批准路线；未继续扩展能力。
- 是否改代码：是，12 Swift + 2 直接相关脚本；完整列表见第 4 节。是否改 Runtime API / DR schema / target / Stage8：均否。
- 是否需要停止：**是**，Release guard 失败及增量工程未收口；停止原因是用户本轮明确边界和代码规范提交门槛，非 Stage7 红线违规。没有新提交授权例外。

## 10. 最终本地交付检查

最终只读核验已完成（命令结果与比较记录保留在 Git 外 `final-local-checks.json`）：

| 核验项 | 实际结果 |
| --- | --- |
| Clean HEAD / upstream / 实时远端 | 全部 `e0b4f686d8b872ffac4fb9abfa9dadb7f0377e9a`；实时 `git ls-remote` exit 0 |
| 本轮新 commit / push | 均无；没有新 40 位提交 SHA |
| 改动范围 | 12 Swift + 2 直接相关脚本 + 3 文档，共 17 文件；没有白名单外改动 |
| staging area | 空；未执行 staging 或提交 |
| 验证前后源码身份 | 13 Swift + 2 脚本全部原字节一致，验证停止后未补代码 |
| `git diff --check` | exit 0；仅 whitespace diff 检查，不是工具 lint PASS |
| 文档相对链接 | 本报告及 README 所有本地链接目标存在 |
| 私人资产／密钥 | 改动与未跟踪交付无 DR / PCM / WAV / raw log / key 文件；新增文本无私人绝对路径或密钥字面值候选 |
| ACE3 / VP 研究 worktree | HEAD、工作区 diff 与 status 的任务前后指纹均一致；没有写入原件 |
| 历史报告／规则 | AGENTS、Test2 / T3.0-F / T3.2-A 历史报告、旧合同、研究报告与 lint 配置未改 |

本报告与 README / DEVLOG 的最后修订仅补证据来源、只读核验和状态；未再次执行运行测试、构建或修改源码。两名交叉 reviewer 已分别确认其实际范围内的最终事实；工具计数与完整分类由 `/root/lint_hosts` 复算，不把自身作者复审写成独立审核。完成后停止。
