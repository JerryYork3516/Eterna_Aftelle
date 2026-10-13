# Eterna Aftelle · ACE3 Step 2A · 最小音频可观测性实现

日期：2026-10-13。基线：`ACE3` / `2b873f527ed93cebcc698d8b335671c555d419b6`。

主控验收补记（Step 2A-F，2026-10-13）：根据本轮冻结授权，**Step 2 Design = APPROVED；Step 2A = IMPLEMENTATION_ACCEPTED；Step 2A-Q = QUALITY_PASS**。下文测试结果及 REVIEW_PENDING 状态保留为各次交付的历史记录，本次主控验收以此补记为准。本补记不宣称远端已冻结；FROZEN 以本轮提交推送及远端 SHA 核验成功为准。Step 1 = FROZEN；Step 2B–2D / Step 3A HIL = NOT_STARTED；Test3 = BLOCKED；execution_authorized = false；NO_PATCH（生产声学算法）。

结论：**IMPLEMENTED_TESTED**；Step 2A-Q 质量复核结论：**QUALITY_PASS**，见 §9。新增 SwiftLint error/warning 已消除；C/H 恢复原有 16 errors / 63 warnings。不是主控验收通过、整库质量检查全绿、真实设备无扰动或 Test3 PASS。

§1–8 保留 Step 2A 初次交付记录及其证据边界；其中 §7 的 lint 失败是修复前快照。Step 2A-Q 的修改范围、当前位置、重新验证结果及完整性检查以 §9 为准。

状态：Step 1 = FROZEN；Step 2 Design = APPROVED（本轮主控授权）；Step 2A = REVIEW_PENDING；Step 2B–2D = NOT_STARTED；Step 3A = NOT_STARTED；**Test3 = BLOCKED；execution_authorized = false；NO_PATCH（生产声学算法）**。

## 1. 范围与前置核验

按 AGENTS.md 和 [Step 2 设计](test3_ace3_step2_observability_review.md) 实施，仅新增 O6 标量 sidecar 与 O1 调用边界。开始时分支、HEAD 符合要求，已跟踪源码和暂存区无修改；原有未提交设计报告及两份原有未跟踪 PCM 保留。设计报告 SHA-256：`6f8fb4af5f9e3ce50fb4e70e3ec8730516ed986db3d010eecaa3b6eda5e6ffda`，结束时一致。

本轮不提交、不推送；不创建回滚提交，以主控的明确禁止为准。没有访问两份 PCM 的内容或计算其哈希，仅查看 Git 文件名/未跟踪状态。没有读取 SSD 私人录音，没有访问或修改 quarantine。没有启动 App、音频引擎、设备监听、麦克风、扬声器或 HIL。测试信号是在内存中生成的数值序列，不能当作真人或物理声学代理。

| 文件 | 本轮改动 |
|---|---|
| [MacSpeechAudioObservation.swift](../../apps/macos/Aftelle/MacSpeechAudioObservation.swift) | 新建；固定标量结构、MPSC ring、显式 arm/seal、有限 worker、诊断游标 |
| [MacSpeechAudioCapture.swift](../../apps/macos/Aftelle/MacSpeechAudioCapture.swift) | 原生 Capture/Render tap、48k converter、Capture 锁/拒收/转换失败边界；纯内存测试入口 |
| [MacSpeechAcousticEchoHost.swift](../../apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift) | queue.sync 提交/开始/返回、每次 AEC 调用、既有 FIFO 清空位置的旁路记录 |
| [project.pbxproj](../../apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj) | 新文件编译成员；仅 Debug 增加 `AFTELLE_AUDIO_OBSERVATION` |
| [AudioObservationTests.swift](../../tools/ace3_observation_tests/AudioObservationTests.swift) | 内存夹具、并发、故障、等价性测试 |
| [check.sh](../../tools/ace3_observation_tests/check.sh) | 确定性编译/测试；可选链接现有 AEC3 后端 |
| [inspect.py](../../tools/ace3_observation_tests/inspect.py) | 非实时标量解析、完整性检查、调用来源与 raw48 区间关联 |
| 本报告 | 交付与复审证据 |

未修改 Step 1/Step 2 报告、WebRTC/桥接/DSP、Qwen、Gate/分类/baseline/确认算法、Runtime、正式协议、DR、任何阈值、delay 输入计算、pre-roll 或 hangover。未实现 O0/O2/O3/O4/O5。Host FIFO 的既有清空事件不是 AEC3 内部 Reset 观测。

## 2. O6 结构、容量与并发证书

### 2.1 已有设施为何不能直接充当此实时记录器

复用了既有 callback、Host frame、converter 游标和故障语义，没有复制旧 PCM capsule。Step 2 §8 已确认的旧设施限制仍成立：Host acoustic replay capsule 的 `reserveCapacity` 不是硬上限；旧 capture trace 有截断；独立诊断 ring 使用 NSLock，不能证明多实时生产者不等待。新 sidecar 不 arm 这些旧设施，不调用其分类器或再次采样其有状态决策。

实现入口见 O6 `arm:143`、`begin:223`、`finish:258`、`seal:333`、`consume:360`、`writeRecord:448`。单例在 Host/engine/converter 构造时预热，早于 tap；默认不 arm。即使未 arm，Debug 仍保留预分配内存和轻量守卫，因此不声称开销为零。

### 2.2 固定资源

