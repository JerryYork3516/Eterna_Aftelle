# T3.2-A · R5-M01 Historical Fidelity & HOST Native Readiness

schema_version: 1。2026-10-20（Asia/Shanghai）。**仅离线核验，无新增设备运行。**

结论：**R5不足以精确复现历史成功条件，但可保留为有限的独立真人REF验证。HOST同run幅度定位能力存在，整体诊断准备为PARTIAL，不能据统计量确认语音损伤或Apple根因。**

## 1. Git与实际身份

开始HEAD、upstream及实时远端均为`63d10a581d70840b51c781de253fca0f1fd1c222`，隔离工作区干净；分支`codex/reference-host-comparison-preparation`推送到`Test3-AppleVP-Clean`。原7冲突工作区不写入，交付前按原status/index保护快照核验。

历史源码固定为`c64c7e2629ec775062fdc2ea1e4a934c73c1fa75`。R5已有登记REF为`R4_GUI_ENTRY_ADAPTED_REF`，二进制SHA `65fadd2acbb09dc9cf19e8f8a93013ad795ff93cef543a3e65420d5d59a9a52b`；本轮复用R5身份核验，不重建、不重复权限/设备预检。当前HOST三份相关源码与R4登记构建基线`bcfa84e`无diff。只新增本文，交付commit由最终Git对象给出。

## 2. 历史成功条件：已提交证据与未知项

以下为冻结23/24号报告的既有证据，**不是本轮重新读取私人录音/Manifest或实机测量**。

| 项目 | 可证实范围 |
|---|---|
| 历史产物 | 23§1：Release SHA `099b328f4bcc28bd111d8e02a358665e73b8bf0a354d870959ca0d9d24a3ec5b`，CLI/ad hoc宿主；不同于当前GUI派生产物 |
| 居民素材 | 23§3：16kHz/Mono/Float32、128000帧/8秒，Peak0.6877746582；文件/PCM双SHA当时匹配私人登记，**具体SHA未公开**。源2–7秒每个一秒段有数字信号；精确非零外沿UNKNOWN |
| 2–4秒是否真有Render | 23§7：实际display至下一request内完整buffer含30400帧，Render ch0非零18573个；完整128000帧匹配登记素材、mismatches0，play因果检查成立。**有数字Render，不只是软件阶段；不是精确物理声压计时** |
| 启动/提示 | 23§5：arm至observationStart 0.361447秒；playRequest +2.004226秒，真人提示显示+4.001779秒；13秒正式窗、0.5秒postroll、16秒admission。postroll覆盖仍UNVERIFIED |
| 配置/设备 | 23§3–4：运行Input/Output VP=true、AGC=true、bypass=false、inputMuted=false；默认登记USB/Built-in。USB唯一物理来源仅SUPPORTED_ONLY，不能凭默认路线认定 |
| 音量/Mic Mode | 历史输出读值0.7619839907；preferred/active Mic Mode原始值均0，为进程属性。输入增益/摆位/现场条件依赖用户“未变”见证，不能核实历史输入60%或跨run相同声压 |
| 听感 | 24§5–6：真人完整/双讲段“正常，无异常”；未报告可辨居民回声；现场重叠>1秒为有限见证。仅VP-C_RESEARCH_POSITIVE_WITH_LIMITATIONS，不是正式AEC/Test3 PASS |

冻结源码依据：`VPCWindow.swift:55–99`先等Input/Render均ready，再记录观察原点；`VPCSession.swift:136–138`的ready是已写入有效records/frames，**不是非零语音或AEC已收敛证明**。`VPCWindow.swift:72–79`为整段schedule→prepare→start→validate，`:30–35`在resident阶段请求play；`AppleEngineDriver.swift:40–56`为原Player→Mixer→Output及整段排程，原Tap未改。

## 3. 历史素材恢复及R5保真边界

