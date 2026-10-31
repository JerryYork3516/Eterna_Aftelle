# T3.2-A / R5-M27：原始AEC跨运行稳定性筛查准备

日期：2026-10-31（Asia/Shanghai）。**准备通过后获本批新授权，三轮均已完成、技术门禁与资源释放通过；结果依次为ECHO_NOT_DETECTED / ECHO_DETECTED / INCONCLUSIVE。未取得3/3低残留，复现同构独立App运行间的居民模板残留分类差异，根因仍UNKNOWN。** M26-D3的A/B低残留不能证明跨App长期稳定，也不能证明B优于A。

## 1. Git与修改范围

起始HEAD、upstream、实时远端均为`4778d8cecbd63e2b753d6d6b5d3b7eba0f9bceba`。跨文件修改前建立空回滚提交`9a37b16af16db14a4ac6bcec76b2333d21b1563b`。工作仅在既有干净隔离Worktree；原现场7冲突、索引与14项未跟踪证据以元数据指纹核对。

仅新增：

| 文件 / 函数 | 作用 |
|---|---|
| `tools/reference_host_comparison/m27_stability.py`：`context/child_plan/validate_contract/check_plan` | 独立M27父批次、三轮固定A、候选与父子身份绑定；复用原只读预检 |
| 同文件：`qualify_result/run_batch/main` | 一次性授权、最多三轮、Stop/失败即终止、保留逐轮原结果；仅显式CLI可调用设备入口 |
| `tools/reference_host_comparison/test_m27.py` | Fake子进程、真实本地管道、合成元数据及原严格证据资格负控 |
| 本报告 | 脱敏准备交付 |

**未修改App、生产源码、原M20/M22/M26控制器、评分器或任何音频处理。** 无新Engine、Tap、Runtime、DSP、音频状态Owner或HIL框架。

## 2. 最小控制合同及兼容边界

CONFIRMED：原M26批次只允许`TRIPLE_EQUAL → FIRST_CHANNEL_ONLY`，不能接收三轮A。RED将新三A合同交给原批次，预期被`fresh M26 authorization and complete frozen plan required`拒绝。这证明接口适配必要，**不是生产AEC故障RED**。

M27采用外部父批次，循环固定`range(1, 4)`，每次只调用既有`m20_batch.device_round(..., allocation=True)`：

1. 父身份为`R5_M27`，轮次1/2/3，全部TRIPLE_EQUAL；子UUID由新父UUID与轮次确定，三者互异。
2. 每次实际App运行仍是**真实M26-A单轮**，保留`R5_M26 / TRIPLE_EQUAL / round=1 / limit=2`原事件及原Native/PCM证据。父轮次不写入或替换子事件，不冒充M26-B或原M26完整A/B批次。
3. 子视图`ready=false`，不能交给原M26批次执行器取得完整A/B授权。M27的三轮上限、授权及消费标记由独立父合同负责；没有修改冻结`ARMS`。
4. 原App可见标题仍为M26-A单轮；外层显示`M27_ROUND`及1/3、2/3、3/3和父子映射。报告/原件明确保留这两层身份，不宣称App新增了原生M27入口。
5. 每轮由原入口新建App/Engine并完成Stop、封存、显式导出、精确PID退出与设备空闲核验，成功返回后才进入下一轮。每轮仍为4秒静默预热、15秒评分、score+3秒居民一次；评分PCM上限720000 bytes，不保留预热PCM。
6. 原二进制/素材、原UI/TCC、原时钟/代际、16槽观察溢出、Native丢包、最终drain/queued、配置变化、导出与资源保护均保留。父层再次核对原子身份、RunID、代际、构建/素材及释放状态；不建立新的音频资格标准。

授权字符串为`授权开始M27单批3轮原始AEC稳定性测试`。默认不执行；旧授权、未READY计划、默认禁用执行器均拒绝。独立消费标记独占创建，完成或失败后均不可复用；Stop文件、原App Stop及取消沿原安全清理路径终止剩余轮次，不自动重试或增加第四轮。

## 3. 离线验证与失败记录

命令均在`tools/reference_host_comparison`下执行，使用登记的非私人Fixture及Fake；`R3_BUNDLE/R3_HOST_EXECUTABLE`绑定登记候选，REF不执行。

