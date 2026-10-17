# T3.2-A-D2-R3 — Real Acoustic A/B/C Retest

日期：2026-10-17（Asia/Shanghai）。状态：`REVIEW_PENDING`。**A=FAIL；B/C=NOT_RUN**。A 的控制链与已观测内容时间轴通过，但用户确认导出录音仍能听到居民语音，因此停止后续设备实验。T3.2-A 不具备实机收口条件。本轮没有生产或测试代码修改、参数调整、设备重试或 Provider 调用。

## 1. 基线、范围与运行前检查

- Repository：`JerryYork3516/Eterna_Aftelle`；branch：`Test3-AppleVP-Clean`；起点 HEAD/upstream/实时远端均为 `17336f2cc914ba5778d82f48f9668f9b2506826a`。
- 工作位置为独立 Clean worktree。暂存区为空，受跟踪工作区干净；原有未跟踪的 `T3_2_A_D_real_device_validation.md` 保留，不纳入本次提交。
- 已读 AGENTS、[正式计划入口](README.md)、[v2 原生语音计划](T3_1_R2_native_voice_experience_plan.md)相关范围、[M01 报告](T3_2_A_D2_R2_M01_content_timeline_and_silent_validation.md)及 [Stage7 Checklist](../../stage7_forbidden_checklist.md)。M01 已接受和无声 A/B/C 通过属于前序证据，不替代本轮有声验收。
- 默认输入 I-01 为 USB 麦克风，默认输出 O-01 为 Mac 内置扬声器。CoreAudio 读回均可用、无独占 owner、启动前无运行占用；原生设备标识只在本机内存比对，未写入本报告。
- 系统实际输出 **55%、未静音**，输入60%；没有自动改音量、设备或模式。Microphone Mode=`UNKNOWN`，未继续研究模式。
- 系统设置的 Aftelle 麦克风开关实际读为 on，未操作开关或请求新权限。启动前无 Aftelle 残留进程。
- 受控证据位置为 `~/Library/Caches/com.eterna.aftelle.debug-apple-vp-evidence/`，目录0700、当前用户所有、可写、规范化路径无 symlink，位于 Git 外。导出文件0600，无覆盖。

预检实际命令/操作：Git `rev-parse`、`status --short`、`ls-remote`；CoreAudio 只读属性查询；`osascript -e 'get volume settings'`；`pgrep -x Aftelle`；固定文件 SHA-256/格式和目录元数据核验；系统设置权限页只读观察。核心预检脚本 exit0；启动前 `pgrep` exit1 表示进程不存在，不是设备失败。

## 2. 真实源码、构建与固定语音身份

复用 M01 的 `.build/t3_2_a_d2_r2_m01/DerivedData/Build/Products/Debug/Aftelle.app`，没有重编译。当前源码/测试五文件摘要与 M01 `candidate-code-identity.json`、当前 HEAD blob 一致；运行前及 A 完成后再次核对，无源码变化。当前 HEAD 是已提交的验证候选，M01 报告中的旧运行 checkpoint/diff 身份保持历史口径。

| 实际运行 Debug 映像 | SHA-256 |
| --- | --- |
| `Contents/MacOS/Aftelle` | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| `Contents/MacOS/Aftelle.debug.dylib` | `98918302e7a8be058b772e1e1a498786c5ec9cb09ba7bec90a317b9bcb4c9fdf` |

只启动一个 A 实例；实际 argv 为上述二进制加 `--apple-vp-acoustic-test`，未使用 silent-smoke。对同一 PID 核验主程序和 dylib 均实际映射。隔离界面显示无 resident/session/provider 加载、Runtime interruption=DISABLED；沿用正式共享 Host/Capture/OutputHost/Player，不使用研究 CLI 或另一套 Engine。Cascaded、RuntimeCore、Qwen Adapter、Input Bridge、取消/clear、Session/Memory 均未修改。

