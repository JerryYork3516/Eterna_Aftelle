# T3.2-A · R5-M09 · Raw Timestamp Diagnostics

日期：2026-10-22。结论：**离线准备通过；等待新的设备授权**。本节点没有修复或放宽时钟校验，没有验证历史时钟偏差或AEC根因。

## 1. 身份与范围

- 开始时本地HEAD、upstream、实时远端均为 `fb3303b0465f863027f3d6c4c80c0afabaad6b9f`；目标远端分支 `Test3-AppleVP-Clean`。
- 在已登记的干净隔离Worktree实施；跨文件修改前本地回滚点 `8ee6861`（空checkpoint）。最终交付提交由Git提交记录及交付回执确认。
- 修改仅限 Capture DEBUG诊断、AppController既有JSON出口、直接定点测试/脚本和本报告。没有读取历史WAV/PCM、私人Manifest或原始设备日志。
- 原冲突工作区的7个冲突文件内容、HEAD、索引、unmerged记录及14个未跟踪文件的大小/mtime与既有保护基线一致；仅只读核验。

## 2. 字段与固定窗口

既有Native统计现在附带 `raw_timestamp_diagnostic`。正常连续时钟输出 `null`；首次既有 `native_clock` / `content_time` 拒收或缺失host时间时冻结异常位置，保存前2次、当次及后最多2次callback，最多5条。缺少前史或停止导致后史缺失时不补造；`following_status=unavailable_after_seal` 明确标记封存时不完整的后史。

| 覆盖项 | 导出内容 |
|---|---|
| 原始AudioTimeStamp | sampleTime、host ticks、rateScalar、word clock、全部SMPTE字段、mFlags、reserved |
| 有效性 | host/sample flags；rateScalar的flag、有限性及正值判定；不改变既有时钟判定 |
| 原始数值 | sampleTime/rateScalar保留Double bit pattern；非有限JSON数值为null，原始bits仍在 |
| 两种采样率 | AVAudioTime.sampleRate与buffer ASBD sample rate分别保留 |
| 当前buffer | frameLength及完整ASBD标量字段，含channel数、格式flags、字节/帧/包等 |
| 相邻差值 | 转换后的host ns差、sample frames差、前buffer帧数推导的名义预期差 |
| 到达时间 | 原有DispatchTime callback arrival及相邻差，仅作辅助 |
| 身份 | 从同一不可变Native快照导出RunID、generation、configurationID及sealed状态 |

新快照复制的是**时间戳元数据**，不持有AudioTime/PCM buffer对象或样本。Native仍是Apple VP处理后信号，不是Pre-VP原音。原始host ticks依SDK `AudioTimeStamp.mHostTime` 的mach_absolute_time语义保存；ns仍由既有AVAudioTime换算，不更改时钟域或把arrival当内容时间。

## 3. 同步、容量与行为隔离

- 固定5个optional值槽，当前arm64 ABI实测 `MemoryLayout.stride=840 bytes`；正常路径滚动前史，首次异常后只填2槽，满后停止采样诊断字段。
- 复用已有 `captureProcessingLock`；未新增锁、队列、Engine、Tap、Gate或状态Owner。新记录仅C结构/标量复制和有界赋值，无数组增长、文件IO、同步日志、JSON编码或重试。
- snapshot读取继续在原控制路径锁内复制，字典/数组构造及JSON编码只在既有非实时导出调用发生。该判断是源码/离线证据，设备端耗时、锁竞争及实时调度影响仍 **UNKNOWN**；没有声称整个原callback无锁或零开销。
- 原configuration/generation及sealed门禁保护记录。错误身份元数据直接忽略，不增加既有拒收计数；合法旧host但被原fence拒收的callback不进入当前窗口。缺失host仅在身份匹配时记录，原fence拒收不变。
- Stop/route rebuild原封存行为保留；clear/重新arm通过原统计对象生命周期释放记录，不自动reset generation，不等待后续callback。
- 两份Swift去除DEBUG分支后的Release源码与基线**逐字节一致**。输入/输出Converter、`recordClock`、容差、contentTimeValid latch、PCM样本及M02隔离修复没有改变。

## 4. 实际离线验证与失败记录

本机原始回执均留在Git忽略的 `.build/r5_m09/`，不提交构建产物或完整本机日志。

