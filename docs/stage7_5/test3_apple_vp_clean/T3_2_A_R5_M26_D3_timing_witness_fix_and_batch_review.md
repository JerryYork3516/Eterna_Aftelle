# T3.2-A / R5-M26-D3：时间见证器漏记修复与A/B实机审核

日期：2026-10-30（Asia/Shanghai）。**离线修复验收通过；新批A/B各执行一次、技术门禁通过，冻结检测器均为ECHO_NOT_DETECTED。物理发声见证尚未取得，AEC声学验收仍UNVERIFIED。** 本报告A/B均为居民独讲，字母仅表示输出声道分配臂。

## 1. 身份、范围与确认缺陷

起始HEAD/upstream/实时远端一致：`ff9c0cf8ff2886d692ed1123d0c56a6781dedb3b`。跨文件修改前回滚提交`e75e07bb071465624589e922633d76d4a9c9fe22`；修复提交`af0bad7d224b78d2232c72ea16059ccbaf54222f`先Commit+Push并核验三方一致，再创建新批。最终报告提交SHA见Git记录，避免自引用。

**CONFIRMED_CODE_DEFECT：DEBUG时间观察在共享busy标记竞争时直接放弃回调。** 原`MacSpeechNativeVoiceTiming.input/render`经单次CAS调用`update`；控制快照或其他更新持有标记时，实际Input/Render元数据没有保存，只增加`skippedUpdates`。随后对不完整观察计算的sample/host缺口不能等同真实PCM丢帧。

确定性RED持有真实update标记，交付非零合成Buffer及连续时间元数据，旧实现exit133，失败于`occupied timing reader must not discard actual callback metadata`。这确认了实现缺陷；上一批究竟由哪一个竞争者占用标记仍UNKNOWN，没有回填历史事件。

| 修改文件及位置 | 实际变更 |
|---|---|
| `apps/macos/Aftelle/MacSpeechAudioCapture.swift`：`MacSpeechNativeVoiceTiming.input/render`、`enqueue/drainCallbacks/apply`、`snapshot`及M22分遍标记 | 仅DEBUG的固定16槽回调元数据移交；主状态仍由原busy标记保护。Input/Render不因读者占用立即丢弃记录；使用原身份、格式及连续性验证 |
| `tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift`：3个`testTiming…`及原m26-only入口 | 竞争、溢出、未发布记录、双生产者、可复用Buffer、真实缺帧、错误身份、Stop及原快照预算回归 |
| `tools/reference_host_comparison/integration.py:26` | 仅重新登记实际新M26 dylib SHA；原身份校验、UI及M20/M22候选不变 |
| 本报告 | 脱敏交付，不提交音频或原始Manifest |

## 2. 修复合同与实时安全

16槽在arm阶段预分配，仅复制内容host/sample时间、arrival、帧数、采样率、配置/代际及已扫描的非零范围/计数。**不持有AVAudioPCMBuffer、PCM样本或语音。** 原子序号确定消费顺序；槽位由free→writing→published→free，通过release/acquire发布。缓冲回调在取得原状态标记后最多消费16条；控制快照等待仍为原20次/5ms预算。

容量满、序号不符或真正不能保留的观察继续增加`skippedUpdates`并保持不合格；未完整发布的记录不能被读作完整快照。控制事件/通知的原失败计数保留。原`skippedUpdates==0`、配置、时钟、包守恒及导出门禁没有修改；没有把丢失清零、补造回调、插值、重置generation或放宽时间容差。

Render在回调中复制扫描结果，并锁定当时M22播放序号，避免延后消费时归入另一遍。原全局连续性检查仍能报告真实间隔。新函数均为原见证器内部实现，没有新增Engine、Tap、诊断系统或音频状态Owner。