| 项目 | 固定值/实测分配证书 |
|---|---:|
| schema_version | 1 |
| 事件结构 | 28 × UInt64；stride = 224 bytes |
| ring 槽 | 16,384；小于 32,768 上限 |
| payload 分配 | 3,670,016 bytes |
| 每槽发布标记 Atomic&lt;UInt64&gt; | 131,072 bytes |
| 唯一 pthread worker 栈 | 262,144 bytes |
| 控制对象、pthread bookkeeping、guard 与标量临时存储预算 | 65,536 bytes |
| 本组件容量证书合计 | **4,128,768 bytes &lt; 8,388,608 bytes** |
| 单次窗口 | (0, 60,000,000,000] ns；超过 60 秒的 arm 被拒绝 |
| 内容 | 固定数值记录；无 PCM、字符串、转录、Key、设备 UID 或对象地址 |

数组一次分配，运行中不 resize，不创建逐事件 Task、Dispatch 异步闭包或无限队列。证书使用 `malloc_size` 核对两块分配，包含固定 worker 栈与 64 KiB 辅助预算；它是本次新增 O1/O6 组件的容量证书，不是整 App RSS 或系统文件缓存的测量。旧设施未开启，既有音频缓冲不计作新 sidecar 分配。没有声称 Foundation/系统缓存及真实设备峰值已经实测。Step 2D 仍须验证实际常驻增量与回调性能；如超过授权预算必须停测。

在双路均为 10ms callback 时，常见事件量约 900/s（路径不同会变化），持续 60 秒必须依赖 worker 排空，容量不承诺可缓存整个窗口。worker 停滞超过容量即 INVALID 并关闭新记录，绝不以扩容或生产者等待延长窗口。

### 2.3 多生产者安全依据

1. `gate` 原子值含 run 序号和 off/armed/closing/sealed。生产者读取 armed 后增加 `inFlight`，再次验证同一 gate；跨 arm/seal 的迟到入口不会把旧 run 写进新 run。
2. `head.fetchAdd` 分配唯一 ticket；只做一次容量判断，没有生产者重试循环、自旋等待或锁。超容量 ticket 计入 lost，原子 INVALID 并关闭新接纳，不写任何 slot。
3. 合法 ticket 独占 `ticket % capacity`。生产者写固定 payload，release 发布该 ticket；消费者 acquire 对应发布标记之后才读。消费者完成复制/写出才 release 推进 tail；未发布的旧 slot 阻止其被绕过复用。
4. 多线程可以不同顺序完成，worker 按 ticket 顺序消费；不能拿文件行顺序冒充墙钟完成顺序。所有真实边界另有时间字段。
5. 已接纳的生产者可以在 seal 后完成。若 100ms worker 收尾宽限仍有 pending，封口 INVALID；`inFlight != 0` 禁止 rearm，直到旧所有者完成。缓冲为进程生命周期单例，不因 seal 释放给仍在运行的生产者。
6. `NSLock` 仅用于控制线程的 arm/seal；`pthread_join`、文件 open/write/close 仅在控制/worker，不在生产者。音频线程只有有界标量准备、时钟读取、原子操作和 payload 拷贝。原有音频锁仍按原路径执行，不新增诊断锁等待。

8 个并发生产者分四轮提交总计 32,000 事件，测试唯一 ticket、payload 无撕裂、逐生产者覆盖和 ring 复用；轮间控制线程等待排空不是实时背压。Thread Sanitizer 38 项检查退出 0，无 race 报告。ARM64 优化汇编的 `begin/finish` 为原生原子指令，无分配、Swift 动态独占检查、mutex 或文件 write 调用；这是指定编译产物的检查，不是所有 Debug 框架 getter 的耗时证书。

### 2.4 arm、seal 与失败合同

每次新 run 在控制线程生成独立 UUID；事件用本进程序号引用 header UUID，配合 schema 组成身份。目的文件必须由调用方提供；独占创建、权限 0600，不覆盖旧文件。没有 App UI、自动 arm 或新测试编排器。

- header kind=100：schema、run UUID、arm/worker 开始/deadline、时钟 timebase、容量。
- footer kind=101：seal 请求/完成、reserved、drained、written、lost、pending、INVALID bitset。
- INVALID：1 overflow；2 deadline；4 写入/打开失败；8 pending；16 worker 初始化/创建失败。原因使用 bitset，后发错误不覆盖前发错误。
- 守恒：`reserved = written + lost + pending`。`Summary.admitted` 对应 head 的 reservation 尝试总数，包含 overflow ticket，并不意味着全部接纳成功。
- 达到 deadline 时 worker 或下一次生产者入口会关门；无播放也自动到期。已接受事件仍可完成收尾，不接纳 deadline 后的新事件。
- 写失败继续做有限的标量收尾/计数，不调用音频停止、Reset、Gate 或 Runtime；诊断故障不改变音频生命周期。
- missing header/footer、半条记录、重复 ticket、run 不一致、计数不守恒，检查器明确拒收。正常 footer 仅表示 `RECORDER_COMPLETE`；**验收还必须配合同一 run 的控制线程 `seal()` Summary，且 invalid/lost/pending 全为 0**。
- 文件 close 失败可能晚于 footer 写出；磁盘完全失效也不可能保证将错误本身写入同一磁盘。最终内存 Summary 会标 INVALID，检查器明确输出 `REQUIRES_CONTROL_SEAL_SUMMARY`。孤立文件不得升级为完整 HIL 证据。
- worker 在内核文件 IO 中停顿时，控制线程的 join 可能等待；音频线程不 join。异常进程退出没有可信封口，已验证缺 footer 被拒收。100ms 是 worker 可运行时的收尾宽限，不是磁盘 IO 或系统调度的硬实时保证。

