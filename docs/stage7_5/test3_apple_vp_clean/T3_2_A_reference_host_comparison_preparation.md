# T3.2-A · 旧 VP-C / HOST 同条件对照准备

日期：2026-10-19。性质：隔离恢复、源码接口核验和无设备离线验证。审核类型：SELF_REVIEW。

## 1. 结论先行

**REFERENCE_HOST_PREPARATION=PARTIAL；READY_FOR_DEVICE_COMPARISON=false。**

已恢复冻结 REF 源码，核验到与23号报告摘要相同的历史 Release 可执行文件，并在隔离目录用当前工具链重新构建、通过33个必要离线测试。HOST既有构建与干净基线源码仍可绑定。现有蓝牙控制器的9个自测通过。

但两项接口限制已确认，不能用外部脚本或格式转换掩盖：

1. **居民素材准入不相容。** REF要求恰好8秒、Float32；HOST现有综合C要求3–6秒、24kHz/Mono/PCM16LE。当前4.751333秒居民WAV实际不能通过冻结REF加载器；仅改容器/编码也不能消除时长门槛冲突。
2. **REF缺少实时控制事件出口。** 观察窗起点、近端提示和结束事件存在于进程内，最终写入封存Manifest；现有HOST控制器消费的实时ScoreControl管道并不存在于冻结REF。不能轮询最终Manifest、看UI或按进程启动时间推算。

本轮没有修改两端内部实现、放宽素材门槛、生成替代语音或执行设备实验。需要主控批准明确的比较协议及最小事件适配后，才能建立可执行的自动对照。这里确认的是兼容性限制，不是Apple VP声学根因或生产代码BUG。

## 2. Git隔离与保护

| 项目 | 实际核验 |
|---|---|
| HOST审核源码 | `28a8589eddbf59b2a8fd0c73ebdfd3e8341b7273` |
| REF冻结源码 | `c64c7e2629ec775062fdc2ea1e4a934c73c1fa75` |
| 原目标分支 | `Test3-AppleVP-Clean`；开始时HEAD、upstream、实时远端均为HOST审核源码 |
| 原工作区异常 | 7个未解决冲突、另5个暂存修改；涉及音频及RuntimeCore。未修改其索引、文件或分支 |
| 用户追加授权 | “允许隔离继续，仅提交本轮报告及适配文件（推荐）” |
| 实际交付分支 | 独立受管工作区中的 `codex/reference-host-comparison-preparation`，从HOST审核源码创建，upstream为 `origin/Test3-AppleVP-Clean` |
| 写入范围 | 本报告；构建、探针与离线数值回执留在独立工作区被Git忽略的 `.build/reference_host_preparation/` |
| 其他工作区 | 未执行stash/pop、reset/clean、切分支、冲突解决或索引修改；原研究工作区仅只读取得已登记REF产物 |

原目标工作区的完整status与index SHA已在Git外保存用于前后核验。历史未跟踪报告及PCM没有暂存、读取内容或上传。交付后的三方HEAD核验针对**隔离交付工作区**；原冲突工作区保留旧HEAD，不通过移动其分支假装同步。

## 3. REF / HOST源码、构建与依赖身份

### REF

冻结commit中 `tools/apple_vp_reference_v1/` 的124个文件逐个导出并记录SHA；未复制研究工作区未提交源码。`5e9c9254e6191e6411fa78d06c45934be041d2ec`（23号报告代码基线）至冻结commit的该工具源码diff为空。

| 产物 | 本轮SHA-256 | 身份解释 |
|---|---|---|
| 历史Release `apple-vp-reference` | `099b328f4bcc28bd111d8e02a358665e73b8bf0a354d870959ca0d9d24a3ec5b` | 与23号报告一致；复制到隔离目录后仍一致，codesign严格验证exit0；本轮未运行它 |
| 当前工具链重建Debug `apple-vp-reference` | `099ad48c3d13fa7ddd61d81865fe17067191837125345a2bd200fceddf351f40` | **冻结源码在当前工具链重新构建**，不是历史成功实验原二进制 |
| 历史VPC提示资源 | `0348e8afb7f9a224349ae237adce6496895bbf40920d27a136dd8d9c4522ae01` | 与原产物一起逐文件复制、核验；未声称复现报告中的bundle聚合摘要算法 |

Package使用Swift tools 6.0、Swift语言模式5、macOS14最低版本；内部目标为VPRecorder（C）、VPReferenceCore和VPReferenceAudio，无外部Swift包依赖。本轮工具链为Apple Swift 6.4、Xcode27.0（27A266a）、macOS SDK27.0；宿主macOS26.6.2（25G83）。未升级依赖或改音频实现。

