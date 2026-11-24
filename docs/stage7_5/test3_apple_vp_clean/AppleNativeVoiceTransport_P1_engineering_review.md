# AppleNativeVoiceTransport · P1 工程报告

2026-11-24（Asia/Shanghai）。**P1 = REVIEW_PENDING；P2 = NOT_STARTED。**

P1自身验收通过，**完整离线准入 = PARTIAL**（既有Timer审核指纹阻塞，见下）。仅实现独立内核并执行离线验收；没有生产实例化、设备运行、声学实验、私人音频分析或 Provider 请求。本报告不证明实际 AEC、起音、延迟、音质或物理播放完成。

## 身份与修改范围

- 授权基线：`086835a6eb34cf2a935dcdc0c5e5c21648d71ead`；冻结运行源码：`574fc735ca239c9b334029debbdee546cda18d49`。
- 本地检查点：`2526f4c`；工程源码：`60439d0b2f1ef4e877ae532d48b2a5a75c527b74`。
- 实施目录：`vp-reference-host-preparation/Eterna_Aftelle`，沿用本地 `codex/reference-host-comparison-preparation`；交付远端 `Test3-AppleVP-Clean`。原同名冲突工作树不切换、不更新索引。

| 文件 | 职责 |
|---|---|
| `apps/macos/NativeVoiceTransport/NativeVoiceRing.h`、`.c` | 预分配 C11 单生产者/单消费者帧环、失效/确认、分类计数及水位 |
| `NativeVoiceClock.swift` | SampleTime 连续性、实际 HostTime 映射与恢复、500ms freshness |
| `NativeVoiceStreamingSRC.swift` | 串行 Worker 的单级系统 SRC、EOS/尾部、PCM16LE 编解码 |
| `AppleNativeVoiceTransportWorker.swift` | 身份镜像、采集组包、播放转换、从帧环消费时间戳 |
| `Aftelle-Bridging-Header.h`、`Aftelle.xcodeproj/project.pbxproj` | 一个 include、4 份已有 target 的编译成员；没有新 target |
| `tools/native_voice_transport_tests/{RingTests.c,TransportTests.swift,check.sh,guard.py}` | 并发/受控竞争、SRC/时钟/身份测试及冻结源码隔离 Guard |
| 本报告、正式 README、DEVLOG | 交付记录与停止线 |

## 缓冲与代际契约

- 采集环：未来实时回调唯一生产者、串行 Worker 唯一消费者；播放环：Worker 唯一生产者、未来实时回调唯一消费者。一个控制调用方串行发布失效；创建/销毁只在两个端点停止后进行。P1 不创建线程、Engine 或音频节点。
- 环以 Mono Float32 单帧保存原回调戳与块内 offset，接收任意合法帧数，整块写入或整块拒绝；容量由创建者确定，不假设 10ms 周期。实时 API 无分配、锁、日志、等待或 SRC；播放的 expected_audio 必须由未来调用者按当前epoch的真实期望提供，不能由队列水位推断，空闲/真实欠载/本次read失效静音分别计数；消费工作有容量与请求帧数上界。
- 编译期 `ATOMIC_LLONG_LOCK_FREE == 2`；创建时对所有原子字段逐一 `atomic_is_lock_free`，失败拒绝创建。
- 控制只 release-store 严格递增、不复用的 transportToken；禁止它改 read/write cursor。消费者通过 O(1) 快照跳过已发布旧队列并 release-store ack。新 token 写入在 ack 前拒绝；clear 前已开始、ack 后才发布的旧写由逐帧 tag 拒绝。读后复核失效则不返回采集内容，播放返回显式失效静音。
- `NativeVoiceIdentity` 镜像 runtimeGeneration、routeEpoch、playbackEpoch、captureGeneration、configurationID。任一身份变化须绑定更高 transportToken；Worker 拒绝完整身份不符的 PCM。采样率变化另须更换 configurationID 并重建两个 SRC。token/帧索引耗尽拒绝，不环绕；由未来调用者在静止状态重建。
- **逻辑失效**是 active token 发布；**消费侧确认**表示快照内队列已逻辑清空、迟到旧写不能消费；**物理播放结束**需要未来 Engine/设备观测，P1 无此证明。已完成最终检查的在途读可能在线性化失效之前返回；P2 必须在提交/调度边界继续核验 token，不能把 ack 当作扬声器已静音。
- 分别记录满载事件、拒收丢帧、旧代际帧、清空丢弃、真实欠载、空闲静音、失效静音、当前/最高水位。水位是近似并发统计，不作同步栅栏。capture 永不补零；未来播放调用方必须按该次身份的真实播放预期传入 expected_audio，不能将主动空闲当成欠载。

