# T3.2-A / R5-M03 · Bluetooth A/B/C单批次审核

日期：2026-10-20。schema_version：1。

**最新批次已实际执行A/B/C各一次，取得三份本地录音；整体PARTIAL，不能宣布声学PASS。** A/B完成原评分流程；C在quiet阶段因Input内容时钟校验失败安全停止，未完成整个15秒评分。A出现居民模板残留特征及数字满幅；C相较B的代理语音匹配减弱。三组均已封存、显式导出、退出并释放设备，未追加录音。用户试听PENDING。

第1–7节保留初次交付`e5e6af8c6efcc16069eaee3598acf7d20a978af1`的失败记录，第8节保留`e91a123f6fde633fe054f5372410f4acc06d58f7`的采集前取消记录；**第9节为用户再次明确要求重新开始后的实际结果**。历史零录音状态不代表本次批次，也未被覆盖或改写为成功。

## 1. Git、构建与范围

开始时隔离工作区干净，HEAD / upstream / 实时远端均为：
`33ecc8e24cc69bc5b201f3f499525d58ee9cae16`。
跨文件修改前建立本地回滚点：
`91b4400b21fdffe6642620ac68d20225eb1bb7b3`。
源码候选是该回滚点加本轮补丁，不能只用回滚点代表最终源码。交付commit由Git及最终回复给出。

继续使用既有干净隔离工作区，推送目标为`Test3-AppleVP-Clean`。原工作区7个冲突、索引、暂存/未跟踪清单与原保护快照一致；没有操作ACE3、stash/pop、reset/clean或强推。

| 最终Debug产物 | SHA-256 |
| --- | --- |
| App主可执行文件 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| `Aftelle.debug.dylib` | `6f81387668c4625c88f80895778dad46e4a8a39badde25ad95527ae4492e2eef` |
| 复用R3蓝牙播放器，未重建/运行 | `ff47b7a948fde6cc47c96ffdee30822563c89abc32e94419390942e213d037d8` |

构建前后源码摘要一致。最终AppController SHA：
`d3170ef3cf9cd430088c484ece9dc3a6212800937b3b86bbf0d9114e91e3c827`；
ContentView SHA：
`3a038ee92874ba3c9d9afc8bc317e51f2503de53417a8b228e46f98370012704`。

M02修复原样保留：AcousticEchoHost SHA
`4a6153bca24c5bf237247374c05b9524443371e83e7ad71811957e9bb6cde8fe`；
AudioCapture SHA
`c2385929dcda156c45095b4cc7f52f862c77ff5b79067662527b9a4a1f496ca1`。
两文件本轮均无修改。旧R4 dylib登记保留；M03使用独立精确SHA，未删除二进制校验。

## 2. 一次只读预检

| 项目 | 实际结果 |
| --- | --- |
| TinyUSB | USB、alive=1、running=0、默认输入；系统枚举16kHz/1ch，输入60% |
| Mac mini内置扬声器 | alive=1、running=0、默认输出；48kHz/2ch，55%、未静音 |
| 小爱音箱 | Bluetooth、alive=1、running=0、44.1kHz/2ch；UID与原播放器登记匹配，未公开UID |
| 小爱音量 | 当前接口UNKNOWN；未改变设置，不能称绝对声压已校准 |
| Aftelle/REF/代理残留进程 | 无；定点pgrep exit1代表无匹配 |
| 受控Caches | 本人所有、0700、无symlink、可写；检查时可用空间约2.38GB |
| 系统Mic Mode | UNKNOWN；没有切换或猜测 |
| 本轮App自身权限、运行时VP/AGC | NOT_RUN / DEVICE_UNVERIFIED；在离线门禁停止，未启动App查询或请求新权限 |

设备枚举格式不是Apple VP启动后的Native格式。本轮没有Input/Output VP、AGC、bypass、inputMuted实机读回，不使用旧结果填充。

