# Eterna Aftelle · T3.2-A-D2-F1 · Root Cause Repair & Silent Dry Run

日期：2026-10-17（Asia/Shanghai）。**REVIEW_PENDING**。离线检查、Fake A/B/C 和当前 Bluetooth 路线各一次真实无声预演通过；原 D2 USB 麦克风＋内置扬声器路线未复验，**READY_FOR_HUMAN_TEST=false**。

## 1. Git、授权与范围

- 起点 HEAD／upstream／实时远端均为 `34f6bcf6803084d4445c13aefc19974ab2751e6c`，分支 `Test3-AppleVP-Clean`，独立 Clean worktree。staging 空；原未跟踪 D 预检报告保留、排除提交。
- 按 AGENTS 跨文件回滚要求创建本地空 checkpoint `d975923bb635d22b0d41dedb71215387a58c09a5`；没有 reset／clean／stash／切换 worktree。私有前像、命令、摘要及日志置于 Git 忽略的 `.build/t3_2_a_d2_f1/`，不覆盖 D1/R2 或首次 D2 证据。
- 本次主控明确授权离线修复、构建及短时无声设备预演；不授权真人语音保存、正式有声 A/B/C、用户试听、Provider 或正式 Human Gate。未沿用上轮有声设备授权。
- 仅修改下表源码／测试及本报告、README、DEVLOG；原 ACE3／VP 研究 worktree、RuntimeCore、Qwen Adapter、Input Bridge 中断机制、Provider cancel、Playback clear、Session／Memory、DR／fixture、旧合同与 lint 配置不改。

| 文件 | 实际修改 |
| --- | --- |
| `MacSpeechAudioCapture.swift` | 停止状态下协商 VP Mixer→Output 格式；保留原格式 Guard、Converter、锁／callback fence；有界 DEBUG 配置阶段／格式及错误 domain/code |
| `AppController.swift` | 显式 DEBUG 无声场景参数，复用既有 Prepare／Start／Collect／Seal／Export／Cleanup；零值输出、输入内容不保留；未知系统权限不自动申请 |
| `ContentView.swift` | 隔离 DEBUG 测试页一行 `.task` 接回原 Controller.start；普通页面与 Release 不改 |
| R81 `RealtimeInterruptionEvidenceTests.swift` | Fake A/B/C 完整导出／清理，零值输出、输入不保留、重复 start 与权限负控 |
| R81 `check.sh` | 只更新新增覆盖后的精确计数 40 cases／283 checks；原断言保留 |

`MacSpeechAudioOutputPlayer.swift`、`MacSpeechAudioOutputHost.swift` 仅只读定位，不修改。未建立第二 Engine、Player、Runtime Owner 或声源 Gate。

## 2. 根因与最小修复

### 已确认的工程缺陷

原流程在 `setVoiceProcessingEnabled(true)` 后读取 Input.outputFormat 与 Output.inputFormat，并要求采样率／声道一致，却没有先完成 Mixer→Output 格式协商。Apple SDK `AVAudioIONode.h` 的 `setVoiceProcessingEnabled:error:` 说明要求 VP 两端格式一致，且只允许在 Engine 停止时改格式；[Apple API 入口](https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:))。

原 D2 日志中近端客户端为 1ch／44100Hz、远端客户端为 2ch／44100Hz，支持该缺口，但原始 Swift 终止错误已被 Player 压为 `output_unavailable`，**无法追溯出当时原始 NSError**。没有将 `-10877` 日志直接改判为终止根因。

本次三次真实无声读回进一步证实格式合同缺陷：VP 输入为 **48000Hz／3ch**，输出协商前 **2ch**；按输入实际格式连接原 mainMixer→output 后，实际两端均为 **48000Hz／3ch**，原 Guard 通过、原 Converter 创建及 Engine start 成功。原等声道 Guard 在协商前会拒绝该实际路线，协商后保留 Guard 即可运行。

