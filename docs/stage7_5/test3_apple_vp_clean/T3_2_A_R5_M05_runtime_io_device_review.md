# T3.2-A / R5-M05 · Apple VP运行态I/O单次实机审核

**结论：本次A录音及两份M04读回均已取得，但输入物理归属仍未通过核验，M05=PARTIAL / IO_BINDING_UNVERIFIED。** 两个AU的deviceID都等于系统默认Mac mini输出设备，系统默认输入则为另一个TinyUSB设备；读回对象不是Aggregate。这里只确认属性差异，不据此宣布“误用了扬声器作为麦克风”或修复音频接线。实际VP属性及图格式稳定，HAL读回约2ms。处理后居民播放窗能量明显低于M03旧A，但缺少本轮现场声压/听感及未经VP处理的参考，**AEC_ROOT_CAUSE仍UNKNOWN，声学验收不判PASS**。

## 1. 源码、构建与授权

- 开始时HEAD / upstream / 实时远端一致：`f90c9272467b8af9846ce4551e354224fb7dafbf`；干净隔离Worktree。M02修复及M04实现保留，无源码修改、重建、全量回归或新增观测工具。
- App launcher SHA-256：`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`。
- 实际Debug dylib：`d53fa0568e08e98371f31399eb830078de80847fb9ed7a2c7fcb50608ae490f2`。构建receipt所列Capture、DeviceMonitor、Fake源码SHA全部匹配；启动后以确切PID和映射路径再次核验App/dylib，未按名称打开其他实例。
- 居民素材：`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`，228108 bytes，24kHz/Mono/PCM16LE，114032 frames / 4.751333秒，首1秒全零，未更换或处理。
- 本轮授权仅为M05 A一次采集、居民一次播放、4秒预热及15秒评分、本地JSON/WAV导出与分析；不复用R4/M03用户同意回执，不运行REF、BT代理、B或C。
- 复用现有A组DEBUG入口及原单次控制循环。原控制器固定旧dylib；仅本机启动胶水将其期待值精确登记为本任务给定M04 SHA，原`require_identity`继续执行，未删除校验或修改仓库脚本。新M05同意及单次排他标记另存；App内原M03/A协议标签保留，不能把该历史标签当作新的用户授权。

## 2. 预检、运行及封存

TinyUSB为默认输入、60%；Mac mini内置扬声器为默认输出、55%、未静音。两者在线、启动前running=0，无Aftelle/REF/代理残留进程；未改路由、音量或Mic Mode。Mic Mode=UNKNOWN。外部TCC数据库只读查询返回`authorization denied`，不等同App麦克风权限被拒；Aftelle原权限流程正常通过，未出现或操作新的系统授权弹窗。

原UI按确切PID完成Prepare A、选择并核验固定素材、可见采集/录音同意、独立JSON及WAV导出确认、Quit。采集前曾纠正文件面板层级和键盘路径输入，最终核实选中`HOST_resident.wav`；首次Cmd-Q未使进程退出，随后使用同PID原菜单正常退出，无重启或强杀。

| 实际项目 | 本轮结果 |
|---|---|
| RunID | `2F4AA935-488D-4777-BC9B-94CAC163F72C` |
| App / Capture / Resident start / completed | 各1次 |
| REF / BT / B / C / 重试 | 全部0次 |
| 外部控制器 / App exit | 0 / 0；原控制循环耗时267.305秒，包含采集前UI与采集后导出等待，不能当作录音时长 |
| Capture返回至Stop | 19.027239秒；名义19秒deadline后调度尾差27.239ms，不能写成严格19.000秒硬截止 |
| Native内容 | 190 buffers / 304000 frames，16kHz，每声道累计19.000秒 |
| Stop / Seal / 导出 / Quit / 释放 | 完成；进程退出、目标设备running=0，前后默认路由/音量一致 |

发现输入绑定读回不能确证时，采集已经封存停止；只完成授权范围内的证据核验及退出，没有追加采集或现场改代码。受控目录0700、JSON/WAV为当前用户所有且0600，无symlink、不覆盖旧文件；本轮音频及原始元数据不上传。

| 本机证据 | bytes | SHA-256 |
|---|---:|---|
| 原导出JSON | 82737 | `b16b65f5029c7b567ca283e951a33e4d6a8fcc261add18168d6bf531966d8764` |
| 原导出评分WAV | 713324 | `710c8d0d9cd8d52345192b243a7560938febebddad1f224e4c2e004dcefde7cf` |

