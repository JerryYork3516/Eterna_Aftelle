# Apple Voice Progress v1 · VP_ON物理输入来源机制审核

日期：2026-10-15（Asia/Shanghai）。节点：Stage 7.5 / VP-A_ON_SOURCE_VERIFICATION_REVIEW。

**裁定：SOURCE_SUPPORTED_ONLY；USB唯一物理输入来源仍UNVERIFIED。** P4的指定近端语句响应与既有USB默认路由支持保留，不重复该证明。现有证据尚不能排除替代或混合的实际物理输入。下文只保留一个条件性取证路线；在已核实公开契约下，尚未找到足以将本VPIO实例实际输入追溯到物理stream的映射能力，故 **DESIGN_CAPABILITY_BLOCKED**，不能交付已证明可执行的确认实验或启动命令。

## 1. 基线与只读范围

开始时分支 `Apple-Voice-Progress-v1` 的HEAD、upstream及实时远端均为 `11c02ef61133c294273e27e8552f0c1e448eea7f`，工作区干净。只新增本13报告，不修改05–12、源码或正式合同。

核对P3/P4、09–12公开报告，及独立工具Driver、配置、设备/aggregate快照、研究准入和probe协议。没有读取任何私人PCM、原始设备日志、登记或身份元数据；不重新查看P4/ON/OFF音频，不将旧授权扩大为新数据访问。没有实时HAL查询、权限请求、Engine初始化/启动、录音、播放或系统路由操作。本机SDK头文件和Apple公开文档仅作静态契约参考，不作新设备观测。

确认对象是**参与该VP_ON采集实例的物理输入端点是否排他地为登记USB**。这不要求AEC不使用远端参考，也不等于客户端每个样本只含未经处理的麦克风信号；正常AEC参考和内部DSP不是第二个物理麦克风。

## 2. 三个命题必须分列

| 命题 | 既有证据 | 当前裁定 |
| --- | --- | --- |
| 运行时系统默认输入是登记USB | P4及10在准入、运行、停止快照匹配登记；本轮未重查当前状态 | CONFIRMED_BY_REPORTED_EVIDENCE，仅默认设备配置 |
| VP_ON能响应近端语音 | P4提示成功轮三声道中均可听到两句现场指定语句，用户逐声道确认 | CONFIRMED_BY_REPORTED_EVIDENCE，不重复P4 |
| 该实例实际物理输入唯一来自USB | 没有完整、同实例的实际所选物理输入链或替代来源排除证据 | UNVERIFIED；整体仅SOURCE_SUPPORTED_ONLY |

12补足OFF Input有可辨居民回声的内容负控，11记录ON未听辨出居民语句。它们不识别ON物理输入来源，不能用两臂听感或RMS差反推唯一USB。

## 3. 源码机制核对

以下路径均相对 `tools/apple_vp_reference_v1/Sources/`，行号对应本次Git基线。

| 文件/位置 | 实际行为及证据边界 |
| --- | --- |
| `VPReferenceAudio/AppleEngineDriver.swift:16–19` | 仅在Engine停止时调用inputNode的VP开关；全文件没有setDeviceID或其他显式USB绑定setter。沿用Apple默认I/O行为，并非独立硬锁USB，也不因此说明接线错误 |
| `VPReferenceCore/ConfigurationPlan.swift:105–134` | 停止检查→启VP→读双端state→读格式→接图→重新读取/核验。VP启用及格式协商不认证物理端点 |
| `VPReferenceAudio/AppleEngineDriver.swift:46–51`及上述配置校验 | VP_ON用Input客户端格式连接mixer→output，并要求相应格式一致。输出/Render也为3ch部分来自接图约束，不能当独立来源见证 |
| `VPReferenceCore/RunningConfigurationPlan.swift:18–30` | 比较运行VP/客户端/硬件侧格式快照，证明已观察配置稳定，不证明选源唯一 |
| `VPReferenceAudio/AudioDeviceSnapshot.swift:11–20,23–44` | 读HAL默认对象、UID、transport、nominal rate；UID经SHA-256成为私有匿名身份。UID匹配证明所读设备对象身份，不说明其他对象的PCM一定由它产生 |
| `VPReferenceAudio/AudioRouteSnapshot.swift:22–59` | 默认设备来自HAL；两个node标识另由auAudioUnit.deviceID取得。匹配/aggregate结构资格分开计算；前后默认ID复查只排除已观察变化，不是原子或全时段路由证明 |
| `VPReferenceAudio/SourceProbeRoutePolicy.swift:11–20` | 默认USB/Built-in合规，并接受普通binding或已知“双node呈现登记Built-in”的诊断路径；不生成来源确认 |
| `VPReferenceAudio/VPAAdmission.swift:62–75` | ON复用上述研究准入；OFF仍要求普通binding。没有通过本审核削弱record、probe或VP-A守卫 |
| `VPReferenceAudio/SourceProbe.swift:75–77,185–193` | Input Tap来自inputNode，Render Tap来自mainMixer，分别标流；源码未见直接把Render写作Input。结束仍记SOURCE_UNVERIFIED，不授声源资格 |

