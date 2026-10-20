# T3.2-A · R5 Independent Human Near-End Isolation

schema_version: 1。日期：2026-10-20（Asia/Shanghai）。**离线准备通过；用户明确不在场，仅授权准备，真实REF运行0次。没有R5声学结果。**

## 1. 结论与授权边界

本轮已核验R4的实际GUI REF、原8秒居民素材、原权限查询、默认路线/音量、受控目录和无代理独立启动路径。无需重建、源码修改、蓝牙播放器或R4自动代理控制器。

准备完成后按任务要求请求新的现场同意。用户原话：

> 本轮不在场，仅完成离线准备

对本地分析及听音导出的独立答复：

> 授权本轮录音的本地分析与听音导出

**第二项答复不构成麦克风录音授权。** 当前无R5录音可供分析/导出，因此没有启动vp-c实验、没有播放居民、没有启动麦克风或读取其他私人录音。没有自动沿用R4授权。

`R5_HUMAN_REFERENCE=NOT_RUN_USER_ABSENT`。不能选择声学情况A/B，不能把未执行当作声学FAIL；也不能用只读预检宣布VP实际运行或真人保留PASS。

## 2. Git和原工作区保护

| 项目 | 核验结果 |
|---|---|
| 开始HEAD / upstream / 实时远端 | `4e8819c9038cdbb60300008b51f360ceba309993`，三方一致 |
| 工作区 | 既有干净隔离`vp-reference-host-preparation/Eterna_Aftelle` |
| 本地分支 / 推送目标 | `codex/reference-host-comparison-preparation` → `Test3-AppleVP-Clean` |
| 原7冲突、索引和未跟踪文件 | status/index与原保护快照一致；无写入 |
| 保护索引SHA | `e4c0f51f433f4f53a3bf77e82aabd5152617f5efdbe441f05559182a56c8b952` |
| 本轮Git文件范围 | 仅新增本报告；预检/参数回执在Git忽略的本地目录 |
| 回滚边界 | 单文件新增文档，无跨文件源码修改，不新增空checkpoint |

未stash/pop、reset/clean、强推、解决冲突或操作ACE3。交付commit与推送后三方核验由Git对象及最终回复给出，不伪造自引用SHA。

## 3. 固定REF和素材

| 产物 | 本轮实际结果 |
|---|---|
| 候选 | R4_GUI_ENTRY_ADAPTED_REF，原R4已登记App内可执行文件 |
| REF SHA-256 / bytes | `65fadd2acbb09dc9cf19e8f8a93013ad795ff93cef543a3e65420d5d59a9a52b` / 2906192 |
| 居民WAV SHA-256 / bytes | `c47d3df54cda56d010b0b6ded27bb75f1e92d9065f390dcb39bee260f317960b` / 512058 |
| 格式和长度 | WAV tag3，16000Hz / Mono / Float32 LE，128000frames，8秒 |
| 原生素材PCM SHA | `1b92a2fe2e7fbdbbb33a0c6a4b0c1794dd6269324371640c330c6d1ad7e37595` |
| 重建/音频变换 | NOT_RUN；现有登记产物可复用，未改变素材、增益或排程 |

原REF GUI入口、ReferenceTool、VPCSession、VPCPrompt、可选事件出口及相关文件摘要留本地预检计划；最终再次核验未变。没有R4启动计划旧源码摘要被当作R5的新执行证明，本轮计划明确记录device_runs=0。

继续保留原VP/AGC配置、Engine图、Input/主Mixer Tap、VPCWindow、封存与verify。REF Native Input已经过Apple VP，不是未经处理的麦克风原音。R5仍不是历史真人VP-C成功实验的完整复现。

## 4. 真实设备只读预检

| 字段 | 实际只读结果 / 限制 |
|---|---|
| 默认输入 | TinyUSB DFU runtime，USB，alive=1、running=0；系统枚举16000Hz/1输入声道 |
| 输入音量 | 60% |
| 默认输出 | Mac mini内置扬声器，alive=1、running=0；系统枚举48000Hz/2输出声道 |
| 输出音量/静音 | 55% / false；CoreAudio scalar 0.5500001311302185 |
| 小爱 | 枚举在线、running=0；本轮不作为近端，不启动播放器，不要求断开蓝牙 |
| REF权限 | 登记二进制`permission-status`读回AUTHORIZED；原命令明确输出no audio started |
| 系统Microphone Mode | UNKNOWN；未猜测、未查询外部TCC数据库、未申请/重置权限 |
| 实验进程 | 开始和结束均无REF/HOST/蓝牙代理实验进程残留 |
| 设备/音量变更 | 无；未调整路线、音量或Mic Mode |
| 缓存安全 | 原受控Caches本人所有、0700、无symlink；新建独立0700准备目录，参数/查询JSON为0600；未创建capture目录/音频文件 |
| 可用空间 | 约1.78GB；仅记录预检时值 |