## 3. O1 实际字段与产生位置

以下位置是 Step 2A 初次交付时的行号，Step 2A-Q 提取辅助函数后的对应位置见 §9.1。所有新增调用及辅助类型均受 `DEBUG && AFTELLE_AUDIO_OBSERVATION` 约束；测试入口还要求 `AUDIO_OBSERVATION_TESTING`。

| 观测点 | 准确位置 | 当场记录 | 不能替代的证据 |
|---|---|---|---|
| Capture native callback | C `startCapture` tap:1160 | kind=1，最早新增入口时钟；原始 hostTime/sampleTime 及两个有效位，frameLength/rate/格式，capture generation；退出 defer | 原生设备 ADC 前声音、真实声到麦克风时刻 |
| Render native callback | C `installRenderReferenceTapLocked`:2045 | 同上，stream=2；Render generation 未提供即 flags 标未知 | 扬声器实际发声、最终播放增益；不能当 render ready |
| 48k converter | C `MacSpeechFloatMono48kConverter.convert`:704 | kind=2；锁前 entered、锁内 began、实际输入/输出累计游标、输入 rate、提交输入标志、AVAudioConverter 原始状态、内容时间/有效位、函数返回 completed | 内部重采样 FIR 每个历史输入对输出的贡献、系统实际到达时刻 |
| Converter reset | C `resetForGenerationTransition`:882 | kind=5；既有 reset 前游标、诊断 epoch 及 next epoch | AEC3 内部 Reset 原因/恢复状态 |
| Capture 串行锁/拒收 | C `processCapture`:1703 | kind=6；锁前/获得执行/完成；generation；fence 拒收、converter 不可用及 frameLength | 不能把被拒收范围算为已处理；native callback 原身份仍保留 |
| Render 早退/失败 | C `processRenderedOutput`:2070；`recordObservationFailure`:2130 | kind=7；缺 converter 或转换异常、native 输入数量；可按同线程调用嵌套关联 callback | 没有转换产出时不得补造 raw48 区间 |
| Host 提交/开始/返回 | H `processRender`:1142；`processCaptureSpans`:1305；`prepareObservedCall`:4629 | kind=3；紧邻 queue.sync 前重新读取 entered，closure 内 began，函数退出 completed；raw48 输入区间、FIFO 余数、playbackSequence、routeResetCount、诊断 epoch | 提交字段是可见调用边界，不是 GCD 内部指令；Host 返回不等于 Runtime 收到 |
| 10ms AEC 调用 | H 两个上述处理函数中的 `backend.processRender/processCapture`；`beginObservedFrame`:4655 | kind=4；明确父 Host call ID、raw48 的 480 样本区间；紧邻 AEC 调用的开始/返回时刻；异常也 defer 完成 | 不是 10 次独立硬件到达；不是内部 4ms block ready，也不是 Gate/packet/Runtime ready |
| 既有 FIFO 清空 | H `recordObservedReset`:4673；`clearFIFOs`:4690，以及原有 playback/generation 清空位置 | kind=5；旧 cursor、pending 样本数、旧/新诊断 epoch | 不是 Runtime route epoch；不替代 O2 的内部 Reset 传播 |

C = [MacSpeechAudioCapture.swift](../../apps/macos/Aftelle/MacSpeechAudioCapture.swift)；H = [MacSpeechAcousticEchoHost.swift](../../apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift)。新增声明/产生点均可在这两份差异中定位。

### 3.1 二进制 schema 1

文件为本机小端的连续 `<28Q` 固定记录。字段按以下顺序保存：

```text
id kind stream parent thread entered began completed contentTime
nativeHostTime nativeSampleTime flags object epoch generation
inputStart inputEnd outputStart outputEnd sampleRate format frameCount
remainderBefore remainderAfter status detail run reserved
```

共同语义：`id` 为 ticket+1；`stream` 1 Capture / 2 Render / 0 待关联 converter；`thread` 为进程内线程关联值，不是设备 UID；`object` 为单调分配的本地对象别名，不是指针；范围均为半开区间。时间字段由具体 kind 定义，不能拿 header/footer 的复用字段当音频字段。

- native kind=1：`nativeHostTime` 为原始 mach ticks，`nativeSampleTime` 为有符号 Int64 bit pattern；`sampleRate` 为 Double bit pattern。flags 1=hostTime 有效、2=sampleTime 有效、4=interleaved、8=generation 未知。`format` 的高/低 32 位为 channels/commonFormat，`detail` 为 ASBD formatID/formatFlags，`reserved` 为 bitsPerChannel/bytesPerFrame。两个时间均无效时两个有效位都清零，不因 status 只存一个优先原因而掩盖另一个。
- converter kind=2：`inputStart/End` 是本 converter native 输入累计游标；`outputStart/End` 是 48k 输出累计游标，均当场读取；flags 4 表示原有 input block 实际提交了输入；`format` 为 AVAudioConverterOutputStatus 的有符号 bit pattern。`contentTime` 为传入内容时间，`detail` 为原有逻辑计算出的输出内容时间；`remainderAfter` 是时间账条目数，不是音频尾样本数。
- converter `reserved` 保存现有失败原因枚举：0 无、1 output_cursor_ahead_of_input、2 output_cursor_uncovered、3 first_input_time_missing、4 input_time_missing、5 input_time_discontinuity、6 其他。没有重新计算或替换 converter 的时钟逻辑。
- Host/frame kind=3/4：raw48 input 区间；`reserved=routeResetCount`，`detail=playbackSequence`，`epoch` 为本 sidecar 的 FIFO epoch。generation 缺失用 flags 8；若 arm 前已存在余数，flags 16 表示来源前缀未知，禁止凭长度补造源身份。
- Host `outputEnd` 是本次已经正常返回的 AEC 调用所覆盖的输入数量，**不是 Gate 放行数量或有效 PCM 交付数量**。AEC 返回后仍可能发生尺寸验证或后续处理失败；父 call 的终态必须一起检查。frame 的 completed 只证明 backend 调用完成。
- reset kind=5：`epoch` 旧值、`detail` 新值，`remainderBefore` 是丢弃的 Host FIFO 样本数量；converter reset 的 input/outputEnd 则为旧游标。没有把诊断 epoch 写回生产状态。
- status：0 正常、1 hostTime 缺失、2 sampleTime 缺失、3 转换失败、4 generation fence 拒收、5 不可用、6 处理失败、7 不连续、8 FIFO overflow、9 未处理、10 pending、11 非目标模式。kind=8/frameAssembly 以及部分状态值为 schema 保留，当前没有对应产生点，不能据其枚举存在声称已观测。