## SRC 与时钟契约

- 两个方向各只有一只 `AVAudioConverter`：原生率 Float32→24k Float32 后饱和编码 PCM16LE；PCM16LE 解码为24k Float32→原生率 Float32。不存在经48k中转。只在串行非实时 Worker 执行；格式为 Mono，合法采样率交由系统转换器资格检查。
- 按实际 requested 帧数取输入，跨块复用系统状态，暂缺输入使用 noDataNow，仅 finish 使用 endOfStream 并 drain。累计输出只覆盖 `floor(totalInputFrames × outputRate / inputRate)`；分数余数可查询，系统滤波越界尾部另计并丢弃，不制造输入内容。系统 normal priming 是滤波器语义，不被用于掩盖采集丢帧。
- 上行只发送完整20ms、480 samples、960 bytes 包。尾部不足480个样本不补齐，记录丢弃；真实 SampleTime 缺口/倒退、显式 droppedFrames 或身份变化会丢弃未组包数据与 SRC 残留，增加局部内容 segment，防止跨缺口拼接。该 segment 不是 Runtime generation 的新权威。
- SampleTime/样本计数决定内容帧序，HostTime 决定真实时间映射。缺失 SampleTime、溢出或真实掉帧打断内容；缺失 HostTime 为 UNKNOWN，倒退/相对锚点跳变为 INVALID。Host 异常不被伪称为采样丢帧。
- 新映射必须由3次独立且连续一致的真实回调戳确认；失败可在同一 Runtime generation 中重新锚定并恢复。只允许一个原生样本周期加1ns取整误差，不放宽旧生产容差、不修改/伪造输入戳。拆分一个回调的派生 offset 不增加独立确认次数。时间状态切换清除组包和 SRC 残留，避免低资格内容获得后续高资格。
- 包时间取第一样本而非最后回调；sampleTime 使用整数差值，HostTime 用溢出检查后加减，避免大绝对 sampleTime 的浮点相减。UNKNOWN/INVALID 的包没有合格 HostTime；未来戳、超过500ms的包 freshness 为 false。VALID+fresh 仅提供必要时间证据，**不产生插话/取消/声源决策权**。
- 系统接口依据：[Apple TN3136](https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions)。旧生产时钟、AGC ON、AEC 与取消门禁未变。

## 实际离线结果

- 工具链：Xcode27.0 / 27A266a、Swift6.4、arm64 macOS；SwiftFormat0.64.7、SwiftLint0.65.1。工具仅放在工作区外，未添加产品依赖。
- `bash tools/native_voice_transport_tests/check.sh {normal,release,tsan,asan}` 四组各 exit0。每组4个C套件、1,000,000帧有序SPSC、30,000次失效切换、2个确定性 clear 竞争、1,216项Swift检查。TSan 无竞争报告；ASan（C+Swift）/UBSan（C）无报告。覆盖边界/回绕/满空、元数据、旧代拒绝、读写 clear、空闲/欠载/失效静音分类。
- SRC 双向验证16k/24k/44.1k/48k/96k/22.05k共12组率对，1/7/128/511/1024等不规则块与整段持续转换对比误差<1e-5，帧数守恒、有限幅度、EOS真实尾部、分数尾帧、重复finish、PCM饱和与小端、奇数字节/NaN/非法格式、配置及SRC代际重置均通过。时钟覆盖缺戳、倒退、跳变、真实丢帧、溢出、同代恢复、拆块伪确认负控与500ms边界。
- 首轮两个验收断言已纠正并保留日志：非整数率重锚的整数ns取整需≤1ns；并发压力最后一代仍可合法写入，收尾须停线程后另发失效。未放松旧代拒绝、token一致性、时钟映射容差或生产测试。
- P1新增Swift格式与严格lint均0违规；提交hook执行格式/lint、原Architecture/Secret/Release Route Guard、新隔离Guard与diff检查。

