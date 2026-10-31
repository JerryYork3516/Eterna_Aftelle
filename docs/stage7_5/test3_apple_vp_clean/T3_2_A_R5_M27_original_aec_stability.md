# T3.2-A / R5-M27：原始AEC跨运行稳定性筛查准备

日期：2026-10-31（Asia/Shanghai）。**离线合同与只读预检通过；设备运行0次，等待本批新授权。** 尚无M27声学结果。M26-D3的A/B低残留不能证明跨App长期稳定，也不能证明B优于A。

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

新父批次：`37B4E60A-5C68-49D9-B90A-75F3714D2249`。新建本机0700受控目录，计划及回执0600；历史计划和消费记录未改，当前批次尚未消费授权。私有READY原件绑定交付后的HEAD，另存`plan.ready.json`并复核；最终HEAD和计划SHA见本机交付回执/最终回复，避免自引用。

只读预检PASS：TinyUSB USB默认输入，系统60%；Mac mini内置扬声器默认输出55%、未静音，HAL scalar=`0.5500001311302185`；登记设备身份匹配、在线空闲，无冲突音频实验实例。冻结App/素材/控制与原确切PID UI脚本SHA全部匹配。没有修改系统音量、路由、Mic Mode或权限。

TCC当前授权不能从外部可靠确认，记UNKNOWN；原App逐轮可见确认、系统权限、显式导出和Stop机制保留。新的系统权限要求或确认无法完成即停止，不能代授TCC。实际Engine运行、VP/AGC、active Standard Mic Mode、运行态设备/格式与加载身份均为NOT_RUN；授权后必须通过原两次读回及证据门禁，不使用配置缓存冒充实测。

## 6. 未来判读、限制与唯一下一步

固定三轮同条件TRIPLE_EQUAL，计划Capture/居民播放各3次、总采集57秒，不使用B、蓝牙、REF或真人讲话。每轮原件保留冻结检测器分类/NCC及反向和静默负控、Render窗RMS、Native/PCM20ms同窗、60ms能量占比、实际VP/AGC/Mic Mode/格式/设备、时钟/丢包、generated/drained/queued及资源证据。

三轮均NOT_DETECTED才输出`STABILITY_SCREEN=3_OF_3_NOT_DETECTED`；有DETECTED则`AEC_RESIDUAL_VARIABILITY=REPRODUCED`；INCONCLUSIVE单独计数。任何技术异常立即停止。冻结阈值不变，不计算ERLE；无独立物理发声证明保持UNVERIFIED。远程听闻不等于声压测量，三轮筛查不等于长期稳定或正式AEC/Test3 PASS。

CONFIRMED：新的有限外层合同、既有候选一致性、离线测试及只读设备条件。HYPOTHESIS：当前原始策略可能保持低残留，尚待新批实际结果。UNKNOWN：未来声学重复性、物理声压、Apple内部参考、AEC/时钟根因。**本轮无确认的生产AEC缺陷，也无新的声学结论。**

SELF_REVIEW：合同与限额PASS；原音频/Release隔离PASS；测试及拒收负控PASS；隐私/Git PASS；科学接受NOT_RUN。新增CRITICAL=0、MAJOR=0、MINOR=0；原M18-E01及正式阻塞保持。

Stage7 Forbidden Checklist：**PASS**。触碰红线：无；修改文件：上述3项；是否改代码：是，仅外部DEBUG控制/测试；Runtime API / DR schema / 平台target / Stage8：均否；是否需要停止请求确认：是，仅本批新设备授权。无生产算法、正式Gate、RuntimeCore、Provider或DR变更，无私人录音读取、上传、播放或新采集。

**唯一下一步：取得“授权开始M27单批3轮原始AEC稳定性测试”后，执行这个新批次，最多三轮；当前停止等待。**

```ini
M27_OFFLINE_PREPARATION=PASS
M27_DEVICE_PRECHECK=PASS
M27_BATCH_EXECUTION=AWAITING_USER_AUTHORIZATION
DEVICE_RUNS=0
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=DEFERRED
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