分类：**CONFIRMED_ENGINEERING_DEFECT — 缺少 VP I/O 格式协商**；原 D2 精确终止 NSError 仍不可恢复，原 USB 路线仍待实测，不将当前 Bluetooth 成功写成原路线已通过。

### 修复顺序

原唯一 Engine attach Player → 确认 stopped → 原生 VP enable、bypass=false、inputMuted=false、AGC=true → 读取实际 Input 格式并拒绝无效值 → **在同一 Engine 连接 mainMixer→output，使用该实际格式** → 重新读取 Mixer／Input／Output 格式 → 执行原一致性 Guard → 原 Player 连接／Converter／VP 读回／Tap。

不删除格式检查，不假定研究工具的 16kHz／3ch，不改变 Output prepare 与 Capture start 的调用顺序，不切到 AEC3 继续运行。Cascaded 分支直接跳过 Apple 协商 helper，保留原 AEC3 格式、来源与生命周期。异常仍走原拆图／资源释放及 fail-closed。

DEBUG 诊断仅在原 Engine 控制锁内更新一个有界字典，记录 enable／negotiate／validate／create_converters／validated 阶段、实际格式，以及配置失败时的原 Error domain/code；音频 callback 不访问该字典。Release 不含该诊断或无声入口。未引入逐帧日志／数据库，也未把所有 Player Converter 错误包装问题扩展成新框架。

## 3. 无声入口与隐私隔离

明确同时提供 `--apple-vp-acoustic-test` 和 `--apple-vp-silent-smoke=A|B|C` 才进入自动无声控制。单独原 D1 参数保持手动，不自动启动设备；普通启动保持原行为。只接受 A/B/C，默认关闭。

- A/C 通过原 OutputHost／Player 排程 **2 秒、24000Hz Mono PCM16LE 零值 PCM**；没有读取或播放固定有声 WAV。B 不准备／播放 Output。
- 每个场景 collection 最多 4 秒，独立 App 实例、run UUID 与 generation；每项实际设备启动一次，不循环重试。Start fence 防止重复 `.task` 创建并行 run。
- 保留原每包 generation、序列、20ms 内容时间、960 bytes、容量检查；输入内容校验后丢弃，仅保留有界包时间／计数和原 native 累计统计。FrameBuffer／Converter 的瞬时处理内存不写文件；run.pcm 始终空。
- JSON 中 `silent_smoke=true`、`retained_pcm_bytes=0`、`processed_sha256=null`；WAV 接口明确拒绝无声模式。只在此显式无声启动模式自动导出统计 JSON 到原受控 Caches，0700／0600、同 run、无覆盖／symlink 放宽。普通 D1 仍需显式导出同意。
- 无新权限请求：如果本 App 的系统麦克风权限不是 authorized，直接封存错误，交由用户处理系统确认，不代点授权。三次真实运行均无新系统授权请求。
- 不建立正常 Runtime／Provider／Store 依赖，不读私人 DR、历史 Session、Provider 配置或 Keychain，不产生 Runtime Decision。正式中断继续关闭。

## 4. 首次失败与修正记录

1. R81 首轮 exit **133**：新长零值 Fake 输出用例未驱动 FakePlayer completion，等待完整排程超时。补上真实 Fake 消费事件直到 completed；生产队列／超时及所有断言未改。
2. 第二轮功能断言已通过，runner exit **1**：预期计数未包含新增 A/C 导出负控。实际为 40 cases／282 checks；更新精确计数后最终 exit 0，不减少断言。
3. Host 首轮 178 checks 通过，但静态检查 exit **1**：helper 变量名与原静态 `inputNode` 模式不符。恢复变量名，保留测试器原样；最终 exit 0。
4. 首次启动预检停在 idle／run UNKNOWN：隔离 View 不走普通页面的 `.task { controller.start() }`。**此时无 run、无设备启动**。保留 20 秒超时观察，补齐 DEBUG 页同一生命周期调用后重新构建／Guard，再开始首次真实设备 A。没有把该启动预检记作一次声学或设备成功。
5. 首轮增量格式／空行／行宽及新增 configure 函数长度问题局部关闭；将原 VP 配置抽为同锁内短 helper，执行顺序不变。没有全文件格式化或改规则。
6. 最终 SELF_REVIEW 将旧“默认不自动导出”负控保持在显式无声自动统计导出之前，并在删除合成目录前另检查空目录；避免先清理再断言掩盖额外导出。只改测试／runner，最终 40 cases／283 checks；生产源码及三次实机构建不变。
7. 首次二进制接口 probe 用未解码 Swift 符号名而未匹配到 Debug 方法；改为 `nm`＋`swift-demangle` 后确认 Debug 有诊断接口、Release 无。原 probe 记录保留；不是编译、设备失败或 Release 泄漏，不据此重跑设备。

