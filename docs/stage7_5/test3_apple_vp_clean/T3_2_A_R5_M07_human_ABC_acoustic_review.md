# T3.2-A / R5-M07 · 真人A/B/C声学实验审核

**三组各真实采集一次；用户试听A/B正向，C仍轻微忽大忽小。C另因内容时钟拒收提前停止，完整流程不能判PASS。** 本轮不使用蓝牙代理或REF。所有数值均来自本轮同RunID的Native统计/真正保存WAV；没有VP前原音，不将Native称为未经处理的麦克风信号。声学根因仍UNKNOWN，正式状态不前推。

## 1. Git、授权与最小DEBUG适配

开始时HEAD/upstream/实时远端均为`6f74de80dec2e397999b63a951947e2f1b2e6a7a`。干净隔离Worktree，跨文件修改前建立本地回滚提交`e1d009791a0a4cb384ba6fdd874294a02ed6947e`。原7个冲突、索引及未跟踪现场保持不变，不stash/pop、reset/clean或强推。

普通A/B入口不能直接提供本轮相同19秒预算，故复用原M03评分逻辑增加独立`--apple-vp-human-abc=A|B|C` DEBUG入口。Prepare固定AGC-ON、WARMUP_4S、RECORDING、15秒评分及720000bytes上限，严格与BT批次互斥；旧M03入口和事件保持原协议。UI明确显示真人来源与A安静/B,C讲话提示。

新增M07 ScoreControl标记`batch=R5_M07, source=human, proxy_requested=false`，使用`human_speech_stop_ns`；外部适配仅将该截止时刻翻译给原SingleRun时钟检查，不启动代理进程，不发送物理PLAY/STOP命令。保持默认设备禁用、精确二进制/素材校验、RunID/组别/源身份、单次O_EXCL登记、前组同run导出/释放门禁及取消清理。旧M03/REF同意回执未冒用。

没有修改Capture、AcousticHost、Converter、channelMap、Engine/Player/Mixer图、DSP、RuntimeCore、Provider、Gate或正式授权。M02隔离修复、M04读回均保留。新增原生Engine/Tap=0；只有每组独立生命周期中原有共享Engine。

## 2. 候选及设备身份

- App launcher SHA-256：`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`。
- 实际Debug dylib：`f1339555b1de0be412629e58013ba6686d0de09851a37496b835a3d5b1812fd7`；三组启动后均用确切PID及映射路径复核同一候选，未按应用名称启动其他实例。
- 实际录音候选源码已冻结于`fd990fd418272c7e686b1948f85b209bc3894dd3`，对应上述dylib；整个App已在本机逐字节归档。交付前仅对两处UI调用及Fake参数缩进做空白/换行修正，去除空白后源码字符一致，字符串和音频行为未改。交付版Debug再次构建exit0，7.100秒，dylib=`094ce973dc6f3589db56fedca067af4ddc1d0865534bc5150952a66c603f764c`，外部入口登记此精确新身份；**交付版未用于任何新增实机运行，不能替代本轮实际f133…身份**。
- 以下源码摘要对应实际录音候选f133…，不是交付版UI摘要；交付版`ContentView.swift`为`4106f470db105c618cb983b9781f8a1c2862be816ead2b79a827e8d5edf87d0e`。
- 构建源码 `AppController.swift`：`91780204d0d5d8f12ab613b9a8485fcf2f3e5ffd56aff935572e6954fb1265c1`。
- 构建源码 `ContentView.swift`：`81fa3a618b745976cfb67c6ad829c5ff122fe28e9390fd1c5958e84638d6a99a`。
- 构建源码 `MacSpeechAudioCapture.swift`：`8a8ca38221c61375303f445b7d14feb36f91151f04d77504e51454064f5bfe18`。
- 构建源码 `MacSpeechAcousticEchoHost.swift`：`4a6153bca24c5bf237247374c05b9524443371e83e7ad71811957e9bb6cde8fe`。
- 固定居民：SHA-256 `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`；24kHz/Mono/PCM16LE，114032frames，4.751333秒，首1秒全零。没有换素材、调增益或重新合成。
- 默认输入TinyUSB，60%；默认输出Mac mini内置扬声器，55%、未静音，两者在线。首次读回为100%；用户手动调整后读回54%，随后明确授权仅精确设置输出55%，复核通过后才采集。未改输入音量、默认路由或Mic Mode。
- Mic Mode仍UNKNOWN。每组均执行原App采集可见同意及两次显式JSON/WAV导出；未出现或操作新的系统授权弹窗。
- M04实际Input/Output AU getter仍同指默认输出对象，所有快照binding=`UNKNOWN_UNVERIFIED_BINDING`。结合M06，这不是输入错接证明；**物理输入归属未升级为CONFIRMED**。没有实施M06 Raw或新的方向查询。

