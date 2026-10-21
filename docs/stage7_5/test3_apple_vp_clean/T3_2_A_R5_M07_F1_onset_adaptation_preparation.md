# T3.2-A / R5-M07-F1 · 真人起音顺序对照离线准备

**PREPARATION_READY；停在READY_AWAITING_USER_AUTHORIZATION。实机运行0次，不能判断AEC适应、首字泄漏或吞字是否改善。** 2026-10-21完成离线准备；旧设备授权不继承，必须收到本轮“授权开始A/B实验”后才允许启动。

## 1. Git及限定修改

起始HEAD＝upstream＝实时远端：`9eb5194f171a59f29e26837a1f43832bf089da0b`。使用既有干净隔离Worktree，跨文件修改前建立回滚提交`d05bf9a5ad680bd4f47aa5f6adaac6a20d566c64`。原7个冲突、索引及未跟踪现场保持；不stash/pop、reset/clean、强推或操作ACE3。

复用M07真人C、ScoreControl、单次控制器及原权限/显式导出/Shutdown流程。新增DEBUG参数`--apple-vp-human-onset=A|B`：两组内部scenario均为C，F1的A不是旧“居民独讲A”，F1的B也不是旧“真人独讲B”。Prepare固定起音profile、AGC-ON、WARMUP_4S、RECORDING、15秒评分及720000bytes上限；混用旧M07/BT参数、未登记profile或错误配置拒绝。

仅改AppController/ContentView的DEBUG引导与元数据、既有Python控制器、直接Fake测试及本报告/DEVLOG。Capture、AcousticHost、Converter、channelMap、Engine/Player/Mixer图、音频格式、AGC/NS/AEC、Gate、Provider/RuntimeCore及时间戳容差未改。新增Engine/Tap/音频Owner/诊断框架均0；M02修复及M04读回保留。

## 2. 冻结实验与实际时序边界

| 项目 | F1 A：居民先讲 | F1 B：真人先讲 |
|---|---|---|
| 预热 | 安静4秒，持续Capture/转换/drain，不保留PCM | 相同 |
| 评分0秒 | 真人安静 | 真人开始持续朗读 |
| score+3秒 | 原路径请求居民播放一次 | 相同 |
| 真人起音规则 | **实际听到居民1–2秒后开始**，继续到11秒 | 居民发声时不中断，继续到11秒 |
| 11–15秒 | 停止讲话、安静至封存 | 相同 |
| 未来运行额度 | 独立RunID、最多1次 | 独立RunID、最多1次 |

两组重复同句：“绿色纸船经过小桥，我会继续说完这句话。”居民内容和文件不变：“这是一段固定语音，用来检查回声和人声。”不使用蓝牙代理或REF，不要求用户调设备、计时或操作终端。

**A的约5.5秒视觉讲话提示只是辅助。** 固定居民有1秒前导静默，预期非零Render约score+4秒，故给出约1.5秒间隔的提示；没有据此测得实际声学间隔。屏幕明确要求实际听到居民1–2秒后再讲话，即使视觉提示已出现也不能提前。B提示绑定score+0。记录`control_cue_ns`的是控制路径发出提示的时间，UI实际可见时间、物理居民起音、真人起音仍待实机核验，不能把提示等同物理事实。

保持原评分起点、3/9/11秒阶段事件及居民排程；旧`human_only/double_talk`标签在F1仅是软件阶段名，A前段不据此写成人声或双讲。每组19秒软件预算；沿用原控制/Stop调度，未来须报告实际采集时长，不能预写严格19.000秒。只留评分内完整20ms包，最多750包/720000bytes；预热不留存、跨界包排除、不补零。queued及Converter partial tail依原合同登记，不保证15秒WAV完整。

这一对实验改变真人相对于居民的起音顺序及独讲铺垫，真人声压/精确波形不能完全匹配。A优于B最多支持“顺序/适应相关”的假设，不能单独证明Apple AEC或AGC根因；两组正常也不能追溯消除历史失败。

## 3. 构建、素材及只读预检

新Debug构建未启动过：