这里的系统1声道/采样率是未启动音频流时的设备枚举，不能代替VP运行后16kHz/3ch的读回。实际inputEnabled/outputEnabled、AGC、bypass、inputMuted、Native格式均为 **DEVICE_UNVERIFIED / NOT_RUN**；须在后续独立授权后由原REF门禁实际核验。

## 5. 无代理独立执行方案（未启动）

原入口可以独立使用：ReferenceTool解析原`vp-c`参数，先完成原NSAlert可见确认，再执行VPCSession；权限、路由、素材、VP及封存校验原样保留。`VPCComparisonEvents.fromEnvironment`在没有`AFTELLE_VPC_COMPARISON_FD`时返回nil；manifest原观察事件仍由VPCWindow记录。

因此后续只需直接启动已登记REF App内二进制，显式清除该可选比较FD环境变量，不使用`device_once.py`、R4代理控制循环、NSSound近端播放器或HOST。不需要新增启动适配代码。原13秒观察加0.5秒postroll、CLI的16秒安全预算保持；改变的非音频参数仅是新私有输出目录和非私人study alias `r5-human-ref`。

拟用原命令合同如下；**只是记录，没有执行**：

```text
<registered REF executable> vp-c
  --authorize-vp-c --material-content-reviewed --enable-audio --arm-diagnostics
  --mode VP_ON --duration 16
  --target-registration <original private registration>
  --material <registered 8s Float32 WAV>
  --material-sha256 c47d3df54cda56d010b0b6ded27bb75f1e92d9065f390dcb39bee260f317960b
  --material-pcm-sha256 1b92a2fe2e7fbdbbb33a0c6a4b0c1794dd6269324371640c330c6d1ad7e37595
  --study-id r5-human-ref --output-dir <new private REF_capture>
```

授权后仍须通过REF原可见确认及系统权限；上面参数不是绕过同意的开关。原注册文件、设备UID和绝对私有路径不进入Git。后续启动前还需重新只读核验设备及音量，不能把本次快照当作未来设备保证。

## 6. 预定窗口与实际取证状态

原提示已核验：nearEnd提示固定句子，其他阶段显示安静；没有改写VPCPrompt或VPCWindow。

| 观察窗口 | 原计划 | 本轮实际音频/统计 |
|---|---|---|
| 0–2秒 | 用户安静 | NOT_RUN |
| 2–4秒 | 居民播放计划，用户安静；派生素材非零约第4秒 | NOT_RUN |
| 4–9秒 | 用户连续说“绿色纸船经过小桥，我会继续说完这句话。” | NOT_RUN |
| 9–10秒 | 用户停止，安静 | NOT_RUN |
| 10–13秒 | 用户继续安静 | NOT_RUN |

原生三声道、RMS/Peak、满幅/非有限、Render内容时间、PCM覆盖、Stop/Seal/verify、RunID和用户试听均 **NOT_RUN**。实际录音0、居民播放0、蓝牙代理0、HOST0；没有伪造RunID或用旧R4数据填充本轮。

如后续获得新现场录音同意，继续使用原封存及统计能力。仅在本机导出本次Native听音WAV、保留编码/幅度及原文件身份；是否可用ch0代表三声道必须针对新run重新核验，不能继承R4相等结论。未取得本次具体真人录音的公开授权前，只推送脱敏报告。

## 7. 与R4结果及假设的关系

R4已记录REF和HOST同Mac蓝牙代理下均有用户报告的断续/忽大忽小，居民是否可辨UNKNOWN。该旧结果继续保留，没有重跑或读取旧私人录音。

“同Mac蓝牙代理可能参与Apple系统回声参考”仍是 **HYPOTHESIS**，不是已确认的Apple内部机制。本轮无真人数据，不能支持或否定它；也不能证明REF真人恢复正常、Aftelle存在独有缺陷、AGC导致异常或任何根因已找到。

