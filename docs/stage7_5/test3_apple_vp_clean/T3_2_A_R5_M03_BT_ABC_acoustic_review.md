# T3.2-A / R5-M03 · Bluetooth A/B/C单批次审核

日期：2026-10-20。schema_version：1。

**本轮BLOCKED在离线控制验证，A/B/C实际录音均为0次，没有新的声学结论。** 设备、素材只读检查成立；新增DEBUG控制的Swift Fake通过，外部控制器14项中13项通过、1项测试夹具错误。任务限定一次Fake验证，未重跑，未将部分通过作为设备准入。

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