| 命令/检查 | 次数和真实结果 |
|---|---|
| `bash tools/speech_aec_host_tests/check.sh m09-clock-only` RED | 1轮，exit1（预期）；合成2.182375ms host偏差确实触发原native_clock=1，但旧snapshot无原始时间戳诊断字段 |
| 首次GREEN编译 | exit1；测试误将Float数组传给要求AVAudioPCMBuffer的既有API，尚未执行断言；只修正测试调用，保留 `green.log` |
| 同命令修正后GREEN | 1轮，exit0，8 cases / 141 checks |
| 最终代码冻结后同命令复核 | 1轮，exit0，8 / 141；`green_final.log` |
| `bash tools/speech_aec_host_tests/check.sh m08-clock-only` | 1轮，exit0，49 cases / 1012 checks：M08复现5/84、原clock9/800、Native16/77、Profile19/51 |
| Debug xcodebuild | 1轮，exit0，BUILD SUCCEEDED；15.88秒；独立SSD DerivedData，旧产物保留 |
| 无DEBUG的Capture/Host library编译 + nm | 1轮，exit0；无MacSpeechRawTimestamp或Native DEBUG符号；没有执行Release库 |
| Release Route / Architecture / Secret Guard | 各1轮，全部exit0 |
| 增量SwiftFormat / SwiftLint | 最终新增违规0，新B类0；新测试文件0违规；两份大文件基线90项、候选90项，历史C19/C23等债务保持，全文件lint仍exit2 |
| `bash -n`、`git diff --check`、文件/隐私/Stage7范围检查 | PASS |

8类新测试：正常2000callback无异常导出；首次host异常前后精确窗口/容量/JSON身份；初次content fault与提前Seal；缺失flags及未标记/NaN/Inf/零/负rateScalar；错误configuration/generation不污染及新代清理；host偏差诊断开/关Float32与PCM字节一致；真实sample gap拒收与原generation reset；原owner锁模型下并发读写快照。前后窗口快照按值复制，不因后续callback改变。既有拒收计数完全一致，非零样本及顺序未改。

RED证明的是旧诊断缺失，**不是**历史时钟偏差的根因；GREEN证明元数据记录和隔离，不是放行异常。rateScalar不用于补偿、纠偏或容差调整。本轮未运行FAST、FULL_CURRENT、全量Swift回归或设备矩阵。

## 5. 实际构建身份

工具链：Xcode27.0 (27A266a)，Apple Swift6.4，macOS SDK27.0。Debug构建使用项目Aftelle scheme、macOS destination、禁用自动依赖更新及 `CODE_SIGNING_ALLOWED=NO`；未启动App。

| 产物/源码 | SHA-256 |
|---|---|
| Debug App主可执行文件 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug dylib | `5cec419639ec2a8d8a1da229a3b64c82eede47dedd6f81da826aada863c5701a` |
| 无DEBUG Capture测试library | `afe67ad42cc74edbae859c77a873ebd25ae65f7ab21b1e6576a7ebf6a02622e5` |
| Capture源码 | `a1a1bfac46fb685fdd2091ad9400c2a17a720b24e435d1e5908e407919248f6d` |
| AppController源码 | `ed061a491ce9fe3656298e2ebff8d42e8652a62435830039ea08afaa30a4b997` |
| AcousticEchoHost未变 | `4a6153bca24c5bf237247374c05b9524443371e83e7ad71811957e9bb6cde8fe` |

App SHA指主可执行文件，不是对整个.app目录的任意目录摘要。Release相关检查为本次受影响源码的无DEBUG编译/符号与源码隔离、Release Route Guard；没有重新构建完整Release App。

## 6. 下一次采集门槛与未解决事项

当前仅 `R5_M09=READY_AWAITING_USER_AUTHORIZATION`。未来须用户再次明确授权设备运行，沿用原App系统权限、确认、导出及生命周期流程，先核验本次构建SHA与身份。不得继承M07/F1/R4授权。

未来主控指定的一次现有实验若触发异常，核对同RunID/generation/configurationID的raw flags、原始ticks/sample/rateScalar、名义host差与实际差及arrival；仅分析现有最多5条。无异常时诊断为null；立即停止时后续数据可能不足，不为凑齐窗口追加采集或自动重试。记录触发的是严格native_clock还是content_time，不能将更晚不同异常冒称首次异常。

**UNKNOWN**：历史2–3ms偏差究竟来自硬件、AVAudioTime标志/速率、调度或其他环节；实际设备数据中rateScalar是否有效；真实丢帧与host异常的因果关系；诊断实机开销；AEC根因。当前实现保留全部原fail-closed语义，仍可能因同一异常提前停止；未保证未来一定能取得后2个callback。

## 7. 五维SELF_REVIEW与等级

| 维度 | 结论 |
|---|---|
| 架构/Stage边界 | PASS；仅DEBUG元数据及既有出口，六红线及Forbidden Checklist通过 |
| 正确性/隔离 | PASS（离线）；真实断帧仍拒收，PCM/既有计数不变 |
| 实时安全 | 静态有界检查PASS；复用原锁，无新callback IO/扩容；实机开销UNKNOWN |
| 隐私/权限 | PASS；本轮App运行、采集、播放、蓝牙、音频读取均0次，未改权限 |
| 回归/交付 | 定点、新旧回归、Debug与Release隔离、三Guard PASS；不掩盖历史lint债务 |

新增CRITICAL=0、MAJOR=0、MINOR=0。既有时钟拒收/提前停止及声学验收风险继续OPEN；不把诊断准备称为根因修复或真人双讲PASS。

```ini
R5_M09=READY_AWAITING_USER_AUTHORIZATION
DEVICE_EXECUTION=NOT_AUTHORIZED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