| 固定非私人素材 | SHA-256 | 实际格式/长度 |
| --- | --- | --- |
| 居民 | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` | 228108 bytes；24kHz/Mono/PCM16LE；114032帧，4.751333秒；首1秒全零 |
| 原代理`REF_proxy.wav` | `1c7081f8271251804e01234be8a0ff8344062d09c311592634cb8fdf6b992d0a` | 528698 bytes；24kHz/Mono/PCM16LE；264310帧，11.012917秒；首秒有非零内容 |

没有重合成、转换、替换或更改素材增益；没有用R4带4秒静默的HOST代理冒充原代理。

## 3. 最小DEBUG适配

- `AppController.swift`：增加显式`--apple-vp-bt-abc=A|B|C`登记和Prepare冻结，限定AGC-ON / WARMUP_4S / RECORDING。沿用原综合C时钟、持续drain、15秒评分、720000字节上限、跨界包排除及Stop/Seal/导出。B仍Prepare原OutputHost，但不排程居民；A/C原播放策略不变。
- `ContentView.swift`：仅在上述DEBUG参数下显示本组Prepare；原Start采集/录音确认和JSON/WAV显式导出确认保留。未新增自动授权或绕过系统权限。
- `integration.py` / `m03_once.py`：复用原SingleRun、管道循环和R3播放器。A不启动代理进程；B/C明确选原登记`REF_proxy.wav`，不是改名替换。事件绑定M03组别与原RunID，使用原mach_absolute纳秒及50ms控制迟到限制。
- 每组尝试排他登记，前一组完成并有安全释放审核后才允许下一组；默认设备启动禁用，R4同意字符串不能授权M03。取消/异常继续原STOP、终止和回收路径。
- 对应测试复用现有D1 Fake和R3 Fake子进程，不引入HIL框架、音频Engine、Tap、DSP、Gate或新的音频状态Owner。

本轮没有修改生产转换、channelMap、AEC/AGC/NS算法、RuntimeCore、Provider或正式插话链。普通综合C、silent-smoke不进入新的M03参数分支；未执行它们的完整回归，不能将源码隔离称为全矩阵回归PASS。

## 4. 一次Fake验证及阻塞

| 实际命令 | 次数 | exit / 结果 |
| --- | ---: | --- |
| `bash tools/realtime_interruption_evidence_tests/check.sh m03-only` | 1 | 0；7 cases / 251 checks，30.233秒 |
| `python3 -B tools/reference_host_comparison/test_m03.py` | 1 | **1**；14 tests，13通过 / 1 error，0.248秒 |

以上是同一轮离线门禁的App和外部控制器两部分，不是实机运行。

Swift验证三组分别950个合成20ms包持续处理，预热200包不留存，评分750包/720000字节；A/C居民各一次、B零次；schedule/stop组别和内容时钟、冻结配置、清理、缺管道、取消、满管道/断管道及跨界包负控通过。所有音频均Fake/合成数据。

Python通过A/B/C事件链、A零代理进程、B/C原代理身份、PLAY/STOP各一次、错误组别/RunID、迟到、时钟异常、缺失/重复事件、EOF、取消、错误二进制及默认禁用。**重复启动禁止用例尚未完成验证**：

```text
test_one_attempt ... ERROR
ValueError: owned 0700 evidence directory required
```

该用例的TemporaryDirectory返回含`/var`别名的路径；入口按现有安全约束要求`path.resolve() == path`，在进入预期单次登记断言前拒绝。确认是**测试夹具路径错误**，不是设备异常或声学根因；安全检查没有放宽。

已将测试夹具改为`Path(root).resolve() / "A"`。该单行修正后**NOT_RERUN**，遵守本轮一次Fake预算。不能据代码推断宣布14/14 PASS，也不能以其他13项通过代替这个缺口。新设备入口候选仍未通过完整离线门禁。

失败日志SHA：
`2a77745c9064666bf5346e8712279e0ec25dd20c23513c17a15e999b686d15f6`。
Swift日志SHA：
`0f858bf33b4264a6b18baab23a98f4218ae0ffade1fa7291bdfd752aaeafd204`。
完整命令、源/产物摘要和日志仅保存在Git忽略的`.build/r5_m03/`。

## 5. 构建、Guard与增量规范

实际Debug构建命令：

```sh
xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle \
  -configuration Debug -destination platform=macOS \
  -derivedDataPath .build/r5_m03/DerivedData \
  -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