## 5. 离线验证与构建

全部使用既有 Fake／合成依赖，不启动设备／Provider。最终源码冻结后通过；之后仅 DEBUG View 一行接线改变，补跑两配置及三项 Guard；控制／Host／Converter 源码与已通过版本相同，不重复无关 Test2 全套。

| 实际入口 | cases／checks | 最终 exit／结果 |
| --- | --- | --- |
| `tools/realtime_release_route_guard/check.sh` | 原完整权限／Release Guard | 0／PASS；View 改后再次 0 |
| `tools/speech_audio_host_tests/check.sh` | 178 checks | 0／PASS |
| `tools/speech_audio_output_tests/check.sh` | 238 checks | 0／PASS |
| `tools/speech_aec_host_tests/check.sh` | AEC 1165 checks；Converter 25 cases／221 checks；Replay self-check | 0／PASS |
| R81 `check.sh d1-only` | 40 cases／283 checks | 0／PASS；Fake A/B/C Prepare→Start→Capture/Playback→Stop→Seal→Export→Cleanup |
| AEC `check.sh d1-stats-only` | 10 cases／49 checks | 0／PASS |
| `tools/architecture_guard/check.sh` | 原规则 | 0／PASS；View 改后再次 0 |
| `tools/secret_guard/check.sh` | 原规则＋本轮文件另查 | 0／PASS；View 改后再次 0 |
| Debug build | 仅构建 | 0／PASS；最终 View 版 0 |
| Release unsigned build | 仅构建 | 0／PASS；最终 View 版 0 |
| 未受影响的 Qwen／Runtime／Session／Memory 全套 | 不重复执行 | NOT_RUN；Test2 原结果不改判 |

构建沿用 `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug|Release -destination platform=macOS -derivedDataPath <本机Git忽略目录> -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build`。新 DerivedData 复用本机依赖缓存，不修改旧 D1/R2 构建证据。构建／工具／回归完整命令与 exit 保存在本机结果 JSON。

最终 Debug executable SHA-256：`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`；实际载入 debug dylib SHA-256：`05e7d7530ef559e35ab8440ac76bd25e7b209d832b6d993e365d4cddc0ba7a28`。stub 本身未变，不能只凭 executable SHA 判断代码；三次实际进程均核验 argv 与两项 loaded images。17 项源码／测试／脚本 SHA 在 run 前及全部退出时逐项一致。此后仅 R81 测试／runner 恢复负控位置并复验至 40/283，生产源码和实际构建字节未变；提交前分别保存最终测试与运行生产源码清单，不把两次测试版本伪装成同一 hash。

运行 HEAD 为上述空 checkpoint，工作区源码 diff SHA-256：`82ce6198684912a8ae07dfbf5a184eaf74c9e6b49329ec9e360e69c475a47502`。该摘要是**运行前源码 diff**；之后新增文档不会冒充同一全工作区 diff。manifest 的 source_commit／build_identity 仍为 null，由本机外部清单绑定，未补写静态假值。

## 6. 当前设备环境与真实无声结果