空 Host 输入保留 status=unprocessed，不产生 AEC frame；began=0 表示没有 queue 开始记录，不是“零等待”。缺时间、不支持模式、来源不完整、overflow/lost/pending 必须分别作为相应指标 INVALID/UNAVAILABLE，不从零值推断有效时刻。

## 4. 双时钟、来源与实际 ready 对账

```mermaid
sequenceDiagram
    participant N as Native device clock / callback
    participant C as Converter
    participant Q as Host queue
    participant A as AEC backend
    participant W as Sidecar worker
    Note over N: content: sampleTime/rate + hostTime valid bits
    N->>N: actual callback entered (mach clock ns)
    N->>C: converter entered / lock acquired
    C-->>N: actual cursor interval + completed
    N->>Q: queue.sync submit timestamp
    Q->>Q: actual execution began
    loop each 480 samples; one 100ms callback can contain 10 frames
        Q->>A: frame began + parent Host call ID
        A-->>Q: frame completed (AEC call ready)
    end
    Q-->>N: Host return + FIFO tail / terminal status
    N->>N: native callback exit
    Note over W: asynchronously drain release-published scalar tickets
    Note over N,W: File order is reservation order, not arrival/ready time
```

`entered/began/completed` 使用 `mach_absolute_time` 与 header 的固定 timebase 转为 ns。原始 host ticks 单独保留；内容时间仍是既有 AVAudioTime/转换器逻辑的值，不能当 callback 到达时间。设备 sampleTime 按设备/对象/epoch、有效率、连续片段分别处理，44.1k 原生单位不得直接与 raw48 单位相减。两设备同属 host timebase也不证明其采样振荡器无漂移。

身份层次：`(run UUID, native callback id)` → 同线程、真实区间嵌套的 converter event → 对应 Host call → `(host object, stream, diagnostic epoch, raw48 interval)` → AEC frame。frame 直接保存父 Host call ID；callback/generation 由离线账在同线程完整嵌套区间内唯一关联，零个或多个候选均不得猜测。检查器同时输出 converter object/epoch/output interval，跨 Host callback 余数用多个 fragment 表达。

`EXACT_CALL_LEDGER` 只表示 raw48 提交账无缺口/重叠且调用祖先唯一，不表示每个重采样滤波器 tap 的原生样本影响，更不表示物理声源归属。执行该 frame 的 callback 和贡献 raw48 的 callback 可以不同。前置余数来源未知、直接调用 Host 的纯单元夹具、诊断截断等保留 `INVALID_OR_UNAVAILABLE`；不伪装成完整身份。Render 的实际播放 generation、Runtime route epoch 与 O0 播放对象尚未关联，明确未知。

可计算本次调用的 queue wait、converter wrapper latency、AEC call duration、Host duration 及不同 stream 的实际完成先后；不把内容时间差、离线支持下界或 AEC completed 当正式检测/Runtime 延迟。Capture 原有处理耗时反馈可能受诊断开销影响，本轮没有减去、固定或重写生产 delay；物理影响留待 Step 2D。

## 5. 授权范围内验证

所有命令均为编译、纯内存合成数值测试或本轮标量文件检查。没有录制、播放或打开现有 PCM。日志及二进制仅在本地忽略目录 `.build/ace3-step2a/`，没有加入交付或 Git。