```

执行3次，均exit0：初版18.234秒；局部复杂度/格式修正后5.663秒；最终冻结构建5.194秒。没有启动App。前两次产物未用于设备，最终以本报告登记的dylib为准。最终构建日志SHA：
`c2dc6225f0e403d5609f782735bc80e8cf3ed4b0ce481447e4e4c4608d0c64e4`。

Release Route、Architecture、Secret Guard各执行一次，均exit0；无FULL_CURRENT、Release整App构建、HIL或声学重试。Release Guard验证源码投影隔离，不冒充新Release二进制实测。

SwiftFormat / SwiftLint基线各一次、候选各三次，仅修正本轮新增范围。最终分别7094 / 166个历史finding，与基线相同；新增finding及修改行finding均0。全文件exit分别1 / 2，历史FAIL及C19/C23债务保留，新增B类问题0。没有全库格式化、禁用规则或调低门槛。

## 6. A/B/C执行与声学证据

| 项目 | A居民独讲 | B近端代理独讲 | C双讲 |
| --- | --- | --- | --- |
| App/Engine实机启动次数 | 0 | 0 | 0 |
| 麦克风录音/居民播放/BT播放 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| RunID、本地WAV/JSON | 未生成 | 未生成 | 未生成 |
| 控制链实机结果 | NOT_RUN | NOT_RUN | NOT_RUN |
| Native/保存WAV分窗统计 | NOT_RUN | NOT_RUN | NOT_RUN |
| AGC/VP、callback、drop/stale/reject/fallback | DEVICE_UNVERIFIED | DEVICE_UNVERIFIED | DEVICE_UNVERIFIED |
| 物理覆盖、尾包、可懂度、回声/人声保留 | NOT_EVIDENCED | NOT_EVIDENCED | NOT_EVIDENCED |

总真实采集0秒。没有读取历史私人音频，没有公开上传音频、原始Manifest、设备UID或完整设备日志；没有转录或代替用户试听。

本轮不能比较B/C的0–3秒、4–7.75秒或A/C的共同窗口。Native损伤、后级转换额外损伤、仅双讲变化均UNKNOWN，不能复用历史数据制造本轮结果。未来同窗比较仍须分别计算Native统计、全部drained统计和真正保留WAV样本；没有的Native细分窗不得由整窗RMS代替。

`SOURCE_REFERENCE_ISOLATION=UNKNOWN`。软件PLAY时刻不等于蓝牙物理起音，同Mac代理仍不能替代独立真人近端证据。

## 7. 五维审核、问题等级及下一步

| 维度 | 结论 |
| --- | --- |
| 功能 | PARTIAL：App Fake通过，外部单次登记测试未完成；实机未准入 |
| 安全/隐私 | PASS：失败时停在设备启动前；零实际音频，原系统/UI同意及导出门禁未绕过 |
| 证据 | PASS_FOR_BLOCKED：明确保留exit1、修正后未复核、零RunID和UNKNOWN，不伪造声学PASS |
| 工程/增量规范 | PARTIAL：最终Debug构建及三Guard通过，新增B类0；完整Fake门禁未通过 |
| Stage7 Forbidden Checklist | PASS：无新平台、DR schema、Runtime API、正式Gate、Provider所有权或Stage8变更 |

新增CRITICAL=0、**MAJOR=1：M03离线准入尚未闭合**、MINOR=0。未发现新的生产声学缺陷，不能把测试夹具错误解释为Apple VP或AGC异常。

唯一下一项建议：主控允许一次受影响控制器复核，验证已修正夹具的单次登记/拒绝第二次启动；通过并重新确认易变设备条件后，再决定是否重新授权设备批次。本轮不消耗设备次数，也不把尚未执行的录音自动留给后台继续运行。

```ini
R5_M03=BLOCKED_OFFLINE_CONTROL_GATE
M03_SWIFT_FAKE=PASS
M03_CONTROLLER_FAKE=FAIL_13_OF_14
M03_FIXTURE_PATH_CORRECTION=APPLIED_NOT_RETESTED
READY_FOR_DEVICE_BATCH=false
A_DEVICE_RUNS=0
B_DEVICE_RUNS=0
C_DEVICE_RUNS=0
USER_LISTENING=NOT_REQUESTED_USER_ABSENT
SOURCE_REFERENCE_ISOLATION=UNKNOWN
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```

## 8. 修正后续跑：离线门禁通过，实机批次在采集前停止

### 8.1 身份与复核

续跑开始时HEAD / upstream / 实时远端均为：
`e5e6af8c6efcc16069eaee3598acf7d20a978af1`，隔离工作区干净。
只复核受影响的Python控制测试，没有重复Swift Fake、构建、FULL_CURRENT或声学测试，也没有修改源码、二进制或门槛。

| 检查 | 续跑实际结果 |
| --- | --- |
| `python3 -B tools/reference_host_comparison/test_m03.py` | 追加1轮，**14/14 PASS，exit0，0.277秒**；包含单次登记及拒绝第二次启动 |
| Debug App / dylib、AppController / ContentView、M02 Host摘要 | 与第1节冻结值一致；运行中`lsof`也定位到本次候选App及dylib |
| 素材 | 两份SHA、格式、帧数和居民首1秒全零均与第2节一致 |
| TinyUSB / Mac / 小爱 | 在线；默认路线匹配，开始前均running=0；输入60%、输出55%、未静音；小爱UID匹配但音量UNKNOWN |
| 目录 | 本人所有、0700、无symlink、可写；可用空间约2.11GB；新批次目录不覆盖历史结果 |
| 原冲突工作区 | 续跑前后均7个冲突，status和索引摘要与保护快照完全相同 |
| 文档/隐私 | `git diff --check`、单文件白名单及私人字段检查通过；本次Secret Guard追加1轮exit0 |

追加测试使用既有R3 bundle和本次冻结HOST可执行文件；REF变量为`NOT_USED_M03_NEVER_STARTS_REF`，Fake不启动设备。通过日志SHA：
`ab0d51b544d8b964dec1819d6cc17fce75062ddd9908e2ca10c6d6e8ef62b68f`。
上轮失败日志继续保留，累计Python控制测试2轮：先exit1，修正后exit0。

### 8.2 实际启动、操作错误与停止

仅调用一次：

```sh
python3 -u -B tools/reference_host_comparison/m03_once.py --group A \
  --consent R5_M03_ABC_ONCE_LOCAL_RECORDING_AND_ANALYSIS \
  --bundle .build/reference_host_r3/candidate1 \
  --executable .build/r5_m03/DerivedData/Build/Products/Debug/Aftelle.app/Contents/MacOS/Aftelle \
  --evidence '<本机0700新批次目录>/A'