| 身份 | SHA-256 |
|---|---|
| App launcher | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| F1 Debug dylib | `ecf6a86f4f05b3a594c978af45fc47d7af96c6761a9f7c1419ee494c96de8d5e` |
| AppController源码 | `67ba4ee0de1437b9217a5cce2f18d7baef744890447c4643413fdc10cd6ac8a0` |
| ContentView源码 | `4befd177d4502f1b8fe1518604ffaba7d108957975457b164fa15d50808e11fb` |
| 原固定居民WAV | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` |

Debug位于Git忽略的`.build/r5_m07_f1/DerivedData/Build/Products/Debug/Aftelle.app`；`integration.F1_HOST_DYLIB_SHA`精确登记新dylib，旧M07产物不能进入F1。原M07登记和产物未替换。素材为24kHz/Mono/PCM16LE，114032frames、4.751333秒，前24000样本全零；本轮仅核验既有非私人素材，没有播放、替换或重合成。

只读HAL及系统音量：默认输入TinyUSB USB、16kHz/1ch、60%；默认输出Mac mini内置扬声器、48kHz/2ch、55%、未静音；两设备alive且running=0，无Aftelle进程。未改设备、音量或Mic Mode。系统Mic Mode=UNKNOWN；尝试只读目标Debug bundle的TCC麦克风行被系统拒绝（sqlite exit1），**权限状态UNKNOWN**。不请求权限；以后经新授权启动时必须由App走原TCC流程，出现新的系统交互要求即停止。

旧双音`--preflight`因小爱不在线而exit1；它错误地要求本轮不需要的蓝牙输出。未修改原工具：仅在Git外复用其原Core Audio属性getter查询当前默认输入/输出，查询exit0，未实例化Engine/NSSound或打开音频流。没有为通过预检而连接蓝牙、切换路由或降低设备目标。

原受控Caches：当前用户拥有、0700、无symlink、可写，既有JSON/WAV仅检查文件属性且为0600，未打开其内容；构建前可用约1.31GB。未来每RunID须用新文件并拒绝覆盖，JSON/WAV0600；仅本机保存和有限分析，不继承M07三份WAV的公开授权。实际运行前重新只读核对路线/音量、空间、素材和二进制。

## 4. 单次控制、授权与后续执行程序

F1 ScoreControl使用`batch=R5_M07_F1, scenario=C, onset_group=A|B, source=human, proxy_requested=false`；同RunID/评分起点绑定`human_start_cue_ns`和`human_speech_stop_ns=score+11秒`。保留原有界非阻塞管道、时钟、重复/外来事件拒绝、EOF/进程异常清理及原UI看门狗。只消费真人元数据，不产生代理PLAY/STOP。

原`m07_once.py`增加显式`--onset`，使用独立F1当前同意标记及`M07_F1_A/B_consumed.json`排他登记。缺少新同意或使用旧M07标记时，默认禁止真实子进程；B须核验同批A的RunID、导出/退出/释放回执，不能用旧M07的A冒充。每组只启动一个App，取消能回收，失败不自动重试。F1 C组参数及混合来源参数均拒绝。

以下只登记未来命令形状，**本轮未执行**：

```sh
python3 -B tools/reference_host_comparison/m07_once.py --onset --group A \
  --bundle "$REGISTERED_BUNDLE" --executable "$F1_EXECUTABLE" \
  --evidence "$NEW_PRIVATE_BATCH/A" --consent "$NEW_F1_CONSENT"