| 要求 | 验证/结果 | 退出码 |
|---|---|---:|
| A 默认关闭 | 初始 begin 返回 nil；关闭后不发布；Debug 不带 feature 宏仍编译；Release 无 sidecar 符号；排除诊断分支后与 HEAD 的原路径相同 | 0 |
| B 开关等价 | Host fixture 比较逐字节 PCM、完整 observation（分类/Gate/epoch/来源）、backend 调用及 delay 参数顺序；实际 AEC3 后端亦一致 | 0 |
| C 10/100ms | Host 480/4800 分批；native/converter 44.1k 与 48k 的 10/100ms 分批；多 frame 共享真实 callback 祖先，逐帧时间包含于父调用 | 0 |
| D 两种 rate/游标 | 实际 AVAudioConverter 的 4410→4800 输出及累计游标；两个 rate 的转换器 on/off 逐样本及内容时间一致 | 0 |
| E 缺时间 | 构造 host-only/sample-only AVAudioTime，原始有效位与缺失原因保留；converter 失败原因不填假时间 | 0 |
| F 不连续/reset/generation | 不连续输入、240-sample 余数、既有生命周期清空、generation fence 拒收；run/epoch 转换不串用 | 0 |
| G MPSC | 8 生产者、32,000 事件、slot 复用、唯一 ID/无撕裂/每生产者覆盖；TSAN recorder 子集 38 项 | 0 |
| H 满/停滞/写失败 | 显式停 worker、capacity+1 触发 overflow/lost；停止接纳；写入失败、打开失败、worker 创建失败均 INVALID | 0 |
| I seal 完整性 | 未结束生产者得到 pending=1/INVALID；旧 owner 未完成禁止重用；reserved/written/lost/pending 守恒 | 0 |
| J 无播放/异常 | 空 run 仅 arm/seal；空输入明确未处理；超过 60 秒 arm 被拒；短 deadline 自动终止；子进程直接退出后检查器拒收缺 footer | 0 |
| 实际 AEC3 等价 | 既有桥接对象与既有 AEC3 静态库，PCM **63,360 bytes / 66 observations** 开关一致；wrapper 将原有 delay 调用原样传给真实 backend | 0 |
| 旧定向回归 | `--converter-timing-only` **90** 项；`--test3-timing-only` **8** 项；未执行历史 PCM replay/训练/调参实验 | 0 |

新套件结果：**451 checks**；包含真实 AEC3 比较后 **456 checks**。这是断言数量，不是实体声学场景数。TSAN 38 项是 recorder 专项，不冒充整条设备链线程安全证明。

主要复现入口：先用 `xcodebuild` 编译 Debug，再执行 `bash tools/ace3_observation_tests/check.sh --production-aec`。不传参数时只编译/执行默认纯内存套件。该可选后端目标为现有项目的 arm64/macOS 26.5，使用现有 AEC3 库，不下载模型或改变参数。TSAN 使用同一套件以 `-sanitize=thread` 编译，再加 `--recorder-only`；异常退出夹具为 `--abrupt-exit`。不要运行未列入本轮授权的全量音频实验脚本。

本轮修正了新诊断代码中 arm 后首次 reset epoch 初始化、失败 arm 身份、worker 初始化失败 INVALID 等实现问题；这些是本轮 sidecar 的开发修正，不是新发现的生产声学算法缺陷。并发无背压的大突发触发过预期 overflow，正常负载测试随后与专门的 overflow 测试分开，没有放宽容量。

## 6. DEBUG/Release、等价性和未验证边界

- Debug、Release `xcodebuild` 均 **BUILD SUCCEEDED / exit 0**；只构建，不启动 App，不签名部署。工程仅 Debug 定义 feature 宏；helper 整文件还要求 DEBUG，Release 即使误传 feature 宏也不启用。
- 最终 Release 可执行文件符号检查不存在 `MacSpeechAudioObservation`；Debug 存在。`AUDIO_OBSERVATION_TESTING` 不在 App 工程配置，故 fault switches 和内存测试入口不进入正常 App Debug/Release。
- 对 C/H 进行条件分支展开和空白归一比较：Release、Debug feature-off 与固定 HEAD 的非诊断语句一致；唯一显式归一项是 converter 增加诊断前置语句后，Swift 原有隐式 `try lock.withLock` 返回改为等价的显式 `return try lock.withLock`。不是整二进制逐字节相同的声明。
- 真实 AEC3 与 converter 的确定性开关等价已经测得；完整设备 callback 中真实耗时参与生产延迟反馈，所以不能用该结果推断 live delay、P99、underrun 或真实音质必然不变。
- AEC 调用完成只说明 backend 返回。Gate 动作、24k packet 的全部 fragment/终态、Input Bridge、Runtime 正式观察、AEC 内部 block/reset/baseline 传播仍缺 O2–O5；本轮没有新增相关正式协议或权限。

## 7. 初次交付的工具质量检查与风险

SwiftFormat 0.63.1、SwiftLint 0.65.1 CLI 仅置于本轮构建缓存，从各自官方发布物取得并校验下载 SHA-256；没有新增项目包依赖或系统安装。初次交付时新 helper 与测试文件：SwiftFormat lint exit 0；SwiftLint 默认 lint exit 0，**12 个 warning**（文件/函数/类型长度、复杂度、tuple、括号风格），不是 strict 模式全绿。

对原有 C/H 整文件检查：固定 HEAD 基线 **16 errors / 63 warnings**；初次交付 **17 errors / 65 warnings，exit 2**。新增 `processRender` 函数长度超默认 100 行 error，以及诊断造成的复杂度/类型长度 warning；其余多为原有大文件/大函数等问题。该失败在 Step 2A-Q 中修复，结果见 §9；历史问题仍使 **FULL_FILE_LINT_NOT_CLEAN**。没有 suppress 规则或更改生产算法来掩盖结果，也没有授权范围外的全文件格式化。本报告的 IMPLEMENTED_TESTED 不能作为整库 lint PASS 或提交许可。

主要风险与后续验证边界：