系统默认 I-02／O-02 均为 **Bluetooth** 音频设备，标称输入 24kHz／1ch、输出 48kHz／2ch，与 D2 原 I-01 USB 麦克风＋O-01 内置扬声器不同。私人设备名称／UID 仅在本机登记。实际读回输出 63%、输入 50%、未静音，预演后相同；执行者未调整设备、音量或系统麦克风模式。**System Microphone Mode=UNKNOWN**，不从私有日志整数推导公开模式。

| 场景 | run UUID | 无声控制链 | 原输出行为 |
| --- | --- | --- | --- |
| A | `D53AF045-B7B7-4E2E-8243-996200BF28C5` | PASS | Output prepare／schedule／start／complete，各一次；零值源 |
| B | `341B2BB0-C526-4883-AFF8-83F6DB68B8B0` | PASS | 无 Output prepare／play，符合 Human-only 控制路径；无人声保存 |
| C | `497207DE-BF92-4615-A378-4C71D8F86E87` | PASS | Output prepare／schedule／start／complete，各一次；零值源，非真实双讲 |

三项均：Capture generation 1、configurationID 2；VP 输入／输出 true，AGC true，bypass false，inputMuted false；实际原生格式 **48000Hz／3ch／Float32／non-interleaved**，原输出合同为 24000Hz／Mono／PCM16LE。

每项 native 40 buffers／192000 frames，生成 199 个完整包、实际 drain 194 个包，每包 960 bytes，序列 1…194、内容时间间隔准确 20000000ns；drain 内容 186240 bytes，**保留的 PCM bytes 为 0**。封存时尚有 5 个 queued 完整包，Stop 后由原关闭流程丢弃；不是丢包计数，也不宣称全程末尾已导出或 converter partial tail 完整。

三项 observed drop／stale／native rejects／native issues 为 0；A/C underrun／旧 playback callback reject 为 0；三个声道每项 full-scale／over-scale／non-finite 计数均为 0。安静环境的统计不能证明真人语音、AGC 听感、回声抑制或 VP-C 削波风险已通过。

每项均完成 seal→原 OutputHost.close→Host.shutdown，然后通过 App 原生 Quit 退出，再启动下一个独立实例。结束后 Aftelle 进程不存在，源码身份未变；未观察到崩溃／死锁或旧 callback 复活。封存 manifest 的 capture_state=捕获中是 **shutdown 前快照**，不能拿该字段当关闭后的状态；实际退出／sealed 顺序与 Fake Stop fence 分开核验。

本地统计 JSON 摘要：

| 场景 | JSON SHA-256 |
| --- | --- |
| A | `f6c2349180288dc1134620368692227219712c08eeef92bcebc94cf067d30118` |
| B | `d78b0b63133b6986dc7752eba7f76690f4e99a29805e10c08f11d06ff0556535` |
| C | `2e3e0ab0dd6c2c82d814893766e513c22401c0439d7dcf2b99df611ad6f5b05a` |

三份均同 run／0600、位于原 0700 专属 Caches；没有对应 WAV，processed_sha256=null。原始 JSON／日志不入 Git。正式有声 A/B/C、真人录音、用户试听、物理双讲及 AEC／NS／AGC 质量均 **NOT_RUN**，不累计 53 次数。

## 7. 正式测试准备与剩余准入条件

已完成：源／Debug artifact 身份、现有隔离入口、Fake 全链、当前路线设备初始化／计数／关闭、受控 Caches 权限、固定非私人样本 SHA 校验和用户指引。后续不需要临时找样本或现场编译／排障。

固定文件仍是 Git 忽略的 `tts_sample_v1/d2_fixed_zh_24k_mono_pcm16le_preroll1s_v1.wav`（本机 D2 preflight 目录）。文本“这是一段固定语音，用来检查回声和人声。”，24kHz Mono PCM16LE，228108 bytes，4.751333 秒含 1 秒前导静默，SHA-256 `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`；仅复核非私人资产，未播放有声内容。

