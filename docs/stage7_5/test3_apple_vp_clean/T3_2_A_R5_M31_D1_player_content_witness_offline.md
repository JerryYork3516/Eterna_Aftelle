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