1. **NOT_MEASURED：真实设备 P50/P95/P99/max、callback deadline、CPU/RSS 增量、underrun/overrun、实际 delay 反馈差异。** 原子争用、缓存流量、时钟读取、ARC、AVAudioTime/format getter 都不是零成本。Step 2D 才能在独立授权下作设备对照；本轮没有性能阈值放宽。
2. worker 使用单条固定记录 write，可能增加 syscall/调度负载；文件系统长停顿会使诊断无效。禁止用无限队列、提高预算、音频线程文件 IO 或等待 worker 补救。
3. 60 秒上限不是“保证每次得到完整 60 秒记录”；满环、超时、写失败、pending 都必须使该 run 的相应验收失败。关闭后的音频继续原路径运行。
4. 元数据仍可能泄露设备格式和使用时段，因此仅私有诊断文件；公开报告不包含私人路径、原始音频/转录/UID/凭据。header UUID、对象别名不是设备实名。
5. `seal()` 的最终 Summary 是完整性合同的一部分；单独复制一个看似完整的二进制文件不能证明 close 成功、无 late pending 或真实声源完整。
6. 无物理 ground truth：无法由 AEC 差异断言真人受损，无法给纯居民回声/近端代理/实体真人发正式资格。42 个错误资格、4 条确认链等冻结失败结论未被重跑或改写。

## 8. 完整性、Stage 7 和下一步

最终检查：分支/HEAD 保持基线；暂存区为空；仅表 §1 的源码/工程/新测试/本报告属于本轮。Step 2 未提交设计报告哈希未变。两个原有 PCM 仍为原路径下未跟踪文件，没有被本轮读取内容、哈希、暂存、移动或删除。未访问 SSD/quarantine，因此不声称对其做过内容级前后哈希证明；本轮没有向其写入。`git diff --check` 通过。无 commit/push/reset/clean/force push。

代码与本地证据身份保存在忽略目录的 `source-manifest.json`、`source-isolation.json`、`producer-assembly.json`；主要日志为 `debug-build.log`、`release-build.log`、`production-aec.log`、`tsan.log`、`existing-converter.log`、`existing-timing.log` 与质量工具 JSON。均为本轮合成/编译标量证据，未公开或纳入 Git；哈希证书不包含原有 PCM。

Stage 7 前/后越界检查：**PASS**。仅 macOS DEBUG 诊断；RuntimeCore/HostEnv 三层职责、Provider/secret 所有权、DR 只读/版本、Memory/Trace 边界、Runtime 中断授权均未变。新增 worker 仅在显式诊断 arm 后消费固定 ring，不是居民 scheduler、常驻监听、自动工具循环或 Stage 8 功能。没有跨 brain/platform 内部实现修改、平台 target 或正式 Runtime API。

**Step 2B：O1/O6 代码、容量/并发证据及 §9 质量复核结果可交由主控复审；只有复审接受并另行授权后才能进入。当前不能自动继续。** Step 3A 尚不具备完整观测、同步、物理真值及设备扰动验证前提。没有证据支持在本轮修改生产声学算法；NO_PATCH。

最终保持：Step 1 = FROZEN；Step 2 Design = APPROVED；Step 2A = REVIEW_PENDING；Step 2B–2D = NOT_STARTED；Step 3A = NOT_STARTED；Test3 = BLOCKED；execution_authorized = false。完成本报告后停止，等待主控复审。

## 9. Step 2A-Q 质量复核

日期：2026-10-13。结论：**QUALITY_PASS**，仅指本次新增 lint 回归修复及下列非设备验证通过。真实设备性能没有测量，Step 2B 没有获得授权。

### 9.1 前置检查与准确修改范围

分支和 HEAD 与本报告基线一致。修复前七份 Step 2A 源码、工程、测试文件逐一匹配初次交付的本地 `source-manifest.json`；没有无法解释的其他任务修改。先保存修复前文本，再作窄范围提取。原设计报告及初次交付证据未覆盖，两份未跟踪 PCM 未读取内容、哈希、暂存、移动或删除。遵守本轮明确的禁止提交要求，没有创建回滚提交。

下表为本轮相对 Step 2A 初次交付的差异；行号指本次交付源码，不是冻结 HEAD。

| 文件及位置 | 质量修复 | 行为约束 |
|---|---|---|
| [Host](../../apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift) `processRender:1142`、`processCaptureSpans:1282`、`beginObservedCall:4601`、`completeObservedFrame:4607`、`beginObservedFrame:4641` | 提取 DEBUG 事件开始、空输入状态和 frame 完成赋值；frame offset 在原 helper 返回前推进；局部参数换行整理。`processRender` lint 计数 123→100 行 | `queue.sync`、AEC 调用、catch/fallback、生产计数及 replay 顺序不变；无生产算法提取 |
| [Capture](../../apps/macos/Aftelle/MacSpeechAudioCapture.swift) `MacSpeechFloatMono48kConverter` 的 DEBUG 扩展 `:887`，`prepareObservation:888`、`recordObservedCursors:902`、`recordObservedOutput:907`、`recordObservedConverterReset:915`；`processRenderedOutput:2090` | 仅移出既有诊断字段赋值；合并相邻同条件 DEBUG guard，整理该函数内原诊断参数换行 | converter 锁、输入 block、输出游标、时间计算、reset 先后不变 |
| [记录器](../../apps/macos/Aftelle/MacSpeechAudioObservation.swift) `consume:280`、`finishConsumption:322`、`makeHeader:344`、`drainPublishedEvent:361` | 拆出 worker 的 header、单槽消费与 footer/close；文件降至 400 行 | producer、arm/seal、原子内存顺序、ticket/ready/tail、关门及失败协议不变；不增加实时线程 IO |
| 新增 [MacSpeechAudioObservationTypes.swift](../../apps/macos/Aftelle/MacSpeechAudioObservationTypes.swift) | 原样迁移 Event、Kind、Status、Cursor，以及 Summary/Invalid 和 converter 原因映射 | schema 1、28 个 UInt64 的字段顺序、枚举数值和游标逻辑不变；整文件 DEBUG/feature 隔离 |
| [AudioObservationTests.swift](../../tools/ace3_observation_tests/AudioObservationTests.swift)、新增 [AudioObservationFixtures.swift](../../tools/ace3_observation_tests/AudioObservationFixtures.swift) | 移出内存夹具；长断言组提取为测试 helper；原大 tuple 改为命名 `HostFixtureResult`；局部括号格式修正 | 保留全部原断言和执行次序；真实 AEC 的 delay 转发仍在；未减少故障测试或诊断字段 |
| [check.sh](../../tools/ace3_observation_tests/check.sh)、[project.pbxproj](../../apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj) | 加入两个拆分文件的适用编译成员 | 编译参数、宏、目标、部署版本不变；fixture 仅进入测试，Types 进入 App |
| 本报告 | 增加质量复核；明确原章节为历史交付快照 | Step 1 冻结报告及 Step 2 设计报告不变 |