| 验证 | 实际结果 |
|---|---|
| RED：`python3 -m unittest test_m27.BatchTests.test_three_independent_a_runs_use_original_single_round_contract -v` | 1轮exit1，原M26合同明确拒绝三A；未启动设备 |
| 初次GREEN：`python3 -m unittest test_m27 -v` | 1轮exit0，8项通过 |
| 完整定点：`python3 -m unittest test_m27 test_m20 test_m22 test_m26 -v` | 42项：M27=9、M20=18、M22=6、M26=9。41项通过；1项旧M22因遗漏`M20_RESIDENT_WAV`环境变量而setup错误，exit1 |
| 受影响项复核：补齐登记素材变量，`python3 -m unittest test_m22.EvidenceTests.test_two_template_windows_and_no_audio_mutation -v` | 仅复核该项，exit0；不改断言、素材或代码取得通过。最终42个不同测试均有通过记录 |
| `python3 -m py_compile tools/reference_host_comparison/{m27_stability,test_m27}.py` | exit0 |
| 三项Guard：Release Route / Architecture / Secret，各`check.sh` | 各1轮exit0 |
| 增量规范 / `git diff --check` / 文件白名单与隐私检查 | PASS；未修改Swift，无SwiftFormat/SwiftLint增量对象 |
| Debug / Release构建及Swift回归 | 本轮NOT_RUN；App及其依赖未变，复用M26-D3既有构建/隔离结果，实测候选SHA一致 |

Fake覆盖：三A身份/三个独立子进程与RunID、原单轮管道/退出、拒绝B及第四轮、同构建/素材/策略、错误SHA/RunID/代际、Stop、清理失败、默认禁用、授权复用、目录/父子错配。声学DETECTED与INCONCLUSIVE原样保留，不选择性删除或触发重试。新增CLI测试将设备调用替换为Mock，确认实际入口仍委托原`allocation=True`单轮。

16槽真实实现不重复修改或编译：Capture源码SHA仍为`f8cf47b0de2205e7e70177db6c16ceb0a615730892d4ae605e6fdee9cc45d49c`，复用[M26-D3报告](T3_2_A_R5_M26_D3_timing_witness_fix_and_batch_review.md)的245 checks、竞争/真溢出/代际/真实缺帧及TSan证据。本轮另以原`audit_manifest`验证正常完整观察可通过，而非零skipped/invalid/stale、Input/Render时间缺口、Native拒收、丢包、Seal队列及身份不符仍拒绝。没有把观察遗漏等同真实丢帧或放宽门禁。

## 4. 冻结身份