原子API依据：[Apple wrappingAdd合同](https://developer.apple.com/documentation/synchronization/atomic/wrappingadd%28_%3Aordering%3A%29-35sou)、[Swift SE-0410](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0410-atomics.md)。实时路径没有新增等待、HAL查询、文件IO、同步日志或容器扩容；暂存是数值元数据，已有Render扫描维持原上限。没有测量硬实时最坏耗时，固定操作上限及TSan结果不等于所有线程交错的形式证明。

## 3. 实际离线验证及失败记录

| 检查 | 次数、结果 |
|---|---|
| RED：原`check.sh m26-only` | 1轮，编译成功、预期断言失败exit133；设备0 |
| 首次GREEN | 编译exit1：测试钩子的非逃逸闭包传入可选闭包参数；改为非逃逸空默认闭包，未调整断言 |
| GREEN | 同入口exit0，245 checks，`m26_fake_device_access=ZERO` |
| 确定性负控 | 16条保存、17条真实溢出仍计数1；暂停发布时快照不可用；真实sample/host跳变仍报告；旧代际/非法Buffer/Stop后更新仍拒绝；双生产者保留记录及可复用Buffer元数据 |
| Thread Sanitizer | 首次缺少登记素材环境变量，fixture读文件失败exit133，不作为PASS；补齐原`M20_RESIDENT_WAV`后245 checks、exit0，未报告运行时数据竞争 |
| 原M20/M19、M22 Swift回归 | 各1轮，396 / 124 checks、exit0；真实设备0 |
| 受影响Python回归 | 1轮51 tests、exit0；使用新候选身份、Fake进程及原合成/非私人素材 |
| Debug / Release构建 | 各1轮BUILD SUCCEEDED、exit0，独立DerivedData，未覆盖历史候选 |
| Release隔离 | Capture非DEBUG投影与基线逐字节一致；Release无时间见证器/M26入口符号；音频算法、Converter、Output及冻结评分器无差异 |
| 三项Guard | Release Route / Architecture / Secret Guard各1轮exit0 |
| 增量规范 | 新增格式/lint违规0；历史lint债务Capture10、测试12保持独立。初检type_body_length新增1项，移入同文件既有private extension后消除；未清理无关债务 |

格式重排时一次本地移动脚本未匹配已格式化注释，写入前退出，没有损坏文件；随后按实际标记完成同一局部移动。没有降低测试、门禁或规范标准取得PASS。没有FULL_CURRENT、ASR、DTW、Raw采集或额外声学实验。

## 4. 新候选及批次预检

| 身份 | SHA-256 |
|---|---|
| Capture源码（与本次构建一致） | `f8cf47b0de2205e7e70177db6c16ceb0a615730892d4ae605e6fdee9cc45d49c` |
| Debug launcher | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| **新Debug dylib** | `cac8ebb261362d6d5c443fbd5c4d5ddf179b7744589df3e335bfe5ee06b904f7` |
| Release隔离产物 | `5329382a6d8e5d96284af861ad322a30d329b92b3dc00b9f74a04f819e41bd76` |
| 原居民素材 | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` |
| 冻结M20评分器 | `f9363dd62100563fe80c5693b4889dea65e60f7c99c2a36715feb8f4c46b49ae` |
| 新计划原件 | `979b803ce19863c0922128813d1f63d97a63f2d3e6d18443077b6570bd1e4ab4` |

本次用户明确授权“定点验证通过后，创建新批次直接执行A/B各一次，不自动重试”。新UUID：`04134A43-89F4-4672-B260-45C361FA0275`；绑定修复提交及新脚本/构建身份。旧916C…、27721703…批次和消费标记均保留；新批单独记录并消费本次授权。

设备只读预检通过：TinyUSB USB输入系统60%；Mac mini内置扬声器系统55%、未静音，HAL scalar=`0.5500001311302185`，设备身份一致、空闲，无冲突实例。没有修改设备、音量、Mic Mode或TCC。新建0700目录、文件0600。保留原App可见确认、显式导出、随时Stop及精确PID退出。

## 5. 两臂实际结果

每臂独立App/PID/RunID，4秒预热+15秒评分计划，score+3秒请求同一居民一次。实际Capture=2、居民Playback=2、JSON/WAV导出各2；无重试、无追加实验，无蓝牙、REF或真人C。

| 项目 | A：TRIPLE_EQUAL `[x,x,x]` | B：FIRST_CHANNEL_ONLY `[x,0,0]` |
|---|---|---|
| RunID | `BD30440E-F730-43D5-B4EE-EF2C20EFC07C` | `BA29C3DA-4DBE-46ED-8F50-23A1D192E4EF` |
| 控制/技术/资源 | 通过；App exit0、设备释放 | 通过；App exit0、设备释放 |
| 分配Session | 48 buffers / 76010 frames；已关闭 | 48 buffers / 76010 frames；已关闭 |
| Native缓冲数 / 时间见证Input数 | 190 / 190，304000 frames | 189 / 189，302400 frames |
| `skippedUpdates` / invalid / stale | 0 / 0 / 0 | 0 / 0 / 0 |
| Input及Render sample/host缺口 | 全0 | 全0 |
| Native拒收 / raw timestamp异常 | 全0 / 无 | 全0 / 无 |
| generated=drained；封存队列 | 949=949；0 | 944=944；0 |
| 末次drain pending/drained | 5 / 5 | 0 / 0 |
| capture drop/stale；播放underrun/reject | 全0 | 全0 |
| 实存WAV | 14.96秒 / 359040 frames / 748包 | 14.86秒 / 356640 frames / 743包 |
| 20ms同窗/保存样本核验 | 748个MATCHED_CONTENT_COVERAGE | 743个MATCHED_CONTENT_COVERAGE |
| 非零Render，WAV原点 | 4.182100–7.929774秒 | 4.182092–7.929766秒 |
| 冻结检测器结果 | **ECHO_NOT_DETECTED** | **ECHO_NOT_DETECTED** |
| 居民模板NCC（有符号） | −0.007752 | −0.095149 |
| 反向 / 静默负控绝对NCC | 0.015499 / 0.038603 | 0.051137 / 0.047448 |
| 全局最大绝对NCC | 0.041887 | 0.095149 |
| 检测器播放窗口RMS | −55.767dBFS | −52.247dBFS |
| 该窗Peak / PCM端点样本 | 0.040833 / 0 | 0.107666 / 0 |
| Render窗最大60ms能量占比 | 85.657% | 94.409% |
| 预热PCM保存 / 首尾覆盖 | 0 bytes / PARTIAL | 0 bytes / PARTIAL |
| 用户物理发声见证 | PENDING / UNVERIFIED | PENDING / UNVERIFIED |

两臂Capture/Playback Generation=1、ConfigurationID=2；各两次读回均VP Input/Output及AGC开启，bypass=false、inputMuted=false、Engine running；active/preferred Mic Mode均Standard（公共App-route API）。两次格式稳定，图内16kHz/3ch planar Float32、硬件输出16kHz/2ch；进程输入共享I/O集合及输出默认设备元数据资格通过。Engine配置事件及skippedNotifications均0，监听已关闭。两App实际加载身份均按确切PID核验，最终输入/输出running=0。

评分PCM分别718080 / 713280 bytes，低于原720000上限；Native样本覆盖分别19.0 / 18.9秒，未把样本覆盖当作硬件流精确起止。预热PCM未保留，首尾PARTIAL未补零、插值或声称完整覆盖。弱NCC的最佳匹配位置不作物理延迟解释。

共同WAV 4.00–7.74秒完整187个20ms窗口：Native ch0 / 实存PCM RMS分别A=−68.205 / −68.220dBFS，B=−51.450 / −51.451dBFS。两种采样率通过同内容时间覆盖配对，不比较样本索引。较高短时能量仍有突发主导，声源未归属，不能将A/B能量差解释为回声衰减或B的AEC优劣。

## 6. 证据限制、隐私及结论

**CONFIRMED：** 共享标记导致漏记的路径已由离线RED/GREEN修复；本批两臂无观测遗漏、无Native拒收/包丢失，均完成原控制、导出及资源释放。**没有新增暂存命中计数**，实机未证明一定发生过竞争；确认的是修复候选兼容原流程和本批观察完整。

**UNKNOWN：** Apple内部AEC参考、历史声学跨运行差异及瞬态来源。已一次性请求两臂物理发声见证，交付时尚无反馈，保持UNVERIFIED。软件Render/播放完成不代替扬声器实际发声。即使后续见证成立，本批两臂都低于同一模板检出条件，也未支持B优于A，不能宣布长期AEC稳定或把3ch判为BUG。

独立App/Engine生命周期、固定A→B顺序及实际声压仍是混杂。声道分配可能改变扬声器响度，同为系统55%不保证相同声压。本轮不将B纳入生产策略，不自动追加实验或关闭T3.2-A。

原WAV SHA：A=`ac8752ec81cbc9a8e76d3a2e5236addae612d4878b0287891f9326d6c9d15e78`；B=`15043b66b78d09c28d66eb69c542397a69d2deda58c44e2450ac620d44006493`。私人WAV/JSON、设备UID及完整日志仅留本机；不上传、不转写、不自动播放。Git仅提交上述源码/测试/身份常量及本报告，原7冲突、索引和14项未跟踪证据交付前后核对。

SELF_REVIEW：合同/真实损失负控PASS；实时有界及Release隔离PASS；定点回归/规范PASS；隐私/Git PASS；科学接受PARTIAL（物理见证及因果归属不足）。新增CRITICAL=0、MAJOR=0、MINOR=0；历史规范债务及M18-E01独立保留。Stage7 Forbidden Checklist=**PASS**：无新Engine/Tap/HIL，无AEC/AGC/NS、AudioGraph、Converter、时钟容差、正式Gate、RuntimeCore、Provider、DR/API或平台/Stage8变更。

**唯一下一步：** 交主控审核本批合格A/B及待补的物理见证，再决定是否需要进一步实验；当前不作生产声道策略变更。

```ini
TIMING_WITNESS_FIX=OFFLINE_PASS
M26_D3_BATCH_TECHNICAL=PASS
A=ECHO_NOT_DETECTED
B=ECHO_NOT_DETECTED
CAPTURES=2
RESIDENT_PLAYBACKS=2
RETRIES=0
PHYSICAL_EMISSION=UNVERIFIED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=DEFERRED
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