本方案将近端改为真人，但声压、口型/语音内容、物理起止和环境不会与代理完全相同，因此即使后续实际执行，也不是严格单变量物理实验。居民约第4秒才实际非零的限制不变，不能声称复现历史有效2–4秒居民独讲。

## 8. 实际命令和检查

| 实际执行 | exit / 结果 |
|---|---|
| `git status --short --branch`、`rev-parse HEAD/@{upstream}`、`ls-remote origin refs/heads/Test3-AppleVP-Clean` | 各0；开始三方一致、工作区干净 |
| 指定REF/WAV的SHA、RIFF格式/128000帧及PCM摘要核验 | 0；固定身份全部匹配 |
| 原保护快照status/index只读对比 | 0；原7冲突不变 |
| 既有CoreAudio查询器`--preflight`（仅查询分支） | 0；目标默认设备在线且running0 |
| `osascript -e 'get volume settings'` | 0；input60/output55/mutedfalse |
| 登记REF二进制`permission-status` | 0；AUTHORIZED，no audio started；没有执行vp-c |
| 限定名称进程查询、目录权限/所有权/symlink/空间检查 | 0；无残留，安全目录可写，无录音文件 |
| 最终指定源文件摘要复核 | 0；未发生源码/产物变化 |
| 原独立入口/可选FD及原提示源码核对 | 只读；没有把源码核验计作设备执行case |
| `bash tools/secret_guard/check.sh`、文档diff/单文件白名单及隐私范围检查 | 各0；secret-guard: ok，仅本报告，无私人路径/音频/设备UID |
| 编译、Fake回归、FULL_CURRENT、vp-c、录音分析、verify | NOT_RUN；无代码变更，用户不在场/未授权采集 |

预检参数/授权状态及查询回执仅在Git忽略的`.build/reference_host_r5/precheck/`。没有保存新的环境声音，没有自动播放/转录，没有上传私人音频或系统日志。

## 9. 五维SELF_REVIEW与问题等级

| 维度 | 结论 |
|---|---|
| TECHNICAL | PASS_OFFLINE_PREPARATION：固定产物/素材可复用、无代理入口存在；真实VP/声学DEVICE_UNVERIFIED |
| ENGINEERING | PASS_SCOPED：仅新增本报告；无源码、参数算法、测试标准或诊断框架变更 |
| EVIDENCE | PASS_FOR_NOT_RUN：保留实际命令/摘要/只读权限与用户原话；零run、不伪造统计或听感 |
| CONSISTENCY | PASS：用户不在场即停止设备流程；本地分析同意不代替录音授权，R4公开音频授权不延伸至R5真人录音 |
| Stage7 Forbidden Checklist | PASS：无代码、Runtime API、DR schema、新平台target或Stage8变化，无新增Engine/Tap，无设备流启动、Provider调用或正式Gate前推 |

新增CRITICAL=0、MAJOR=0、MINOR=0。当前执行阻塞是用户不在场、没有本次现场录音同意，不是已确认工程故障。R4既有声学/证据问题仍OPEN；AEC根因UNKNOWN。

唯一下一项：用户在场并明确批准本次REF录音后，重新核验易变设备条件，再按原可见流程执行一次。当前不安排、不中途后台等待录音、不自动启动后续节点。

```ini
R5_OFFLINE_PREPARATION=PASS
READY_FOR_USER_CONSENT=true
R5_HUMAN_REFERENCE=NOT_RUN_USER_ABSENT
DEVICE_EXECUTION=REQUIRES_NEW_USER_CONSENT
LOCAL_R5_ANALYSIS_AND_LISTENING_EXPORT=AUTHORIZED_NO_RECORDING_AVAILABLE
REF_RUN_LIMIT=1
REF_ACTUAL_RUNS=0
PROXY_ACTUAL_RUNS=0
HOST_RUN=NOT_AUTHORIZED
R5_RUN_ID=NOT_CREATED
VP_DEVICE_READBACK=NOT_RUN
R5_ACOUSTIC_RESULT=NOT_RUN
R5_USER_LISTENING=NOT_RUN
PUBLIC_R5_HUMAN_AUDIO=NOT_AUTHORIZED
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