限定检查冻结工具/报告树及已登记非私人R2/R3素材目录：没有取得可绑定历史双SHA的原件；公开23号报告明确将双SHA留在私人记录，R1准备报告§5也未核验原文件。**HISTORICAL_MATERIAL=NOT_RECOVERED；HISTORICAL_FILE_AND_PCM_SHA=NOT_VERIFIED。** 这是白名单内的结论，不是全盘不存在性证明；到此停止查找，未读取私人原登记/Manifest、未从历史Render反推、未新造替代素材。

本轮唯一素材核验组只读取现R5登记的非私人派生WAV：SHA `c47d3df54cda56d010b0b6ded27bb75f1e92d9065f390dcb39bee260f317960b`匹配；16k/Mono/Float32、128000帧；非零帧半开区间[31990,91953)，源内[1.999375,5.7470625)秒，Peak0.6742768884、RMS0.0891684211。

按原t=2请求play，**名义数字非零外沿约[3.999375,7.7470625)秒**；不是R5实测。R5真实运行仍0次，R4实际Render延迟不能直接移用。R2§4已说明：该文件由当前Tingting源经SRC、额外前后静默派生，非历史原素材；不以共同8秒格式替代身份。

| 关键条件 | 历史成功记录 | 现R5准备 |
|---|---|---|
| 2–4秒居民铺垫 | 有已报告非零Render | 几乎全为派生静默，约4秒才开始非零 |
| 音频实现 | 原冻结音频路径/CLI Release | 保留音频路径，另有R2事件和R4 GUI入口适配；二进制不同 |
| 输出音量 | 报告读值0.761984 | R5预检快照55%；未跨API/声压校准，不能直接换算dB差 |
| 输入/系统模式 | 登记USB、增益现场未变、进程模式原始0 | TinyUSB输入60%预检；Mic Mode UNKNOWN，跨run物理等价未证 |

故历史复现 **INCOMPLETE**。恢复旧素材、音量或系统模式均不能凭猜测实施，需先核实身份并由主控另行批准；本轮未替换当前R5配置。

## 4. HOST现有诊断能力：PARTIAL

本次一次定点源码/已交付报告核验；没有读取R4私人统计JSON或任何历史真人WAV/PCM。

| 能力 | 分类 | 依据与边界 |
|---|---|---|
| VP后Native、转换前采样点 | AVAILABLE | `MacSpeechAudioCapture.swift:2451–2464`配置VP；`:2174–2203`验证后安装Input Tap；`:2784–2790`先recordNative，再AVAudioConverter。不是ADC原音 |
| 同run、同内容时间窗幅度 | AVAILABLE | `AppController.swift:7883–7892`将同一WindowPlan交给Native/PCM；Capture`:3051–3064`核对runID/generation，`:1223–1230`输出窗口内容边界；AppController`:8437–8460`导出身份/覆盖/Native统计。须采用已有带warmupProfile的入口，不能假定所有普通C均有分窗 |
| 实际转换链 | AVAILABLE | Capture`:788–805`取ch0→48k Mono，`:2746–2748`经Host→输出Converter；`MacSpeechAcousticEchoHost.swift:1181–1198`有效Apple路径返回原samples。Native与最终Int16统计可作粗层级幅度对照，不直接定位某个算法BUG |
| 与最终评分WAV逐窗关联 | PARTIAL | AppController`:141–167`先对所有drain包recordPCM，再决定整包保留；`:8059–8088`才追加WAV。故`warmup.pcm_statistics`不等于WAV实际样本集合，需按`:8310`现有packet序号/内容时间/字节元数据对齐真实保留范围 |
| 三声道内容相等证据 | PARTIAL | Capture`:1152–1158,1203–1220`确实逐样本比较有限值，并输出compared/equal计数，不是比较Peak/RMS。R4报告仅支持本run已统计窗口的数值相等；本轮不重读私人计数。它不证明全程字节相等、窗口外或未来真人run也相等 |
| 10月18日两次真人C首3秒追溯 | NOT_AVAILABLE | 既有真人C报告有最终WAV低能量和全局Native统计，没有可追溯的同窗Native音频/该窗完整对照，不能倒填新分窗能力 |
| 真人可懂度/吞字、精确Native→PCM波形损伤 | NOT_AVAILABLE | HOST未保存可复验Native波形；RMS/Peak相近仍可能有内容变化或声源混淆，没有VP前原音对照 |