| 现有入口 | 实际结果 |
|---|---|
| `env -u CFFIXED_USER_HOME bash tools/t3_2_a_validation/check.sh FULL_CURRENT` | exit1；8 PASS / 1 FAIL / 12 NOT_RUN；未复用历史结果 |
| 矩阵第9项 `speech_aec_host_tests/check.sh` | Converter65/6830、声道12/3194、Host1206、合成Replay、Delay20及硬件延迟门禁通过；Timer18项中3项FAIL，原因 `SNAPSHOT_CALLER_CONTRACT` |
| 基线定向负控（只读复制三份原文件，再调原Gate） | 在授权基线086835a6同样exit1/同一reason；三份源码与Gate均逐字节等于当前；没有更新指纹或放宽旧门禁 |
| 独立 Input Bridge | exit0，32 cases / 210 checks；身份/换代/Stop迟到音频及原编译入口PASS |
| 独立 Confirmed Cancel | exit0，1 / 62；额外插话、播放clear、历史/Memory写入均0 |
| 独立 Latency/Stale | exit0，1 / 68；N+1重绑有效，额外generation变化与播放clear均0；真实设备/Provider延迟NOT_RUN |
| 独立Debug / Release | 两次 `xcodebuild ... -configuration {Debug,Release} ... CODE_SIGNING_ALLOWED=NO build` 均exit0 / BUILD SUCCEEDED，产物未启动 |
| 原 `build_identity.py` | exit0；Debug timing符号PRESENT、Release ABSENT；application_launched=false |

矩阵原失败保持FAIL，后12项保持NOT_RUN；独立结果不补写或拼成21/21。既有Timer调用方审核指纹须主控另行处理，P1不改冻结运行源码。因而本轮不宣称完整工程准入PASS。

- 矩阵收据：`.build/t3_2_a_validation/full_current-5hf1bl4s/results.json`，SHA-256 `b8dceed7cd68f8de8d4c3eb73215a926843d2cea158aa52df3b104dc903606e0`。
- 本轮P1及独立构建/回归日志、保护/Fixture与基线失败复现收据：`.build/apple_native_voice_transport_p1_20261124/evidence/`。四组P1日志SHA与源码身份见 `unit-results.json`，所有独立日志摘要见 `manifest.json`；完整失败首次日志保留。
- 构建产物：同目录上级 `DerivedData`；Debug dylib SHA `0c4881c763aad6ba76a8050061b23d92bb75e6b58b33f20d4536727b150a5add`，Release executable SHA `4498650b9a156e0c63851eff797531b422e57b62481a5b40a5b4ccc1dd1df86b`。

## 生产零切换、保护及风险

- Guard 对冻结提交的64份既有 App 文件逐字节相等；排除的两份构建文件另验证桥接头恰好追加一个include、pbxproj仅16行新增。旧Host/UI/Controller无任何 Worker/nvt_ring 调用；新增Swift没有Engine、SourceNode/SinkNode、设备、网络或自动线程入口。
- 没有修改RuntimeCore、Runtime API、DR schema/fixture、Provider、Cascaded、AEC、阈值、AGC设置或旧时钟。P1独立代码入target编译不代表投入生产。