固定样本为前序已批准的 macOS 离线 Tingting 合成语音：“这是一段固定语音，用来检查回声和人声。”文件名 `d2_fixed_zh_24k_mono_pcm16le_preroll1s_v1.wav`，位于 Git 忽略的 `.build/t3_2_a_d2_preflight/tts_sample_v1/`。格式24kHz/Mono/PCM16LE，114032 samples、228108 bytes，总长4.751333秒，含1秒前导静默；SHA-256：

`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`

本轮重新核验样本文件及本次 manifest 的 playback SHA 一致，没有生成新样本、读取其他录音或调用 Provider。

## 3. 本次独立授权与执行顺序

全部预检和 A 准备完成后，向用户展示实际设备、55%音量、固定内容、每项最多15秒、仅本机保存/导出和手动试听范围。用户明确回复：

> 授权上述范围；A已就绪，保持安静

随后仅执行一次 A：原界面 Start → 本地授权确认 → Output prepare/Capture start/固定 WAV playback → 自动结束 → Seal/Host shutdown → 显式 JSON/WAV 导出。提供本地试听文件后正常 Quit 并核实设备释放；用户手动试听并反馈，没有自动播放录音。A 结果确定前没有准备或启动 B/C；确定 A 声学失败后停止，无第二次运行。

本轮未重跑 M01 已通过且源码未变化的 Debug/Release、Guard、Host/Playback/Converter 或其他离线套件，均为 `NOT_RUN（复用已绑定的既有证据）`，没有写成本轮新 PASS。

## 4. A 的实际控制链与 PCM 证据

Run UUID：`B3F72FC9-35EE-49D1-8C5F-E16EC49A2628`；scenario=A；非 silent；上限15000000000ns/720000bytes。

| 项目 | 实测 |
| --- | --- |
| 配置 | stage=validated；configurationID=2；capture generation=1 |
| Apple VP | input=true、output=true、AGC=true、bypass=false、inputMuted=false |
| VP 格式 | 输入/输出均16000Hz、3声道；原 I/O 格式 Guard通过 |
| 原生采集 | Float32、非交错、16000Hz/3声道；149 buffers、每声道238400 frames，标称14.90秒 |
| 目标格式 | 24000Hz/Mono/PCM16LE、channel[0]、20ms/480 samples/960 bytes |
| generated/drained/queued | **744/744/0**；实际保留714240bytes、357120 samples、14.88秒 |
| 包序列 | 1–744，全部相邻序号差1、内容时间差20000000ns、每包960bytes |
| content_time/native_clock | **0/0** |
| 其他输入拒收 | 全部0，包括 packet clock/time/length、route/configuration change、capture fence、stale context、各转换/格式/容量错误 |
| drop/stale | **0/0** |
| coverage/issues | coverage_valid=true；issues为空；native sealed=true |
| 播放 | generation=1、started=1、state=completed、underrun=0、rejected callback=0 |
| 错误 | run/capture/playback error均null，无 playback_failed/capture_failed |
| 各原生声道 | samples=238400、peak=1.0、full_scale=4、over_scale=0、non_finite=0 |

VP/AGC 是配置阶段实际读回，不冒充每个时刻的独立连续状态测量；原路线/配置 fence 拒收为0。AGC enabled 不代表音量质量 PASS。三个声道的相同计数不是三个独立声学样本；4个满幅样本须如实保留，不能宣布无削波风险。

时间锚点（monotonic ns）：

| 区间 | 记录 |
| --- | --- |
| 首/末 native buffer hostTime | 707341104149458 / 707355904077667 |
| 首/末 native sampleTime | 640 / 237440 |
| **实际已 drain** 首包起点 → 末包结束（exclusive） | **707341104149458 → 707355984149458** |

首/末 native 锚点跨度的 host/sample 偏差约-71792ns；本次 content_time/native_clock 均0，保留相邻连续性检查，没有把累计偏差重新当作实际样本缺口。本轮只记录已接受 M01 修复后的真实结果，不修改算法或再次重判历史失败。

### 尾音和覆盖限制