未来正式窗口：原 15 秒 collection；A 用户保持安静；B 进入 running 后自然说“今天我想聊聊刚才的事情”；C 在固定语音可听见时说同句，并由真实见证记录物理重叠是否 >1 秒。完整源语音后观察 0–500ms 残回声并至少 1 秒 post-roll；B/C 从真人／居民较晚结束后计。预登记最短 A 源窗口 5.751333 秒留有余量，不把预算写成实际覆盖；实际 drain／queued／partial tail 必须另核。

未来取得有声录音及导出授权后，使用原受保护 JSON/WAV 功能；本地输出位置由界面展示，只交用户手动访问并试听对应 run 文件，执行者不自动播放、不上传。用户反馈分别记录回声、人声首尾／完整性、双讲消音和增益突变；没有试听就保持 NOT_RUN。

**当前还不能发出 READY_FOR_HUMAN_TEST：** 本轮实际默认是 Bluetooth，不是原 D2 的 USB＋内置扬声器，也未证明它能作为目标外放声学路线；原路线无声初始化未复验，系统 Microphone Mode 尚未取得可验证登记。本轮禁止自动切换设备，故未切换并额外复跑。主控须先确认最终物理测试路线；目标路线的无声预检与模式登记完成前，不要求用户参加有声测试。已有编译／代码／工具准备不再交由用户等待。

## 8. 增量规范与结构债务

使用原固定工具 SwiftFormat 0.63.1、SwiftLint 0.65.1，同 15 个显式 Swift 文件／规则／参数；另从起点 34f6bcf 导出同范围只读源码副本重新计算基线，未改配置、规则、阈值或 disable。

| 工具 | 实测起点 | 首轮 | 最终 | 结论 |
| --- | --- | --- | --- | --- |
| SwiftFormat | 20856／exit1 | 20859／exit1 | 20856／exit1 | **FAIL**，新增未匹配 0 |
| SwiftLint strict | 384／exit2 | 386／exit2；中间 387 | 384／exit2 | **FAIL**，新增 B0 |

按文件／rule／reason／Git 行映射归因，不使用总数差冒充新增数。最终 7 个原因文本变化中，6 项是既有文件／类型长度增长，1 项为原 AppController.start 函数 82→81 行的改善；无新增规则违规、无新增函数复杂度／长度违规。初期新增 configure 函数长度已真实关闭。

| 既有 C 指标 | 起点→最终 |
| --- | --- |
| Capture file／Engine type | 2368→2407；781→817 |
| R81 test file | 3388→3458 |
| ContentView file | 3414→3415 |
| AppController file／type | 8178→8229；6737→6742 |

这 6 项是既有结构债务的指标增长，不是额外 6 个新 B 类或与 C19／旧 C23 可直接相加的独立问题。历史 C19／C23 的分登记与阶段结束后治理继续，ENGINEERING 仍 **REWORK／DEBT_DEFERRED**。本次依据主控指定的“新增 B0、历史 C 继续登记、完成后自动 Commit/Push”节点授权交付；未改 04 规范，未把全量工具 FAIL 改成 PASS，不创建永久规范例外。功能／安全／Release Guard 无豁免。

## 9. 五维审核与问题登记

实际审核来源均为 `/root` **SELF_REVIEW**：源码与锁／生命周期分析、真实命令／二进制／run 核验、五维检查和文档脱敏。未委派独立 Reviewer，不冒充独立复审；Fake 与设备、控制链与物理声学分别判断。

| 维度 | 结论与范围 |
| --- | --- |
| TECHNICAL | 当前 Bluetooth 无声控制链 PASS；原 D2 物理路线未复验，完整设备收口 **REWORK** |
| ENGINEERING | **REWORK／DEBT_DEFERRED**；B0，原 Owner／取消／Release 边界保持，全局工具 FAIL 保留 |
| EVIDENCE | PASS；首失败、启动 idle、外部构建绑定、queued 尾部、未知模式、未试听分别记录 |
| CONSISTENCY | PASS；T3.1-R2 原计划与 Test2 原链不改，未把 Bluetooth 控制结果替代原扬声器声学／正式 Test3 |
| Stage7 Forbidden Checklist | PASS；见下表 |