```

命令通过精确二进制/素材校验，排他登记A尝试，并启动正确DEBUG实例。执行员按已授权AppleScript操作原Prepare及文件选择UI。所见状态为`phase=ready`、`run=UNKNOWN`、`packets=0 bytes=0`、VP/AGC未读回；尚未核验完成素材选择，未点击原采集确认。

文件选择操作未按预期完成后，执行员错误使用`cua.getApp("Aftelle")`读取界面。该名称被解析到另一份本机普通Aftelle安装产物，工具启动了它。随后`ps`确认存在正确DEBUG实例和错误普通实例两个进程。这是**确认的执行员应用定位错误**，不是Apple VP、M02隔离修复或声学代码根因，也不是无害的成功UI读取。

发现后立即按进程命令身份核验并向错误普通实例及A控制器发送SIGTERM；控制器原取消清理路径回收DEBUG子进程。A执行器**exit1**，回执：

```text
status=FAIL
error=M03 operator cancellation
events=[]
commands=[]
```

没有删除或重置`M03_A_consumed.json`，没有伪造前组`release.json`，没有自动重试A。B/C目录和尝试标记均未创建。

| 实际执行项目 | A | B | C |
| --- | ---: | ---: | ---: |
| M03入口调用 / 正确DEBUG App启动 | 1 / 1 | 0 / 0 | 0 / 0 |
| 原采集确认 / 实验麦克风采集 | 0 / 0 | 0 / 0 | 0 / 0 |
| 居民播放 / BT代理播放 | 0 / 0 | 0 / 0 | 0 / 0 |
| 实验RunID / 新录音JSON/WAV | 无 | 无 | 无 |
| 实机控制结果 | FAIL_BEFORE_CAPTURE | NOT_RUN | NOT_RUN |

另有1次错误普通App启动，不能隐去或算作正确隔离运行。未操作它的开始按钮，未读取其私人内容；未进一步调查其内部初始化副作用，因此不宣称这次操作完全满足隔离要求。

清理复核：相关进程定点查询exit1（无匹配），TinyUSB/Mac/小爱均`running=0`；默认设备与音量不变。原Caches除本批次目录外无新增条目；批次仅保存0600的尝试登记和失败控制回执，没有录音。没有请求或自动接受新的系统麦克风授权。

A失败回执SHA：
`011fb37d56288b92344e890b18d1c10dc8521a010bc95b0c62c30b0d34cd46b8`。
清理证据SHA：
`b976567a11d521177ae2250b8cf4ebce4a44d06c9e97a2fda1f05fa672179785`。
原始执行命令、PID、路径和设备字段仅留本机，不进入公开报告。

### 8.3 判定、审核与剩余工作

原离线夹具MAJOR已解决；**新增MAJOR=1：UI按名称定位误启普通实例，批次执行失败**。新增CRITICAL=0、MINOR=0。没有新的生产源码缺陷证据，没有任何Native/WAV分窗、回声、人声保留或同窗A/B/C比较结果。

| 五维SELF_REVIEW | 结论 |
| --- | --- |
| 功能 | BLOCKED：离线14/14通过；正确App仅到Prepare，三组录音未完成 |
| 安全/隐私 | REWORK：误启动普通实例属于执行范围偏离；已停止全部、释放进程/设备，无新录音上传或权限绕过 |
| 证据 | PASS_FOR_FAILURE_REPORT：保留原exit1、修正exit0及新取消exit1，区分App启动与录音次数 |
| 工程/增量规范 | 本次仅改报告；冻结构建和已通过Guard证据复用，新增源码B类0，历史债务未改 |
| Stage7 Forbidden Checklist | REWORK：架构、Runtime API、DR schema、平台及Stage均未变；执行隔离失败已如实登记，禁止把它记为整任务PASS |

后续操作纠正必须绑定控制器返回的**确切PID和已核验可执行路径**，在UI原确认前复核窗口归属；不得再以显示名称`Aftelle`获取可能自动启动其他安装的应用。本次没有更改应用权限或生产逻辑来解决界面问题。

唯一下一项建议：主控审核本次停止记录后，另行决定是否恢复该受控批次；若恢复，沿用按PID的原UI流程，保留新的单次登记和全部安全门禁。本次不自行清空尝试标记或追加采集。

```ini
R5_M03=BLOCKED_UNEXPECTED_PROCESS_BEFORE_CAPTURE
M03_CONTROLLER_FAKE=PASS_14_OF_14
M03_FIXTURE_PATH_CORRECTION=VERIFIED
A_ENTRY_ATTEMPTS=1
A_CAPTURE_RUNS=0
B_CAPTURE_RUNS=0
C_CAPTURE_RUNS=0
UNEXPECTED_ORDINARY_APP_STARTS=1
CLEANUP=PROCESSES_EXITED_DEVICES_NOT_RUNNING
USER_LISTENING=NOT_REQUESTED_USER_ABSENT
SOURCE_REFERENCE_ISOLATION=UNKNOWN
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```

## 9. 再次授权后的单批次实机结果（当前结论）

### 9.1 身份、操作纠正与执行范围

用户再次要求“重新开始，未完成实验不要停止，并且完成后让我试听”。本次开始时隔离工作区干净，HEAD / upstream / 实时远端均为
`e91a123f6fde633fe054f5372410f4acc06d58f7`。运行源码、App/dylib、M02 Host及两份素材摘要逐项匹配第1–2节登记；本次未重建、未修改源码或阈值。最终提交仅更新本报告。

纠正的是UI执行方式：只对控制器返回的确切PID操作原界面，使用`lsof`核验实际App及dylib；不再按应用显示名称获取/启动实例。AppleScript仅操作原Prepare、文件选择、采集同意、分别导出JSON/WAV及Quit。文件列表标题行和AppleScript保留变量名问题在采集前修正，没有增加App或Capture次数。本批普通Aftelle误启动0次；第8节旧失败和尝试标记保留。

一次准备复核确认TinyUSB输入60%、Mac内置输出55%未静音、小爱在线且UID匹配；未修改默认路由、系统音量、Mic Mode、播放器音量或素材。三组运行后均核验进程退出、设备`running=0`及相同路由/音量，再决定是否进入下一组。Mic Mode、小爱绝对音量/声压和摆位校准仍UNKNOWN。App沿用已取得的系统权限，没有新TCC请求或自动操作系统授权。

| 本批实际项目 | A：居民独讲 | B：BT近端独讲 | C：双讲 |
| --- | --- | --- | --- |
| RunID | `F60F1D2A-4B68-4A05-8260-5BC567F71721` | `44430CFD-991C-46B2-8446-E400A77A9FD1` | `DFF89229-7E56-42D9-A8AF-ECAA9EC0EBE6` |
| App / Capture次数 | 1 / 1 | 1 / 1 | 1 / 1 |
| 居民start / completed | 1 / 1 | 0 / 0 | 1 / 1 |
| BT PLAY / STOP | 0 / 0；无代理进程 | 1 / 1 | 1 / 1 |
| 外部控制器 / App退出码 | 0 / 0 | 0 / 0 | 0 / 0 |
| App实验错误 | 无 | 无 | `voice_processing_unverified`，见9.5 |
| 实验控制结果 | PASS_WITH_TAIL_LIMITATION | PASS_WITH_TAIL_LIMITATION | **FAIL_EARLY_CLOCK_REJECTION** |
| 保存评分WAV | 14.86秒 | 14.86秒 | **13.36秒，部分结果** |
| Stop / Seal / 导出 / Quit / 释放 | 完成 | 完成 | 安全停止后完成 |

三份外部回执均写`CONTROL_COMPLETED_DEVICE`；这只表示外部执行循环和进程退出完成，**不能覆盖C的App失败状态**。C释放审核明确`safe_to_continue=false`。未重试、未执行第四次采集。

三组Capture启动返回至停止分别19.004546、19.014272、17.515729秒，合计55.534547秒。A/B相对19秒名义deadline有4.546/14.272ms停止调度尾差，不能写成精确19.000秒。以更早的`engineStartBefore`至停止计算，三组总跨度56.086780秒，仍小于57秒整批上限。Native实际记录内容分别18.9、19.0、17.5秒。

### 9.2 实机配置与真实软件时间

三组实际读回均为Input VP=true、Output VP=true、AGC=true、bypass=false、inputMuted=false；Capture/Playback generation均1、configurationID均2。原生Input与Output为16kHz/3ch非交错Float32；Output ASBD flags=41、layoutTag=9633795、descriptionCount=0。最终评分WAV为24kHz/Mono/PCM16LE。

每组configuration事件仅准备与Shutdown各一次，route事件0；没有运行中身份变更。三份JSON的`source_commit`/`build_identity`为null，因此源码/构建身份由本次外部SHA、启动参数、PID和映射文件核验绑定，不能称JSON本身已携带完整构建身份。

以下均相对评分内容边界，单位秒；负值处于预热。调用、回调到达和内容时间分别列出，不是物理声学起止。

| 实际事件 | A | B | C |
| --- | ---: | ---: | ---: |
| Engine.start调用前 / 返回 | −4.186296 / −4.000663 | −4.182950 / −4.001179 | −4.182987 / −4.000824 |
| Capture启动返回 | −4.000000 | −4.000000 | −4.000000 |
| 首Input callback到达 / 内容 | −3.872991 / −4.004802 | −3.874039 / −4.005276 | −3.873030 / −4.004199 |
| 四阶段实际提示 | 0.026161 / 3.002102 / 9.024391 / 11.024079 | 0.015652 / 3.017713 / 9.001272 / 11.017524 | 0.009248 / 3.008228 / 9.008030 / 11.023871 |
| 居民Player.play调用前 / 返回 | 3.047742 / 3.069064 | 未调用 | 3.061927 / 3.069538 |
| 居民Playback completed | 7.941620 | 未播放 | 7.938650 |
| Player Render首末非零内容 | 4.197262–7.944915 | 无非零Render | 4.197871–7.945535 |
| 代理PLAY调用前 / 返回 | 不适用 | 0.000771 / 0.329165 | 0.000084 / 0.403865 |
| 代理STOP调用 | 不适用 | 11.000964 | 11.000305 |
| Capture停止 | 15.004546 | 15.014272 | **13.515729** |

三组预热Native分窗覆盖约4秒，持续Converter/drain，未保留预热PCM、未重启Engine或重置generation。BT软件PLAY及时发出，但返回耗时约329/404ms；真实物理起音/停止和Apple处理延迟未校准。Player Render不等于扬声器实际发声，也不等于Apple内部AEC参考。`SOURCE_REFERENCE_ISOLATION=UNKNOWN`。

### 9.3 Native、drain、保存内容与尾部

| 证据 | A | B | C |
| --- | ---: | ---: | ---: |
| Native buffers / frames | 189 / 302400 | 190 / 304000 | 175 / 280000 |
| generated / drained / queued | 944 / 944 / 0 | 949 / 944 / 5 | 869 / 869 / 0 |
| 预热不留存包 / 跨界排除包 / 窗外排除包 | 199 / 1 / 1 | 199 / 1 / 1 | 199 / 1 / 1 |
| 真正留存20ms包 | 743 | 743 | 668 |
| 真正留存PCM字节 | 713280 | 713280 | 641280 |
| 保存内容起止（score秒） | 0.015198–14.875198 | 0.014724–14.874724 | 0.015801–13.375801 |
| score尾部未留存 | 124.802ms | 125.276ms | **1624.199ms** |
| quiet已drain覆盖 | 3.851119秒 | 3.857200秒 | 2.351930秒 |
| Native full_scale（各声道） | 23 / 23 / 23 | 0 / 0 / 0 | 0 / 0 / 0 |
| WAV精确PCM16端点样本 | 33 | 0 | 0 |
| Capture drop / stale | 0 / 0 | 0 / 0 | 0 / 0 |
| Native拒绝 | 0 | 0 | `native_clock=1; content_time=1` |
| Playback reject / underrun | 0 / 0 | 0 / 0 | 0 / 0 |
| Input host / sample不连续 | 0 / 0 | 0 / 0 | **1 / 0** |
| Input最大相邻起点间隔 | 100.008208ms | 100.001791ms | **102.182375ms** |
| Render host / sample不连续 | 0 / 0 | 0 / 0 | 0 / 0 |
| Render最大相邻起点间隔 | 100.008250ms | 100.001792ms | 100.002791ms |
| DEBUG skip / stale callback / invalid buffer | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |

所有保存包的序号和20ms内容时间连续，没有保存WAV内部的已知缺包；**不能据此否认C最后一次内容时钟拒绝**。C的Native `coverage_valid=false`，A/B=true。所有预热留存字节0、评分留存小于720000字节。所有组`TAIL_COVERAGE=PARTIAL`、converter partial tail=UNKNOWN；queued=0也未证明完整尾部，B queued=5不自动等同真实丢帧。没有补零或改时间戳。

Manifest的`capture_state=capturing`来自停止前快照；实际停止事件、sealed、callbacksClosed、进程退出和设备`running=0`共同证明清理完成，不以该旧快照误报仍在录音。

### 9.4 声学数值：同窗比较与限制

下表只统计**真正写入WAV的评分PCM**，幅度按PCM16/32768归一化，单位dBFS；不代表声压、可懂度或用户听感。

| 评分内容窗口 | A RMS / Peak | B RMS / Peak | C RMS / Peak |
| --- | ---: | ---: | ---: |
| 0–3秒 | −91.01 / −64.29 | −18.28 / −1.98 | −17.79 / −1.58 |
| 3–9秒 | −18.99 / 0.00 | −24.38 / −9.77 | −25.94 / −7.25 |
| **4–7.75秒** | **−17.03 / 0.00** | **−24.42 / −9.81** | **−27.11 / −7.25** |
| 9–11秒 | −100.58 / −84.29 | −24.58 / −10.86 | −26.02 / −11.67 |
| 11秒至实际保存末尾 | −99.52 / −84.29 | −33.62 / −13.43 | −32.58 / −14.22 |

首窗均缺约15ms前沿；quiet末尾覆盖不同，最后一行不是完整同窗15秒比较。4–7.75秒各有90000个保存样本，精确零样本A=10886、B=3171、C=33017。C的零样本比例36.69%高于B的3.52%，但Float32量化至PCM16会产生零；Native的3–9秒精确零样本B/C均0。**不同窗口、不同量化口径的零计数不能证明Native硬静音或Converter丢帧。**

20ms评分网格的最大RMS正向绝对变化：

| 组 | 内容时间 | 相邻RMS线性值 | dB变化 |
| --- | ---: | --- | ---: |
| A | 4.640秒 | 0.067571 → 0.498430 | +17.36 |
| B | 1.100秒 | 0.199805 → 0.385148 | +5.70 |
| C | 1.160秒 | 0.185355 → 0.368758 | +5.97 |

A的33个PCM端点位于score 4.647989–4.662114秒；Native同播放大窗已有每声道23个满幅值，非有限和超范围计数均0。确认数字满幅存在，不能直接归因为AGC BUG或模拟输入硬件削波。B/C最大起音变化也可能含原语音音节包络，不能只用阶跃阈值宣布异常。

Native各声道每窗均有实际有限样本逐值比较统计：`numerically_equal_to_ch0_samples == compared_to_ch0_finite_samples`；本次所有窗成立。这比相同Peak/计数更强，但不是对Apple内部声道物理含义的证明。

以下比较同RunID、相同声明内容窗口内的**Native ch0与全部drained PCM**，不是用drained统计冒充WAV：

| 窗口 | A Native → drained PCM RMS | B Native → drained PCM RMS | C Native → drained PCM RMS |
| --- | --- | --- | --- |
| 0–3秒 | −90.990 → −91.032 | −18.3034 → −18.3037 | −17.8166 → −17.8170 |
| 3–9秒 | −18.9855 → −18.9886 | −24.3755 → −24.3758 | −25.9407 → −25.9409 |
| 9–11秒 | −100.926 → −100.582 | −24.5812 → −24.5816 | −26.0207 → −26.0213 |

B/C有声大窗的后级RMS差均小于0.001dB。Native→PCM没有显示大窗额外增益损失；A极低能量窗有PCM16量化差。现有Native仅提供0–3、3–9、9–11、quiet等窗，**没有独立4–7.75秒或20ms Native统计**，故不能把局部吞字/消音精确定位到VP前后，也不能用整窗RMS排除所有转换损伤。

固定素材辅助相关性沿用本机数值方法：去均值归一化互相关，明确时间偏移搜索；同时用倒放模板、A无代理、B无居民作负控。没有新增声学验收阈值。

| 模板 / 波形绝对NCC峰值 | A | B | C |
| --- | ---: | ---: | ---: |
| 代理源0–3秒 | 0.035（无代理负控） | 0.577 | 0.555 |
| 代理源4–7.75秒 | 0.063（无代理负控） | **0.687** | **0.294** |
| 居民源1–4.75秒 | **0.411** | 0.072（无居民负控） | 0.120 |

代理源4–7.75秒模板在输出score 4–5秒候选起点搜索，B/C最佳起点4.8026/4.8098秒，倒放负控分别0.115/0.047，20ms包络相关分别0.910/0.351。它是延迟搜索后的模板特征，不能冒充精确软件4–7.75秒的物理双讲证据。居民模板A倒放负控0.093，C倒放0.065；混合信号、相同Tingting声线、AEC频谱变化和未知声学延迟均限制声源归属。

由此支持：B/C首段都有代理内容特征；C重叠附近的代理匹配和能量分布较B退化；A出现居民来源残留的数值证据。**尚不能宣告居民可听程度、真人保留PASS、AGC因果或Apple内部参考隔离。** C较低的居民相关性也不能证明听不到回声。

居民最后非零Player Render后0–500ms：A RMS −35.51dBFS、Peak −19.90；后续500–1500ms RMS −99.63。C对应−24.78/−26.83dBFS，但此时代理仍在播放，不能全部称回声尾音。BT软件STOP后的0–500ms B/C RMS −24.73/−25.81，500–1000ms降至−81.09/−93.49；真实扬声器停止与音频处理延迟UNKNOWN。

### 9.5 C安全停止的确认路径

**CONFIRMED：Input相邻host内容时间出现一次2.182375ms偏差，触发`native_clock`与`content_time`各1次；原生sampleTime仍连续。** 最后VP/AGC实际读回均有效，`voice_processing`拒绝为0。错误字符串不能直接解释成VP关闭。

只读核对冻结源码：

- `MacSpeechAudioCapture.swift:967`的`continuousInputHostTimeLocked`按一个原生采样周期验证相邻host时间；16kHz时容差62.5µs。超出后将`sampleTimeContinuityValid=false`，后续内容时间无效，直到原generation重置路径恢复。
- 同文件`recordClock`及`prepareAppleCapture`分别记录`native_clock`和缺失内容时间的`content_time`；没有放宽容差或现场重同步。
- `AppController.swift:7974`的`collectAppleVPAcousticFrames`要求Native issues为空；此条件失败与VP读回失败共用`voiceProcessingUnavailable`错误，因此本次呈现`voice_processing_unverified`。随即走原Stop/Seal/Shutdown。

确认的是**时钟拒绝→实验安全停止的传播路径**；目前不能区分设备真实漏采、host时钟抖动或别的调度原因，不能据此确认生产BUG。该停止发生在score约13.516秒，晚于主要重叠窗，不能解释4–7.75秒代理特征退化，也不能追溯认定历史真人前三秒近静音的根因。

M02隔离补丁未改变；本轮没有旧软件AEC3 fallback导致断流的直接证据。Manifest未完整导出所有AcousticHost fallback状态，缺失项保持UNKNOWN。没有为得到PASS改DSP、时间戳阈值或重跑C。

### 9.6 本地证据、命令与检查次数

本轮JSON/WAV由原UI逐项确认导出至原受控Caches，目录0700、文件0600、当前用户所有、无symlink；每组独立RunID，未覆盖旧文件。三份WAV都只含本轮评分留存，processed数据SHA与对应Manifest匹配。Native只保留有界统计，没有另存完整Native原音；Native本身也已经过Apple VP。

| 组 | WAV bytes / SHA-256 | JSON bytes / SHA-256 |
| --- | --- | --- |
| A | 713324 / `87a0e5e91db130597e02706620e0b23584018d989fa17654665cc74dd797d44c` | 65070 / `99978f967dc9767b1c0d3c33178c062b3fd7cbc4a336ed90208ce463876b51f2` |
| B | 713324 / `ddbc4aff5073fd4d0f45498b0b757cfb8f1c293fb07dfe47da3b2c820331a9cc` | 64481 / `e497c147d9922d12bd1ea7bffc63f29658c0c31782811f99297fa3b29407feda` |
| C | 641324 / `4d61b1bfbeacfc33a02b485f86e646f6828272e02f8de9e11e8ba3e18d6b6382` | 60898 / `9c1dc95b1b0a22147d3e7c172de9583d0446a90a9850344958c52012a1864129` |

实际设备命令与第8.2节相同，分别`--group A`、`--group B`、`--group C`，每组新建独立受控子目录，调用各1次、外部exit均0；C的实验失败另按Manifest裁定。B/C代理进程退出0；原STOP回执证明`not_playing=1`，不以自然播放完成回调代替停止证据。

| 本次实际执行 | 次数 / 结果 |
| --- | --- |
| 启动前Git、冻结二进制/素材、设备预检 | 一次准备复核，PASS；组间另做停止释放与路线不变检查 |
| A/B/C UI与设备执行 | 各1次；原采集及JSON/WAV导出确认均实际完成 |
| `python3 -B .build/r5_m03/resume2/review_release.py A <A-RunID>` | 1次，exit0，允许进入B |
| 同一脚本审核B | 1次，exit0，允许进入C |
| C故障与释放审核 | 1次，进程/设备已释放；明确禁止继续 |
| `python3 -B .build/r5_m03/resume2/analyze_batch.py` | 1次，exit0；仅本轮三份新WAV和两份固定合成素材 |
| 本次Fake、Swift回归、构建、FULL_CURRENT | **0次**；未改代码，复用第4–5、8.1节真实证据 |
| 文档diff、单文件白名单/隐私检查 | 1轮，PASS |
| `bash tools/secret_guard/check.sh` | 1轮，exit0 |

本地统计结果SHA：`8c3caa45e4334a95e95cb91f48783291224686a7a7649de7d9c214016c8480f8`；
有限分析脚本SHA：`f84e5ce97f794872716034648110d0ba78bbd1131eb4309994bce8a5ab7b6408`。
沿用已有统计函数，仅提取函数定义，不执行旧脚本内历史私人音频读取。无自动播放、转录、云端音频分析或Git音频上传；对用户仅提供本机原WAV试听入口，`USER_LISTENING=PENDING`。

### 9.7 五维审核、分级与唯一下一步

| 维度 | 当前结论 |
| --- | --- |
| 功能 | PARTIAL：三组各运行一次且取得有效文件；A/B原流程完成，C内容时钟拒收提前停止 |
| 安全/隐私 | PASS：新授权、原UI/TCC门禁、限定次数与总预算、无预热录音留存、进程/设备释放；音频不公开 |
| 证据 | PASS_WITH_LIMITATIONS：区分进程exit与实验失败、Native/drained/WAV、物理时序UNKNOWN、C缺尾和试听待定 |
| 工程/规范 | 本次报告变更，生产源码0改动、M02保留；新增源码B类0，历史格式/lint及C19/C23债务不变 |
| Stage7 Forbidden Checklist | PASS：A–H逐项未越界；Runtime API、DR schema、平台target、Provider所有权、正式Human Gate和Stage状态无变化 |

本批新增确认生产代码BUG=0；**MAJOR=1：C因Native内容时钟拒绝未完成全部评分**；CRITICAL=0、MINOR=0。A数字满幅/居民残留和C代理匹配下降是本批确认数值及待听感审核的既有声学风险新证据，不把它们偷换为已确认AGC/AEC代码BUG。旧第8节误启普通App问题本批未复现，旧记录仍保留。

唯一下一项建议：主控结合本批A/B/C试听及C时钟拒绝证据审核，决定是否单独授权时钟路径的定点调查/修复；不追加设备、不先调增益或DSP。原7个冲突工作区的status、索引及未跟踪清单与保护快照一致。本次Git仅提交本报告，推送后核验三方HEAD；交付commit由最终回复及Git记录给出。

```ini
R5_M03=PARTIAL_BATCH_EVIDENCE_DELIVERED
A_CAPTURE_RUNS=1
B_CAPTURE_RUNS=1
C_CAPTURE_RUNS=1
A_CONTROL_CHAIN=PASS_WITH_TAIL_LIMITATION
B_CONTROL_CHAIN=PASS_WITH_TAIL_LIMITATION
C_CONTROL_CHAIN=FAIL_EARLY_CLOCK_REJECTION
C_SAVED_SCORING_SECONDS=13.36
ADDITIONAL_CAPTURE_RUNS=0
TAIL_COVERAGE=PARTIAL
CONVERTER_PARTIAL_TAIL=UNKNOWN
USER_LISTENING=PENDING
SOURCE_REFERENCE_ISOLATION=UNKNOWN
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
SQ-M1=OPEN
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