R4报告§6同run 3–9秒Native RMS0.09231500、PCM统计0.09231348（约−0.00014dB）支持该**统计**能力，不能代替真人保留。其0–3秒代理本来静默，不能验证真人首段；skip2、140ms评分首尾缺口、partial tail UNKNOWN仍保留。

未来粗定位只需核对现有字段：runID/generation/configurationID、同一score起点与window边界、first/last content、样本数/排除/invalid及覆盖、Native各声道与Int16 RMS/Peak/零值/满幅、保留packet元数据（源码位置见上表）。**Native同窗ch0已近零且Int16同样近零，说明低能量在该转换前已存在，但不能归罪VP而排除设备/声源；Native ch0正常而同窗Int16显著降低，才支持继续查后级。** 两边幅度正常仍不能证明语音完整。

若要判定细粒度断续/吞字，缺的是同run Native可复验内容或更短同窗内容证据，单添一个全局RMS字段无效。相关取证保留需要主控另行裁定和具体私人音频授权；本轮停止在能力缺口，不新增代码、Tap或保存链。Host里的`rawCaptureRMS=0`是原音不可得占位（`:1241–1244`），不是原始麦克风近零的测量。

## 5. 下一次准入与实际验证次数

**建议有条件准入现有R5有限真人REF，不建议以“历史精确复现”名义准入。** 用户在场并另行明确授权后最多运行一次；先由用户试听及主控判断诊断价值，再决定是否单独授权HOST。即使REF良好也不能直接判HOST代码BUG。本轮不预授权、不启动设备，也不恢复旧音量/Mic Mode。

| 本轮实际验证 | 命令/方式及结果 | 次数 |
|---|---|---:|
| Git身份 | `rev-parse HEAD/@{upstream}`、`ls-remote`、`status`，exit0；开始三方一致 | 一组 |
| 素材身份/格式/非零窗 | 定点树/登记目录查找；Python stdlib读取上述单份非私人WAV，SHA/格式/128000帧断言exit0；历史NOT_RECOVERED/NOT_VERIFIED后停止 | 1组 |
| HOST现有能力 | 上述函数/报告定点核验；相关三份源码对`bcfa84e..HEAD`的`git diff --quiet` exit0 | 1次，只读 |
| Secret Guard | `bash tools/secret_guard/check.sh`，exit0，secret-guard: ok | 1次 |
| 文档范围/隐私 | 单报告白名单、`git diff --cached --check`、无私人路径/UID/Token/音频、原冲突保护及源码不变核验，exit0 | 1次 |

设备采集、麦克风录音、居民/蓝牙播放、HOST真实运行、Swift全量回归、新增测试框架均 **0**；没有编译、重新合成/归一化或放宽标准。Git仅本报告，本地核验数值回执留Git忽略目录。原7冲突、历史证据和正式治理状态不变。

五维：技术PARTIAL、工程PASS、证据PARTIAL、一致性PASS、Stage7 Forbidden Checklist **PASS**。无生产代码/Runtime API/DR schema/新target/Stage8变更，无需新权限；新增CRITICAL/MAJOR/MINOR=0/0/0，旧问题未关闭。

```ini
HISTORICAL_FIDELITY=INCOMPLETE
HISTORICAL_MATERIAL=NOT_RECOVERED
HISTORICAL_MATERIAL_SHA=NOT_VERIFIED
HOST_NATIVE_DIAGNOSTIC_READINESS=PARTIAL
REF_HUMAN_ENTRY_RECOMMENDATION=CONDITIONAL_LIMITED_PROTOCOL
DEVICE_EXECUTION=NOT_AUTHORIZED_IN_THIS_TASK
HOST_HUMAN_EXECUTION=NOT_AUTHORIZED
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
