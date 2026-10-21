# T3.2-A / R5-M07-F1 · 真人起音顺序实机与试听审核

**A：用户未听到居民回声，无吞字、消音或音量波动；B：用户听到居民声，存在上述人声问题。起音顺序影响=SUPPORTED（有限），Apple VP初始适应机制=HYPOTHESIS，AEC_ROOT_CAUSE=UNKNOWN。** 有效A/B已各完成一次并退出；本轮含额外、经用户逐次授权的失败/未就绪尝试，全部单列，不覆盖。2026-10-21。

## 1. 源码、授权和证据范围

开始时HEAD＝upstream＝实时远端均为`dec2a7ab30859561ff866cd767847efdc918ea25`。本次实机阶段未修改任何生产或DEBUG源码，没有改变时间戳容差、AGC/NS/AEC、Engine/Player/Mixer、转换器或音频格式。跨文件交付前空提交回滚点：`e4e59c22477386f4cdedcd0effedd841d037b62a`。源文件摘要仍匹配F1冻结计划，M02隔离修复及M04读回保留。

| 冻结对象 | SHA-256 |
|---|---|
| App launcher | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| 实际加载F1 Debug dylib | `ecf6a86f4f05b3a594c978af45fc47d7af96c6761a9f7c1419ee494c96de8d5e` |
| AppController | `67ba4ee0de1437b9217a5cce2f18d7baef744890447c4643413fdc10cd6ac8a0` |
| ContentView | `4befd177d4502f1b8fe1518604ffaba7d108957975457b164fa15d50808e11fb` |
| Capture（未改） | `8a8ca38221c61375303f445b7d14feb36f91151f04d77504e51454064f5bfe18` |
| AcousticHost（未改） | `4a6153bca24c5bf237247374c05b9524443371e83e7ad71811957e9bb6cde8fe` |
| 居民固定WAV | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` |

居民为24kHz/Mono/PCM16LE、114032frames、4.751333秒，前1秒全零。两组同句“绿色纸船经过小桥，我会继续说完这句话。”；不启动蓝牙或REF。输入TinyUSB 60%；默认输出Mac mini内置扬声器55%、未静音。开始时输出81.25%，用户明确允许仅将内置扬声器精确设55%，随后及重启B前、退出后均读回55%，输入仍60%；未切路由或Mic Mode（UNKNOWN）。

用户先明确授权本轮真人A/B、WAV/JSON本地导出分析，随后分别授权重新A和未就绪B；B重启前回复“已就绪，开始B”。所有实际App均按确切PID核验已加载dylib，只操作原实验确认、文件面板和显式导出，不操作新TCC弹窗。当前两份JSON的`build_identity/source_commit`仍为null，源码/二进制关联由独立SHA和PID加载路径回执证明，未伪写Manifest。

试听后用户明确要求“推送WAV让GPT也审核”。已再次核验目标仓库PUBLIC，本次公开授权仅用于下列两份有效评分WAV：原字节复制，不归一化、降噪、裁剪、补零或重新编码。它们是**Apple VP处理后的原始导出WAV**，不存在本轮Pre-VP原音；没有上传失败/取消录音、JSON、原始Manifest、设备UID、完整日志或其他私人数据。

## 2. 全部真实尝试与失败记录

| 实际顺序 | RunID | 结果及退出 |
|---|---|---|
| A首次 | `9DBBA9CB-C135-4F4F-A04E-0366EDBDA475` | 预热约0.822秒即`voice_processing_unverified`；8个Native buffer、0.8秒内容，未进入评分/播放，评分PCM0；显式保存失败JSON，无WAV；正常Quit，控制器exit0 |
| A用户授权重启 | `2EA7AF35-7D1B-4512-8059-E65B3B091B8B` | 4秒预热＋15秒评分完成，显式JSON/WAV导出，正常Quit；控制器exit0；作为本报告A |
| B未就绪 | `ED06C7CA-11B3-4958-82C4-063F8E0D7F2F` | UI已封存`cancelled`，Native13.9秒，内存评分9.86秒；用户要求重新开始。导出前240秒看门狗触发，控制器exit1并清理；JSON/WAV未保存，仅UI/控制元数据留本机；不纳入对照 |
| B用户确认就绪后重启 | `AE5A2F99-C3FA-41DF-81A8-3BBD67755EC7` | 完成，原流程导出JSON/WAV，正常Quit；控制器exit0；作为本报告B |

实际麦克风启动总数4（A2/B2）；有效对照A1/B1。新增尝试均由用户新指令授权，不删除旧consumed标记，不重标失败为成功。新B使用独立RunID/证据目录，复用同批有效A的真实、字节一致结果与释放回执，未重跑A。取消B没有音频导出，无法补造其封存文件或完整声学结果。

首次A的VP/AGC本身读回正确；真正拒绝项为`content_time/native_clock`各1，VP拒绝0。Native sampleTime连续，但hostTime最大相邻偏差约3.239541ms，首末内容时钟残差约3.241416ms。有效A/B则无此拒绝。因此这不是已证实的AEC缺陷，也没有通过放宽阈值“修复”。

只读定位`MacSpeechAudioCapture.swift`原转换器时钟校验与既有`ConverterTimelineTests.swift`：错误代会持续失效，原generation reset可恢复。Git外确定性合成测试首次编译exit0、运行−5：标准三声道fixture格式构造为nil；仅将fixture改用已有discrete三声道layout后编译/运行均exit0，3cases/4checks验证“host jump拒绝、无reset持续阻断、原reset后样本/时间与新实例一致”。没有修改产品、容差或断言；不是对真实逐buffer时间戳的完整重放。设备恢复采用原Shutdown后的新进程/generation，底层时钟跳变原因仍UNKNOWN。

## 3. 有效A/B技术与时间线

两组均实际读回：VP Input/Output=true、AGC=true、bypass=false、inputMuted=false；Native16kHz/3ch Float32，最终24kHz/Mono/PCM16LE。Capture/Playback generation=1，configurationID=2，两次运行态快照身份一致、Engine running=true、图连接存在；`bindingStatus=UNKNOWN_UNVERIFIED_BINDING`，不据此宣称内部AEC参考已验证。

| 相对评分内容起点的实际事件 | A | B |
|---|---:|---:|
| Engine.start返回 | −4.003661s | −4.003244s |
| 软件评分阶段开始 | +0.011371s | +0.006403s |
| 真人讲话控制提示 | +5.506183s | +0.006403s |
| Player.play调用 | +3.051884s | +3.054716s |
| playbackStarted | +3.067483s | +3.068059s |
| 非零Player Render内容 | 4.194162–7.941831s | 4.195042–7.942711s |
| playbackCompleted控制事件 | +7.931692s | +7.949055s |
| 9秒/11秒阶段事件 | +9.012212/+11.019603s | +9.004421/+11.008960s |
| Capture Stop控制事件 | +15.014872s | +15.015551s |
| Engine启动后/播放后HAL读回耗时 | 2.481959/1.545500ms | 2.194916/1.169417ms |

每组Playback prepare/start/completed各1；Input190buffers/304000frames（每声道19秒），Render189buffers；sample/host discontinuity、missing/backward/duplicate、drop/stale/reject/underrun/skip均0。Native及Render最大EndGap分别为A2.250/2.292μs、B1.500/1.541μs。停止、封存、两次显式导出及正常Quit完成，退出后无Aftelle进程，两默认设备running=0。

Render是PlayerNode的数字内容时间，不是物理扬声器发声时刻；playbackCompleted是控制调用时间，二者不能相减当传播延迟。A约5.5秒提示仅辅助，不能证明真人恰好在居民物理起音1–2秒后讲话；物理间隔和重叠精确时长未测量。

## 4. Native、实际WAV与覆盖

以下为同RunID、同内容窗口；Native是VP后统计，非未经处理原音。表中PCM为**实际WAV样本**，不拿全部drain冒充留存。零能量记−∞；A0–3秒按规则安静，Native仅Float32极小非零值，不是一次“真人独讲静音失败”。

| 评分窗 | A Native RMS / WAV RMS / WAV Peak（dBFS） | B Native RMS / WAV RMS / WAV Peak（dBFS） |
|---|---:|---:|
| 0–3s | 极小 / −∞ / −∞ | −17.704 / −17.686 / −2.326 |
| 3–9s | −19.649 / −19.649 / −0.352 | −21.921 / −21.921 / −4.454 |
| 9–11s | −23.627 / −23.628 / −5.813 | −30.068 / −30.068 / −11.858 |
| 11–15s（实际覆盖至约14.873s） | −26.829 / −26.697 / −6.492 | −31.492 / −31.360 / −11.542 |

A4–5.5秒WAV RMS−79.484、Peak−47.511dBFS；A5.5–7.75秒−17.898dBFS。B对应两窗RMS−20.455/−24.057dBFS。两组人声起音、内容及声压不同，不能据混合RMS差直接判断AEC性能。quiet窗仍有非零内容，声源/讲话停止的精确时刻UNKNOWN，不能自动算成居民尾回声。Native/全部drain与WAV的首尾覆盖略异，quiet RMS的约0.13dB差不构成转换增益缺陷。

Native全程满幅/过幅/非有限计数各声道均0；WAV精确端点样本均0。已统计各窗的三声道有限样本均与ch0逐样本数值相等，不推断Apple内部声道物理含义。全WAV Peak A−0.352dBFS、B−2.326dBFS，未出现满幅。最大相邻20ms非零RMS上升A38.093dB@score11.372s、B49.292dB@score10.453s；前窗分别低至−71.648/−100.494dBFS，这些静默附近比值不是AGC BUG或爆音判据，需听感及原音对照。

| 尾包/保存指标 | A | B |
|---|---:|---:|
| capture generated_at_seal / drained | 944 / 944 | 944 / 944 |
| 稍后Native packet_count | 949 | 949 |
| queued_at_seal | 0 | 0 |
| 预热丢弃/边界排除/窗外排除包 | 199 / 1 / 1 | 199 / 1 / 1 |
| 留存评分包/PCM bytes | 743 / 713280 | 743 / 713280 |
| 评分WAV覆盖 | 0.012082–14.872082s | 0.012961–14.872961s |
| 前端/尾端未覆盖 | 12.082 / 127.918ms | 12.961 / 127.039ms |
| quiet已drain内容 | 3.852479s | 3.864001s |

WAV均356640samples、14.86秒，总713324bytes，低于720000bytes PCM上限；预热留存0。已保留包sequence202–944连续，内容时间严格20ms，内部缺口0；未补零。`captureFinal`快照与随后Native seal不是原子操作：AppController当前8247–8250行先读capture snapshot再seal Native，随后才close/shutdown。949与944不能当作同步计数，也不据queued=0宣称全尾导出。**TAIL_COVERAGE=PARTIAL；converter partial tail=UNKNOWN**；现有统计不证明整个15秒全部保存。

## 5. 原件身份、公开副本与用户原话

本机原件目录0700、JSON/WAV0600、当前用户拥有且无symlink。只复制本表两份WAV到公开证据目录，SHA及字节数逐项一致，PCM体SHA另与Manifest核对；JSON仅列摘要，文件不上传。

| 场景/链接 | RunID | WAV源件＝公开副本SHA-256 | JSON SHA-256（仅本机） |
|---|---|---|---|
| [A：居民先讲](evidence/r5_m07_f1_human_onset_20261021/A_resident_first.wav) | `2EA7AF35-7D1B-4512-8059-E65B3B091B8B` | `454bb244aa2b04b76a9696c9ae088cc251b07b8a7ff5ab8474f7c04024f64446` | `231689fb2ec03983e53dbe5ba0d878b2ceb902eccf76ba8ac2a7f17b8bfc4885` |
| [B：真人先讲](evidence/r5_m07_f1_human_onset_20261021/B_human_first.wav) | `AE5A2F99-C3FA-41DF-81A8-3BBD67755EC7` | `446ee5dd044f943a9898b6310edc985f07bc70f98ddd35d9495f950e4da73a0e` | `fb3fa7f4817a574e07058ba791290ef42a308715dc19e39dfd7f39f25156c237` |

用户完整原话（包含本次两份WAV公开提交授权）：

> A听不到居民声音，B可以。A没有吞字消音和忽大忽小，B有。其他没问题。推送WAV让GPT也审核

这是用户现场试听，Codex未代替其听感、未自动转录。对A的起音等待及两组>1秒物理重叠问题，用户概括回复“其他没问题”；保留此一般性见证，不补造精确时间。B具体吞字位置及居民首字是否为唯一泄漏点仍UNKNOWN，不能由RMS定位到词。

**CONFIRMED**：本轮同构建、同设备目标、同居民素材；两组技术链正常并导出；A/B用户听感不同；未发现本轮后级转换造成整体幅度损坏或满幅。

**HYPOTHESIS**：先有居民参考/回声铺垫可能改善适应或双讲行为；本对照支持顺序相关性，尚未分离真人内容/声压、环境状态和Apple内部处理。

**UNKNOWN**：Pre-VP原音、实际内部AEC参考、精确人声起止/漏词、quiet声源、根因，以及旧时钟跳变机制。不得据A听感良好关闭T3.2-A，亦不把B问题宣布为Apple算法BUG。唯一下一项建议：主控先审这两份原字节WAV及本报告，决定是否需要后续行动；不自动追加录音。

## 6. 命令、审核与正式状态

本轮实际受控执行命令（`$LOCAL_*`为Git外单次证据目录的脱敏替代，非通用播放器）：

- `python3 -B "$LOCAL_INITIAL/launch_group.py" A`：初次A exit0但音频错误；`python3 -B "$LOCAL_RESUME/launch_group.py" A`：有效A exit0。
- `python3 -B "$LOCAL_RESUME/launch_group.py" B`：未就绪B exit1（240秒退出看门狗）。
- `python3 -B "$LOCAL_B_READY/launch_group.py" B`：新B exit0；PID绑定原UI导出/退出脚本exit0。
- `swiftc -parse-as-library -framework AVFoundation -framework CoreAudio apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift apps/macos/Aftelle/MacSpeechAudioCapture.swift "$LOCAL_INITIAL/ClockRecovery[_v2].swift" -o "$LOCAL_TEST"`：两次定点fixture编译均exit0；首次测试−5、修正fixture后三项/四断言exit0。不是重新构建App。
- `python3 -B "$LOCAL_B_READY/analyze_current_pair.py"`：一次两份有效WAV/JSON分析，exit0；SHA、24kHz/Mono/PCM16LE、帧数、PCM体摘要、20ms连续性、留存覆盖及0600全部核验。仅处理本轮授权音频，无自动播放或转录。
- `git diff --check`、三文件白名单/私密信息及源文件摘要检查：均exit0，白名单3/3；`bash tools/secret_guard/check.sh`：1次、exit0、`secret-guard: ok`。未重复FAST、FULL_CURRENT、App构建或设备矩阵。

五维SELF_REVIEW：功能＝完成经授权的A/B与重启；证据＝失败/有效运行、Native/WAV、软件/物理、用户/数值分开；架构＝无源码或DSP变更；隐私＝仅新明确授权的两份WAV公开，其余原件/Manifest/设备信息本地；工程＝身份、原门禁、原看门狗、精确PID、唯一RunID/单次标记、退出释放和Git隔离均保留。

CRITICAL新增0；MAJOR：B残留/人声损伤听感仍OPEN，既有内容时钟拒收仍OPEN，不冒称已修；MINOR：未就绪B在导出等待超时而没有音频文件、尾部PARTIAL、具体漏词/物理起音未定量。首次合成fixture失败及修正均留痕，未归咎生产代码。

Stage7 Forbidden Checklist=PASS：无六红线变化；本提交仅新增本报告和两份当前明确授权音频，无源码、Runtime API、DR schema、平台target或Stage8变动。原7个冲突、原index、冲突文件摘要及14个未跟踪文件大小/mtime均与基线一致；未stash/pop、reset/clean或强推。

```ini
F1_EFFECTIVE_A=COMPLETED
F1_EFFECTIVE_B=COMPLETED
F1_ACTUAL_CAPTURE_ATTEMPTS_A=2
F1_ACTUAL_CAPTURE_ATTEMPTS_B=2
ONSET_ORDER_EFFECT=SUPPORTED_LIMITED
INITIAL_AEC_ADAPTATION=HYPOTHESIS
A_USER_LISTENING=NO_REPORTED_ECHO_OR_RETENTION_ISSUE
B_USER_LISTENING=ECHO_AND_RETENTION_GAIN_ISSUES_REPORTED
TAIL_COVERAGE=PARTIAL
DEVICE_EXECUTION=CLOSED_NO_FURTHER_RUNS
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