### HOST

复用 `full_current-9w4j67qu/DerivedData` 的已验证产物。`bcfa84e96ba17fe1b314bc15f8f6a72542ae3eb5..28a8589eddbf59b2a8fd0c73ebdfd3e8341b7273` 在 `apps/macos` 与 `tools` 下无源码差异。没有使用原冲突工作区的当前未提交Swift源码重建。

| 身份 | 本轮重新计算的SHA-256 |
|---|---|
| Debug主程序 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug dylib | `34ca1dc87ed28229fc2992503253d272eca4833dea5fdb2f7ceaf20c25267ba1` |
| Release主程序 | `c9c209f7c7a1f5d772a4f3f5e0e384fa69ecb0897d1ada994ec283e6daef8477` |
| FULL_CURRENT既有results.json | `fb409fff4fa0e612e4664479d63860ed97ebb800d635e06729a6c4b0e3dbc06d` |
| 既有最终验证receipt | `da09b4d60f80b70a7465e3e6bbfa905ec432fbbf1fc052b6cc1458cfbb6452c3` |

FULL_CURRENT receipt为21项PASS、各exit0。这是**历史执行结果与当前干净源码的身份复核**，不是本轮重新执行。没有重跑FULL_CURRENT、HOST Debug/Release构建或无关回归。

## 4. 可比条件表

下表分别记录外部条件、保留的实现差异和未统一条件；“未改动”不等于“已证明相同”。本轮未查询实际设备或运行权限，设备准入留待另行授权的前置检查。

| 类别 / 条件 | REF | HOST | 本轮结论及影响 |
|---|---|---|---|
| 外部：输入/增益 | 历史登记USB输入；当前实际设备与增益未查 | 目标TinyUSB、60% | 可计划统一；**DEVICE_UNVERIFIED**，不能沿用历史设备PASS |
| 外部：居民输出 | 历史Built-in；23号读值0.7619839906692505 | 目标Mac mini内置、55% | 历史实验音量不同；未来须同一实际读值，不能把历史成功与当前失败视为同条件 |
| 外部：近端 | 历史真人发声 | 当前拟用小爱蓝牙代理 | 需REF/HOST都用同一代理素材、UID播放器；历史真人研究不能直接变成代理真值 |
| 外部：音箱音量/摆位/环境 | 无当前校准证据 | 无当前校准证据 | **UNKNOWN**；不调整设备，不用“未修改”代替测量 |
| 外部：Mic Mode | 历史preferred/active原始值0/0，仍有限制 | 当前状态未查 | **UNKNOWN**；未来能可靠只读取得才登记 |
| VP/AGC/bypass/mute | 历史运行true/true/false/false；REF验证AGC仅要求可读取 | HOST AGC-ON精确读回资格 | 目标值可一致，但REF现有门禁不保证AGC一定true；未来必须单独核验实际读回 |
| 居民素材 | 原生Float32、恰好8秒 | 24kMonoPCM16、综合C仅3–6秒 | **BLOCKED**；需要主控批准比较入口的有限准入适配，不能只转换格式 |
| 近端素材 | 冻结提示要求4–9秒连续发声 | 现有代理0–11秒 | **BLOCKED for same timing**；相同文件SHA也不等于相同播放区间 |
| 启动及就绪 | 完整素材先排程；Engine start后等Input和Mixer Render均有有效写入才开窗 | Output prepare、Capture start；WARMUP_4S连续处理/drain后评分 | **保留的实现差异**；不得先把REF改为HOST时序再称旧参考 |
| 居民播放 | 观察窗+2秒开始，整段8秒排程 | 评分+3秒触发，原100ms分块/Fade，原素材含1秒前导静默 | 多项差异；不是严格单变量因果实验 |
| 窗口 | 13秒观察+0.5秒post-roll，总准入16秒 | 4秒预热+15秒评分，总19秒 | 尚未统一；不能仅重新标记阶段名称 |
| Render观测位置 | mainMixerNode Tap | PlayerNode Tap | 保留差异；两者均非Apple内部AEC参考的直接观测 |
| 输入保存 | VP后原生Float32多声道，原Recorder封存 | VP后ch0→48kMono→24kPCM16；仅评分音频最多720000bytes | 不同输出表示；不能直接比较容器SHA或称原始输入完全等价 |
| 终止/覆盖 | Stop、Recorder seal、事后Manifest；历史post-roll仍UNVERIFIED | Stop/Seal/Shutdown；排队尾包及Converter partial tail限制 | 各自按实际内容时间核算，不能因exit0宣布完整覆盖 |