| 对象 | SHA-256 |
|---|---|
| Debug launcher | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug dylib（原M26-D3） | `cac8ebb261362d6d5c443fbd5c4d5ddf179b7744589df3e335bfe5ee06b904f7` |
| 原居民WAV | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` |
| 冻结M20_v0.1评分器 | `f9363dd62100563fe80c5693b4889dea65e60f7c99c2a36715feb8f4c46b49ae` |
| 新M27控制器 | `612697b8ffdb823910db834ad262e69135b8f41a0afac38dd4472798d8e3f9f7` |
| M27测试 | `229bac95801d9e08d48291b356506b8eaff1e0eb2c7c6fc5a13805238648f241` |
| 复用Release产物 | `5329382a6d8e5d96284af861ad322a30d329b92b3dc00b9f74a04f819e41bd76` |

以上磁盘身份已核验；实际加载PID/dylib仍为NOT_RUN，授权后必须由原运行身份门禁确认。与基线相比App/生产链及M20/M22/M26/集成源码diff为空，Release未增加执行入口。

## 5. 设备只读预检与新计划

新父批次：`37B4E60A-5C68-49D9-B90A-75F3714D2249`。新建本机0700受控目录，计划及回执0600；历史计划和消费记录未改。READY计划绑定准备提交`0d6b0aed01c9e9d2995ef0dc71fa0eaf24a23a31`，文件SHA为`31788e9c209dee66d94988921d832121f88e3155ded20c5d23cf94f747c0961f`。准备时未消费授权；下述实际批次已消费一次。计划原件保持不变，不追写最终报告提交SHA。

只读预检PASS：TinyUSB USB默认输入，系统60%；Mac mini内置扬声器默认输出55%、未静音，HAL scalar=`0.5500001311302185`；登记设备身份匹配、在线空闲，无冲突音频实验实例。冻结App/素材/控制与原确切PID UI脚本SHA全部匹配。没有修改系统音量、路由、Mic Mode或权限。

准备时TCC当前授权不能从外部可靠确认，记UNKNOWN；原App逐轮可见确认、系统权限、显式导出和Stop机制保留。新的系统权限要求或确认无法完成即停止，不能代授TCC。准备阶段的Engine运行、VP/AGC、active Standard Mic Mode、运行态设备/格式与加载身份均为NOT_RUN；本次获授权后的实际读回见第8节，不使用配置缓存冒充实测。

## 6. 冻结判读规则与准备期结论

固定三轮同条件TRIPLE_EQUAL，计划Capture/居民播放各3次、总采集57秒，不使用B、蓝牙、REF或真人讲话。每轮原件保留冻结检测器分类/NCC及反向和静默负控、Render窗RMS、Native/PCM20ms同窗、60ms能量占比、实际VP/AGC/Mic Mode/格式/设备、时钟/丢包、generated/drained/queued及资源证据。

三轮均NOT_DETECTED才输出`STABILITY_SCREEN=3_OF_3_NOT_DETECTED`；有DETECTED则`AEC_RESIDUAL_VARIABILITY=REPRODUCED`；INCONCLUSIVE单独计数。任何技术异常立即停止。冻结阈值不变，不计算ERLE；无独立物理发声证明保持UNVERIFIED。远程听闻不等于声压测量，三轮筛查不等于长期稳定或正式AEC/Test3 PASS。

准备期CONFIRMED：新的有限外层合同、既有候选一致性、离线测试及只读设备条件。准备期尚无设备结果；此后的实际证据和结论见第7–10节，未将Fake或准备PASS冒充声学PASS。

准备期SELF_REVIEW：合同与限额PASS；原音频/Release隔离PASS；测试及拒收负控PASS；隐私/Git PASS；当时科学接受NOT_RUN。准备实现新增CRITICAL=0、MAJOR=0、MINOR=0；原M18-E01及正式阻塞保持。

Stage7 Forbidden Checklist：**PASS**。触碰红线：无；修改文件：上述3项；是否改代码：是，仅外部DEBUG控制/测试；Runtime API / DR schema / 平台target / Stage8：均否；是否需要停止请求确认：是，仅本批新设备授权。无生产算法、正式Gate、RuntimeCore、Provider或DR变更，无私人录音读取、上传、播放或新采集。

## 7. 授权、身份与实际执行次数

用户明确回复：**“授权开始M27单批3轮原始AEC稳定性测试”**。重新核验源码三方HEAD为`0d6b0aed01c9e9d2995ef0dc71fa0eaf24a23a31`、未消费计划及全部冻结文件、设备60%/55%/未静音/在线空闲后，通过唯一`m27_stability.py --plan … --authorization …`入口执行。源候选、素材、时间参数和评分器均未改变。

父批次一次性消费新授权。实际Capture=3、居民Playback=3、JSON Export=3、WAV Export=3；各轮独立App/PID/RunID/Engine；无B、无蓝牙、无REF、无重试或第四轮。19秒为每轮计划上限，Native内容帧观察分别19.0/18.9/18.9秒，合计56.8秒。原UI录音/导出确认沿原流程完成，未代授新系统权限。

| M27轮次 | 原M26-A子UUID（各自均为真实A/1/2） | 实际RunID |
|---|---|---|
| 1 | `0BB09353-E531-5812-8779-FA5D078F14A4` | `E35C146C-25F6-40EA-AD49-313CA7522FE7` |
| 2 | `426AAE31-4F96-5C4C-8697-3F961D594501` | `C905818D-2102-4A80-9C0C-42576D40C44B` |
| 3 | `0407F071-782C-55E6-8EBD-2F4DA34F1A61` | `95FB4F7C-4E71-4E0B-B9B9-683D63B905CA` |

三轮的TRIPLE_EQUAL见证均为48 buffers / 76010 frames，16kHz/3ch/Float32/planar/DiscreteInOrder，原素材SHA、构建SHA、RunID、capture/playback generation及configurationID闭合。每轮3次确切PID/路径/加载映射/文件SHA验证均VERIFIED，每次只需1次身份读回尝试。App退出码均0，设备释放后才进入下一轮；批次控制器exit0、BATCH_COMPLETE存在，BATCH_STOPPED不存在。

## 8. 逐轮结果及技术证据

下表原样保留M20_v0.1分类。NCC保留符号，检测器按其冻结规则处理极性；低NCC搜索lag不解释为物理声传播延迟。RMS为冻结检测器的Render起点−0.1秒至终点+0.8秒边界窗，约WAV 4.082–8.730秒。

| 轮次 | 冻结分类 | NCC | 反向/静默负控绝对NCC | PCM边界窗RMS dBFS | Render有声范围内最大60ms能量占比 |
|---|---|---:|---|---:|---:|
| 1 | ECHO_NOT_DETECTED | +0.086429 | 0.057087 / 0.027510 | −51.758 | 99.771% |
| 2 | ECHO_DETECTED | −0.450994 | 0.102731 / 0.035421 | −17.613 | 16.632% |
| 3 | INCONCLUSIVE | −0.063790 | 0.048021 / 0.065135 | −46.443 | 52.107% |

R1原因`BELOW_FIXED_SCREENING_LIMIT`，且低能量主要来自短突发，不能把它当作“无任何异常声音”或AEC正式PASS。R2原因`FIXED_RESIDENT_TEMPLATE_PRESENT`，包络相关0.585、能量集中度0.999985，支持固定居民模板残留，非单个60ms突发支配。R3原因`AMBIGUOUS_TEMPLATE_OR_ENERGY`，模板与负控接近，不计成功或失败，也不因其低于R2能量而重标成功。没有当前WAV的用户试听裁定，不能移用M24对其他突发的听感。

Native已经经过Apple VP。按M19内容时间选择4.00–7.74秒的187个完整20ms窗；7.74–7.75秒末10ms不插值、不补零。Native每窗320样本/16kHz，PCM每窗480样本/24kHz，分别累加同覆盖窗的均方能量：

| 轮次 | VP后Native ch0 RMS dBFS | 保存PCM RMS dBFS | PCM−Native dB | Peak Native / PCM（该范围） |
|---|---:|---:|---:|---|
| 1 | −52.77683 | −52.77720 | −0.00037 | 0.088507 / 0.088806 |
| 2 | −16.73132 | −16.73539 | −0.00407 | 1.000000 / 1.000000 |
| 3 | −50.45709 | −50.46575 | −0.00866 | 0.097461 / 0.099854 |

R2相对R1约36dB的大窗差异已经存在于VP后Native；没有新的证据支持后级转换造成这次整体差异。**这不是逐20ms数字相等声明**：局部比值有极值，例如R1/R3约−10dB出现在Native约−106dBFS的低能量窗，PCM量化底噪、SRC及边界响应需保留；不能用极值认定动态增益BUG，更不能由这些统计定位Apple内部机制。

| 技术项目 | 第1轮 | 第2轮 | 第3轮 |
|---|---|---|---|
| 非零Player Render，WAV秒 | 4.182081–7.929749 | 4.182083–7.929752 | 4.182104–7.929779 |
| Input Native buffers / frames | 190 / 304000 | 189 / 302400 | 189 / 302400 |
| Render buffers | 189 | 189 | 189 |
| generated / drained / queued-at-seal | 949 / 949 / 0 | 944 / 944 / 0 | 944 / 944 / 0 |
| Stop末次pending / drained | 5 / 5 | 0 / 0 | 0 / 0 |
| 保存PCM packets / bytes | 748 / 718080 | 743 / 713280 | 743 / 713280 |
| 实际WAV时长 | 14.96秒 | 14.86秒 | 14.86秒 |
| 完整M19匹配20ms窗数 | 748 | 743 | 743 |
| VP后Native ch0满幅 / over-scale / 非有限 | 0 / 0 / 0 | 37 / 0 / 0 | 0 / 0 / 0 |
| 保存PCM端点命中 | 0 | 41 | 0 |
| HAL读回耗时ms，Engine / Playback | 4.041 / 3.392 | 4.024 / 3.213 | 4.042 / 3.213 |

三轮Input/Render的missing、duplicate、backwards、sample/host discontinuity均0；skippedUpdates/invalidBuffers/staleCallbacks均0；Capture drop/stale、Playback underrun/rejected及所有Native拒收均0。raw_timestamp_diagnostic均null，历史时钟异常本批未复现，不宣布时钟已修复。Engine配置变化0、skippedNotifications=0、观察关闭CONFIRMED。

六份真实运行态快照均Engine running、VP Input/Output ON、AGC ON、bypass=false、inputMuted=false，active与preferred Mic Mode均0（Standard，公开应用路由API）。六份完整格式/ASBD/layout一致：Input、Player、Mixer及Output client均16kHz/3ch非交错Float32，公开hardwareOutput读回16kHz/2ch。进程方向设备集合跨轮一致；input为2项共享I/O集合且`PROCESS_SHARED_IO_DEVICE_SET_METADATA_QUALIFIED`，output为1项且`PROCESS_DEVICE_METADATA_MATCHES_DEFAULT`，各次PID复核正确。**这不是独立物理输入端点或Apple内部AEC参考已被确认的证明。**

R2有Native满幅37/302400（约0.01224%）及PCM端点41/356640（约0.01150%），提示短时饱和/削波风险；原持续满幅保护（>1%）未触发，没有修改门禁后续跑。满幅在VP后Native已出现，但没有ADC Raw，不能判定硬件、AGC、AEC或其他具体层造成。R1/R3仍有未归属突发，未擅自播放或转写。

三份WAV均24kHz/Mono/PCM16LE。原有packet-aligned评分首尾覆盖仍PARTIAL：14.86–14.96秒不冒充完整15秒，预热PCM保留0 bytes。保存窗内包顺序/内容时间连续，2234个M19窗口全部MATCHED_CONTENT_COVERAGE，与真正保存WAV的PCM统计逐窗核对；不以全部drained统计替代WAV内容。

本机原WAV SHA-256：R1=`ceeb47ca9d8013fd7b236c3e0437d13b5982bbb39f207b5a8b36bc23f79bb11b`；R2=`97b85243369c5d48693cc794eebd0cb6d1a2f8f725f41416554fc12ad9d1d94e`；R3=`56db9b050d2f66029822ec685d2070e94c93fc5755e502fd7569ddf3076840e0`。三份JSON/WAV SHA重新核验一致，仅本机保存，不提交原件、UID、原句或完整日志。

## 9. 用户听闻及物理证明边界

批次结束后用户先回复**“听到”**，随后明确选择**“只能确认听到，轮次或地点不确定”**。据此R1/R2/R3逐轮听闻归属均UNKNOWN，现场/远程归属UNKNOWN，未代填三轮见证。原反馈及澄清分别本机保存；不重播、不录音、不要求用户分析WAV，独立声压测量NOT_AVAILABLE。冻结批次原记录的physical_emission=UNVERIFIED保持不变，第1轮低残留不能用于确认“当轮实体扬声器已发声且受到有效AEC抑制”，更不能升级为长期稳定证明。

## 10. 最终判断与交付

- **CONFIRMED**：相同候选、素材、TRIPLE_EQUAL策略和固定系统设置下，三次独立生命周期得到不同的冻结分类；第2轮固定居民模板残留，第1轮低于检测界限，第3轮证据含混，全部原样保留。`STABILITY_SCREEN=3_OF_3_NOT_DETECTED`未成立，`AEC_RESIDUAL_VARIABILITY=REPRODUCED`仅表示本筛查的残留差异，不代表因果根因确认。
- **SUPPORTED**：这次大幅差异的产生层级在VP后Native或更早，非最终PCM整体增益变化；未见可解释差异的公开设备集合、格式、Mic Mode、VP/AGC开关、配置变化或时间连续性异常。
- **HYPOTHESIS / UNKNOWN**：真实输入声压/环境、处理历史、Apple内部自适应/AGC/参考状态仍不能区分。公开属性相同不等于内部状态相同。本轮没有确认可修复的生产代码缺陷，不能据此关闭AGC、强制改声道或宣称Apple BUG。

历史M20与本批都出现跨运行模板残留差异，M26-D3一次原始A的低残留未能证明稳定。各批候选/合同不同，不能将这些小样本合并为长期可靠性或失效率统计。

实际新增验证：本批预检、运行身份、原严格技术/声学资格、JSON/WAV SHA和内容窗、最终设备空闲、文件权限及Git保护检查。没有修改源码或阈值，没有重跑无关构建/大回归。结束交付仅更新本报告；代码仍为准备提交原件。

最终SELF_REVIEW：合同/限额PASS；技术资格与资源PASS；既有候选/Release隔离PASS；隐私/Git PASS；科学结论PARTIAL（稳定性未建立、声源/内部机制未定位）。新确认生产代码缺陷=0；既有声学MAJOR阻塞保持OPEN；R2短时满幅作为本批风险提交主控，未将其包装为新代码BUG。Stage7 Forbidden Checklist最终PASS，边界及正式状态不变。

最终越界检查：触碰红线无；本次结束交付修改文件仅本报告；改代码否；Runtime API / DR schema / 平台target / Stage8均否；不再申请追加设备执行，停止等待主控审核。

**唯一下一步：交主控复核本批R2强模板残留及VP后满幅证据，限定下一验证假设；本批已结束，暂不修改生产策略或追加设备实验。**

```ini
M27_OFFLINE_PREPARATION=PASS
M27_DEVICE_PRECHECK=PASS
M27_BATCH_EXECUTION=COMPLETED_AUTHORIZATION_CONSUMED
DEVICE_RUNS=3
STABILITY_SCREEN=NOT_ESTABLISHED
AEC_RESIDUAL_VARIABILITY=REPRODUCED
ECHO_DETECTED=1
ECHO_NOT_DETECTED=1
INCONCLUSIVE=1
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