## 3. 尝试、实际运行和清理

首次A在文件选择/可见确认之前耗尽原240秒UI看门狗，控制器exit1并回收App；schedule/RunID/PCM均未产生，真实录音0、居民播放0。原失败和排他标记保留。用户随后明确回复“允许重新准备并完成A/B/C”，才建立独立续行目录，未删标记或伪造同意。修正的是操作者对原文件面板层级/聚焦的操作方式，没有改UI看门狗、权限门禁或音频实现。

续行使用按确切PID绑定的AppleScript完成原面板和确认。A/B/C各一次采集；居民播放1/0/1，BT/REF/第四次采集均0。每组导出、正常菜单Quit、进程退出和设备running=0后才进入下一组。C失败后不再采集。受控目录0700、原JSON/WAV0600、无symlink和覆盖；公开副本是后来单独授权的三份WAV，原件留本机不变。

| 实际项目 | A居民独讲 | B真人独讲 | C真人双讲 |
|---|---:|---:|---:|
| RunID | `6732FC36-F824-4835-8EC9-05145C972BAB` | `2924502E-9463-4CE8-A8C7-CA797EE39C7A` | `1686FD38-F0AD-49DE-9F9B-B00A2F4CE324` |
| Capture返回至Stop秒 | 19.020025 | 19.020435 | 18.323813 |
| Native buffers / frames | 190 / 304000 | 190 / 304000 | 183 / 292800 |
| generated / drained / queued | 949 / 944 / 5 | 949 / 944 / 5 | 909 / 909 / 0 |
| 留存包 / PCM bytes | 743 / 713280 | 743 / 713280 | 708 / 679680 |
| 保存WAV秒 / 内容score区间 | 14.86 / [0.011493,14.871493) | 14.86 / [0.013050,14.873050) | 14.16 / [0.013024,14.173024) |
| quiet已drain覆盖秒 | 3.846595 | 3.865098 | 3.170792 |
| Native每声道满幅 / WAV端点 | 0 / 0 | 6 / 5 | 0 / 0 |
| DEBUG skip / Input观测host不连续 | 5 / 4 | 0 / 0 | 0 / 1 |

A/B按原19秒deadline结束，控制调度尾差约20ms，不写成严格19.000秒硬截止。C在score 14.323813秒安全停止。三组已留存包的序号与20ms内容时间均连续；预热199包不保留、跨界1包及窗外1包不伪装成评分。三组TAIL_COVERAGE=PARTIAL，Converter partial tail=UNKNOWN。C queued=0也不能证明15秒完整，A/B queued=5也不直接等同真实丢帧。

## 4. 运行态、时序与明确失败

五份M04快照同各自RunID/generation/configuration：A/C各2份，B因不播放居民只有Engine启动后1份。全部读回Input VP=true、Output VP=true、AGC=true、bypass=false、inputMuted=false、engineRunning=true；Player/Mixer/Output图格式仍16kHz/3ch Float32，Output端口16kHz/2ch，硬件枚举48kHz。来源语义及内部AEC参考继续UNKNOWN。