`inspect.py` 本轮未修改。没有修改 SwiftLint 规则、配置、忽略路径或添加 disable 注释；未对 C/H 作全文件格式化。O6 当前入口为 `arm:77`、`begin:157`、`finish:192`、`seal:253`、`writeRecord:380`；Host `prepareObservedCall` 为 `:4615`，`recordObservedReset` 为 `:4660`。

### 9.2 SwiftLint 三方对比及剩余 warning

沿用 Step 2A 缓存的 **SwiftLint 0.65.1 / SwiftFormat 0.63.1**，同一项目默认 lint 规则。固定 HEAD 的 C/H 用 `git show` 导出到本地缓存检查，未切换分支或覆盖工作区。

| 快照/范围 | errors | warnings | 退出码 |
|---|---:|---:|---:|
| 固定 HEAD 原始 C/H | 16 | 63 | 2 |
| Step 2A-Q 修复前 C/H | 17 | 65 | 2 |
| Step 2A-Q 修复后 C/H | **16** | **63** | 2（仅历史错误） |
| 修复前新增 helper/tests 两份 Swift 文件 | 0 | 12 | 0（默认模式） |
| 修复后 helper/types/tests/fixtures 四份 Swift 文件 | **0** | **0** | **0（strict）** |
| 修复后上述四份 Swift 文件，SwiftFormat `--lint --swift-version 6` | — | 无需格式修改 | 0 |

除总数外，按“文件名、规则、严重度、去空白后的诊断位置源码”逐项比较固定 HEAD 与修复后 C/H；file-length 项以文件身份比较。全部 79 项历史诊断签名一致。由此确认 **新增 error = 0，新增 C/H warning = 0**，没有用新的违规替换历史违规来凑计数。原有 16 个 error 未清理；整文件 lint 仍是失败状态，不能描述为整库全绿。

新增 helper/tests 的原 12 个 warning 全部消除，**无剩余新增 warning、无规则豁免**。提取后的生产路径并未承担新的条件判断；空输入状态判断仍只属于原 DEBUG 诊断。

### 9.3 构建、原测试及故障覆盖

沿用原 Xcode 工程、scheme、Debug/Release 配置、DerivedData、Swift 编译器、AEC3 静态库与桥接对象；仅编译和纯内存测试，没有启动 App 或设备。常规命令仍为 `xcodebuild ... -scheme Aftelle -configuration Debug/Release ... CODE_SIGNING_ALLOWED=NO build` 与 §5 的脚本；TSAN 沿用原 `-sanitize=thread` recorder-only 配置。

| 检查 | 本次结果 | 退出码 |
|---|---|---:|
| Debug / Release 构建 | 两者 BUILD SUCCEEDED | 各 0 |
| O1/O6 确定性套件 | **451 checks** | 0 |
| 原有真实 AEC3 扩展 | **456 checks**；PCM 63,360 bytes、66 observations 开关一致 | 0 |
| 修复前保存的原始测试文件编译到修复后源码 | 原文件未作断言重写；**451 / 456 checks** 均通过 | 各 0 |
| TSAN recorder | **38 checks**，无 race 报告 | 0 |
| 原 converter timing / Test3 timing | **90 / 8 checks** | 各 0 |
| 修复前/后独立 golden 比较 | fake/真实 AEC、44.1k/48k converter 的 PCM/决策/顺序/标量事件一致 | 0 |
| 提前退出 | 子进程 exit 0；检查器按预期拒收 missing seal，断言通过 | 0（验证器） |
| 源码隔离及结构比较 | 非诊断语句、生产者/控制协议、schema/cursor 一致 | 0 |

451/456 是断言数量，不是实体场景数量。测试仍覆盖 10ms/100ms 分批、缺失 native 时间有效位、44.1k/48k 游标、不连续时间、reset/generation fence、尾段/失败、空输入与无播放；8 生产者 32,000 事件及复用；ring 满、worker 停滞、写盘/打开/创建失败；seal 后 pending、lost、INVALID、禁止旧 owner 未结束时 rearm。容量溢出使诊断失效，没有改变音频生命周期或放宽预算。

### 9.4 PCM、决策与真实观测边界等价

验证不是仅凭编译成功：