- 本轮 queued=0，未出现前序5个排队尾包；14.88秒完全来自实际 drain 和导出 WAV 数据，不以 generated 数量替代已保存覆盖。
- `partial_converter_tail_samples=null`，保持 **UNKNOWN**。原生14.90秒与完整包14.88秒不相等，不能把差值直接解释成已测得的 Converter partial tail，亦未补零或补造尾包。
- 1秒前导静默属于固定 WAV 资产属性，不是经物理时间标定的麦克风预留窗口。用户确认现场完整播放、全程安静且播完后距采集结束至少1秒；这是**用户见证的 post-roll**，不是 sample-aligned 测量。
- manifest 未包含实际扬声器/真人讲话起止的独立 monotonic 时间戳；A 没有计划的真人讲话。播放结束后0–500ms的精确内容切片、精确 post-roll 时长仍 **UNKNOWN**。不能凭4.751秒文件长和14.88秒录音长直接宣称物理窗口已标定完整，也不能将未测尾音单独判 PASS。
- manifest 的 `source_commit`/`build_identity` 原值均null，未伪填。真实源码、加载映像和 run 由本轮 Git 外预检清单及本报告关联。

## 5. 本地导出及用户真实试听

JSON/WAV 均为受控 Caches 中对应 run UUID 的原文件；不上传。WAV header符合目标格式；data部分 SHA 与 manifest `processed_sha256`相同，且 data bytes=744×960。只读核验脚本 exit0。

| 资产 | SHA-256 |
| --- | --- |
| `run-B3F72FC9-35EE-49D1-8C5F-E16EC49A2628.json` | `acebe42fd5ea01deea972c020a6434bd13510eb67ff24296f1577e8a12387d93` |
| `run-B3F72FC9-35EE-49D1-8C5F-E16EC49A2628.wav` | `b586b54a8207d1f8808fb428ce7a3fbfe89b8c6b62867b48606fef09bb7ae375` |
| WAV data / processed PCM | `b5e9bf177c9a2104e30b2bcc293b59b2a623854c7225354f2c974fc2c2b37589` |

用户第一条反馈原话：

> 能听到居民语音，无其他问题

为避免把现场外放和导出录音混淆，进一步澄清后用户明确回复：

> 导出的A录音也能听到居民语音

对“全程保持安静、现场固定语音完整播放、播放结束至采集结束至少1秒”三项，用户回复：

> 三项都确认

`USER_LISTENING=COMPLETED`，但**不能标记 USER_LISTENING_PASS**。在用户安静、现场完整外放的负控中，处理后录音仍有可听到的居民语音，未满足本轮居民回声抑制要求。用户未报告其他问题；不据此擅自关闭历史“起音音量变化”，也不虚构其可接受性或音量标定结果。

## 6. 分项判断和停止决定

| 场景 | 控制链 | 已观测内容时间轴 | 真实声学/用户试听验收 | 本轮结果 |
| --- | --- | --- | --- | --- |
| A Resident-only | PASS | PASS（已 drain 包及 native coverage） | FAIL：导出录音仍能听到居民语音；精确尾音窗口另为UNKNOWN | **FAIL** |
| B Human-only | NOT_RUN | NOT_RUN | NOT_RUN | **NOT_RUN** |
| C Double-talk | NOT_RUN | NOT_RUN | NOT_RUN | **NOT_RUN** |

AEC 本轮结果为 FAIL，不是“VP未启用”的证据，也不是已定位的 Apple 算法缺陷。没有可支持 ERLE、AEC/NS 抑制分贝、算法延迟或改善百分比的数据，这些保持UNKNOWN。真人保留及持续双讲本轮未验，物理双讲>1秒资格未取得。

A 封存与导出后正常菜单 Quit；`pgrep -x Aftelle` exit1确认进程不存在，CoreAudio 两设备仍为原目标路线、alive1/hog-1/running0，音量仍55%未静音。manifest 的 capture_state=capturing 为 shutdown前快照，不能单独代替终态；UI sealed、原 shutdown路径及退出后快照共同记录释放。未观察到崩溃或死锁，未进行资源压力或泄漏专门测试。

本轮 A 后停止，B/C不启动，无有声重试、阈值调整或修复。不得以 M01 无声 PASS、输入连续或 VP enabled 将本次声学失败改判。所有数据属于 D2工程验证，不累计正式53-A～E次数。