| score相对软件时间，秒 | A | B | C |
|---|---:|---:|---:|
| human_only提示 | 0.017284 | 0.010363 | 0.024936 |
| score+3阶段 | 3.024481 | 3.003745 | 3.002481 |
| human_tail提示 | 9.002511 | 9.019959 | 9.022342 |
| quiet提示 | 11.024897 | 11.007952 | 11.002232 |
| Resident Playback started→completed | 3.099110→7.965814 | 未播放 | 3.068634→7.950955 |
| 非零Player Render内容 | 4.225577–7.973246 | 无 | 4.195104–7.942772 |
| HAL两次/一次耗时ms | 2.343000/1.602250 | 2.115666 | 2.156250/1.617791 |

以上是软件/Render时间，不是扬声器物理发声或真人物理重叠证据。用户另行确认：“确认现场听到居民并持续双讲超过1秒”，据此记录C物理重叠为`WITNESSED_GT_1S_WITH_LIMITATIONS`，不是精确起止计量。B/C相对评分起点的实际讲话边界仍未单独确认。

- **A观测限制：** Native实际统计190buffers/304000frames、时钟拒收0、保存PCM连续；DEBUG Input时序仅185buffers并有skip5、4处host/sample观测间隔，最大约300ms。不能把丢失的观测补成完整回调证据，也不能将其直接判定为真实音频丢帧。Render观测无不连续。
- **B：** Native/Render连续性观测无不连续，Native各声道满幅6；WAV正端点5个，内容score约1.569–1.577秒。用户试听清楚完整；少量端点不自动等同可听失真，也不能忽略数字边界风险。
- **C明确工程失败：** `error=voice_processing_unverified`，Native `issues=[content_time,native_clock]`，两类拒收各1；VP属性拒收为0，不能将总括错误码解释为VP/AGC关闭。末个Native host时间相对首sample锚点累计偏差+2.073126ms，最大相邻host结束间隙2.165292ms，sample序号未跳。当前源码按输入采样周期检查内容时间（`MacSpeechAudioCapture.swift:645–661,1542–1564`），不是可擅自放宽的“2ms容差”。本轮没有修改它；该独立时钟失败发生在居民Render结束约6.38秒之后，不作为AEC根因。
- 三组Capture drop/stale=0，Playback reject/underrun=0；A/B其他Native拒收0。C已接纳前缀仍连续，不能把此前全部录音丢弃或写成完整15秒。终态identityChanges=1保留，快照configuration一致；Stop后Shutdown的configuration变化不冒称评分中路由改变。Manifest无独立AcousticHost fallback计数，fallback是否曾发生不由空error字段推成0。

## 5. 声学数值及用户试听

下表仅为真正保存WAV的RMS/Peak，单位dBFS（PCM16/32768），不是SPL、ERLE或可懂度。A的软件窗口名不表示有人讲话；B的3–9秒也不表示发生双讲。

| score窗口 | A | B | C |
|---|---:|---:|---:|
| 0–3 | -30.94 / -5.16 | -17.64 / -0.00 | -17.86 / -0.01 |
| 3–9 | -59.63 / -26.79 | -21.37 / -3.21 | -23.43 / -7.34 |
| 4–7.75 | -57.83 / -26.79 | -20.50 / -3.21 | -23.52 / -7.56 |
| 9–11 | -72.78 / -58.05 | -30.94 / -12.74 | -20.89 / -6.61 |
| 11–15（尾部PARTIAL） | -73.28 / -58.49 | -33.88 / -10.29 | -30.20 / -9.55 |

同RunID同窗Native ch0与全部drained PCM：B/C前三个评分窗RMS差约−0.0001至−0.0004dB，A相应窗约−0.0004至−0.0107dB。quiet差约−0.149/+0.132/+0.161dB，边缘实际覆盖不同。没有支持后级Converter大幅整体增益损伤的证据；大窗相同不证明每个字或每个瞬态都完整。三组Native各窗口有限样本逐值相等计数与比较数一致，不只是Peak相同；不推断Apple内部三声道物理含义。

