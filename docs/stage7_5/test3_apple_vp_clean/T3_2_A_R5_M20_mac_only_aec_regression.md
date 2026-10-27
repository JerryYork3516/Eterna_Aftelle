# R5-M20 · Mac-only AEC自动回归v0.1离线准备

**离线实现与回归通过；设备预检BLOCKED。真实Capture、播放、录音、App运行均为0次。** 当前默认输入、输出都是非目标蓝牙设备，系统输入53%、输出75%；没有改动任何设备设置。目标仍是TinyUSB系统输入60%、Mac mini内置扬声器55%、未静音。因此本轮不请求设备批次授权，不产生声学结论。

## 1. Git与冻结身份

起始HEAD、upstream与实时远端均为`2390e6b2a8dd769bfaaa1aa45f51f7a65e1c9e32`。沿用已登记干净隔离Worktree，本地分支跟踪`origin/Test3-AppleVP-Clean`。跨文件修改前建立空回滚提交`53bd57b8a51435bc1117fd87c132d9218cdee82f`。最终代码SHA为包含本报告的交付提交，推送后另行核验三方一致。

| 冻结对象 | SHA-256 |
|---|---|
| `AppController.swift` | `0bc15faf70b0aa3dea05d8e92c1011d911a942234865a82b3e067b36e41b0ec8` |
| `ContentView.swift` | `a700e62ceb4687139053dc01d5f5f978c5c555c9d5b58410e67447131d759b4f` |
| Debug dylib | `9992d3b86a02920669aa471d03a72610b6c0260d7ff444c03f3547afdc80e635` |
| App启动器 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| `m20_echo.py` | `f9363dd62100563fe80c5693b4889dea65e60f7c99c2a36715feb8f4c46b49ae` |
| 固定居民WAV | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` |

居民源经完整SHA和WAV解析核验：24kHz、Mono、PCM16LE，114032 frames，4.751333秒，原1秒静默前导保留。没有生成、替换或提交音频。`MacSpeechAudioCapture.swift`的SHA仍为M19的`5ddaa6e05e5f6c6c6a6dcc11e4d681da7ab94a2fb8013e92b4a23a61faa92313`，M02/M04/M12/M19能力保留。

## 2. 最小控制适配

- `AppController.swift`：新增DEBUG `AppleVPMacAECBatchRun`，参数限定batch UUID、1–3轮及当前轮次；`prepareAppleVPAcousticTest`/`acceptsMacAECPreparation`只允许A、RECORDING、AGC-ON、WARMUP_4S、15秒评分及720KB上限。不能混入BT、人声C、silent-smoke、AGC-OFF或其他素材；同一App生命周期不能再次Capture。Stop在准备阶段也能撤销本轮。
- `ContentView.swift`与两个既有语言资源：显示batch UUID和轮次、固定设备/素材/19秒计划/本地留存范围；保留原Start确认及每次显式JSON/WAV导出。活动App的Stop终止本轮；外部控制器的取消或私有`STOP`标记终止整个批次。
- `integration.py`：复用原管道与`SingleRun`时钟合同，增加M20身份验证、确切PID的原UI回调和取消检查。M20不启动或验证蓝牙播放器，不运行REF；只读取已登记原控制器源码。
- `m20_batch.py`：默认入口拒绝设备执行。未来明确授权后，一个冻结计划绑定唯一私有证据目录，排他创建授权消耗记录；即使首次设备/SHA预检失败也不复用。最多依次3轮，各自新App/PID、独立RunID。每轮重新核验设备与冻结文件，完成原UI导出和确切PID退出，确认I/O释放后分析、再进入下一轮。声学检测到回声可以继续对照；任何身份、权限、配置、导出、取消或清理失败停止余下批次，不重试。
- `prepare/start/stop_host_original_ui.applescript`复用已验证原操作，`finish_host_original_ui.applescript`原样保留。只操作所持PID；退出仍精确选择Aftelle App菜单及完整Quit标题。取消时优先原Stop/封存；无法安全操作原窗口时，只回收所持子进程并保留失败。未执行这些脚本的设备操作handler。

未来执行使用`m20_batch.py --plan <本批私有计划> --evidence <计划绑定目录> --authorize-batch '授权开始M20单批3轮AEC测试'`。该参数只记录操作者已获得的新同意，不能产生授权。当前没有有效设备计划或授权消耗记录；不会因本次准备自动运行。每轮原App确认仍须真实显示并合法完成，不以JSON或旧同意回执代替。

## 3. 固定评分及边界

`m20_echo.py`仅在App退出后本地处理新评分WAV；音频只在内存分析。24kHz PCM16样本按32768归一化；保留现有M19的VP后Native ch0 16kHz与最终PCM 24kHz同内容时间20ms行，复核PCM行确实对应保存WAV。Native不是ADC Raw，不新增Native录音或Tap。

参数在首轮验证前固定，后续未修改：

| 项目 | v0.1固定值 |
|---|---|
| 居民模板 | 源[1.00,4.75)秒，90000 samples |
| 主搜索 | Player首非零内容时间−0.10至+0.65秒，逐样本去均值NCC |
| 错位检查 | 全局候选起点[0,10.5]秒；强匹配落在主搜索外则INCONCLUSIVE |
| 负控 | 相同模板倒序、WAV尾部9–10.1秒候选起点、无回声与静音参考 |
| 检测到回声 | 绝对NCC≥0.25；超出反向/尾部负控≥0.10；20ms包络相关≥0.35；播放及延后800ms范围能量占比≥0.70；该范围RMS>−50dBFS |
| 未检测到 | 主及全局绝对NCC<0.12，播放范围RMS≤−50dBFS，且所需技术/时间证据可信 |
| 其余结果 | INCONCLUSIVE，不调整阈值 |

波形分析秒数以实际保存WAV起点为原点，Render内容时间换算到同一原点；Native/PCM配对仍用绝对内容纳秒，不把WAV首字节冒充score t=0。合成已知位移定位误差≤1个24kHz样本（约41.7µs），不是物理起音精度。主搜索假设不能覆盖所有真实声学延迟或非线性处理，v0.1没有实测误报率、漏报率或可懂度保证。参数参考既有[M10报告](T3_2_A_R5_M10_echo_residual_difference_review.md)，本轮没有读取历史麦克风WAV或私人Manifest。

有限性、身份、时钟、SRC/短窗配对、完整模板覆盖或Render观察不足时返回INCONCLUSIVE。读取失败不使用默认值伪造运行态；Native/PCM持续满幅比例>1%作为停止剩余轮次的保护，不是AEC评分门槛。WAV不足14秒不能形成有效模板评分；跨评分边界包及Converter尾部继续如实排除，不补零。

**三个标签仅描述当前检测证据。`ECHO_NOT_DETECTED`始终保留`aec_acceptance=UNVERIFIED`、`physical_emission=UNVERIFIED`。** 全零麦克风也可能得到该标签，不能证明扬声器已发声。软件Render、dataPlayedBack、设备在线和正确VP属性均不能单独替代物理证明；未来如需现场见证，优先一次询问批次见证，并分别保留各轮证据限制。不计算ERLE，不做ASR/DTW，不推断Apple内部AEC参考。

## 4. 实际离线验证

| 验证命令/范围 | 实际结果 |
|---|---|
| `M20_RESIDENT_WAV=<固定非私人源> bash tools/realtime_interruption_evidence_tests/check.sh m20-only` | 最终exit 0，248 checks；真实设备访问0。19秒Fake处理、750个评分包/720KB、预热不留存、原录音/扬声器同意、错误素材/拒绝权限/Stop及清理；M19 RECORDING/STATS_ONLY导出不退化 |
| `bash tools/speech_aec_host_tests/check.sh m19-only` | exit 0，354 checks；设备与系统查询0，统计器行为不变 |
| Python unittest：`test_m20`、`test_m20_fixture`、`test_m20_control`、`test_m07`、`test_failure_evidence`、`test_original_ui` | 最终exit 0，41 cases，2.070秒。合成正负控、实际固定居民的内存合成回声、原管道Fake、旧控制/失败保全/精确菜单回归。旧协议候选SHA仅在Fake测试注入，实机入口独立锁定本次M20 SHA |
| `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug -destination platform=macOS -derivedDataPath <受控目录> -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build` | 1次，exit 0，17.094秒，未启动App |
| 同上，`-configuration Release`及独立构建目录 | 1次，exit 0，30.970秒；Release符号/字符串无M20类型和启动参数。新增语言资源不产生Release测试入口 |
| 四份原UI脚本`osacompile` | exit 0，仅编译；菜单选择器的离线handler测试未执行窗口操作 |
| 增量SwiftFormat 0.63.1 / SwiftLint 0.65.1 | 新增规范违规0。三个文件历史Lint计数分别80/76/12，未清理；Fake编译的历史并发警告保留 |
| Release Route / Architecture / Secret Guard | 各1次，均exit 0；完整回执留本地 |

最终Python运行覆盖：错误/旧授权拒绝，绑定目录不可改绑，第四轮拒绝，初次预检失败消耗授权，重复RunID拒绝，取消/EOF/错时钟/外来事件/错误SHA/输出清理失败终止；原UI在Fake PID上失败时保全证据。

准备失败记录均保留本地：①最初弱合成回声低于既定−50dBFS界限，测试却要求检测成功；更正为检测下限INCONCLUSIVE用例，参数未改。②Fake提前STOP测试漏接其即时模拟的`subprocess.TimeoutExpired`；补齐失败断言，没有放宽运行控制。③只读预检遇到非目标蓝牙设备的标量字符串UNKNOWN，初版数值比较抛TypeError；补充明确的目标路线和数值类型拒绝，仍判BLOCKED。没有真实录音失败或自动重试。

## 5. 设备预检与停止

CONFIRMED：当前默认输入/输出均非目标蓝牙设备；系统音量53%/75%，HAL输出标量UNKNOWN；设备在线且未运行，没有Aftelle/REF/代理实验实例。Cache目录0700、文件0600检查通过。没有调整音量、默认设备、静音或Mic Mode。没有打开任何麦克风流、播放、申请系统权限、读取私人录音或上传音频。

UNKNOWN：冻结App当前TCC状态无法从外部可靠读取，原合法权限门禁保留；实际加载身份、Engine运行态VP/AGC/Mic Mode、进程方向设备、配置事件和短窗实际结果都必须等未来新授权运行，不能借用M19-D1值。没有物理发声证明或本轮声学数据。

唯一下一步：恢复目标默认设备及60%/55%条件后，仅重新做只读预检；通过后再单独请求本批最多3轮授权。当前不会显示“全部准备完成，授权开始”的执行询问。

## 6. SELF_REVIEW与交付边界

| 维度 | 结论 |
|---|---|
| 范围 | PASS；现有唯一Capture/Engine/Tap/M19链，未新增音频框架 |
| 安全与同意 | 离线PASS；默认禁用、固定上限、原确认/显式导出与确切PID清理；当前设备BLOCKED |
| 数值证据 | 合成PASS；真实声学/物理发声与检测误差率UNKNOWN |
| 回归与Release | PASS；Debug/Release各一次，新增规范问题0 |
| 隐私与Git | 仅代码、最小测试、脱敏报告；原7冲突、索引与14项未跟踪证据保留；无音频、UID、私人JSON或日志入Git |

CRITICAL=0；MAJOR=1（设备路由/音量不满足）；MINOR=2（检测器缺少实机误差校准、原UI/权限及物理证据仍待授权验证），均不定义为AEC代码根因。

Stage7 Forbidden Checklist：PASS；无六红线、Runtime API、DR schema、Provider、RuntimeCore、新平台或Stage8变更。没有修改AEC/AGC/NS、Converter、AudioGraph、时钟容差、正式声源/中断Gate或M18-E01。没有Formal Test3或真人双讲验收。

```ini
M20_OFFLINE_IMPLEMENTATION=PASS
DEVICE_PRECHECK=BLOCKED_TARGET_ROUTE_AND_VOLUMES
M20_OFFLINE_READY=false
BATCH_DEVICE_RUNS=0
BATCH_EXECUTION=BLOCKED_BEFORE_USER_AUTHORIZATION
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=DEFERRED
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