| 级别／ID | 状态／处置 |
| --- | --- |
| CRITICAL | 0 已确认；未测试范围不宣称风险清零 |
| MAJOR D2-F1 | FIX_IMPLEMENTED／ORIGINAL_ROUTE_RETEST_PENDING；格式协商缺陷已证实并修复，当前路线通过；原 D2 结果不追溯改判 |
| MAJOR F1-route | OPEN／HUMAN_READINESS_BLOCKING；当前 Bluetooth 与目标 USB＋扬声器不同，原路线尚未无声复验，不能宣布正式测试就绪 |
| MAJOR D1-E1（历史） | OPEN／DEBT_DEFERRED；规范全量 FAIL，历史 C19／C23 不在本轮清理 |
| MINOR F1-launch | CLOSED；首个 idle 为 DEBUG 页未调用 Controller.start，接线后真实 A/B/C 可运行 |
| MINOR F1-evidence | OPEN；系统 Microphone Mode 未知、原 D2 原始 NSError 不可恢复、partial tail 与正式声学／试听仍无证据 |
| MINOR F1-fake／style | CLOSED；Fake completion、runner 精确计数、静态变量名及 B 类问题修正，首次失败保留 |
| SQ-M1（历史） | OPEN；不属于本轮 Gate／插话算法研发，也未被本次零值控制实验关闭 |

### Stage7 Forbidden Checklist

Checklist A–H 均 PASS：仅 macOS 单机 Host；无 Stage8／新 target；RuntimeCore 仍平台无关；Host 不新增 Provider／Scheduler／Memory owner；DR／fixture／Runtime API 不改；无 Provider／Keychain／secret 旁路；不写真实 Session／Memory／DR；无后台监听／唤醒词／声纹；UI 经 Controller 的显式 DEBUG 参数，正式中断锁闭，Cascaded AEC3 原路不变。

六条红线逐项 PASS：①大脑不碰平台（未改 RuntimeCore）；②Store 带版本（无 Store 改动）；③三层不黏连（无新 Runtime owner 或直连 Provider）；④DR 只读＋revision（无私人 DR 访问或写回）；⑤逻辑／画法分离（无粒子／Metal 改动）；⑥交互按意图（未改变产品交互模型）。触碰红线：无。

改代码：是，仅本报告 §1 白名单；改 Runtime API／DR schema／新增 target／进入 Stage8：均否。真实输入 PCM／WAV、设备敏感信息、密钥、私人 JSON／日志不入 Git；无需扩围来提交当前交付。不自动执行有声测试或修改默认设备。

## 10. 结论与停止状态

本轮完成最小格式协商修复、离线安全检查、Fake 全链和**当前路线**真实无声预演。继续保持原失败历史；不宣布 Apple 声学有效、不关闭原路线实机验证、不要求用户直接进入正式有声测试。

```text
T3.2-A-D2-F1 = REVIEW_PENDING
Offline Functional Safety = PASS
Incremental B = 0
Fake A/B/C = PASS
Silent A/B/C (current Bluetooth route) = PASS / one device start each
Original USB + built-in speaker route = NOT_RUN (this node)
READY_FOR_HUMAN_TEST = false / TARGET_ROUTE_PREFLIGHT_PENDING
ENGINEERING = REWORK / DEBT_DEFERRED
Human Speech Recording / Acoustic A/B/C / User Listening = NOT_RUN / NOT_AUTHORIZED
T3.2-B = NOT_AUTHORIZED
T3.3 = NOT_STARTED
SQ-M1 = OPEN
Qwen Strict Overlap = 0/3
Formal Test3 = BLOCKED
Test3.execution_authorized = false
```

完成本轮授权的源码／测试／脱敏报告 Commit＋Push 与实时远端核验后停止；不切换设备、不自动复跑目标路线或启动正式有声测试。