旧23/24号结论仍为有限研究证据，不升级为正式AEC/双讲PASS；最新HOST A用户听感与代理C失败结论也未改写。两路代理声音由同一Mac输出，**SOURCE_REFERENCE_ISOLATION=UNKNOWN**。

## 5. 固定素材清单与真实准入结果

只读取两份已登记非私人合成语音；未读取历史麦克风录音、原始PCM或私人Manifest。原件未复制、修改或上传。

| 素材 | 格式 / 帧数 / 时长 / 文件长度 | SHA-256 | Peak / RMS（线性；dBFS） |
|---|---|---|---|
| 当前固定居民 `d2_fixed_zh_24k_mono_pcm16le_preroll1s_v1.wav` | 24kHz/Mono/PCM16LE；114032；4.751333s；228108bytes | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` | 0.6699829102 / 0.1158276853；−3.4787 / −18.7238 |
| 已有蓝牙近端代理 `proxy_human_zh_rate190_24k_mono_pcm16le.wav` | 24kHz/Mono/PCM16LE；264310；11.012917s；528698bytes | `1c7081f8271251804e01234be8a0ff8344062d09c311592634cb8fdf6b992d0a` | 0.7063903809 / 0.1236532180；−3.0191 / −18.1559 |
| 旧成功实验居民素材 | 23号报告：16kHz/Mono/Float32、128000帧、8秒、Peak0.6877746582 | **本轮未定位并核验原文件，UNKNOWN** | 历史值；不是本轮重测 |

当前居民前24000个样本全零，首个非零样本索引24000。旧素材文件及native PCM摘要未在公开23号报告登记，本轮不读取私人登记或从历史Render录音反推素材。未生成未经批准的8秒替代品，也没有截断、补零、归一化、变速或降噪。

**实际无Engine探针的6项观察：**

| 输入与路径 | 本轮结果 |
|---|---|
| 当前居民→冻结 `PCMSourceMaterial.load` | REJECTED；`BLOCKED: material must be a supported linear PCM file` |
| 当前居民→HOST现有WAV解析器+综合C时长条件 | PASS |
| 当前代理→冻结加载器 | 同上REJECTED |
| 当前代理→HOST解析器+居民时长条件 | WAV解析PASS；综合C居民准入拒绝（这不是蓝牙代理角色失败） |
| 内存合成8秒16kFloat32→冻结 `VPAAdmission.inspectMaterial` | PASS；包含固定低幅非零合成数据，不涉及设备 |
| 内存合成8秒24kPCM16→HOST解析器+综合C时长条件 | WAV解析PASS；384000bytes超过综合C288000bytes上限，被拒绝 |

探针链接冻结生产加载/准入函数；HOST解析器从当前源码原文提取，仅调整顶层访问可见性，综合C时长条件按原表达式核对，**不是完整AppController运行**。实际文件首先在冻结加载器中拒绝，本轮未将共享错误字符串擅自定位到某一个内部guard，也不将其误写成已实际触发后续8秒身份guard。格式/时长不相容另有明确源码依据：

- REF `Sources/VPReferenceAudio/PCMSourceMaterial.swift:11–49`；`VPAAdmission.swift:32–46`；`Sources/VPReferenceCore/VPARequest.swift:7`。
- HOST `apps/macos/Aftelle/AppController.swift:7770–7787`、`:8157–8206`。

即使后续批准格式派生，仍须保留源文件、记录派生SHA/长度/Peak/RMS/数值误差，不能称Float32与PCM16逐样本字节等价。本轮因时长交集为空，没有进行无效的格式派生。

## 6. 自动控制兼容性与启动边界

### 已完成的HOST控制核验

复用既有单次 `sync_once.py`，SHA `b81621be6448803ddb3b2c4c7bdaf57fd6cb673ec1898c525758896574692cd9`；既有 `bt_proxy_speech_once` 二进制SHA `3f21479468417218617be4a122a417e865060a46d585b6614aa51a2537653b82`，本轮只计算摘要，未执行播放器。

控制器消费schema1、UUID、`mach_absolute_nanoseconds`、`score_start_ns`及严格`+11s`的`proxy_stop_ns`。PLAY/STOP各一次，拒绝重复/外国runID/错误时基/超时；取消会STOP。HOST实现位于 `AppController.swift:59–91`、`:7697–7729`、`:7883–7899`，管道有界、非阻塞，原App采集/扬声器/本地录音同意仍必需。

现有控制器CLI用`--arm A`表示0秒预热，`--arm B`表示4秒预热；**它们不能直接重命名为REF/HOST语义**。调用外壳需在两个新run目录分别登记REF/HOST身份，不复用旧运行目录。无设备模拟已验证新目录0700、JSON0600、排他创建拒绝覆盖；只保存`device_executed=false`的离线数值状态。

本轮没有找到并重审该NSSound辅助二进制的Swift源码；其按UID输出方式依据既有已验证报告及当前二进制摘要复用。当前蓝牙在线状态、实际UID绑定及播放完成仍是未来设备预检项，不能由本次摘要核验代替。

### REF缺少的接口

冻结 `VPCSession.swift:49–57` 在录制前写prepared，`:141–159` 将事件/提示receipt保存在内存，`:243` 才写最终Manifest。`VPCWindow.swift:55–99` 实际双流就绪后产生`observationStart`；`VPCRequest.swift:26–35`规定0/2/4/9/10/13秒提示。没有可供外部控制器实时消费的同等管道事件。

REF使用`mach_continuous`事件并保存absolute前后夹取及时基；HOST控制器使用absolute纳秒。两者不能直接当作相同数值。现有REF最终事件足以事后分析软件时序，**不足以在本轮未改实现时实时驱动蓝牙近端播放**。

### 准确的现有入口（仅记录，未执行）

REF现有CLI语法来自冻结 `ReferenceTool.swift:63–71` 和 `VPCCommandTests`：

```text
apple-vp-reference vp-c --authorize-vp-c --material-content-reviewed
  --enable-audio --arm-diagnostics --mode VP_ON --duration 16
  --target-registration <validated-private-registration>
  --material <registered-8s-Float32-material>
  --material-sha256 <file-sha> --material-pcm-sha256 <native-pcm-sha>
  --study-id <non-private-alias> --output-dir <new-REF-directory-outside-Git>