| 最大20ms绝对RMS上升 | A | B | C |
|---|---:|---:|---:|
| score秒 / 前后幅度比dB | 0.20 / +22.45 | 1.56 / +6.05 | 1.34 / +8.95 |

A的最大上升发生在居民请求前，声源UNKNOWN。真人语音本身会产生能量变化，B/C此数值不能独立证明AGC BUG。C轻微忽大忽小以用户听感为有效证据，具体机制仍UNKNOWN。

沿用已有居民3.75秒模板、score 3.9–5秒搜索及反向模板负控：

| 波形最大绝对NCC / 反向负控 | A | B（无居民负控场景） | C |
|---|---:|---:|---:|
| 描述性搜索最大值 | 0.0896 / 0.0423 | 0.0474 / 0.0502 | 0.0413 / 0.0344 |

相关性不作为AEC或声源分离门槛，不把小差值称为已辨认居民；本轮真人没有固定可对齐模板，也没有转录。用户试听原话完整保留：

> A听不到居民声音，B清楚完整，C无居民声音，但是真人声音有轻微忽大忽小。没有其他问题。提交推送三份WAV让GPT审核

**A：本轮用户听感支持居民回声抑制；B：本轮用户听感支持清楚完整的人声保留；C：用户未听到居民并另行见证持续双讲超过1秒，但轻微增益波动仍在，加上quiet时钟拒收，维持PARTIAL。** 用户未回答的精确发声时刻不从“没有其他问题”补成PASS。未把用户试听改写为正式声学批准。

## 6. 与M03/M05的有限对照

| 4–7.75秒保存WAV RMS / Peak | M03旧A | M05 A | M07 A |
|---|---:|---:|---:|
| dBFS | −17.03 / 0.00 | −73.68 / −42.74 | −57.83 / −26.79 |

M03 A用户/主控回声FAIL，M05没有当轮用户试听，本轮A用户听不到居民；不追溯改写旧结论。这些处理后能量差不是AEC衰减，也不能证明某次代码修复是原因；环境、实际声压、Mic Mode和物理输入绑定未完全统一。

M03 B/C是同Mac蓝牙代理，其4–7.75秒RMS为−24.42/−27.11dBFS、PCM零值3171/33017（共90000）；本轮是真人，分别−20.50/−23.52dBFS、零值13091/9587。讲话内容、音量和起止未严格对齐，**不计算真人B/C逐样本相关性，不把零比例变化自动称为修复或错误抑制**。本轮首3秒约−17.64/−17.86dBFS，没有重现10月18日约−81dBFS的整体近静音；根因和触发条件依旧UNKNOWN。

M03 C在score约13.516秒因时钟拒收停止；本轮C约14.324秒再次出现同类时间合法性失败。它是需要独立处理的可复核工程问题，不能与居民播放期的声学作用混为一谈。本轮不修时间戳或重复录音。

## 7. 验证、问题与交付

| 实际验证 | 结果 |
|---|---|
| `bash tools/realtime_interruption_evidence_tests/check.sh m07-only`，1次 | exit0；原M03 11cases/287checks；含M07累计15cases/543checks（增量4/256），Fake设备访问0 |
| Python `unittest test_m03 test_m07 -v`，首次 | 19tests，M03 14通过；M07取消负控的异常类型捕获不含`subprocess.TimeoutExpired`，1 error，exit1。是测试异常分类遗漏，未改控制器阈值或启动设备 |
| 修正异常分类后M07定点复核 | 5/5，exit0；独立审核再补足前组RunID/source/release与严格布尔身份门禁，最终6/6，exit0。未重复大型回归 |
| Debug `xcodebuild … -derivedDataPath .build/r5_m07/DerivedData … build`，1次 | exit0，16.998秒；dylib按第2节冻结；没有Release整App重建/FULL_CURRENT/FAST/HIL |
| Release Route / Architecture / Secret Guard，实施后及交付收口各1次 | 均exit0。Release是DEBUG源码投影检查，不冒称新Release二进制验证 |
| 实机启动胶水→`m07_once.py --group A/B/C --consent R5_M07_HUMAN_ABC_ONCE_LOCAL_RECORDING_AND_ANALYSIS` | 初次A采集前UI超时exit1；获新授权后A/B/C控制循环、App退出均exit0。**C音频验收仍FAIL/PARTIAL，控制器exit0只代表生命周期已结束** |
| 本轮有限数值分析，1次 | `python3 -B .build/r5_m07/analyze_current.py`，exit0；只读取这三份当前WAV及固定非私人居民素材，原数值函数复用；无历史私人音频读取/自动转录/模型听音 |