**没有显式setDeviceID不是接入缺陷的证据。** Apple公开AVAudioIONode契约本就规定macOS设备渲染使用系统默认输入/输出；它使当前USB解释合理，但不能替代本任务要求的同实例物理排他证据。[Apple AVAudioIONode](https://developer.apple.com/documentation/avfaudio/avaudioionode)

### aggregate=nil的准确范围

`AudioRouteSnapshot.swift:39–44`只在某node的transport报告为Aggregate时调用aggregate capture。两个getter均呈现Built-in时，两个aggregate字段为nil是本地分支的结果，**并未据此枚举系统aggregate或查询VPIO内部选源链**。

因此05等历史文字中的“无aggregate对象”，只能按“这些暴露node对象的快照没有建立aggregate观测”理解，不能扩大为系统或内部实现不存在aggregate/混合。此处澄清范围，不回写历史文件或撤销P4近端响应支持。

`AggregateDeviceSnapshot.swift:45–83,105–133`会对传入的已暴露aggregate读取full/active成员、composition、tap及有序输入/输出stream的owner、方向、起始channel和数量；资格检查可约束该对象的成员结构。其状态明确为 `MEMBERSHIP_RECORDED_NOT_RUNTIME_PROOF`，不提供本次ON客户端输入到实际所选物理输入流的缺失映射。09暴露aggregate的证据不能移植给ON的Built-in呈现。

## 4. Apple官方与SDK依据

核对本机当前 `MacOSX27.0.sdk`；这是静态契约版本，不是P4或VP-A设备系统的新运行结果。只使用已文档化属性的既定scope/element，不更换getter组合获取有利值，不引入Beta/私有API。

| 契约 | 能支持 | 不能据此支持 |
| --- | --- | --- |
| [AVAudioIONode](https://developer.apple.com/documentation/avfaudio/avaudioionode)，SDK `AVAudioIONode.h:103–104,141–164` | macOS默认I/O、停止态配置VP及双端处理 | 本次实际物理输入排他性或三声道角色 |
| [AUAudioUnit.deviceID](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/deviceid)，SDK `AUAudioUnit.h:1271–1283` | I/O硬件设备getter及独立setter的接口语义 | VPIO下两个node getter必定分别等于两个独立物理输入/输出端点；相同ID也不证明两个node是同一个AU对象 |
| [默认输入属性](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertydefaultinputdevice)，SDK `AudioHardware.h:470–477` | 系统当前默认输入对象；devices属性是可用设备清单 | VPIO实际选中输入链，或“清单中只有一个可见USB”即可排除所有其他来源 |
| [Device Streams](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertystreams)，SDK `AudioHardwareBase.h:643–649,694–698,1085–1093` | UID为设备持久标识；stream的所属设备、input/output方向及起始channel可用于拓扑核对 | 仅列某设备具备的streams就证明该Engine实际选中了它 |
| [Active Subdevices](https://developer.apple.com/documentation/coreaudio/kaudioaggregatedevicepropertyactivesubdevicelist)，SDK `AudioHardware.h:1650–1667` | 已暴露aggregate的full/active成员和composition；full顺序影响stream排列 | Main/clock成员就是全部输入；未暴露aggregate的VPIO内部输入映射 |

Apple的Mac mini（2024）规格在Audio项列出内建扬声器、耳机接口及HDMI输出；不能把报告中的Built-in**输出对象**想当然改称“Mac内建麦克风”。规格也不是本机运行时完整输入设备清单，不能据此排除其他连接输入。[Apple Mac mini规格](https://support.apple.com/en-us/121555)

在本轮查阅的公开契约与SDK中，未找到适用于当前呈现、能将**本VPIO实例实际客户端输入**完整追溯到实际所选物理input stream的充分映射接口。这是本轮能力缺口，不是断言Apple所有接口永远无法做到。开发者论坛案例、默认路由常识或格式巧合均不替代该能力。

## 5. 替代解释排除情况

| 候选解释 | 现有证据能否排除 |
| --- | --- |
| 实际使用另一物理输入（若现场存在） | 不能。P4说话可被不止一个位置的麦克风拾取；没有本实例排他选源链。未确认任何具体替代设备实际存在或被选中 |
| aggregate/内部路径包含其他物理输入 | 不能。ON的nil不提供完整成员/选源信息；也没有证据确认确有这种混合 |
| Input仅是本工具居民播放参考 | P4无居民素材/无播放却录到指定现场语句，不支持“仅本工具居民参考”独自解释其结果；源码也分开两个Tap。但不能顺带排除其他输入或参考污染 |
| 错误Tap标流或软件直接注入 | 在审核源码中未发现将Render直接标为Input或注入指定语句的路径；这是静态工程支持，不是物理唯一来源证明 |
| 相同deviceID说明USB未接入 | 不成立；getter呈现与P4有效近端响应并存，不能由输出标识判实际输入错误 |
| 三个相同声道证明某个物理布局 | 不成立；重复内容不确定mic/reference角色，也不构成三份独立来源证据 |

默认USB、稳定快照和近端响应共同支持USB解释；低Input RMS、听不到居民残留、纯回声内容负控、无INVALID或成功封存均不能补上排他选源链。确认物理输入即使将来成立，也不自动确认真人身份、三声道语义、近端无损或Runtime资格。

## 6. 唯一最小补证路线：同实例物理输入端点排他取证

**当前设计裁定：DESIGN_CAPABILITY_BLOCKED。** 在当前约束及已核实公开API下，无法给出已证明可执行、能确认唯一USB来源的实机实验。以下是唯一条件性取证路线及启动前能力要求，**不是DESIGN_READY或现成命令**。没有映射能力前，不先开8秒Engine“看看能否找到getter”。

### 6.1 明确区分假设

- H-USB：本VP_ON实例实际选中的物理capture输入端点全部来自登记USB。
- H-OTHER/MIX：实际capture链含另一物理输入，或含不能唯一归属的混合/虚拟输入来源。

要区分二者，必须从**同一实例真正选中的输入链**追溯到端点；全局另有可用但明确未选设备，不自动否定H-USB。AEC远端Render参考不算另一物理麦克风。若只得到默认USB和两个Built-in getter，两假设仍不可区分。

### 6.2 启动前必须先满足的静态能力条件

主控须先接受一项适用当前VPIO/macOS的公开契约或可复查官方同实例依据，明确实际所选输入的观测标识及如何追溯owner/stream/成员。随后才能单独审核最小研究控制层实现与设备协议；本轮没有该实现或新的权限。

能力清单只允许既定公开HAL属性：可见设备及物理/虚拟类型、stream owner/direction/channel、已暴露aggregate的full/active成员、composition和tap。**这份清单本身不提供缺失的“该实例实际选中”连接**，不能用罗列更多UID包装完成证明；Main、clock、默认对象也不能代替它。遇到未文档化映射、不可见成员或属性不可用，即停止设计，不尝试其他scope/element、私有API或有利getter。

### 6.3 仅在能力成立且另获批准后的单次条件流程

PROPOSED：一次VP_ON、最长8秒、无居民播放/无语句刺激、不改路由/登记/增益/Mic Mode。复用现有Driver、音频图、原生Tap/Recorder、R2监听及一次stop/seal；在非实时控制路径只增加有界、同实例的已获证输入链取证，完整保留原始对象关系及前后稳定性。原60秒/64MiB/8MiB硬预算不扩大，研究运行再收紧为8秒；枚举超出既有有界reader容量、取证超过既有控制预算或出现状态/证据异常即INVALID并停止，无重试。不得在callback添加分析。

这不需要再次说P4两句话，不依据新PCM幅度或声道相关性分类。**现有source-probe不能借名执行：** `SourceProbeRegistration.swift:4,17–23`固定 `QUIET_TWO_PHRASES_V1`，`SourceProbeWindow.swift:25–33`固定五阶段刺激。普通record守卫也不解除；`inspect-route`只配置而不start，无法冒充实际运行实例证明。若后续另立研究观察入口，须先经独立实现/非设备审核，保留所有已批准入口行为；本轮不实现或提供可执行参数。

只有同实例官方证据完整支持全部实际物理capture端点归属登记USB、成员/混合语义明确、无其他实际输入且配置稳定，才可提请USB_SOURCE_CONFIRMED复审（对应本任务SOURCE_CONFIRMED，仅该实例物理输入端点）。若支持USB有贡献但不能排除其他输入，最多SOURCE_SUPPORTED_ONLY；若实际链不可读/矛盾，SOURCE_UNVERIFIED。新的实例证明也不能追溯把P4/10旧实例改成CONFIRMED。

### 6.4 不采用的捷径

近场敲击、摩擦、遮挡或普通讲话，可能经空气/桌面传到其他输入；AGC/降噪也会改变响应。硬件mute若缺少仅作用目标USB的明确契约同样不可靠；即使确认USB响应随mute变化，也只证明USB贡献，不能单独排除混合。它们不是本报告另列的实验方案，不执行，也不通过重复P4堆积SUPPORTED来宣称排他确认。

因此当前最小后续动作是**主控先处理缺失的同实例官方映射能力依据**，不是新增录音。无法获得时保留来源等级，不把它归因Apple AEC失败，也不扩大为音频架构重构。

## 7. 三维审核及Stage7 Forbidden Checklist

**TECHNICAL_REVIEW：SOURCE_SUPPORTED_ONLY / UNIQUE_PHYSICAL_SOURCE_UNVERIFIED。** 默认I/O接入符合已核对契约，没有由Builtin或重复三声道判接线错误；也没有补足物理排他证据。已明确nil aggregate的实际读取范围。

**ENGINEERING_REVIEW：NO_CODE_CHANGE；DESIGN_CAPABILITY_BLOCKED。** 当前冻结工具的诊断准入和来源限制保持；新确认实验尚缺可执行的观测能力，不制造设计PASS。仅进行源码/SDK/公开文档及报告一致性复核，构建、262项测试、Lint/Format/C11本轮NOT_RUN。

**EVIDENCE_REVIEW：SOURCE_SUPPORTED_ONLY。** P4近端响应继续APPROVED_SOURCE_SUPPORTED，12的OFF内容子项保留；USB唯一物理来源仍UNVERIFIED。没有新实机数据，不授予SOURCE_CONFIRMED、Apple AEC或正式VP-A/Test3 PASS。

| Stage7检查 | 结论 |
| --- | --- |
| 平台/阶段/六红线 | PASS；仅macOS Stage7.5报告，无新target或Stage8，无六红线触碰 |
| Runtime、Qwen全双工、Test2、Provider、DR/Memory/Session/Studio | PASS；代码、协议、API、schema、授权和generation均未修改 |
| Driver/Tap/Recorder/音频图及普通入口 | PASS；只读，未解除守卫、变更VP算法或Runtime声源资格 |
| 设备与数据授权 | PASS；无设备查询/Engine/录音/播放、无私人PCM/登记/原始身份读取；未重跑P4或OFF/ON |
| 历史与ACE3 | PASS；05–12保持，未操作原ACE3工作区、SSD/quarantine |
| Git/隐私 | PASS；仅13脱敏报告，无PCM、私有路径、UID/身份摘要、登记、素材摘要、日志或密钥 |

独立审核者仅只读圈定源码及公开报告，不冒充读取私人设备证据或进行实机复核。

```text
Source verdict = SOURCE_SUPPORTED_ONLY
USB unique physical source = UNVERIFIED
Minimal confirmation experiment = DESIGN_CAPABILITY_BLOCKED
P4 = APPROVED_SOURCE_SUPPORTED (unchanged)
VP-A Formal = BLOCKED
VP-B/C = NOT_AUTHORIZED
Apple AEC PASS = NOT_ESTABLISHED
Test3 = BLOCKED
Test3.execution_authorized = false
```

本报告提交推送后停止，等待主控审核；条件路线及未来单次运行均未获执行授权。