- `/Users/jerryyork/Eterna_Aftelle`：HEAD `131bd51785d406043ea37a31dc91f5894993cb5e`、index SHA-256 `c0fae19879c1f260b4a7cf3ac8076231c0d90e8084b42132bfa3931dd843e8ac`、porcelain/unmerged与登记文件的字节/size/mtime/mode前后相等。
- `/Users/jerryyork/Eterna_Aftelle_Test3_AppleVP_Clean`：HEAD `28a8589eddbf59b2a8fd0c73ebdfd3e8341b7273`、index SHA-256 `e4c0f51f433f4f53a3bf77e82aabd5152617f5efdbe441f05559182a56c8b952`、porcelain/unmerged与登记文件的字节/size/mtime/mode前后相等。
- 原冲突树保留7个冲突文件（18条unmerged entries）、14个未跟踪证据，未暂存/清理/切换/解决冲突。主工作树保持原detached HEAD。仅本次隔离树和获授权远端分支推进。
- 隔离树固定Fixture仍为9,058,396 bytes、0600，SHA-256 `f30d4b2ac33c3598918de992a8178f90b776109d54e3ac33fd88764dde7d1881`；before/after的SHA、size、mtime、mode、inode逐项相等。未重建或改名。
- 推送采用普通快进 `HEAD:refs/heads/Test3-AppleVP-Clean`，不force、不改原同名本地分支。推送后以实时 `ls-remote` 与最终本地HEAD、remote-tracking ref相等作为交付条件；实际回执见 evidence/remote-final.json。


- 未解决风险：真正的回调预算/抖动、协商格式、设备时间戳来源、SRC延迟与质量、全双工行为、取消后物理输出尾部和实际声学效果均未经设备验证。未来P2需接线并验证生命周期及最后提交边界的身份栅栏；当前不进入该工作。frame环逐帧元数据开销与缓存竞争只有离线安全证据，无硬实时性能证明。

## Stage 7 Forbidden Checklist

**结论 PASS（当前P1授权范围）；触碰红线：无。** A阶段与平台、B Runtime边界、C Host职责、D DR/API、E Provider/secret、F Memory/Trace、G Scheduler/多居民、H UI/音频/取消均保持；没有后台监听或常驻麦克风。

- 是否改代码：是，以上独立Host模块与编译绑定；修改清单见上表。
- 触碰红线：无；是否改代码：是，仅P1新增内核、测试和构建声明。
- 是否改Runtime API / DR schema / fixture：否。
- 是否新增平台target / 进入Stage8：否。
- 是否需要停止并请求确认：P1交付后按用户停止线等待主控审核；不是进一步设备授权。

| Forbidden Checklist | 结论及证据 |
|---|---|
| A Stage | PASS，仅macOS P1，无新平台/Stage8 |
| B RuntimeCore | PASS，既有文件零差异，无平台依赖注入Runtime |
| C Host | PASS，仅音频数据转换，不拥有Runtime/Provider决策 |
| D DR / API | PASS，schema/API/fixture未修改，无写回 |
| E Provider / Secret | PASS，无网络/Provider/Keychain入口或secret |
| F Memory / Trace | PASS，无Store、长期状态或Memory写入 |
| G Scheduler | PASS，无新增scheduler、Task或自动后台循环 |
| H UI / Rendering / Speech | PASS，无UI/粒子/Cascaded/生产音频接线，无设备运行 |
| I 验收输出 | PASS，如实保留矩阵FAIL/NOT_RUN，不将离线结果当作声学证明 |

```text
P1 = REVIEW_PENDING
P2 = NOT_STARTED
DEVICE_RUNS = 0
AEC_ROOT_CAUSE = UNKNOWN
CLOCK_ROOT_CAUSE = UNKNOWN
SQ_M1 = OPEN
T3_2_A = BLOCKED
Formal_Test3 = BLOCKED
Test3.execution_authorized = false
```

P1到此停止。P1–P4全部完成并冻结后才进入Gemini统一独立架构审核；审核通过且用户明确授权后才可进行真实实验。