# A正常封存、两次显式导出、Quit和设备释放核实后，才允许同形状的 --group B。
```

变量来自本机冻结计划，不允许任意二进制或旧同意替换。实际GUI沿用M07按确切PID绑定的原面板操作：Prepare F1组别→选择固定WAV→原可见麦克风/本地录音/播放确认→Start→自动封存→分别显式导出JSON/WAV→正常Quit。每组开始前由Codex显示对应讲话规则。不得按App名称启动普通实例，不操作新的TCC授权弹窗。

最终源码、程序和产物摘要、素材、设备只读回执、未授权状态及未来次数上限已保存在本机Git忽略的`.build/r5_m07_f1/execution_plan.json`，未创建实际实验RunID、录音或本轮设备同意回执。

## 5. 实际离线验证与失败记录

| 命令/检查 | 实际结果 |
|---|---|
| `bash tools/realtime_interruption_evidence_tests/check.sh m07-f1-only` | 初轮18cases/725checks，收口18cases/785checks，均exit0；M03原11/287、M07累计15/543保持；F1增量3cases/242checks。两轮是新增约束/提示边界检查后的必要复核 |
| `python3 -B -m unittest test_m03 test_m07 test_m07_f1 -v` | 首次误把R3_HOST_EXECUTABLE指到M07产物，M03身份拒绝，exit1（8failures/4errors）；M07/F1通过。环境纠正为原登记M03产物后25/25通过、exit0；未修改旧SHA或断言 |
| `python3 -B -m unittest test_m07_f1 -v` | 新增终态评分原点改变负控后，受影响5/5通过、exit0；A/B各Fake一次、15种故障子场景，含旧batch、错误group/source/cue/clock/RunID、EOF、重复、缺失、迟到、取消、子进程退出及终态时基改变 |
| `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug -destination platform=macOS -derivedDataPath .build/r5_m07_f1/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build` | 1次、exit0、19.460秒；未启动产物 |
| 新真实产物的`integration.command`仅身份/argv校验 | A/B均通过；旧dylib拒绝、无新同意及旧M07同意均拒绝，App启动0 |
| `bash tools/realtime_release_route_guard/check.sh` / `bash tools/architecture_guard/check.sh` / `bash tools/secret_guard/check.sh` | 各1次、均exit0；Release为源码投影及调用边界验证，不冒称新Release二进制验证 |
| 增量SwiftFormat0.63.1 / SwiftLint0.65.1 | 三份受影响Swift：Format7070→7070（exit1）、Lint168→168（exit2）；新增非结构/B类问题0，历史工具FAIL保留，不写成全量规范PASS |

F1 Fake覆盖固定Prepare、拒绝AGC-OFF/零预热/STATS_ONLY/混合来源、原同意缺失、19秒持续drain与720KB评分隔离、预热marker不进入WAV、无提前讲话提示、原3/9/11秒播放/安静及Stop/Seal/Shutdown。合成PCM样本值与顺序保留；A/B各仅一次居民播放，没有真实麦克风、扬声器、蓝牙或REF访问。

首次增量规范检查发现新增换行及分支复杂度问题，已局部修正，未全文件格式化。既有C19/C23结构债务增长单列：DEBUG View 271→303有效行、共用Fake函数80→100行，原有文件/type长度继续超限；无新结构告警锚点。Swift定点编译保留既有并发警告，不借此清理其他任务。FAST/FULL_CURRENT/Release整App构建/声学测试均NOT_RUN。

## 6. 后续验收、限制与停止

新授权后最多A/B各一次、各19秒软件采集预算、最多15秒评分WAV（720000bytes），4秒预热PCM不保留。重点：居民首字泄漏、具体疑似吞字时间与原句、双讲音量、Native/PCM连续性、Render区间、实际物理重叠、退出/释放和用户原话。

数值仅辅助定位：现有Native为VP后分窗统计，最终WAV可作20ms局部检查；没有Pre-VP原音或逐字Native录音，不能用大窗RMS/相关性判吞字或AEC PASS。A的实际起音未满足“听到居民1–2秒后”，或未能见证双讲超过1秒时，相关对照标INCONCLUSIVE/COVERAGE_PARTIAL，不补造时间。用户不具备当前就绪状态、出现新系统权限、SHA/路由/VP/AGC/时钟/清理异常时停止，保存本地允许证据；不现场修算法、放宽时间戳或追加录音。

M07 C在quiet的`content_time/native_clock`拒收继续独立OPEN，本轮不修。它可能再次截短评分；发生时保留前缀及PARTIAL，不把控制器exit0当完整声学通过。本轮目标中的起音泄漏、吞字及AEC适应均待新的真实证据，根因UNKNOWN。

五维SELF_REVIEW：功能＝最小复用M07且仅改变引导/身份；证据＝Fake/只读元数据/未来物理事实分开；架构＝无音频处理/Runtime变更；隐私＝未读历史麦克风内容、无新录音或音频上传；工程＝固定摘要、负控、构建、单次与清理保护，保留失败及原冲突。

问题分级：本轮新增CRITICAL0、MAJOR0；既有MAJOR时钟拒收OPEN；MINOR为结构债务增长及提示/听感/物理覆盖的证据限制。TCC和Mic Mode UNKNOWN留待合法实机阶段，不据此虚构授权或运行态读回。

Stage7 Forbidden Checklist=PASS：无六红线变化；只改DEBUG引导/外部单次控制/直接测试及文档；Runtime API、DR schema、平台target、Stage8均未改变；设备启动0，无需为本轮离线操作请求设备授权。必须在本轮收口停止等待新授权，不自动前推任何正式状态。

```ini
PREPARATION_READY=true
PREPARATION_STATUS=READY_AWAITING_USER_AUTHORIZATION
F1_A_DEVICE_RUNS=0
F1_B_DEVICE_RUNS=0
NEW_USER_AUTHORIZATION=NOT_RECEIVED
DEVICE_EXECUTION=NOT_AUTHORIZED
RUNTIME_VP_AGC_READBACK=NOT_RUN
HUMAN_LISTENING=NOT_RUN
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