WAV为24kHz/Mono/PCM16LE，14.86秒；PCM data摘要与本轮Manifest的`processed_sha256`匹配。原始deviceID/UID、路径及完整日志只留本机，报告用角色关系表示设备，未公开其标识符。

## 3. 两份M04快照

两份均绑定上述RunID，Capture generation=1、Playback generation=1、configurationID=2。以下为相对评分起点的Mac单调软件时间，不是物理发声时间。

| 读回 | 开始秒 | 结束秒 | 耗时ms |
|---|---:|---:|---:|
| Engine.start成功后 | −4.002823916 | −4.000772250 | 2.051666 |
| Resident Player.play返回后 | 3.066999459 | 3.068582917 | 1.583458 |

两份实际属性相同：engineRunning=true，Input VP=true，Output VP=true，AGC=true，bypass=false，inputMuted=false；Player→Mixer接入bus 0，Mixer→Output连接存在。无HAL读取exception、invalid-format issue或读取中设备变化，两个payload的route/formats/VP完全相同。**bindingStatus两份均为`UNKNOWN_UNVERIFIED_BINDING`，不能写成设备绑定PASS。**

### I/O归属与Aggregate

- 系统默认输入始终为TinyUSB；默认输出始终为Mac mini扬声器。
- `inputNode.auAudioUnit.deviceID == outputNode.auAudioUnit.deviceID == defaultOutput.id`，均不等于`defaultInput.id`。
- 两个读回对象为同一built-in transport、alive的非Aggregate对象，Aggregate列表为空；本轮没有出现被误判的合法Aggregate成员组合。
- 运行时HAL为该输出设备返回2输入/2输出、48kHz的stream元数据；预检及退出后的枚举为0输入/2输出。TinyUSB为16kHz/1输入。**新增输入流的内容含义及其与物理麦克风的映射UNKNOWN**，不能把它们直接命名为原音/AEC/参考。
- 当前快照没有AU对象同一性、方向独立的物理输入来源证据。M04读取的是两个节点的同名`AUAudioUnit.deviceID`，不是一个已被证明可分别定位两方向物理端点的合同。Apple文档仅将其定义为I/O设备；本机SDK的`kAudioOutputUnitProperty_CurrentDevice`定义为Global属性。因此，共享I/O属性/合成输入流是**HYPOTHESIS**；“实际TinyUSB输入错误”仍**UNKNOWN**，未确认生产接线BUG。[Apple deviceID](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/deviceid)、[AVAudioIONode](https://developer.apple.com/documentation/avfaudio/avaudioionode)。

### 六种格式

| 运行态位置 | rate / ch | format / layout |
|---|---|---|
| Input输出 | 16000 / 3 | Float32，非交错；layoutTag=9633795，bitmap=0，descriptionCount=0 |
| Player输出 | 16000 / 3 | 同上 |
| Mixer实际Player输入bus 0 | 16000 / 3 | 同上 |
| Mixer输出 | 16000 / 3 | 同上 |
| Output输入 | 16000 / 3 | 同上 |
| Output输出端口（`hardwareOutput`字段） | 16000 / 2 | Float32，非交错；layout未提供，descriptions为空 |

所有ASBD为formatID=1819304813 (`lpcm`)、flags=41、bitsPerChannel=32、bytesPerFrame/Packet=4、framesPerPacket=1、reserved=0；channels/rate按表。布局描述未截断。`hardwareOutput`是OutputNode端口读回，**不等于HAL物理设备stream的48kHz**，不能据差异声称硬件被错误设置。

## 4. 时序、连续性与尾部

Engine.start调用/返回：−4.181868791 / −4.002956291秒；Capture返回：−4秒；首Input callback到达/内容：−3.875012708 / −4.006959874秒。Resident Player.play调用/返回：3.046157334 / 3.066973125秒；Playback started/completed：3.068588042 / 7.941956417秒；非零Player Render内容：4.195109917–7.942773001秒。固定素材有1秒前导，软件事件和Render均不能证明物理声压或Apple内部参考。

首读回在Engine返回后约0.132ms开始；第二读回在Player返回后约0.026ms开始，延后`playbackStarted`控制事件约1.6ms。没有观测到明显长时间卡顿：Input/Render host及sample不连续、backwards、duplicate均0；最大callback内容起点间隔分别100.006500 / 100.008167ms，DEBUG skip=0、stale callback=0、invalid buffer=0。同步HAL调用位于生命周期锁内，对具体物理播放的因果影响仍未校准，不能宣布绝对无影响。

Capture drop/stale=0/0；Native全部拒绝计数0、issues为空、coverage_valid=true；Playback reject/underrun=0/0。终态timing.identityChanges=1必须保留：准备及Shutdown各有一次configuration事件，后者在Stop后约0.082ms；`tearDownGraph`增加configurationID并重新bind，足以解释该终态计数。两份运行快照ID一致，route事件0，未观察到评分期间配置变化。Manifest无独立AcousticHost fallback事件计数，**fallback=0不能由空error字段冒充**；仅确认M02源码保留且本次未见输入断流/转换拒绝。

generated/drained/queued=949/944/5。预热不留存199包，跨界排除1包、窗外排除1包，评分留存743包/713280 PCM bytes；保存序号与20ms内容时间连续。WAV内容覆盖score 0.013040126–14.873040126秒，首13.040ms及末126.960ms未保存，quiet已drain覆盖3.851269秒。**TAIL_COVERAGE=PARTIAL，Converter partial tail=UNKNOWN**。queued=5不是已确认丢帧，未补零或伪造完整15秒。

## 5. 声学统计及M03旧A对照

Native ch0/ch1/ch2在本轮各窗口的有限样本逐值相等计数均等于比较数；下表Native列适用于三个声道，不推断Apple内部通道含义。PCM按/32768，单位dBFS，不是SPL、可懂度或ERLE。A中没有真人或代理，沿用软件phase名称不表示真的发生双讲。

| score窗口 | Native RMS / Peak | 全部drained PCM RMS | 真正保存WAV RMS / Peak |
|---|---:|---:|---:|
| 0–3秒 | −89.00 / −64.06 | −89.05 | −89.40 / −63.46（首沿PARTIAL） |
| 3–9秒 | −69.40 / −38.23 | −69.46 | −69.46 / −37.50 |
| 9–11秒 | −51.26 / −21.02 | −51.26 | −51.26 / −21.06 |
| 11–15秒 | −64.79 / −33.71 | −64.67 | −64.67 / −33.14（尾部PARTIAL） |

预热Native RMS/Peak为−84.57/−63.80dBFS、drained RMS为−84.60dBFS，预热留存0 bytes。Native与drained同窗RMS差约−0.068至+0.118dB；quiet实际覆盖不同，不能把边缘差异全部归因Converter增益。没有后级大幅增益损伤证据。Native各声道满幅/超范围/非有限均0；保存WAV精确端点0。

| 主要只读比较 | M03旧A | 本轮M05 A |
|---|---:|---:|
| RunID | `F60F1D2A-4B68-4A05-8260-5BC567F71721` | 本报告第2节RunID |
| 4–7.75秒保存WAV RMS / Peak | −17.03 / 0.00 | −73.68 / −42.74 |
| 同窗精确零样本 / 90000 | 10886 | 43277 |
| Native每声道满幅 / WAV端点 | 23 / 33 | 0 / 0 |
| 居民模板最大绝对波形相关 / 反向负控 | 0.4114 / 0.0932 | 0.01585 / 0.01846 |
| 居民模板包络相关 | 0.5613 | 0.1234 |

历史比较仅读取已登记M03旧A数值报告，没有读取其他历史麦克风WAV。固定居民有声模板为源WAV的1–4.75秒，搜索起点score 3.9–5秒，沿用原相关性及反向模板负控。**本轮没有超过负控的稳定居民波形匹配证据**；并不证明完全无残回声。M03原用户“全部失败”及随后主控旧A回声FAIL不改写。本轮USER_LISTENING=NOT_REQUESTED_USER_ABSENT。

同窗RMS下降56.66dB是两个处理后录音的数值差，不是已测AEC衰减或修复效果；系统Mic Mode、现场环境、物理声压及未经VP处理的输入未知，M04也增加了读回。仅凭数字输出不可证明扬声器实际发声幅度保持相同。

本轮最大20ms RMS上升在score 10.36秒：0.0001864→0.0204662，+40.81dB；发生于非零Render结束约2.42秒后，Peak全局约−21.06dBFS，没有满幅。Render结束后0–500ms的WAV RMS/Peak约−60.00/−37.50dBFS，500–1500ms约−65.38/−38.55dBFS。后段声音来源**UNKNOWN**，不能自动标成居民回声、环境讲话或AGC BUG；未转录、未自动播放。

## 6. 检查、裁定与下一项

| 实际命令/检查 | 次数与结果 |
|---|---|
| 既有`device_preflight --preflight`、`get volume settings` | 启动前/退出后各1次，exit0，路由音量一致、目标设备最终不运行 |
| 本机M05启动胶水→既有A控制循环 | 1次，exit0；目标App exit0，代理命令列表为空 |
| 本轮有限分析`python3 -B .build/r5_m05/analyze_m05.py` | 首次exit1：报告脚本误取`generation`键；改用原`capture_generation`后exit0（0.423秒），未改数据、阈值或重录；首错保留 |
| Debug/Release构建、Fake、FAST/FULL_CURRENT | 本轮0次；仅复核M04实际构建/源码身份，不写成新测试PASS |
| diff、文件白名单、隐私 | 顺序最终核验通过；只提交本报告，不提交启动胶水、原始JSON/音频/日志 |
| `bash tools/secret_guard/check.sh` | 1次，exit0；原7冲突及索引一致 |

分析数值报告SHA-256：`fab51325232189ea1793c03ac1104212d00aaf965e2c4f1b7af3ee300880133e`，完整命令/退出码及本轮同意仅留Git忽略的本机目录。

首次最终检查与Guard写日志并行时发生本地断言失败；Guard结束后改为顺序逐项核验，源码、受控文件权限、隐私、单报告白名单及原索引全部通过，未更改音频或安全阈值以取得通过。

- **CONFIRMED**：一次A完成；两份同身份快照存在；VP/AGC/连接/格式稳定；AU两个deviceID同指默认输出，默认USB输入为另一ID；本轮处理后播放窗低能量、无满幅，较M03旧A数值明显不同。
- **HYPOTHESIS**：共享I/O AU或VP合成输入流使单一deviceID不能代表独立物理输入。不能由默认设备枚举或字段名称单独确认。
- **UNKNOWN**：真正TinyUSB输入归属、内部AEC参考、物理播放声压、后段声音来源、声学根因及用户听感；当前仍无可确认的生产代码修复对象。

**唯一下一项建议：先限定核清M04的AU deviceID读取口径，确认是否共享I/O AU以及什么已有属性能合法区分物理输入来源；主控批准前不改setDeviceID、Mixer/Mono→3ch或DSP，也不追加设备实验。** 目前没有足够证据建议生产修复。C组2.18ms时钟拒收仍为独立OPEN，本次拒收为0不关闭旧问题。

五维SELF_REVIEW：功能=PARTIAL（控制链完成，I/O准入仍未证实）；证据=PASS_FOR_LIMITED_CONCLUSION（真实/历史/UNKNOWN分开）；安全隐私=PASS（仅一次、原同意/导出/退出、录音不公开）；架构=PASS（生产代码、图、算法、Engine/Tap均未改）；工程=文档交付，M04历史规范债务不变。新增确认生产缺陷CRITICAL/MAJOR/MINOR=0/0/0；**关键证据阻塞1项：物理输入绑定未确证**，不把它登记成已确认路由BUG。

Stage7 Forbidden Checklist=PASS：触碰红线无；只改本报告；Runtime API/DR schema/平台target/Stage8均未改；无需追加确认完成本轮已授权取证，后续实机须另批。原7冲突、索引与未跟踪现场保持不变。

```ini
R5_M04=ACCEPTED_OFFLINE
R5_M05=PARTIAL_RUNTIME_IO_UNVERIFIED
A_DEVICE_CAPTURE_RUNS=1
RESIDENT_PLAY_RUNS=1
RUNTIME_READBACKS=2
ACTUAL_INPUT_BINDING=UNKNOWN
RUNTIME_VP_PROPERTIES=CONFIRMED_ENABLED
A_ACOUSTIC_ACCEPTANCE=NOT_EVIDENCED
USER_LISTENING=NOT_REQUESTED_USER_ABSENT
TAIL_COVERAGE=PARTIAL
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