## 7. 五维审核与问题登记

实际审核来源全部为 **SELF_REVIEW（Codex）**，没有独立 Reviewer 或独立声学听审的冒称。AI未自动播放/听取录音；听感结论明确来自用户。

| 维度 | 结论 | 范围与理由 |
| --- | --- | --- |
| TECHNICAL | **REWORK** | 正式Host控制/格式/时间轴通过；A居民回声抑制失败，不能推荐实机收口 |
| ENGINEERING | **REWORK / DEBT_DEFERRED** | 本轮无代码变更或新增状态Owner；历史规范FAIL和C19/C23原样保留，不作工程PASS |
| EVIDENCE | **PASS（如实记录失败及限制）** | 本次单次run/源码/映像/资产绑定；用户现场与录音反馈已澄清；drained/queued/partial与物理时间未知明确分开 |
| CONSISTENCY | **PASS** | 满足A失败即停止；无Provider、Test2原链变更或正式Gate；未推进T3.2-B/T3.3 |
| Stage7 Forbidden Checklist | **PASS** | 本轮仅已有macOS DEBUG实验及脱敏报告，六红线与禁止项未触碰 |

| 严重性/编号 | 状态 | 事实及处置 |
| --- | --- | --- |
| CRITICAL | 新增0 | 未发现越权、泄密或生命周期安全失败 |
| MAJOR R3-M01 | **OPEN** | A负控录音仍有居民语音；阻止继续B/C及T3.2-A声学收口。根因未定位，本轮不授权生产修复 |
| MINOR R3-m01 | **OPEN（证据限制）** | 精确物理播放/残回声/post-roll时间与Converter partial tail未知；不宣称全尾部已定量验收 |
| MINOR R3-m02 | **OPEN（观察项）** | 每声道4满幅样本，缺乏其事件时间和听感因果对应；历史起音音量变化未单独关闭，不擅调AGC |

历史 SQ-M1 继续OPEN，未计为本轮新增技术问题。历史 SwiftFormat **FAIL/20856/exit1**、SwiftLint strict **FAIL/384/exit2**沿用 M01 记录，本轮NOT_RUN，不冒充重新执行；C19/C23及既有指标增长继续延期。无新增代码，故本轮没有新增B类或C类代码增长，也不创建永久规范豁免。

## 8. Stage7 最终检查与交付边界

六红线逐项PASS：大脑不碰平台、Store带版本、三层不黏连、DR只读/revision、逻辑/画法分离、Intent语义均未改变。Checklist A–H：仅macOS Host、无Stage8/新target/Runtime API/DR schema；无Provider/Keychain/私人DR/Session访问，无Memory/Scheduler/Interrupt Owner新增，无未授权监听或后台运行。正常Release及Cascaded AEC3未改。

Checklist I：

- 结论：**PASS**；触碰红线：无。
- 修改文件：仅本报告。
- 改代码/Runtime API/DR schema/新增平台target/进入Stage8：均否。
- 原ACE3和Apple VP研究worktree的HEAD、status、diff摘要与本轮开始一致；原有未跟踪D报告摘要不变。
- Git白名单不含PCM、WAV、DR、私人设备标识、密钥或原始日志；本轮录音授权不包括上传。
- 停止受影响实验：**是，A声学失败后停止B/C**。本轮按明确授权仅提交/推送脱敏真实报告，不继续设备测试或生产修复。

**T3.2-A实机收口：不建议。** 需主控审核本次回声失败，另行圈定根因调查或后续测试；本轮不实施修复或安排自动重试。完成报告正常commit/push、核验HEAD=upstream=实时远端后停止。

最终状态：R3=`REVIEW_PENDING`；A=`FAIL`，B/C=`NOT_RUN`；ENGINEERING=`REWORK/DEBT_DEFERRED`；T3.2-B=`NOT_AUTHORIZED`；T3.3=`NOT_STARTED`；SQ-M1=`OPEN`；Qwen Strict Overlap=`0/3`；Formal Test3=`BLOCKED`；Test3.execution_authorized=false。