1. **关闭路径源码证据**：分别展开 Release 与 Debug feature-off 的 C/H，修复前、修复后、固定 HEAD 的非诊断语句 token 相同。只归一空白及 §6 已说明的等价显式 return。
2. **开关测试**：同一确定性输入逐字节比较 PCM、完整 observation（分类、Gate、epoch、来源及 generation 关联）、AEC 调用及 delay 参数顺序；fake 和现有真实 AEC3 后端均通过，converter 输出和内容时间亦一致。
3. **修复前/后独立对比**：另以修复前保存的同一夹具、相同模块名和相同真实后端分别编译两份源码；PCM、决策、backend 操作序列、44.1k/48k converter 内容时间和标量事件按顺序比较。fake/真实 AEC 各 **168 条诊断事件** 的规范化序列一致。仅剔除不可跨 run 相等的实际 entered/began/completed 时钟、线程关联值及 run 别名；header/footer 的 UUID/实际时刻不作相等断言。原始 native 时间、有效位、格式、输入输出范围、parent ID、对象别名、epoch/generation、status/detail 均参与比较。没有把两次运行的实际时钟伪造为相等。
4. **边界逐点核对**：converter 的锁内 began 仍为同一位置；Host entered 仍紧邻 queue.sync，began 仍在原 closure 中；AEC began 仍紧邻 backend 调用前。成功返回后的 `status=0 → finish（读取 completed）→ frame=nil → parent.outputEnd` 按原顺序在同一位置执行，然后才走原生产计数/尺寸验证；异常的 defer 保留。frame offset 仍在建立该帧身份后、AEC began 前推进，nil event 分支也保持原行为。没有用返回后的估计值补造时间。

本地 golden 比较记录真实 AEC PCM SHA-256 为 `ae72a8a11504cd0968766ba348af8a0b951054952143ee5605f2968d59b0de5b`，规范化事件 SHA-256 为 `563d99b175d1e27f7f27e493648c4f8e3711474596ed4bce058d3605edab7f22`；前后相同。它们只是本轮合成数值夹具的身份，不是私人音频或实体真人证据。

没有更改 AEC3 DSP、Render/Capture 顺序、锁范围、分类/Gate/reset/baseline、生产 epoch/generation、delay 输入、源样本范围或 Runtime 权限。函数提取仍可能影响编译后的调度和调用开销；上述证据不推出真实设备时间完全相等。

### 9.5 容量、并发、DEBUG 隔离及性能边界

容量实测证书保持 **4,128,768 bytes，16,384 slots，224-byte event，最长 60 秒**，满足 8 MiB / 32,768 槽上限；schema_version 仍为 1。固定分配、run gate、inFlight、head reservation、ready release/acquire、tail 发布、lost/pending/INVALID 与 seal 守恒协议未变。逐函数检查 recorder 的 15 处初始化/生产者/控制/写记录函数体，去空白后与修复前一致；Event/Kind/Status/Cursor 迁移前后也一致。worker 提取保持原消费与失败顺序，TSAN 和全部故障测试重新通过。

没有新增音频线程锁、文件 IO、动态容器、Task 或状态重算。对提取的 C/H helper 及其隐式闭包作 `-Onone`、DEBUG feature-on 的 SIL 检查：11 个函数/闭包体均无 `alloc_ref`、`alloc_box` 或 `partial_apply` 指令。调用的 recorder begin/finish 未改；原 AVAudioBuffer/format getter 仍只读原字段。该检查支持本次提取未引入堆分配指令，不是所有系统调用的实时耗时证明。

Release 最终可执行文件中的 sidecar 符号数为 **0**；Debug 产物存在诊断符号。新 Types 文件与原 recorder 一样由 `DEBUG && AFTELLE_AUDIO_OBSERVATION` 整体包围；App 工程没有增加测试宏，测试 fixture 不进 App。没有新增 Runtime API、DR 字段、正式协议或自动 arm。

**真实设备 P50/P95/P99/max、回调 deadline、CPU/RSS 增量、underrun/overrun 和 live delay 反馈全部仍为 NOT_MEASURED。** 本轮没有麦克风、扬声器、实体 PCM 实验或 HIL；不能由非设备等价性宣布真实链路零扰动。Step 2D 的独立验证授权仍缺失。

### 9.6 完整性、Stage 7 与停止状态

Step 2A-Q 标量/构建证据仅保存在忽略目录 `.build/ace3-step2aq/`：三方 lint JSON、`lint-signature-check.json`、`source-equivalence.json`、`helper-sil-check.json`、`symbol-isolation.json`、构建/451/456/TSAN/旧定向测试日志、原测试重编译日志、golden 前后摘要和 `abrupt-exit.json`。单独保存本轮源码清单，不覆盖 Step 2A 原清单。不将缓存、生成二进制或诊断数据纳入交付文件。

结束核验：分支/HEAD 未变、暂存区为空、`git diff --check` 通过；Step 1 冻结报告无差异，Step 2 设计 SHA-256 保持 §1 数值；仅 §9.1 的代码/测试/工程与本报告为 Q 修改。两份 PCM 仍原路径未跟踪且没有被操作；SSD/quarantine 未访问或写入，不声称对它们做过内容校验。没有 commit、push、reset、clean 或 force push。

Stage 7 前后越界检查：**PASS**。改动限于 macOS DEBUG O1/O6 及非设备测试；没有修改 brain、Provider、DR、Runtime 中断权限、分类阈值、生产声学算法或 Test3 PASS 合同，也没有新增常驻监听、scheduler、多平台 target 或自动测试设备行为。

**QUALITY_PASS；Step 2A 继续 REVIEW_PENDING。** 可由主控复审本次质量修复；没有自动进入 Step 2B 的许可。Step 1 = FROZEN；Step 2 Design = APPROVED；Step 2B–2D = NOT_STARTED；Step 3A = NOT_STARTED；**Test3 = BLOCKED；execution_authorized = false；NO_PATCH（生产声学算法）**。到此停止。