完整命令、日志、同意及数值回执留本机Git忽略目录；未将原始Manifest、设备UID或完整日志提交。首次规范检查误用不存在的配置文件导致退出，保留失败记录，随后使用同一工具默认配置做基线/候选只读比较，不修改已执行候选。

格式收口沿用已有`--commas inline`口径，基线/候选三份Swift文件的Format告警均7070（exit1）；Lint为166→168（exit2）。新增非结构性规范问题0；两项C19/C23结构告警单列：DEBUG声学View为271行、共享Fake函数为80行。旧file/type长度与全量规范FAIL不清理、不改成PASS。首次默认逗号策略与旧口径不符不计为生产问题；空白修正不改变已冻结的录音候选，交付构建身份另记。

五维SELF_REVIEW：功能=已完成三组有限取证，C有明确时间失败；证据=真实/历史/Fake/用户听感/UNKNOWN分开；架构=只改DEBUG控制和直接测试，生产音频链不变；隐私=采集时仅本地，用户试听后单独明确授权这三份公开副本；工程=定点回归/构建/Guard及单次/取消保护，原7冲突保持。

问题等级：CRITICAL 0；MAJOR 1（C内容时钟拒收导致评分提前终止，既有类别本轮再现，时钟异常来源尚未确认）；MINOR 5（A DEBUG skip5、B少量精确端点、C用户轻微增益波动，以及两项C19/C23结构债务）。未确认新的AEC/AGC算法BUG，不以这些分级自动扩大修复授权。尾包、物理输入、Mic Mode和精确讲话边界继续作为证据限制。

唯一下一项建议：主控先审核本轮三份WAV、用户听感与独立时钟失败，再批准针对性下一步；不继续盲试AGC/蓝牙/新Tap或Raw采集，不自动增加实验。

Stage7 Forbidden Checklist=PASS：无六红线变化；代码仅DEBUG入口/外部适配/直接测试；Runtime API、DR schema、平台target、Stage8均未改；三次有界采集获本轮授权；初次失败后有新明确续行同意；三份公开音频有本次具体授权。正式授权状态不变。

公开试听副本及共同SHA见[本轮试听说明](evidence/r5_m07_human_abc_20261020/LISTENING_EVIDENCE.md)。它们是原导出的处理后评分WAV，不是Pre-VP原音。

```ini
R5_M07=COMPLETED_WITH_C_TIMING_FAILURE
DEVICE_CAPTURE_RUNS=3
A_CAPTURE_RUNS=1
B_CAPTURE_RUNS=1
C_CAPTURE_RUNS=1
BT_RUNS=0
REF_RUNS=0
A_USER_LISTENING=ECHO_NOT_HEARD
B_USER_LISTENING=CLEAR_AND_COMPLETE
C_USER_LISTENING=NO_RESIDENT_MILD_GAIN_VARIATION
C_CONTROL_COMPLETION=FAIL_CONTENT_CLOCK
C_PHYSICAL_OVERLAP_GT1S=WITNESSED_GT_1S_WITH_LIMITATIONS
TAIL_COVERAGE=PARTIAL
ACTUAL_INPUT_BINDING=UNKNOWN
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