```

还需原窗口确认及既有系统麦克风权限；占位值当前未补齐，**不是可执行的已批准命令**。不运行CLI帮助来顺便启动工具。

HOST已有启动链为：控制器准备原NSSound辅助进程→建立非阻塞管道→启动已核验主程序 `--apple-vp-acoustic-test --apple-vp-score-control-fd=<inherited-fd>`→原DEBUG UI选择综合C、AGC-ON/WARMUP_4S及素材→原同意/Start→真实schedule/stop→封存、显式导出、Quit。既有控制器命令接口为 `python3 sync_once.py --arm B --executable <verified-HOST-executable> --fixture <fixed-proxy-WAV>`。本轮没有调用execute路径，也没有绕过UI门禁。

**不存在当前已可安全执行的一对REF/HOST自动比较命令。** 不能将HOST自测PASS记成REF控制兼容PASS。

## 7. 最小适配建议（仅建议，未实现）

唯一下一项：由主控先批准**比较协议与两个必要DEBUG接口的有限适配范围**，暂不授权设备实验。

| 位置 | 精确建议范围 | 保留与影响 |
|---|---|---|
| REF `VPCSession.wait` 的event闭包（141–144）及现有Stop终止闭包（97–102）；`ReferenceTool`参数边界 | 可选、显式登记的有界事件fd：从真实`observationStart`输出已登记near-start/stop计划；从实际终止路径输出cancel/stop；带runID、原时基和absolute夹取界限。不可由UI或墙钟推断 | 不改 `VPCWindow` 内部预热、排程、cue门槛；不在Tap写文件。需异常关闭/丢事件fail-closed测试。若实施，此产物须命名为**冻结源码的观测适配候选**并另记SHA，不能冒称原二进制 |
| HOST `appleVPAcousticPlaybackBytes`（7770）与综合C阶段计划 | 单独登记比较profile，若主控选择保留REF原8秒素材，则仅该profile接收其24kPCM16派生版本，并制定明确对应观察窗/近端窗口 | 不全局放开3–6秒门槛；不改Converter、Fade、Player排程策略或原普通综合C；需主控先裁定窗口、容量、尾部与导出合同 |
| 既有 `SingleRun` 外部控制器的输入翻译层 | 只在真实REF事件接口批准后，精确转换其时基及近端窗口；保留一个PLAY/STOP、UUID、超时与清理。HOST原schema保持 | 当前硬编码11秒不能直接消费REF的4–9秒窗口。现有11.013秒代理如何覆盖共同窗口需预登记，不能静默截断后称完整语句可比 |

先核实旧8秒非私人素材的准确本地指针和登记摘要；本轮未能证明其当前可用。如果该原件不可用，必须让主控裁定重新登记共同非私人内容，不能声称复用了旧成功素材。

REF的 `ConfigurationPlan.swift:148` 仅检查AGC可读取，历史true不保证将来true。后续即便保留冻结音频实现，也必须把实际AGC=true纳入比较资格；不符即中止，不能先按默认值运行后补写PASS。

上述适配均超出本轮可直接修改的内部实现范围，**没有实施**；没有为缺少实时事件新建HIL框架或伪造事件接口。故本轮不提交新的运行适配器。

## 8. 本轮实际离线执行及失败保留

命令别名：`$PREP`为隔离工作区的 `.build/reference_host_preparation`；`$REF`为其 `frozen/tools/apple_vp_reference_v1`；`$SYNC`为已核验的既有 `sync_once.py`；`$RESIDENT/$PROXY`为第5节两份非私人原件。完整绝对命令和回执只保存在Git外，公开报告不包含私人目录清单或设备UID。

| 命令 / 检查 | 本轮数量、结果 | exit / 耗时 |
|---|---|---|
| `xcrun swift test --package-path "$REF" -Xswiftc -warnings-as-errors --filter 'VPCWindowTests\|VPCCommandTests\|VPAMaterialSafetyTests'` | 33 tests：VPCWindow12、VPCCommand8、MaterialSafety13，0 failures；编译冻结源码；全部为已核验无设备用例 | 0 / 17.4771s（构建11.05s） |
| `codesign --verify --strict "$PREP/reused_reference/apple-vp-reference"` | 历史二进制签名验证；未执行 | 0 |
| `"$PREP/material-admission-probe-r2" "$RESIDENT" "$PROXY"` | 6项真实加载/原准入条件诊断，结果见第5节；预期拒绝保留 | 0 / 0.6935s |
| `python3 -B "$SYNC" --self-test` | 9 cases PASS；0/4秒各单次PLAY/STOP，重复/身份/时基/截止时间/取消负控 | 0；该次未单列耗时 |
| AST提取原 `SingleRun` 的附加离线检查 | 9项：缺事件不PLAY、schema/UUID/错误终止拒绝、播放后取消单次STOP、迟到拒绝、原REF事件非HOSTschema拒绝、分目录权限和不覆盖 | 0；未执行真实watchdog进程/播放器 |
| `python3 -B "$PREP/controller_stop_boundary_check.py"` | 1项补充负控：先PLAY，再晚于quiet截止50ms+1ns；准确拒绝为`missed quiet deadline` | 0 / 0.0261s |
| `bash tools/secret_guard/check.sh` | `secret-guard: ok`；另对本报告检查无私人绝对路径、设备UID、音频载荷或密钥 | 0 / 0.1202s |
| 交付前文件身份与白名单核验 | 冻结导出124个源文件SHA未变；HOST验证后源码无差异；原冲突工作区status及index SHA与开始时相同；唯一新增待交付文件为本报告 | 0 |

33个测试只调用合成buffer、Fake闭包或既有内存Recorder fixture，没有创建/启动真实AVAudioEngine。素材探针只用AVAudioFile与内存PCM、静态格式快照；未调用设备准入 `VPAAdmission.prepare` 或实例化Driver。

附加检查原先有一个名称为`missed_stop_deadline`的场景在首次PLAY前迟到，实际只能证明**missed start**拒绝；因此另加上述1项正确的quiet截止负控，不将前者冒充STOP证据。

| 必须保留的初次失败 | 实际退出 / 处理 |
|---|---|
| 当前分支不含冻结工具；按当前路径读取失败 | exit1；改为指定commit只读导出，未切历史worktree |
| 导出脚本使用本机Python3.9不支持的tarfile `filter` 参数 | exit1；只修正Git外导出方式为逐文件git show，导出后124项身份核验 |
| 素材探针首次编译按旧SwiftPM Modules目录链接 | exit1，`no such module VPReferenceCore`；按实际Swift6.4产物路径链接，未改冻结代码 |
| 首次素材探针未捕获冻结加载器拒绝 | returncode −5 / SIGTRAP；原失败源码、结果仍在Git外。修正探针的预期错误报告后才得到第5节结果；不改变任何加载器或门槛 |
| 函数定位时假定独立 `VPCCommand.swift` 文件存在 | rg exit2；使用实际ReferenceTool及既有VPCCommandTests核对入口；不是构建失败 |

核心回执SHA：

- 33项测试log：`14e1c02c76c821a12183670891aec45ec83dbc778cdd7ac9bff1d45c9577c517`。
- 最终素材探针源码：`3423a59319ae44efcd1035f1bca7613bcc1246f0ef3aa7b28300c2ea3ef67d7e`。
- quiet截止负控源码：`93a0894eee370900b1c5b6cfe2471ad2362b3f05e46fb0afa267520b00369249`。

本轮实际执行没有产生私人音频；无测试重试设备、无FULL_CURRENT重复执行。探针修正是无设备错误处理/链接修正，初次失败未删除。

## 9. 后续实机一对实验能回答什么

在主控批准共同素材、近端窗口、外部条件与事件适配，且实时设备/权限/音量/路由身份全部核验后：

- REF可以回答“保留旧VP-C启动、图及整体排程，在本次登记条件下是否仍有可听回声/近端损失”；不能把旧成功结论自动延续到当前设备。
- HOST可以回答“同一登记外部输入下，当前集成链是否仍出现残回声、增益或保留问题”。
- 两者即使出现差异，也只能支持**实现组合与条件相关**，不能直接归因某个Tap、Mixer通道、预热或AGC。输入表示、排程和就绪策略仍不同。
- 代理不能替代真人验收，且同Mac双输出的AEC参考隔离仍UNKNOWN；物理重叠、可懂度和居民回声需实际证据/用户听辨，软件计划与相关性不足以代替。

## 10. 五维SELF_REVIEW、问题等级与阶段

| 维度 | 结论 |
|---|---|
| TECHNICAL | PARTIAL：冻结产物可核验、重建及定点测试通过；共同素材与REF实时控制未就绪 |
| ENGINEERING | PASS（本轮交付范围）：仅一份报告，原冲突现场保持；无生产修改、新增B类代码规范问题0。SwiftFormat/SwiftLint本轮NOT_RUN；历史全量FAIL、C19/C23按原登记保留，不重复规范清理 |
| EVIDENCE | PARTIAL：本轮实测、历史报告、源码推断分开；旧素材身份及当前设备条件UNKNOWN；首错/exit保留 |
| CONSISTENCY | PASS：未以HOST控制自测代替REF同步；未把当前重建产物称作历史二进制；未将研究结论写成正式PASS |
| Stage7 Forbidden Checklist | PASS：未改Runtime/Provider/DR/Memory、生产音频、正式Human Gate；未新增Engine/Tap/服务；没有设备执行或私人音频上传 |

新增生产代码CRITICAL/MAJOR/MINOR：**0/0/0（无生产代码变化）**。准备状态另列：

- **MAJOR-PREP-01 OPEN**：8秒Float32与3–6秒PCM16居民合同没有交集，不能准备同内容且同完整覆盖的现成双端命令。
- **MAJOR-PREP-02 OPEN**：REF无实时可消费事件，且两端near窗口/时基不同；自动同步不能据现有接口合法完成。
- **MINOR-EVIDENCE-01 OPEN**：旧固定素材准确位置/双SHA、当前设备音量/摆位/Mic Mode及辅助播放器源码未完成新一轮验证；其中任何必要设备或素材缺项仍须在实机前阻断，级别不代表可跳过。
- **RESOLVED-LOCAL**：导出/链接/素材探针错误处理已在Git外修正，未改原准入条件，失败证据保留。

```ini
REFERENCE_HOST_PREPARATION=PARTIAL
REFERENCE_BUILD=PASS
BT_CONTROL_COMPATIBILITY=PARTIAL
HOST_CONTROL_OFFLINE=PASS
REF_LIVE_CONTROL=BLOCKED
COMPARABLE_PROTOCOL=BLOCKED
READY_FOR_DEVICE_COMPARISON=false

DEVICE_COMPARISON=NOT_RUN
DEVICE_EXECUTION=NOT_AUTHORIZED_IN_THIS_TASK
PRODUCTION_CODE_CHANGE=NOT_AUTHORIZED
SOURCE_REFERENCE_ISOLATION=UNKNOWN
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
SQ-M1=OPEN
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```

交付仅提交本报告，不提交探针日志、设备身份、历史未跟踪文件或音频。推送后停止，等待主控裁定协议及下一节点授权。
