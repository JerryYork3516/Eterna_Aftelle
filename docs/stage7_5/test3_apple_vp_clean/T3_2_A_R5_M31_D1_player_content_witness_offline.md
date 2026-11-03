# T3.2-A / R5-M31-D1：Player内容见证离线实现与性能验收

初次交付：2026-11-01；最小性能整改复验：2026-11-02（Asia/Shanghai）。§1–6保留首轮记录；**本轮固定预算在观测样本内满足，安全证据仍不完整，整体继续REVIEW_PENDING，不宣称无条件整改PASS或设备准入。** 当前结论见§7及末尾状态。见证器仅DEBUG、默认关闭，真实映射/设备执行均未运行。

## 1. Git、修改范围及身份

起点HEAD/upstream/实时远端均为`ee94a74869e803eb3f66f97bb57995147153fb82`；使用原干净隔离Worktree、本地`codex/reference-host-comparison-preparation`，目标`Test3-AppleVP-Clean`。先报备限定读取范围，沿用用户免除重复确认的指令；跨文件修改前建立空回滚提交`a139faf`，原7冲突、索引及14项证据仅做保护性元数据核验。

| 文件 | 实际改动 |
|---|---|
| [MacSpeechAudioCapture.swift](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2654) | 同文件纯CRC辅助函数、值类型元数据；现有MacSpeechNativeVoiceTiming持有有界摘要历史；接入实际schedule提交点、原Player Tap、两个非实时映射点与原TimingSnapshot JSON子摘要 |
| [RealtimeInterruptionEvidenceTests.swift](../../../tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift#L4232) | 独立逐bit基准、合成内容/时间/队列负控、关闭交错、容量检查及离线性能入口；仅测试程序新增`--m31-only`/`--m31-performance`。原M26分支移入小型测试分流函数，执行内容和断言不变 |
| 本报告 | 脱敏交付；不提交构建产物、原始日志或私人数据 |

未修改第三份生产源码、Controller、原check.sh、M20/M22/M26控制器或评分器。没有生产音频算法修复。

| 本轮实际身份 | SHA-256 |
|---|---|
| Capture源码 | `9d976ae7c7094677a2a7519ea58f9339ffde20cf63bf8d2a2b17fbd37534e09f` |
| 测试源码 | `2f6c767401f23aa22d581fd4c1c094d293a38aacd98d90934256037359782b7c` |
| Debug launcher | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug dylib | `3c322764f1d0ce747ed500a8ff6c87259f0b7560a35f93c97d686e8d9977b786` |
| Release产物 | `04b34489cd8e6a388ec39fa7670d1c767444b370de449a8a4682bbec2ed1ad59` |
| 终版独立测试程序 | `ee791c4b9d316c33857d79784883783f8aaff3b5cb9b0244f1c75c22179c4b79` |

这些是磁盘身份，**加载身份及真实运行均NOT_RUN**。回归只读取已登记非私人居民素材，SHA=`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`；没有读取历史私人WAV/JSON。

## 2. CRC与Source→Render合同

实现严格CRC-64/ECMA-182：poly=`0x42F0E1EBA9EA3693`、init/xorout=0、refin/refout=false。`123456789`得到`0x6C40DF5F0B497347`；空输入、逐字节更新、24种确定性随机分块均与独立逐bit算法核对。组合使用GF(2)多项式乘法/幂，不依赖第三方CRC库；负长度、位长度溢出及不合法空右项拒绝。单字节、内容换序及正负零的字节差异由固定负控检出。

Source位于`allocatedOutputBuffer`之后、原`node.scheduleBuffer(... .dataPlayedBack)`调用之前计算，正常返回后才commit；每声道只读有效frameLength。原Fade、SRC、M26分配及排程调用不改，未提交尾部不计入Ns，M18-E01不修复。

Tap在原bus0回调内、buffer仍有效时读取三声道并计算数值摘要；不保留buffer或PCM。严格要求16kHz/3ch/Float32LE/noninterleaved/DiscreteInOrder(3)，核对完整ASBD关键字段、layout、有限性、实际数据长度及timestamp rate。frameCapacity尾部的合成NaN不会被读入有效内容。

RunID、Capture/Playback Generation、ConfigurationID、不可变epoch、登记Source SHA及Build SHA绑定于准备期。实际Source提交再核当前Capture/配置/播放代次；回调在发布前携带本epoch，不用导出时最新generation补标旧记录。Build SHA在模块内只验证登记格式；未来仍须调用方通过原PID/dylib门禁证明实际身份，不能以传入字符串自证加载。

按M31设计比较整个已观察范围：Tap节点帧区间连续覆盖`[R0,R1)`，要求`R0≤P`且`P+Ns≤R1`；逐声道组合“已观察空闲零前缀＋实际提交流＋已观察零后缀”。CRC初值0使零前缀保持0，不需要保存或补写PCM。缺记录、重复/倒序、首尾未覆盖、非零越出Source范围、错误身份、容量不足分别拒绝资格或给出未归属差异；不靠最佳lag、首非零、截窗或插值取得匹配。

允许结果只有`MAPPED_FINGERPRINT_MATCH`、`MAPPED_DIGEST_DIFFERENT_UNATTRIBUTED`、`INCONCLUSIVE`。有限指纹不能证明无碰撞逐样本相同；相同内容交换、全零块与等长空闲零输出的来源不可区分。本方案不承诺每个Buffer/20ms独立内容通过，也不能从全范围摘要差异定位具体损坏样本。

## 3. 时间映射、关闭及原出口

`enablePlayerContentWitness`只在原AGC-ON Apple模式准备阶段接受，拒绝已running Engine/已playing Player；默认不调用。首次Player.play后的既有运行态读回，以及StopCapture之前，各至多取一组Node↔Player正逆向映射；验证sampleTime、16k rate、逆向0、epoch、两次原点和读取时序。nil或不可信映射返回INCONCLUSIVE，不重试、不在Stop后补算，不把hostTime/评分WAV原点当作Player时间0。

[Apple Node/Player时间合同](https://developer.apple.com/documentation/avfaudio/avaudioplayernode/nodetime(forplayertime:))与[逆向换算](https://developer.apple.com/documentation/avfaudio/avaudioplayernode/playertime(fornodetime:))沿用M31的本机SDK核验。**本轮只验证合成映射及失败拒绝；实际Player API映射NOT_RUN。**

复用原16槽发布路径，apply只追加固定数值行，不执行CRC组合。新增单次CAS的callback租约/关闭位使Stop不等待新增哈希；在途、未发布、溢出或竞争失败不得伪造完整观察。提前Stop保持取消/部分覆盖，Stop触发completion不能升级为完整。不同Run快照、旧代次及关闭后回调拒绝进入当前证据。

原snapshot仍保留20次/5ms获取预算。复杂组合在`nativeVoiceTimingSnapshot`非实时出口、取得原快照并释放原busy标记后执行；只在关闭且无在途工作时读取冻结历史。新`playerContent`子摘要独立声明资格，旧`nonzeroCoverage`、`OBSERVED_PARTIAL_METADATA`及render-generation说明不改写。

## 4. 首轮实时预算、内存与性能失败

硬上限保持：Source≤1MiB/64提交，Tap≤4MiB/2048摘要，每callback≤8192 frames。Tap字节采用单次有界CAS预留，拒绝的预留不增加已接纳预算；任何失败保留原因码并成为OBSERVER_INCONCLUSIVE。16槽及原skippedUpdates语义不变。

实际Row stride=64 bytes，2048行申请131072 bytes；CRC表2048 bytes。连同16槽扩展与8KiB控制元数据预留，结构预算145408 bytes，低于262144 bytes。该数是可审查的申请/结构预算，不是RSS或完整malloc事件测量。回调没有新增显式文件IO、同步日志、锁/等待、容器扩容、Player API、JSON或复杂CRC组合；表与历史在准备阶段分配，音频buffer不归见证器持有。

性能使用实际新增实现和原Timing/16槽结构；每尺寸1000个样本，标准Debug等价未优化编译，比较同内容开启/关闭耗时，新增量=`max(on−off,0)`，包括原扫描、摘要和发布路径的差量。每个合成Run在4MiB及2048行内结束；初始化、分配及统计数组排序在计时之外。未执行音频设备。

| 终版frames | 固定预算ms | 新增p50 | p95 | p99 | 观察最大ms | 预算裁定 |
|---|---:|---:|---:|---:|---:|---|
| 480 | 0.300000 | 0.138374 | 0.158750 | 0.191125 | 0.344708 | FAIL |
| 1600 | 1.000000 | 0.462041 | 0.494334 | 0.526457 | 0.641250 | 本次样本内满足 |
| 8192 | 1.000000 | 2.361875 | 2.457333 | 2.537250 | 14.366792 | FAIL |

预算始终为`min(1ms, frames/16000的1%)`。前一实现阶段测量同样失败：480最大3.554083ms，8192 p50=2.366167ms、最大2.705709ms。之后只修预算记账/资格和规范，再以终版复核；未调阈值、删异常值、增加缓存或为PASS改音频处理。8192的中位数本身已超预算，不能仅归为一次调度尖峰。配对差量有缓存/调度误差，观察最大不是硬实时最坏上界。

动态分配追踪尝试使用本机Xcode Allocations，仅启动合成测试程序；目标停留启动挂起，未取得可用采样。中断/正常终止未完成清理后，按已核验的两个确切PID结束本次追踪器及测试子进程，exit137；不改系统权限、不操作其他进程、不重试追踪。**DYNAMIC_ALLOCATION_OBSERVATION=UNVERIFIED**，不以源码无显式分配或结构预算替代运行分配证明。

历史存储由原Timing对象拥有并在deinit释放；合成关闭测试持有该对象至callback结束。实际App清理中最后一个引用的释放线程及allocator开销尚未取得运行证据，不能宣称所有分配/释放均已证明实时安全，亦须由后续获批的安全核验处理。

因此**PERFORMANCE_BUDGET=FAILED，未来设备准入停止**。没有宣称硬实时安全，也没有修改冻结预算。

## 5. 首轮实际测试、构建、Guard与失败记录

编译源码列表和参数复用原`tools/realtime_interruption_evidence_tests/check.sh`的编译段：`swiftc -D DEBUG -parse-as-library -warn-concurrency -strict-concurrency=complete`及原framework/source列表；本地ignored driver仅保留产物并选择新测试CLI，不修改正式脚本。完整参数和输出留本机。以下终版均在重新编译成功后执行，普通/TSan测试各有独立程序身份。

| 操作 / 实际命令 | 结果 |
|---|---|
| RED：本机复制的原`check.sh m26-only`编译入口，先执行新增旧合同缺口用例 | 1轮，编译成功、断言exit133；单样本幅度改变但旧帧/非零计数相同，原JSON没有内容见证。这是仪器合同RED，非AEC失败 |
| `m31-tests --m31-only`终版 | exit0；6 cases / 3991 checks，device_access=ZERO |
| 独立CRC验证及内容负控 | 标准向量/逐bit、不同分块、改样/换序/丢非零/首尾截断、正负零；全部通过，不修改输入字节 |
| 资格/发布/容量/关闭负控 | 错映射/nil/错rate/逆向、错Run/代次、buffer复用、16/17槽、未发布、2049行、1MiB/4MiB上限、格式/layout/有限性及Stop交错通过；漏记为INCONCLUSIVE，不归为音频损坏 |
| `m31-tests --m26-only`终版 | exit0，原245 checks；含原时间见证器竞争/5ms预算及Output/SRC定点验证 |
| `m31-tests --m20-only` / `--m22-only`终版 | 各exit0；396 / 124 checks；M20包含M19导出检查，设备0 |
| `TSAN_OPTIONS=halt_on_error=1 m31-tsan --m31-only` / `--m26-only`终版 | 各exit0，3991 / 245 checks；没有检测到数据竞争，不代表穷尽所有交错 |
| Stop合成暂停负控 | 普通终版控制登记观察2.042µs，TSan 11.583µs；在callback仍暂停时Stop返回、随后旧发布拒绝。不是实际Engine teardown耗时或硬实时证明 |
| `bash tools/speech_audio_output_tests/check.sh --r3-m01-wav <登记非私人居民素材>` | 1轮exit0；457 checks，其中数字Converter独立对照6 cases / 219 checks；原bit-exact/共享图/边界检查通过，无设备启动 |
| `m31-tests --m31-performance` | 2次已记录测量、每次3尺寸×1000样本；进程exit0表示完成测量，**不表示预算PASS**；两次失败均保留 |
| `xcodebuild … -configuration Debug/Release … CODE_SIGNING_ALLOWED=NO build` | 各2次exit0：首次完整构建及最终资格核验改动后的增量构建；独立DerivedData，不覆盖旧候选、不启动App |
| Release隔离 | Capture非DEBUG投影与起点逐字节相同；Debug有CRC/见证器符号、Release没有；原Output/Converter行为验证通过 |
| Release Route / Architecture / Secret Guard | 各exit0；git diff/文件白名单/隐私检查通过 |
| SwiftFormat 0.64.4 / SwiftLint 0.65.1增量 | 改动范围格式检查exit0；新增lint触发0。两文件原有22项规则债务仍单列（结构长度数值可随新增DEBUG代码变化），全文件lint仍exit2，不冒充全文件清零 |

失败与中间收据：首次两轮GREEN编译分别exit1（AudioChannelBitmap访问和测试表达式类型推断），两次最小修正后3974 checks通过；补齐发布/关闭等覆盖后3988、终版3991。规范拆分测试时又发生一次变量作用域编译错误，单次修正后重新编译通过；一次本地文本定位脚本在写测试前退出。质量编译失败后误用旧程序的普通/回归/TSan收据均标为SUPERSEDED，不用于终版验收，随后明确重编译并重跑上述终版。

本地累计完成收据：M31普通5次、TSan3次（含中间/作废产物）；M26普通3次、TSan2次；M20/M22各3次。增加次数来自新增覆盖、规范整理和终版重编译，不是声学重试。未执行FULL_CURRENT、Python回归（无Python修改）、ASR/DTW、实际Player映射、App音频、麦克风或扬声器实验；真实设备次数0。

## 6. 首轮证据等级、边界及当时建议

**CONFIRMED（离线）：** CRC标准向量及独立算法一致；有序流跨分块可配对；合成内容变化可检出；格式/时间/身份/容量/关闭失败不伪造匹配；原样本和旧门禁未改；Release隔离成立；8192帧新增处理明显不满足既定预算。

**UNKNOWN / NOT_RUN：** 实际Player时间映射可用性、真实Schedule→Tap一致性、仪器对真实调度/声学的影响、瞬时动态分配、硬实时上界、Apple内部AEC参考。没有新的AEC或内容时钟根因证据。Tap匹配即使未来取得，也不覆盖提交点之前的Fade/Converter错误、Tap之后的Mixer/Output、物理扬声器或内部AEC状态；未归属摘要差异也不能直接升级生产缺陷。

**唯一下一步：交主控审核本次性能失败与分配观察缺口，决定是否另行批准最小性能整改；当前保持见证器关闭，不申请设备批次。** 不自动优化、扩大仪器或执行录音。

仅提交两份获准源码/测试及本报告；原始输出、失败回执、合成临时数据和构建产物仅留本机ignored目录。无私人WAV/JSON/UID/Token或私人绝对路径进入Git。原7冲突、索引、status/未合并记录及14项证据size/mtime前后不变。

Stage7 Forbidden Checklist前/后：**PASS**。触碰红线无；生产音频算法、Runtime API、DR schema、平台target、Stage8、正式Gate均不变；不新增Engine/Tap/状态Owner。正常Commit+Push后核验三方HEAD并停止，交主控审核。

## 7. 2026-11-02：最小性能整改与离线复验

### 7.1 准入、修改及因果边界

本轮节点为Stage 7.5.11 / R5-M31-D1。执行前项目/原登记隔离Worktree、clean状态及HEAD/upstream/实时远端均核验为`163bd6257fb370d1e4469e3275f801e1a5ffd980`。未切换/新建分支；跨文件前回滚点`3506bd706ec31431944d2eb0c2376e51ccb099c2`。源码整改提交：**`05aae0944ea373cf43d6652937d2ef6534f58b63`**；本报告另行提交以避免自引用，最终Push后三方HEAD以交付核验值为准。

先分段测量，后仅一次有界源码整改。Capture的diff只有7行：把M31 digest内`for/where + Float.isFinite`改为逐样本`while + Float.bitPattern指数掩码`。没有修改CRC表/更新/组合算法、旧Tap统计、原子操作、队列、Stop、映射、身份、Generation、Epoch、格式/覆盖及全部上限。仍完整验证三声道每个有效样本；没有采样哈希、复用不可信扫描结果、删除负控或增加缓存。

[Apple Float.bitPattern合同](https://developer.apple.com/documentation/swift/float/bitpattern)规定其对应IEEE 754编码。已限定的Float32中，指数位全1（掩码`0x7F800000`）恰好覆盖正负Infinity与所有NaN，其余包含正负零、正规及次正规数均有限。代码读取Float的公开bitPattern，不做不安全内存重绑定或数值变换。新增12种边界编码及4096种固定种子编码，在三声道首/尾位置逐一对照`Float.isFinite`并核对原字节；这与原独立CRC/内容负控共同执行，不把有限样本测试称为穷尽全部位模式。

测试文件只增加有限性等价负控及离线分段诊断入口；原`testM31Performance`与统计函数相对本轮基线全文一致。无优化编译属性/编译级别变更，无AEC/Clock/Converter/Player/Controller/RuntimeCore/DR/正式Gate修改。

### 7.2 热点测量

每段每尺寸1000样本，实际调用原CRC、格式验证及完整digest；有限性隔离项复制原有限循环，使用全部有限的相同合成Buffer。该项是参考循环，不是callback插桩，不能把各段分位数相加当精确调用栈分解。Debug未优化环境及原源码列表/flags保持不变。两次本机Swift interface路径定位未取得文本接口，语义改以Apple官方合同及上述确定性对照核验，未扩大SDK搜索。

| Frames | CRC三声道p50，前→后ms | 原isFinite参考循环p50，前→后ms | 实际digest p50，前→后ms | 格式验证p50，前→后ns |
|---|---:|---:|---:|---:|
| 480 | 0.025000 → 0.026708 | 0.108792 → 0.109291 | 0.134000 → 0.030375 | 83 → 83 |
| 1600 | 0.082458 → 0.089667 | 0.353375 → 0.371583 | 0.435584 → 0.102542 | 83 → 83 |
| 8192 | 0.436458 → 0.448209 | 1.820125 → 1.862625 | 2.238792 → 0.505333 | 84 → 84 |

**SUPPORTED热点归因：** 8192帧首轮digest约2.24ms，其中原有限性参考循环约1.82ms、CRC约0.44ms；整改后CRC保持约0.44ms而实际digest约0.51ms。证据支持新增有限性循环在当前Debug执行方式下主导原开销，**不支持把CRC列为唯一根因**。本轮同时改变循环形态与谓词实现，未进一步把成本归因到单独某个getter、range迭代或编译器指令。

实际共享Input元数据FIFO的独立1000次调用p50/p95/p99/max为0.500/0.583/0.584/35.791µs；隔离无竞争原子序列探针为0/42/42/42ns。0ns表示测量未解析该成本，不代表零成本；Input探针不等于完整Render发布，原子探针也不覆盖竞争。它们只支持固定工作不是已见中位数主热点；真实竞争由原M26及M31负控检查，不能由微基准自证安全。

### 7.3 原口径完整性能比较

同一`--m31-performance`入口，480/1600/8192各1000样本；原`max(on−off,0)`、分位数索引、有效Run上限和所有异常样本保留。无编译/TSan/其他本轮重任务并行参与该完整计时，无系统优先级或设备设置调整。§4历史失败数据原样保留；下表为本轮原实现复测及唯一源码整改后的复验，不选择性替换历史结果。

| 实现 | Frames | 固定预算ms | 新增p50 ms | p95 ms | p99 ms | 观测max ms | 裁定 |
|---|---:|---:|---:|---:|---:|---:|---|
| 原实现本轮复测 | 480 | 0.300000 | 0.134333 | 0.175834 | 0.256458 | 0.374584 | FAILED_BUDGET |
| 原实现本轮复测 | 1600 | 1.000000 | 0.448792 | 0.489417 | 0.523251 | 1.389333 | FAILED_BUDGET |
| 原实现本轮复测 | 8192 | 1.000000 | 2.296334 | 2.437249 | 2.480250 | 2.629082 | FAILED_BUDGET |
| 整改后 | 480 | 0.300000 | 0.031459 | 0.054334 | 0.074084 | 0.197750 | 样本内满足 |
| 整改后 | 1600 | 1.000000 | 0.102208 | 0.134250 | 0.166334 | 0.319625 | 样本内满足 |
| 整改后 | 8192 | 1.000000 | 0.532417 | 0.656500 | 0.694042 | 0.727583 | 样本内满足 |

整改后原预算全部满足，8192帧新增p50相对本轮原实现约下降77%。这是诊断开销改善，不是AEC改善；配对计时仍受调度/缓存影响，观测max不是硬实时最坏上界。未提高预算、丢异常、换小样本或改统计口径。

### 7.4 功能、安全、构建及隐私复验

| 本轮实际执行 | 结果/次数 |
|---|---|
| 新分段诊断`--m31-segments` | 生产实现整改前1次，整改后2次（补固定开销探针后复核）；均exit0、每段/尺寸1000样本；不作性能准入替代 |
| 原完整基准`--m31-performance` | 前/后各1次，exit0；判定见上表，进程exit0本身不作为PASS |
| `--m31-only` | 整改后及终版共3次；各7 cases / 53287 checks、exit0。包含原3991检查和新增有限性等价/不改样本检查 |
| `--m26-only` / `--m20-only` / `--m22-only` | 各1次，245 / 396 / 124 checks、exit0；M20含M19，原门禁、16槽、溢出、关闭与Source/Render负控不变 |
| Output/Converter原脚本及登记非私人素材 | 1次exit0，457 checks（含独立转换6 cases / 219 checks）；无设备 |
| TSan `--m31-only` | 1次exit0，53287 checks，没有报告数据竞争；使用同一整改生产源码，最后仅缩短测试提示文字，未改条件/并发逻辑 |
| Debug / Release构建 | 各1次BUILD SUCCEEDED、exit0，独立DerivedData，未启动App或覆盖旧候选 |
| Release隔离 | 非DEBUG投影与指定基线逐字节相同；Debug存在诊断符号，Release不存在；CRC与原音频路径不变 |
| Release Route / Architecture / Secret Guard | 均exit0；后者分别覆盖源码提交与最终报告提交 |
| SwiftFormat/SwiftLint增量 | 新增违规0；初检1个121字符测试提示缩短，断言不变。原22项规则债务保留，全文件lint仍exit2 |
| Git diff / 3文件白名单 / 隐私 / 原工作区保护 | PASS；7冲突、索引/未合并记录/status及14项证据size/mtime不变 |

没有引入新的显式callback动态分配：整改仅栈上UInt32读取/掩码/循环，不新增表、数组、缓存、Owner、Engine或Tap；原Row64 bytes、历史申请131072 bytes、结构预算145408 bytes及全部容量不变。**以上是静态结构/范围检查，不替代动态分配实测。** 鉴于首轮追踪器未能有效采样，本轮不重新启动该失败追踪器，不扩大权限、不操作无关进程；DYNAMIC_ALLOCATION_OBSERVATION继续UNVERIFIED，原最后引用释放线程风险仍未闭环。

因此仅报告固定离线预算的观测通过；必要安全证据不足，**不报告整体整改PASS，不给出硬实时安全确认或设备准入**。所有测试均为合成Buffer/既有Fake；登记素材只读核SHA后用于原数字转换回归。未读取私人WAV/JSON、未使用实际Player/麦克风/扬声器、未录音或播放、未运行FULL_CURRENT或进入M31-D2，DEVICE_RUNS=0。

本轮没有功能断言/编译失败；有一次增量lint计数比较因上述新增长提示而exit1，提示修正后零新增。动态观察没有新失败重试；首轮失败回执和本轮完整日志均保留本机ignored目录，不上传。

### 7.5 新候选与交付

| 本轮磁盘身份（非实际加载证明） | SHA-256 |
|---|---|
| Capture源码 | `8f8e22fa302d48ddbe5d42ec88eb944bfad3e71a0be9abb3cb5d6a88b24e4951` |
| 测试源码 | `cc2ddca57bed76f41e65796109b7fd828933440ae93a6ae333b4b4fb4bd22d2c` |
| Debug launcher | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug dylib | `b31a16bfde805af4b2ee8c86f66e67026ad26ec0da9b1d044271512c7a6db4bb` |
| Release产物 | `5fc337cb59561943d9db51131b0fd87d622ac70cd7bb597758d017891e5f249a` |

仅上述两份源码/测试及原报告发生修改。源码提交已明确记录，报告提交后正常Push并核验最终HEAD/upstream/实时远端一致；文档自身SHA不自引用，以交付核验为准。真实加载、实际Node↔Player映射及声学结果仍NOT_RUN。

Stage7 Forbidden Checklist本轮前/后：**PASS**。红线无；未改Runtime API/DR schema/平台target/Stage8/正式Gate；不新增音频状态Owner；未修改系统设备、音量或Mic Mode。

**当前唯一下一步：交主控审核本次有界性能改善及仍未取得的动态分配/实时安全证据；停止在M31-D1，不自动复验、启动设备或进入M31-D2。**

```ini
M31_DESIGN=APPROVED
M31_D1_OFFLINE=REVIEW_PENDING
M31_D1_FUNCTIONAL=OFFLINE_PASS
M31_D1_PERFORMANCE=OFFLINE_OBSERVED_BUDGET_PASS
DYNAMIC_ALLOCATION_OBSERVATION=UNVERIFIED
REALTIME_SAFETY=NOT_ESTABLISHED
M31_D1_DEVICE_OFFLINE_CONDITIONS=NOT_MET
M31_REAL_PLAYER_MAPPING=NOT_RUN
M31_DEVICE_EXECUTION=NOT_AUTHORIZED
M31_DEVICE_RUNS=0
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=DEFERRED
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
M31_D2=NOT_STARTED
T3.3=NOT_STARTED
```

## 8. 2026-11-02：实时安全证据补全与离线验收

**本轮裁定：未达到离线实时安全验收。** 动态观察取得有效数据，发现实际Debug路径中的申请/释放；合成生命周期负控支持在途引用安全、Stop不等待新增观察及旧Run隔离，但不能保证最后释放发生在非实时线程。性能仍在原固定预算内，不能用它、TSan或构建通过替代上述安全条件。本节为最新结论，§1–7及其当时状态全部保留。

### 8.1 准入、修改范围与Git身份

执行前原隔离Worktree为clean，HEAD/upstream/实时远端均等于指定基线`7bff51c2030f0455acd07db1ca05eb467d6e5bda`；本地分支仍`codex/reference-host-comparison-preparation`，upstream为`origin/Test3-AppleVP-Clean`。原7项冲突、索引/status/未合并记录摘要及14项证据size/mtime与上次交付一致。未切换Worktree/分支，不执行reset/rebase/stash/clean/强推。

读取仅限AGENTS、Stage7 Checklist、M31设计/本报告、Capture见证器及直接生命周期、当前测试/构建/Guard入口、必要规范和分配观察API依据。沿用用户免除后续范围重复确认的指令；没有读取私人WAV/JSON。跨文件前本地回滚点`ed373bbbce4a397efd6b91433e9b7efdfd8e077a`。

**实际只修改测试文件及本报告。** Capture源码与基线逐字节一致；CRC、有限性、格式、身份/映射、Source 1MiB/64、Tap 4MiB/2048/8192、16槽、5ms快照预算、失败拒绝、默认关闭及Release隔离均未改变。没有生产整改，也没有继续优化CRC。

测试提交为`cc5b94d4d196c36afe51738e35ec6f4bf55ae0cf`。本报告后续单独提交；为避免报告自身SHA自引用，最终报告提交及Push后三方HEAD记录在本节点交付回执。

新增测试位置（本次测试提交行号）：`M31AllocationProbe:8`、`M31CallbackSignals:121`、`M31TimingOwner:127`、`saveM31Performance:4947`、`testM31AllocationObservation:4966`、`observeM31RenderAllocations:5008`、`testM31ReleaseThread:5101`、`testM31CallbackLifetime:5141`、`runM31LastReference:5175`。探针C源码作为测试字符串保留，只有显式`--m31-probe-source`输出和`--m31-allocation`加载；不链接到App。

### 8.2 STATIC_REVIEW：完整新增回调链

| 代码位置（Capture，未改） | 静态事实及限制 |
|---|---|
| `installRenderReferenceTapLocked:4522–4556` | 复用原Player Tap；闭包强捕获当次Timing，weak捕获Engine owner。没有新增Tap或Player API调用 |
| `render:3074–3096` → `contentFingerprint:3304` → `digest:2808` → `CRC64.hash:2668` | 租约/字节预算为单次CAS，失败不等待；只读有效三声道字节、完整有限性检查。循环上限未变；无文件IO、同步日志或动态容器扩容。**源码无显式申请不能排除Swift/框架隐式申请** |
| `enqueue/drain/apply:3466–3535` → `appendContent:3324` | 复用16个预分配Slot，每次最多处理16条复制的数值记录，O(1)追加Row；不持有音频Buffer，不在此组合CRC/构造JSON |
| `enablePlayerContent:3171–3190` | 非实时arm调用CRC.prepare，分配/初始化2048行；Slot数组及16个Slot对象在Timing.init阶段创建，callback不扩容 |
| `finalizedPlayerContent/contentSummary:3192、3338` | 关闭、无在途且原快照资格成立后，控制路径读取历史及做组合/hex/汇总；不会在callback中通过搜索、补零制造配对 |
| `event:3141`、`clearNativeVoiceDebug:4741`、`deinit:2997` | Stop/RouteChange关闭Admission而不等待哈希。Timing还由DebugStats及Tap闭包持有；clear清理属性不等于证明回调闭包已释放。`contentRows`实际deinitialize/deallocate仍在deinit，无显式析构线程限制 |

Row仅含数值/UUID，stride64；存储131072 bytes，CRC表payload2048 bytes；结构预算145408 bytes不变。实际arm中观察到唯一131072-byte申请，以及一个2080-byte申请；后者与表的Array存储相容，不能把该申请大小当完整allocator/RSS统计。容量耗尽走原拒绝路径，未观察到Row或队列扩容；这不代表拒绝路径中整个旧扫描无申请。

### 8.3 DYNAMIC_OBSERVATION：隔离进程实际申请/释放

未重启Instruments、未附加任何其他进程、未扩大权限。使用独立编译的本机合成测试程序，通过显式环境路径加载测试专用C探针。Apple [libmalloc源实现](https://github.com/apple-oss-distributions/libmalloc/blob/main/src/malloc.c)可核对`malloc_logger`、allocate/deallocate flags及参数；该符号是**已弃用的实现SPI，不是App采用的公共API合同**。本机符号及空闲所有权检查成功后才安装，结束时卸载再dlclose；失败不能记作观察成功。

探针只在该测试进程内生效：C固定计数器、线程局部观察区间、64个(type,size)固定聚合槽，无逐事件动态存储/日志或追踪线程。所有事件计数保留，槽不足单列overflow；终版37个观察区间均overflow=0。保存首个对应地址仅用于本机Row释放核验，不公开地址/线程ID。准备探针/TLS、打印及解析均在观察区间外。

正负控：空区间0申请/0释放；实际`malloc(333)/free`为1/1；Swift Array/String为7/7；完整首次arm为2321/2317、225928申请字节。冷启动数值包含运行时初始化，不作为callback开销。观察包括实际完整render、队列延后发布、后续drain/apply、关闭后回调、2049行拒绝及NaN拒绝。

| Frames | witness关闭稳态：申请/释放 | witness开启完整render：申请/释放 | 开启相对关闭的观察差量 | 重复独立digest：申请/释放 | 单声道CRC.hash：申请/释放 |
|---|---:|---:|---:|---:|---:|
| 480 | 1922 / 1922 | 1925 / 1925 | +3 / +3，120 bytes | 3 / 3，120 bytes | 0 / 0 |
| 1600 | 6402 / 6402 | 6405 / 6405 | +3 / +3，120 bytes | 3 / 3，120 bytes | 0 / 0 |
| 8192 | 32770 / 32770 | 32773 / 32773 | +3 / +3，120 bytes | 3 / 3，120 bytes | 0 / 0 |

这些稳态申请均为40-byte块。480帧首次关闭路径另有冷初始化，为1926/1925；8192帧queued/drain/closed分别为32772/32774/32770次申请，释放数相同。Row容量拒绝为9/9，NaN拒绝为6/5；未出现新的131072-byte申请。冷buffer首次digest分别为5/3（480）、4/3（1600/8192），不是重复digest的3/3；不得隐去冷读取差异或外推所有新Tap Buffer已预热。

**CONFIRMED（当前离线Debug）：** callback路径确有申请/释放，见证器关闭时也存在；重复digest存在可复现的3次申请/释放。单独CRC更新本次没有观察到申请，不能据此把新增申请全部归因CRC。`validFormat`冷读取为2/2、后续为0/0。

**UNKNOWN：** 3个40-byte块的具体运行时分配调用点尚未确证。最初怀疑AudioBufferList下标；独立单访问器/成员指针负控均0/0，未支持直接归因，因而没有据此替换生产指针访问或修改CRC。该负控只涉及单访问，不能反推完整digest无申请。此处确认的是安全合同缺口，不是AEC声学根因。

该探针覆盖通过本机libmalloc logger上报的事件，不证明VM/自定义内存池或所有框架内部路径均被覆盖；观察器也会扰动allocator时序。**有效动态观察不等于零申请证明，更不等于真实设备实时安全。** 后续性能测量在无探针的单独进程中执行。

### 8.4 生命周期、并发关闭与析构线程

新增普通/TSan负控复用真实Timing类：在已接纳callback的scan位置合成暂停，分别发captureStopped/routeChanged，再释放控制侧强引用；callback仍持有强引用，完成后旧发布被拒绝，新Run的Render统计仍为0。没有新增生产Owner、等待、后台诊断线程或音频对象。

- **离线支持：** 在途强引用防止提前析构/访问已释放Row；Stop事件在callback仍暂停时返回；关闭后的旧记录不会被当成新Run证据。与原在途摘要INCONCLUSIVE、16槽/容量/身份负控共同通过。
- **实际释放观察：** arm中识别唯一131072-byte Row申请，记录其对应释放；让callback工作线程持有最后引用后，Row在该线程准确释放一次。该释放区间为0次申请、20次释放。没有用预期析构回调代替真实malloc释放事件。
- Stop事件本轮动态观察为3291ns；普通功能测试2000ns、TSan9750ns。它们只是合成Timing.event调用，不是实际Engine Stop/removeTap总耗时或硬实时上界。
- **未闭环风险：** 真实AVAudioNode何时/在哪个线程销毁Tap闭包仍NOT_RUN；没有证明App最后引用始终由控制线程释放。deinit还调用stopObservingEngineConfiguration，若仍有observer，其Foundation清理成本也不能由本次无observer夹具覆盖。

因此UAF/在途/换Run负控通过，**不等于析构线程安全已建立**。合成证据表明析构负担随最后释放者走；实际框架最后引用行为UNKNOWN。本轮没有用TSan PASS替代这一缺口，也不猜测性增加保活Owner、释放线程或新的清理状态机。

### 8.5 原预算性能复测

本次实际源码重新编译；原`--m31-performance`入口、Debug flags、480/1600/8192各1000样本、差量`max(on−off,0)`、分位索引和固定预算均不变。只增加计时之外的可选本地CSV保存，保存全部3000个差量/总耗时及序号，文件0600；没有删除样本。运行时本轮构建/TSan/回归已完成，不与这些重任务并行，无权限/优先级/系统设置改变。

| Frames | 样本 | 固定预算ms | 新增p50 ms | p95 ms | p99 ms | max ms | 预算裁定 |
|---|---:|---:|---:|---:|---:|---:|---|
| 480 | 1000 | 0.300000 | 0.031166 | 0.045750 | 0.056708 | 0.166042 | 样本内满足 |
| 1600 | 1000 | 1.000000 | 0.101625 | 0.128875 | 0.153709 | 0.224042 | 样本内满足 |
| 8192 | 1000 | 1.000000 | 0.514583 | 0.609792 | 0.663750 | 0.732916 | 样本内满足 |

三档预算超限样本均0；开启路径绝对total max分别为0.446875、1.125833、5.335083ms，不能将新增差量冒充完整callback耗时。原历史失败不改写，观察max仍不是硬实时最坏上界。Capture/CRC没有修改，结果不构成新的性能整改或AEC改善。

### 8.6 当前产物复验、失败记录及隐私

| 当前源码实际执行 | 次数、exit及结果 |
|---|---|
| 新编译普通程序`--m31-only` | 1次，exit0，8 cases / 53303 checks；包含原CRC逐bit/组合、有限性、内容/映射/身份/容量/关闭及新增生命周期负控 |
| `--m31-probe-source` → `clang -dynamiclib -std=c11 -O1` → `--m31-allocation` | 终版1次，exit0；C的O1仅用于观察器，Swift Debug工作代码未优化；观察结果是非零申请，不是安全PASS |
| `--m26-only` / `--m20-only` / `--m22-only` | 合格终版各1次exit0，245 / 396 / 124 checks；相同固定非私人居民素材，M20含M19，device_access=ZERO |
| `TSAN_OPTIONS=halt_on_error=1 … --m31-only` / `--m26-only` | 终版各1次exit0，53303 / 245 checks；无数据竞争报告，未穷尽所有交错；不同时启用malloc探针 |
| 原Output/Converter脚本 | 1次exit0，457 checks，其中转换6 cases / 219 checks；合成/登记非私人素材，无Engine/Player设备运行 |
| `xcodebuild … Debug/Release … CODE_SIGNING_ALLOWED=NO build` | 新独立DerivedData各1次BUILD SUCCEEDED、exit0；没有使用旧产物验收或启动App |
| Release隔离 | Capture与基线全文相同；当前Debug有601条见证器/CRC相关符号匹配，Release为0；测试专用SPI不在App源码/链接范围 |
| Release Route / Architecture / Secret Guard | exit0；Secret Guard分别检查测试提交及最终报告；文件白名单/`git diff --check`/隐私检查通过 |
| SwiftFormat / SwiftLint增量 | 格式范围检查通过，新增lint规则计数0；本次测试文件与基线均12项旧债务，全文件lint仍exit2；Capture未变，未冒充全文件无债务 |

失败均保留：首次新增CLI编译遗漏Bool返回，修正后重编译；一次本地编辑脚本在写入前失败并产生重复中间编译，这些中间产物不用于终版验收。初始逐事件探针256/4096槽在准备阶段溢出，8192槽在1600帧路径溢出，均exit133并作废；改为固定64个(type,size)聚合槽，完整保留计数，终版overflow=0，不改变任何见证器容量或性能门槛。没有再扩大逐事件记录或反复重启Instruments。

单访问器负控首次使用无法创建的普通3ch格式而exit133；改为已有DiscreteInOrder(3)登记格式后两种访问均0/0，仅作为归因反证。首次M26回归缺少`M20_RESIDENT_WAV`而文件不存在退出（SIGTRAP；未改断言）；补齐原固定素材及隔离Cache环境后，当前同一新程序重跑通过。两次lint命令路径/参数错误、3项新增规范提示均修正后作增量复核。所有失败/中间收据与完整终版输出留本机ignored目录，不上传。

素材SHA复核仍为`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`。只用合成Buffer和获准的非私人素材；未读私人音频/JSON，未触及原未跟踪证据内容，无ASR、云服务、权限申请、设备HAL实验、App/真实Player/Engine/麦克风/扬声器执行。DEVICE_RUNS=0。

| 当前磁盘身份（非加载/设备证明） | SHA-256 |
|---|---|
| Capture源码（未改） | `8f8e22fa302d48ddbe5d42ec88eb944bfad3e71a0be9abb3cb5d6a88b24e4951` |
| 测试源码 | `2dbccba3b8fda38479d890495f72c2ae653921120022bb8aa572093d21db1f74` |
| 普通测试程序 | `3805e449e8f1c80e9d886f6ea29cc4e69ac8eb5f5463828f2442d4fd5a48b31b` |
| TSan测试程序 | `07978176cb54db8ea896bc2cf053cacc7a045336ca77fd9cbc4b0ade3911d461` |
| 从测试导出的探针C源码 | `3c21f78411d91bb182871e4e374ee6a2c4ba6ec792216fe34327bd41af728e7e` |
| 探针dylib | `5cd3f275e1ae592f9abdba6213daf09d7e130f4a39d415aa94e86bb7c155d71c` |
| 新Debug launcher | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| 新Debug dylib | `deb1218d03350f83a1c0dd82b87bd7b6a0bf92eb61ba0e55977709201d1d6ce0` |
| 新Release产物 | `0459cf77bd61cc4260ec35fb0f1ab1fc6209caec4a28e5e8eb257d91191ebcf3` |

### 8.7 裁定、边界与唯一下一步

- **STATIC_REVIEW：** 固定容量/有限工作及无新增显式IO、扩容、等待成立；没有据此宣称零动态申请。
- **DYNAMIC_OBSERVATION：** 有效的本机离线申请/释放及Row析构线程观察已经取得；结论是存在申请和不受线程约束的最后释放。
- **REAL_DEVICE_VERIFICATION：** NOT_RUN；不把离线结果升级为真实设备硬实时安全、映射通过、AEC根因或Test3准入。

**唯一下一步：保持见证器关闭，交主控审核本次分配及最后引用释放证据，决定是否另行批准调用点级最小整改；当前不进入M31-D2或设备测试。** 没有足够证据安全修改特定分配调用点或实际框架的释放所有权，本轮不猜测性改生产实现。

Stage7 Forbidden Checklist前/后：**PASS**。红线无；只新增测试和追加本报告，未改Runtime API/DR schema/Provider/RuntimeCore/正式Gate/平台target/Stage8；没有新增生产Engine、Tap、状态Owner或长期诊断线程。只提交这两个白名单文件；Push后再核验三方HEAD及原7冲突/索引/14项证据元数据，交付即停止。

```ini
M31_D1_FUNCTIONAL=OFFLINE_PASS
M31_D1_PERFORMANCE=OFFLINE_OBSERVED_BUDGET_PASS
DYNAMIC_ALLOCATION_OBSERVATION=OBSERVED_OFFLINE_ALLOCATIONS
CALLBACK_LIFECYCLE_SAFETY=NOT_ESTABLISHED
REALTIME_SAFETY=NOT_ESTABLISHED
M31_D1_OFFLINE=REVIEW_PENDING
M31_REAL_PLAYER_MAPPING=NOT_RUN
M31_DEVICE_EXECUTION=NOT_AUTHORIZED
M31_DEVICE_RUNS=0
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=DEFERRED
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
M31_D2=NOT_STARTED
T3.3=NOT_STARTED
```

## 9. 2026-11-02：动态分配调用点归因与析构线程定向整改

**当前裁定：新增分配已定位并在离线稳态观察中消除；整体安全验收仍未通过。** 本轮只做一次有依据的产品侧修改：digest的三声道Range迭代改为相同范围的while。生命周期没有足够依据安全修改，保持原实现。原口径性能本次480和8192帧超限，必须恢复为FAILED_BUDGET；不沿用§8的预算通过结论。本节为最新结果，§1–8及所有历史失败原样保留。

### 9.1 起点、范围与提交

起点HEAD/upstream/实时远端均为`a8be3e6c96551cfbed06d45e7c3d2d6de9f5bbfc`，原隔离Worktree clean，本地分支与目标upstream未切换。原7冲突、索引/status/未合并摘要、14项证据size/mtime与§8交付一致；此前9项源码/普通测试/TSan/探针及App磁盘身份重新计算全部匹配。

跨文件前回滚点`af722579754c2cd7f755d6999c31013efda5f530`。实际修改仍仅Capture、直接测试及本报告；代码/测试提交为**`368063b7cbd7ceb5b3b125cf21449422e760239b`**。报告另行提交，最终报告提交SHA及Push后HEAD核验记录在交付回执，避免本报告自引用。

复用AGENTS、Stage7 Checklist、M31设计、§8、既有探针/测试与构建入口；只沿实际所有权链补读Capture、Controller关闭/重置及OutputHost对应函数。没有全仓扫描或读取私人音频/JSON，不修改Controller、OutputHost或其他非白名单文件。

### 9.2 调用点证据：不是根据40-byte大小猜测

在当前实际Capture源码未修改前，重新编译独立`-g`归因程序；Debug/严格并发flags及既有source/framework列表不变，`-g`仅用于此归因产物。普通验收和性能仍使用原无`-g`编译入口。基线Capture SHA为`8f8e22fa302d48ddbe5d42ec88eb944bfad3e71a0be9abb3cb5d6a88b24e4951`；归因程序SHA为`b1e7cd07b75743748a6f315dfe3e561f709a973eda7febaa529f8f6497acf5d8`，独立保存，未被后续程序覆盖。

在原测试专用malloc探针上增加有界调用栈捕获：非观察阶段预热backtrace；仅显式开启的重复digest区间，最多记录3个40-byte申请、每栈最多48帧。捕获重入的分配另计nested，不混入工作计数；符号化/输出在区间关闭后执行。480/1600/8192三档各获得3个实际申请栈，**9个事件的nested均为0**；原64个聚合槽及overflow拒绝保留。没有生产App拦截、系统权限变化或重启Instruments。

实际动态调用关系（从工作代码到观察器）：

```text
MacSpeechPlayerContent.digest(_:) +704
  → Swift.IndexingIterator.next()
  → Swift.Range<A> 的 Collection.subscript.read 协议见证
  → _malloc_zone_malloc_instrumented_or_legacy
  → 本机测试logger
```

三次申请的digest调用位置相同。基线`MacSpeechAudioCapture.swift:2814`为该函数唯一的Range迭代`for channel in 0 ..< 3`；有限性与CRC内部均是while。调用栈及该指令附近的迭代器调用与0/3边界交叉核对，定位于三声道循环，而非AudioBufferList getter或CRC。atos只返回函数及`:0`，**没有伪称取得逐行DWARF信息**；源码行号来自对应基线文本，归因同时依赖真实栈、分段对照及下一节的一次改写前后验证。

| 分段操作 | 离线观察 | 证据边界 |
|---|---|---|
| 保留旧Range形式的三次整数迭代 | 3申请/3释放，120 bytes | 与真实digest栈交叉佐证；不单独用计数作为栈证据 |
| 无Range的三声道BufferList读取 | 首次1申请/0释放，56 bytes | 保留冷读取；未把56-byte具体子调用点写成已确认 |
| 无Range、三声道完整有限性扫描 | 0/0 | 所有有效frame都读取，没有采样或跳帧 |
| validFormat | 首次2/2、48 bytes；后续0/0 | 冷/稳态分开，不声称所有新Buffer均预热 |
| 单声道CRC.hash | 三档均0/0 | CRC代码未改，不将其定性为此次分配原因 |
| 实际基线重复digest | 三档均3/3、120 bytes | 原始申请栈直接来自该实际函数 |

**ALLOCATION_CALLSITE_ATTRIBUTION=CONFIRMED（当前离线Debug环境）。** 工具链为Apple Swift 6.4 / swiftlang-6.4.0.34.1，arm64，macOS 26.6.2。确认的是此构建环境中的Range迭代分配路径，不宣称所有Swift for循环、Release或Apple AEC均有同类缺陷。

### 9.3 单次最小修改及RED/GREEN

Capture只有4行diff（3增1删）：把`for channel in 0 ..< 3`替换为`var channel=0; while channel<3`，在原switch后`channel += 1`。三个声道的顺序、有效frame、字节和有限性谓词完整保留；CRC表/更新/组合、格式/layout、映射、身份、Epoch、Generation、原子操作、队列、容量、关闭及输出调度均未修改。没有其他产品侧尝试或生命周期补丁。

新增零分配断言直接调用实际digest：基线程序`M31_ENFORCE_NEW_ALLOCATIONS=1 … --m31-allocation`在重复digest处exit133，保留`M31 repeated digest must not add allocator events`失败。这是已定位仪器合同RED，不是AEC故障复现。相同断言在上述一次源代码改写及终版重编译后exit0，三档均通过。

| Frames | 基线重复digest申请/释放 | 整改后重复digest申请/释放 | 关闭路径稳态申请/释放 | 开启路径稳态申请/释放 | 本轮增量 |
|---|---:|---:|---:|---:|---:|
| 480 | 3 / 3，120 bytes | 0 / 0，0 bytes | 1922 / 1922，76880 bytes | 1922 / 1922，76880 bytes | 0 / 0 |
| 1600 | 3 / 3，120 bytes | 0 / 0，0 bytes | 6402 / 6402，256080 bytes | 6402 / 6402，256080 bytes | 0 / 0 |
| 8192 | 3 / 3，120 bytes | 0 / 0，0 bytes | 32770 / 32770，1310800 bytes | 32770 / 32770，1310800 bytes | 0 / 0 |

本轮终版43个观察区间均overflow=0；空负控0/0，malloc/free正控1/1，Swift容器正控7/7。完整首个开启render也分别为1922/6402/32770次申请和释放；480帧关闭路径首次冷观察为1925/1925，不能混作稳态差量。

整改后冷digest三档仍各有1申请/0释放、56 bytes，重复调用为0/0；该冷现象未被删去或升级为“全路径无分配”。原扫描先访问Buffer相关属性，实际开启/关闭配对观察未见新增申请。不能据此保证所有真实Tap冷路径与本夹具相同。

480/1600/8192的queued观察分别为1921/6401/32769次申请，后续drain为1923/6403/32771，关闭后为1922/6402/32770；各释放数相同。Row容量拒绝6/6、NaN拒绝5/4；没有Row或队列扩容。原有关闭路径申请并未消失，本轮不把这些旧申请混入M31修复成效，也不扩展修改它们。

### 9.4 真实所有权、析构风险及本轮未改原因

以下位置为当前Capture源码（仅此前循环带来后续行号+2）：

| 所有者/路径 | 已确认事实 | 不能证明的部分 |
|---|---|---|
| `nativeVoiceTimingDebug`与DebugStats.timing | 既有Engine owner属性及统计结构持有Timing | 这两处不是唯一强引用 |
| `installRenderReferenceTapLocked:4524` | 原Player Tap闭包强捕获当次Timing；`if let timing`调用中也有在途强引用 | Apple框架最终何时/在哪个线程销毁闭包，不可由离线静态源码确认 |
| 配置通知闭包 / `deinit:2999` | 通知以weak self登记，执行时可临时持有强引用；deinit调用stopObserving并释放Rows | 若带有observer的deinit落在实时/通知线程，Foundation清理成本未验证 |
| `admitPlayerContentCallback:3289`、Stop/RouteChange事件 | 关闭位阻止新内容哈希租约；旧回调仍可进入原metadata入口，随后按原关闭/身份规则拒绝 | 不等于同步销毁所有Tap闭包或在途引用 |
| `clearNativeVoiceDebug:4743` | 控制路径停止observer并清理两个属性；许可条件是已sealed或Capture未active | 该API未以自身条件保证所有Render闭包引用已释放 |
| Controller `closeAppleVPAcousticRunForShutdown:8607`、`resetAppleVPAcousticPreparation:7970` | 正常关闭先Output.close、Capture.shutdown，后续重新准备时clear；Capture.tearDownGraph沿原路径removeTap/Stop/Reset | 正常顺序是支持证据，不能代替框架最后释放线程的可执行保证 |
| `nativeVoiceTimingSnapshot:4862` → `finalizedPlayerContent:3194` | 先在lifecycleLock内取得强引用，再在锁外读已封存历史；当前依赖Timing存活来保护Row存储 | 不能只在clear中提前free Rows，否则还需处理锁外摘要读者与在途租约；本轮没有实施这种可能引入UAF的改法 |

本次普通/TSan负控继续验证：在途callback被合成暂停，Stop/RouteChange不等待它；控制侧引用消失后，callback强引用保持对象有效；恢复后旧发布被拒绝，新Run不被污染。未观察到当前实现UAF、双重释放或数据竞争，不外推为穷尽性证明。

实际Row释放观察再次得到：最后引用由合成callback工作线程释放，唯一131072-byte Row在该线程释放1次，区间0申请/20释放。Stop事件观察3750ns，普通功能测试2959ns、TSan10084ns；均非真实Engine Stop或硬实时上界。

**本轮不修改生命周期。** 没有在本白名单/禁止新增等待、Owner、释放线程或复杂状态机的条件下证明安全的最小改法。既要保证非实时释放，又要保留在途回调和锁外摘要读取的存储寿命，不能简单把deallocate前移到Stop/clear。实际Apple音频回调成为最后释放者仍UNKNOWN；有明确的离线风险模型，尚无真实音频线程执行证据。CALLBACK_LIFECYCLE_SAFETY及REALTIME_SAFETY继续NOT_ESTABLISHED。

### 9.5 原口径性能：本轮必须裁定失败

最终无探针普通程序，原`--m31-performance`，480/1600/8192各1000样本；原函数、`max(on−off,0)`、分位索引、预算和CSV保存逻辑相对起点未变。先结束构建/TSan/回归再测量，不并行运行本轮重任务；探针未加载，无系统优先级/音频配置调整。仅测量1次，所有3000样本及失败样本留本机0600 CSV。

| Frames | 固定预算ms | 新增p50 ms | p95 ms | p99 ms | max ms | 超限样本 | 裁定 |
|---|---:|---:|---:|---:|---:|---:|---|
| 480 | 0.300000 | 0.029834 | 0.049626 | 0.376376 | 3.856667 | 13 / 1000 | FAILED_BUDGET |
| 1600 | 1.000000 | 0.100792 | 0.127542 | 0.149417 | 0.212834 | 0 / 1000 | 样本内满足 |
| 8192 | 1.000000 | 0.508166 | 0.600625 | 0.636251 | 1.005125 | 1 / 1000 | FAILED_BUDGET |

开启路径绝对total max为4.133917/1.139542/5.701417ms；不把增量当作完整callback耗时。没有证明尾部超限原因，不把它仅归为系统抢占；不以更低中位数或零新增申请抵消失败，不重跑筛选、删样、提高预算或作第二轮性能整改。§8的通过数据仍保留，但不作为本轮通过依据。

### 9.6 当前源码复验、规范与失败记录

| 实际执行 | 次数/结果 |
|---|---|
| 归因程序及实际申请栈 | 修改前合格1次exit0，9个真实事件、nested=0；原型观察另1次exit0，后续合格产物单独保存并登记SHA |
| 零新增分配合同RED / GREEN | 实际基线RED 1次exit133；终版GREEN 1次exit0，43区间无溢出，三档重复digest及完整开启/关闭配对如上 |
| `--m31-only` | 终版1次exit0，8 cases / 53303 checks；原CRC逐bit/组合、有限性与全部内容/映射/身份/容量/关闭负控保持 |
| `--m26-only` / `--m20-only` / `--m22-only` | 终版各1次exit0，245 / 396 / 124 checks；M20含M19，device_access=ZERO |
| TSan `--m31-only` / `--m26-only` | 终版各1次exit0，53303 / 245 checks；无数据竞争报告，不能替代析构线程或硬实时证明 |
| 原Output/Converter脚本 | 1次exit0，457 checks，其中转换6 cases / 219 checks；用原登记非私人居民素材，无设备 |
| Debug / Release构建 | 新DerivedData各1次BUILD SUCCEEDED、exit0；App源码在之后测试夹具修正中未改变，未使用旧App候选或启动App |
| Release隔离 | 非DEBUG源码投影与起点逐字节相同；Debug见证器/CRC符号匹配601，Release为0 |
| 原三项Guard | Release Route / Architecture / Secret均exit0；Secret覆盖源码/测试提交及最终报告 |
| SwiftFormat / SwiftLint增量 | 格式检查exit0，无新增规则计数；两源码原22项债务不变，全文件lint仍exit2 |
| 文件范围 / diff / 隐私 / Stage7 Checklist | PASS；只改3个白名单文件，未改Owner、AudioGraph、Converter、AEC/AGC/NS、CLOCK、Controller或正式Gate |

一次测试夹具失败如实保留：首次预期GREEN在480帧处因新增稳态观察后重复了queued/drain的sampleTime，被原门禁拒绝（子进程SIGTRAP，外层exit1）。修正仅为把新夹具的最后一个位置从2 buffers改为3 buffers，原断言/时钟容差不变；重新编译普通/TSan产物并重跑全部定点验收。此前普通/TSan各模式已完成的1次通过作为中间收据，不替代终版。没有第二次产品侧修复尝试。

本次两次提交前远端只读复核出现GitHub TLS `SSL_ERROR_SYSCALL`，exit128；不能用该失败推断远端HEAD相同或不同。没有更改认证/TLS校验或系统网络设置。后续正常Push是否完成、最终三方HEAD是否核验成功，以本节点交付回执明确记录，不将本地Commit当作已推送。

### 9.7 新产物身份与最终状态

| 当前磁盘身份（非实际加载证明） | SHA-256 |
|---|---|
| Capture | `285dfa966ca6b6ae39276ce5aaa544626998f0bb8949819c4a31d4c0875ff5dd` |
| 测试源码 | `e75f74511f888a76cb1577c6710aefbc46db2dfee132441b88ceb9f9864c6535` |
| 普通测试程序 | `3b8fec6bbec5bc7892b23631513a540b49ac25714639ec9a973d017baa9e66e9` |
| TSan程序 | `1a758bb275308f8e4a63b43f8fbdf1f77bd0b83680f873878ce41a9cd013e5e9` |
| 终版探针C源码 | `a29b69091001a3b4d14725aae8bbb37e534e500e5aa8b2047d28cc54627aa288` |
| 终版探针dylib | `4db01c7073d198534f83bbcc99bf1796c30f177922e8d3a55422d7c110233621` |
| 新Debug launcher | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| 新Debug dylib | `2875df92df73c76e814f5a543681be0a2a8e3a901880f0aa65a879e93282cfeb` |
| 新Release产物 | `d357e65989f25169e28d97f2f0e6ea4aa89090d82b4527fb9360bb8eeaf44f6c` |

仅合成Buffer及原登记非私人素材（SHA `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`）。未读取私人录音/JSON，未运行真实Player/Engine、麦克风、扬声器、录音、ASR或声学实验；PRIVATE_AUDIO_UPLOAD=0，DEVICE_RUNS=0。原始栈/地址、日志、CSV、探针临时文件与构建产物仅留本机受控ignored目录，不提交Git。

**唯一建议：继续留在M31-D1，提交主控审核尚未满足的性能及控制侧释放保证；本轮不建议评估M31-D2。** 不自动开展第二轮整改、设备验证或其他节点。

Stage7 Forbidden Checklist前/后：**PASS**。触碰红线无；未改Runtime API、DR schema、平台target或Stage8；没有新增生产Engine/Tap/状态Owner/诊断线程，旧Guard及所有冻结预算/门槛不变。最终交付后停止。

```ini
M31_D1_FUNCTIONAL=OFFLINE_PASS
M31_D1_PERFORMANCE=FAILED_BUDGET
NEW_CALLBACK_ALLOCATIONS=OFFLINE_OBSERVED_ZERO_INCREMENT
ALLOCATION_CALLSITE_ATTRIBUTION=CONFIRMED
CALLBACK_LIFECYCLE_SAFETY=NOT_ESTABLISHED
REALTIME_SAFETY=NOT_ESTABLISHED
M31_D1_OFFLINE=REVIEW_PENDING
M31_REAL_PLAYER_MAPPING=NOT_RUN
M31_DEVICE_EXECUTION=NOT_AUTHORIZED
M31_DEVICE_RUNS=0
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=DEFERRED
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
M31_D2=NOT_STARTED
T3.3=NOT_STARTED
```


## 10. M31-D2：受控撤回与 T3.2-A 阶段收口（2026-11-03）

**裁定：M31 诊断实现已完成可证明边界内的撤回；M31-D2 为 PARTIAL，正式离线入口仍有阻塞，T3.2-A 不满足下一节点准入。** 本章是当前状态；§1–9 是不可追溯改判的历史记录。停止 M31 性能优化，不新增替代内容见证器，不将撤回作为 AEC 或硬实时安全验收。

### 10.1 任务、Git 身份与保护门禁

- 起点：`1fcee1332eead9cea2fbad3b4e31d34ac5ee7405`，开始时 HEAD、upstream 与实时远端完全一致，工作区 clean。
- 仅使用原 `vp-reference-host-preparation/Eterna_Aftelle` 隔离 Worktree；本地既有分支 `codex/reference-host-comparison-preparation`，追踪 `origin/Test3-AppleVP-Clean`。没有新分支、切换 Worktree、checkout、reset、rebase、stash、clean、强推或解决旧冲突。
- 跨文件修改前的可审计空回滚点：`340ce0896a0defee5500cbf2ed9ec2b7e4d2dc64`。
- 最小撤回源码/测试提交：`19002b3261836cbb6f4180dc14a3b9a1ecd54f55`。本章及 README 为其后的文档收口提交，最终完整交付 SHA、Push 和三方 HEAD 查验由本轮交付回执记录，不能把源码提交冒充文档交付 HEAD。
- 原受保护 Worktree 的 7 项冲突、索引及 14 项未跟踪证据已作前后元数据核对；只核验 HEAD、status、unmerged、index 摘要及文件大小/mtime，不读取证据内容。本轮不访问私人 WAV/JSON、设备 UID、居民原句或历史私人日志。

实际修改仅四个授权文件：本 Capture、原定向测试、本报告追加部分、README 最小状态索引。其余生产实现、正式计划、工具、冻结评分器与测试断言均只读。

### 10.2 依赖清单与撤回依据

不是整体回滚某个历史 Commit。先审计 `ee94a74869e803eb3f66f97bb57995147153fb82`（M31 实现前）至任务基线在两份源码中的全部差异，再对已证实仅属于 M31 的差异逐文件撤回。区间内源码变更为 M31 初版、性能整改、分配/生命周期审计及已归因循环修正，没有其他节点的音频功能混入。

| 分类 | 实际处置与证据 |
|---|---|
| A：M31 内容实现 | 删除 `MacSpeechContentCRC64`、`MacSpeechPlayerContent`、Source/Render 指纹、内容 Identity/Row/Mapping/Summary、Epoch/内容租约及容量状态；删除 `contentRows` 分配、131072-byte Row 析构、`appendContent`、内容时间映射和封存后内容摘要 |
| A：接入/出口 | 删除 schedule 前的内容准备/提交、Tap 内指纹计算、CallbackRecord 指纹、额外 timestampRate、`enablePlayerContentWitness`、最终内容查询与可选 `playerContent` JSON 字段；原已有时间/格式/覆盖字段保留 |
| A：测试/探针 | 移除 M31 CRC、内容、映射、性能、分段计时、分配拦截 C 源码与生命周期探针的执行实现；旧 M31 执行参数明确拒绝。原函数和历史源代码可按原 Commit 完整追溯，不删除本机历史收据 |
| B：既有观察与控制 | 保留 `MacSpeechTimingSnapshot`、`MacSpeechNativeVoiceTiming`、16 槽发布/消费、溢出拒绝、原 event、Input/Render 连续性、scheduled/nonzero 计数、Stop/RouteChange/Generation/Stale 规则及 M12/M19 证据 |
| B：M20/M22/M26 | 原 App 同意、批次次数、Stop、导出/退出、身份及声道合同保留；未改控制器、Python 批次脚本、评分器、阈值或计划，没有新设备计划/授权消耗记录 |
| C：正式能力/Test2 | 未改 Apple VP、AEC/AGC/NS、Clock、Converter、Player 调度、AudioGraph、Provider、RuntimeCore、DR 或正式 Gate。Test2 已批准的历史能力与失败记录均不撤销、不重新宣称批准 |

**机械边界证明：** 当前 `MacSpeechAudioCapture.swift` 与上述 M31 前锚点逐字节相同，SHA-256 为 `f8cf47b0de2205e7e70177db6c16ceb0a615730892d4ae605e6fdee9cc45d49c`。测试移除新增撤回检查及其小型分派后，与该锚点的原测试函数/路由逐字节相同；M26 原分支仅放入测试模式分派函数，所有旧测试函数体及断言不变。

依赖查询限定 tracked Swift/Python/shell：M31 具体类型与调用只在这两份源码中存在，Controller、M20/M22/M26 与正式自动化没有消费该新增 JSON 字段；撤回后实现符号/调用引用为 0。保留的一处 `playerContent` 文本是测试 JSON 字段不存在的负控，不是残留执行入口。

当前关键源码位置：Capture `MacSpeechTimingSnapshot:2654`、16 槽 Timing `:2680/:2686`、原 event `:2846`、Input/Render/scheduled `:2888/:2896/:2912`、原队列/消费 `:2955/:3020`、schedule `:3379`、teardown/route `:3671/:3723/:3749`、原 Player Tap `:4012`、clear/snapshot `:4230/:4318`。撤回检查在测试 `testM31Withdrawal:4232`，独立模式分派 `runWithdrawalTestMode:4290`；共 8 项断言。

### 10.3 最小 diff、风险与保留的能力边界

源码提交相对起点：Capture `+31/-579`，测试 `+40/-1087`，合计 `+71/-1666`。新增行主要是恢复原 event/路由位置及 8 项撤回检查；不是新音频功能。文档仅末尾追加和入口索引，不覆盖任何旧 FAIL。

当前检查证明原 scheduled/render 帧数、非零计数、Run/Configuration/Generation 仍可导出；Stop 和 RouteChange 后旧 callback 被拒绝，旧身份不能进入新 Run。**原 `nonzeroCoverage` 继续为 `UNKNOWN: scheduled-to-player content alignment is not established`。** 不再提供内容逐样本/指纹一致性资格。

M31 新增的哈希/Row 路径不再存在，因此其回调增量和大块 Row 随最后引用析构的风险不再属于当前实现；这依据删除后的实际源码和产物引用，不是一次“零分配实测”。旧 Timing/闭包/observer 的既有申请、释放与 Apple 框架线程行为没有被优化或获得新的硬实时保证。不能把撤回或 TSan PASS 写成整个回调实时安全已建立。

所有历史结论保留：§1–9 的全部性能失败及曾观察到的通过、分配现象、§9 Range 调用点归因与新增稳态申请消除、随后 480/8192 帧尾部预算失败、最后引用析构线程未闭环，均不改判。§9 的 480 帧 13/1000、8192 帧 1/1000 超限和 Row 释放证据仍有效于当时版本。未再次运行 M31 性能/分配探针，不将其旧结果作为当前功能验收。

### 10.4 本轮实际离线复验

普通和 TSan 测试均从本轮实际源码新编译；Debug/Release 各用新 DerivedData 构建，没有启动 App 或真实 Player/Engine。只使用合成 Buffer 及原登记非私人居民素材（SHA `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`）。

| 检查 | 当前结果与范围 |
|---|---|
| 撤回 `--m31-withdrawal-only` | 终版 exit0，8 checks；JSON 出口、原帧/非零/身份、Stop/RouteChange 及旧代拒绝；无设备 |
| M26 / M20 / M22 | 终版各 exit0，245 / 396 / 124 checks；M20 包含 M19；device_access=ZERO |
| TSan | 终版撤回/M26 各 exit0，8 / 245 checks，无数据竞争报告；不外推为 Apple 音频线程硬实时证明 |
| 原 Output/Converter 入口 | exit0，457 checks，其中 3ch Converter 合成对照 6 cases / 219 checks；原字节/排程合同保留 |
| Host / 原 Playback | 正式 FAST 中 exit0，178 / 238 checks |
| 原 AEC full 脚本 | exit1，在测试执行前因旧编译成员缺失而失败，详见下节；不记 PASS |
| 补充 AEC 单元 | 现有 `MacSpeechAcousticEchoHostTests.swift` 以完整当前 Host 源码依赖独立新编译，exit0，1206 checks |
| 补充原 Capture 诊断 | 同样只修正本机临时编译依赖、不改测试：RawTimestamp 8 cases / 141 checks；D1 Native Stats 16 / 77；VP Profile 19 / 51；Warm-up 26 / 92，均 exit0、无设备 |
| 原输入 Converter / ch0 资格 | 原非 DEBUG 编译参数和源码列表，exit0，65 cases / 6830 checks；其中声道映射 12 / 3194；合成数字行为，不外推物理声道语义 |
| Debug / Release | 各 1 次 BUILD SUCCEEDED、exit0；其后只整理测试分派与报告，App 源码/构建输入未变 |
| Release 隔离 | Capture 非 DEBUG 源码投影与任务起点逐字节相同；Debug 与 Release 的 M31 相关符号均 0；原 Timing 相关符号 Debug 515、Release 0 |
| Release Route / Architecture / Secret Guard | 正式 FAST 及源码提交前均 exit0；文档交付前再次检查最终暂存范围 |
| 规范 / diff | 新增测试范围 SwiftFormat lint exit0；两源码 SwiftLint 仍 exit2，原 22 项规则计数不变、无新增规则违规。开发中一次新增 force_cast/主函数长度提示已仅在测试侧消除，不改旧断言；历史 C19/C23 不改判 |

补充编译不是修补正式脚本：使用既有实际测试，加入当前完整 Host 编译成员（含 M26 类型实际所在的 OutputPlayer 等），临时 driver/产物仅留本机忽略目录。它证明这些程序中的离线行为，但不替代正式入口的资格和失败结果。初版撤回测试曾先完成一次通过；测试侧取消强转并隔离模式分派后，重新编译普通/TSan 并完整重跑上述终版 M20/M22/M26/撤回，不复用旧二进制。

### 10.5 正式自动化的两个现有阻塞

1. **FAST：7 PASS / 1 FAIL，总 exit1。** 最后 `debug-stats-timing` 调用只读的 `tools/speech_aec_host_tests/check.sh d1-stats-only`，其 Debug 编译列表缺少定义 `MacSpeechChannelAllocation` 的当前源文件，实际报类型不在 scope。原 full 脚本也在同一依赖处失败。该脚本 SHA `43e56747bd7fdc73c302b0e11ac9a6cd74ca79bffc21f071a78b17728a5e8b7b` 与任务起点相同；M26 类型引用在起点及 M31 前 Capture 已存在。因此确认是当前既有入口的编译成员缺口，不能归因为本次 M31 撤回，也不能据此断言 AEC 失效。
2. **TEST3：BLOCKED，总 exit2，候选执行次数 0。** 原固定合成 fixture `apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident` 在准备时即不存在；原 runner 给出 `Fixed offline fixture missing`，未执行其 7 入口/11 不变量。本轮未补造、替换 fixture 或删掉检查，不把历史 T3.0-F/Test2 PASS 当作本次重验 PASS。

两个正式模式各尝试 1 次，保留原收据；没有重新跑 FULL_CURRENT 或 legacy FULL。自动化记录的 source_commit 是回滚点 `340ce0896a0defee5500cbf2ed9ec2b7e4d2dc64` 及当时工作区身份，不冒称最终文档提交；其中失败的实际 Capture 与本轮源码提交完全相同。随后测试模式分派整理不影响 FAST 编译单元，TEST3 始终未执行，故不重复同一失败入口或降低它的断言。正式原脚本/fixture 不在本轮修改范围，**APPLE_VP_BASELINE_REGRESSION 只能为 PARTIAL。**

### 10.6 冻结磁盘身份（不代表加载/设备准入）

| 产物 | SHA-256 |
|---|---|
| 当前 Capture | `f8cf47b0de2205e7e70177db6c16ceb0a615730892d4ae605e6fdee9cc45d49c` |
| 当前定向测试源码 | `af6cfe7d895ef30da25799f89d01bb029f4913a363377c1df23907ee84d9754d` |
| Debug launcher | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug dylib | `0555edf68c36feb73b36f06b0ef71fa2f50b51ec97cf7f73814ab9a6e23309b0` |
| Release executable | `9cc916fe56e69630625028a7272e25f9cdb2da6a9353f94371f1659b424197d7` |

没有创建设备批次、启动进程或核验实际加载，不复用旧设备授权。日志、原始测试输出、构建产物及临时 driver 只留本机忽略目录，不提交 Git。

### 10.7 T3.2-A 正式状态与未关闭事项

依据 [T3.1-R2 正式方案 §7–9](T3_1_R2_native_voice_experience_plan.md) 与 [正式入口](README.md)，本轮区分机械实现、诊断交付、声学资格、下一节点授权：

| 事项 | 已有事实 / 当前阻塞 | 所属后续范围与处理方式 |
|---|---|---|
| Apple VP 机械实现 | 既有共享 Engine、VP 配置/读回、Capture/Playback/Converter、Generation/Stop/Route 安全与本轮可执行离线回归保留；没有生产 AEC 代码根因修复 | T3.2-A 保留实现；补齐本章正式入口阻塞后重新作独立离线资格判断，不用部分 PASS 取代全部门禁 |
| M31 诊断研发 | 历史功能测试、CRC 归因及失败已留档；性能与析构线程条件未验收，当前实现撤回 | M31-D1 `BLOCKED_CLOSED_FOR_REWORK`，本路线收口；本轮不建议继续性能优化或再造诊断系统 |
| AEC 最终声学资格 | M27 跨运行强残留已复现；M28 R2 约 3.28 秒模板匹配、99.665% PCM 能量位于 Render，差异已在 VP 后 Native；仍未确认根因。一些低残留及用户未听到回声不能证明稳定 PASS | T3.2-A 路线特定纯回声/真人完整性/双讲的正式资格仍需主控另行决定；本轮不增加录音或替代物理见证 |
| CLOCK | 历史约 2–3ms hostTime 偏差与 fail-closed、generation reset 恢复已有证据；本轮保留拒收、诊断及合成回归，不代表根因确认 | 独立 CLOCK 问题保持 UNKNOWN；只接受后续有明确新证据的单独授权调查，不放宽容差、不混入 AEC 判定 |
| 起音 / R3-M01 | 历史“听不到居民回声，但是有起音”的性质/影响未正式验收；M24 四段非语音短促声分类不等于工程声源或资格确认 | T3.2-A 声学起音项 OPEN；不得以 M31 撤回、合成 onset 或自动化 FAIL 替代听感/技术联合判断 |
| SQ-M1 | Apple 处理结果与既有声学接口的兼容/安全未收口；机械 PCM 可运行不关闭此项 | OPEN；限制 T3.3 安全验收、T3.4 正式开放及 T3.5，不新建复杂声源资格体系 |
| Test2 与正式离线再验 | 原已批准的身份/Decision/cancel/clear/N+1/Session/Memory 安全合同保留，本轮未改这些源码；TEST3 因 fixture 缺失未重验 | 原批准历史保持；恢复固定原 fixture 与正式编译成员后才可补本轮完整回归，不重写旧 FAIL/期望摘要 |
| T3.2-B / T3.3 与 Human Gate | A 尚未正式冻结，SQ-M1、起音/声学及离线准入未闭环；Qwen Strict Overlap 仍为历史 0/3，T3.P 独立 | B 本轮 NOT_AUTHORIZED；T3.3 NOT_STARTED，不进入 Runtime 接口或后续 T3.4/53-A～E Human Gate；正式 Test3 BLOCKED/false |
| M18-E01 / 工程债务 | 原 EOF minor deferred 与 C19/C23 不属于本次撤回，不因诊断退出而消失 | 保持 DEFERRED / 原登记的 Stage7.5 后治理，不能把任意小 BUG 命名为 AEC 根因 |

**下一节点准入：不满足。** 没有新的 APPROVED/FROZEN，没有正式 Test3 次数、STS 插话验收、真实硬实时或 Apple 内部 AEC 参考路径的证明。不能将自动化编译失败解释为 Apple AEC 失效。

**唯一下一步建议：交主控独立审核本次撤回及 BLOCKED 收口；如要恢复工程准入，单独批准修复原正式离线回归入口（补全既有 M26 编译依赖并恢复原固定合成 fixture），保持原断言与身份检查。** 不再沿同一 M31 诊断优化路线推进，不默认安排无目标设备实验。

### 10.8 检查、交付与停止

历史 §1–9 与起点逐字节前缀一致；只追加本章，README 只加当前索引。旧源码、回滚点、失败报告和本机原收据不删除。Stage7 Forbidden Checklist 前/后 **PASS**：无 Runtime/DR 契约、平台 target、Stage8、音频算法、Owner、线程、正式 Gate 或设备权限变更。最终暂存白名单、diff、隐私检查及原保护状态复核后，按用户要求正常 Commit + Push，无论本章 PARTIAL 均交付，不用本地 Commit 代替 Push。

```ini
M31_D1=BLOCKED_CLOSED_FOR_REWORK
M31_D2=PARTIAL
M31_WITHDRAWAL=COMPLETED_OFFLINE_VERIFIED
APPLE_VP_BASELINE_REGRESSION=PARTIAL
RELEASE_ISOLATION=PASS
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
SQ_M1=OPEN
T3.2_A=BLOCKED
T3.2_B=NOT_AUTHORIZED
T3.3=NOT_STARTED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
DEVICE_RUNS=0
```

最终 COMMIT_SHA、PUSH_VERIFIED 以正常推送后 HEAD = upstream = 实时远端的独立交付回执为准。完成后停止，等待 ChatGPT 主控审核；不启动设备、不进入下一节点。
