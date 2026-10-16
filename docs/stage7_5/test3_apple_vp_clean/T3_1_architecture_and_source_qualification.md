# Eterna Aftelle · T3.1 · Apple VP 架构与声源资格协议草案

> **SUPERSEDED（2026-10-16）**：本文件保留为历史 v1，以下问题、状态及审核记录原样保留。当前唯一计划入口为 [README v2](README.md)，执行口径见 [T3.1-R2 Native Voice Experience](T3_1_R2_native_voice_experience_plan.md)；新设计仍 REVIEW_PENDING，不自动生效或关闭历史问题。

日期：2026-10-16（Asia/Shanghai）。版本：`T3.1-DRAFT-v1`。入口：[正式节点计划](README.md)。验收映射及审核登记：[合同草案](T3_1_apple_vp_test3_contract_draft.md)。

**T3.1 = REVIEW_PENDING；Source Qualification Design = DESIGN_BLOCKED。** 本文提交最小生命周期、分层证据约束与反例方法供审核；没有形成可正式授予真人资格的因果判别规则，不能建议整体 APPROVED。协议字段均为设计语义，不是已新增的 API、类型或生产行为。

T3.0 Documentation 已由本轮主控指令批准；Baseline Verification 仍为 `PARTIAL / FIXTURE_BLOCKED`。缺口允许本轮纯设计，继续阻止 T3.2。生产 Apple VP 未开始，正式 Test3 保持 BLOCKED/false。本轮不改源码、不执行构建/测试、Engine、设备或 Provider，不读私人 PCM/WAV/DR。

## 1. 冻结输入和七项事实

| 来源身份 | 本轮判断及证据边界 |
| --- | --- |
| 设计起点 `28eb59d76c7767ae5b5986ba1601e7de720f71d0` | HEAD/upstream/实时远端一致，初始工作区干净；生产源码仍为 Test2 `728423813ebfc60e303372f3761fc631ac1c03d1` |
| [Test2 验收](../../r8_5_3_test2_acceptance.md) | 本地身份、恢复、播放、持久化安全在批准范围 PASS；严格 Qwen overlap 仍 0/3；不是新路线验收 |
| [T3.0 审核](T3_0_baseline_review.md) | 历史 Debug/Release 和 Host/Playback PASS；依赖未跟踪 DR fixture 的安全回归受阻，本轮未重跑或补造 |
| Controller `729–741、778–790` | Realtime/Cascaded 共用 Host，capture/player 共用 engine owner |
| Capture `686–687、850–862、943–980` | mode/AcousticHost 固定；Apple 播放主动 mute；配置顺序和 muted listener 启动依赖不能原样作为持续双讲方案 |
| Host/Capture/Runtime 分类链 | Apple disabled stats、uncertain 标签与旧 AEC 指标依赖，不能直接复用为 Apple 资格事实 |
| 冻结 VP 研究 `c64c7e2629ec775062fdc2ea1e4a934c73c1fa75` | 02 架构报告与 24 号支持有限积极路线选择，不提供有效 source rule；研究工具与正式 App 分离 |

上述源码位置按 Test2 标注。关键来源：[Capture](https://github.com/JerryYork3516/Eterna_Aftelle/blob/728423813ebfc60e303372f3761fc631ac1c03d1/apps/macos/Aftelle/MacSpeechAudioCapture.swift#L686)、[Runtime 分类与 facts](https://github.com/JerryYork3516/Eterna_Aftelle/blob/728423813ebfc60e303372f3761fc631ac1c03d1/apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift#L448)、[VP-02](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/docs/stage7_5/apple_voice_progress_v1/02_apple_vp_architecture_review.md)、[VP-24](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/docs/stage7_5/apple_voice_progress_v1/24_vpc_vp_on_content_review.md)。

## 2. Backend Lifecycle Contract

### 2.1 路线与唯一 Owner

Realtime 的目标后端为 Apple VP；Cascaded 保留 WebRTC AEC3、`.aec3Processed` 来源语义和原语音消息行为。同一时间只有一个实际 AVAudioEngine、一个 playerNode 和一条采集链。更换后端时可销毁后重建同一 owner 内部的 engine，但禁止新旧并行工作或再建 route 专属 owner。

| 状态/动作 | 唯一 Owner | 其他组件的限制 |
| --- | --- | --- |
| 选定业务 Route、lease、Runtime routeEpoch/generation、最终取消 | RuntimeCore | Controller/Host 不自行 acquire、推进或重绑 Runtime 身份 |
| 前台 Start/Stop、Host 跨 actor 操作协调和 attempt reservation | AppController 现有生命周期协调 | 只协调资源，不能授予 Brain/声源资格；OrchestrationKernel 仅窄转发 |
| engine/playerNode/tap、后端配置、配置失效和 `audioConfigID` | `SystemMacSpeechVoiceProcessingEngine` | 原稳定 facade 供 capture/player 共用；配置号不是 Runtime routeEpoch |
| capture/prepared generation、帧 buffer、设备事实 | MacSpeechAudioHost | 只上报物理路由变化，不生成 Runtime 切代决定 |
| playback generation、queue/scheduled/in-flight、pressure waiter/watchdog | MacSpeechAudioOutputHost | clear/cancel 按 Runtime Decision；设备故障安全停机单列原因 |
| 播放格式/converter 缓存 | MacSpeechAudioOutputPlayer | 只委托共享 engine，无独立 engine/取消 owner |
| 近端 Activity 的窗口、连续性、hangover | MacSpeechAcousticEchoHost 内唯一串行 Activity 状态 | 不另加 HAL Gate；Bridge/Controller/Runtime 不重复维护活动检测窗口 |
| 源资格证据配对/消费与正式授权 | RuntimeCore 既有证据状态 | 判别规则未解决时只能 UNKNOWN；不建第二资格服务或全局可信布尔开关 |
| binding/pump、身份校验、事实传递 | Realtime Input/Output Bridge | 不认证声源、不造 confidence、不持有新的取消策略 |

`audioConfigID` 表示同一 engine owner 的配置代次，覆盖 backend、设备路线或格式变化；复用可用的本地资源代次机制，不能再造一套独立 Host routeEpoch。每次失效单调更换配置身份，旧配置永远不可恢复为当前。具体内部承载在实施前窄化，不修改公共 Runtime/DR/Store schema。

### 2.2 状态及切换条件

以下是资源语义，不要求新增同名通用状态机；以现有 owner 状态导出单一可信快照。

| 状态 | 允许动作 | 拒绝动作 / 完成条件 |
| --- | --- | --- |
| QUIESCENT | 预约后端配置、读取新路线格式 | 必须同时满足下面的全空闲条件；不能只看 engine.isRunning=false |
| CONFIGURING | owner 内停止状态建图、验证格式/VP、发布新配置 | 拒绝 Capture/Playback start、第二次配置；失败不发布 ready |
| PREPARED | 在同配置下启动当前受权 capture/output，或显式 close 释放 | 禁止后端切换；preparedGeneration、converter 缓存也算占用 |
| ACTIVE | 当前配置下 capture/playback/duplex、合法 clear/Stop | 禁止后端切换；自然 completed 不能自动视为 QUIESCENT |
| QUIESCING / REBUILDING | 撤销数据有效性、拒绝新输入、关闭旧资源、按原后端重建 | 拒绝新 Route admission；旧 completion 不推进新状态 |
| FAILED | 保持无新数据/资格/播放授权，报告明确错误，安全 close | 禁止静默切 WebRTC/half-duplex 继续冒充 Apple；不自动重试 |
| CLOSED | 完成本次资源关闭；仅新的合法前台生命周期可重新预约 | App termination 后不得由迟到权限/回调重新启动 |

全空闲合取：没有 active/preparing/prepared capture generation、未完成 Start/Stop/rebuild/transition、Bridge pump/send/receive/drain、未决输出 prepare、queued/scheduled/in-flight PCM、pressure continuation、watchdog 或有效 tap；Player converter 已 close/reset，engine 停止，旧 Provider/Runtime route 已按既有规则 definitive settle。`stop()`、`clear()`、`queue=0`、`completed` 任一项单独都不足。

切换请求先只读核对全空闲条件；任何 active/prepared/queued/in-flight 或其他占用均无副作用拒绝，不能由 switch 请求自动 Stop/clear/close 来制造空闲。旧资源只能由独立获准的既有 Stop/close 生命周期收束，完成后重新发起切换。合格请求再取得现有 Host 生命周期 reservation；engine owner 在锁内复验本地空闲与 operation/config token，锁外建图，最后按相同 token 发布。跨 actor await 后再次校验，避免快照后新 prepare 抢占。旧任务只可清理自己拥有的资源，不能拆新 config。reservation 不拥有 Runtime lease，Runtime admission 仍由 RuntimeCore 决定。

### 2.3 Stop / Reset / Route Rebuild

1. 显式 Stop 先走现有 Runtime 停止/失效流程，Controller 撤销 Start admission。设备故障时 Host 可立即禁止不安全音频，再通知 Runtime；这是资源安全停机，不伪造 semantic confirmed、generation advance 或正式 cancel。
2. 在各 owner 内先标记旧 config/capture/playback 不再接收，拒新 enqueue/回调；Runtime 撤销相应 pending 资格、语义配对及旧 target。只允许 Runtime 改自己的 lease/epoch/generation。
3. 取消/收束 pump、watchdog、pressure waiter；撤活后在状态锁外移除 capture/render tap、停止 node/engine。不得持锁等待会重取同锁的 callback；不得从 input pump 同步等待其自身退休。
4. 释放 prepared generation、排程/在途 buffer、converter/sample cursor、packetizer、缓存格式和 Activity 历史；每个 completion 按旧 operation/config/binding 幂等拒绝。Output `stop()` 不清 Player 格式，切换必须 `close()` 或等价显式释放。
5. 确认全空闲后才重新配置。Reset 不能只是清计数：必须声明重置对象、失效身份及 Runtime 处置；不能清掉失败记录取得 PASS。
6. Route rebuild 在同一预登记后端上重新取实际设备/格式并验证，成功只发布新的平台配置/传输事实。`routeDidRebuild` 通知不等于 ready、恢复听说或资格有效；失败保持 FAILED/stopped。是否 automatic rebound 必须按真实行为记录，显式 Restart 不冒充 automatic。

重新启动必须经当前 Runtime/Controller admission 和全新有效 binding。不能从旧 config 复制 source verdict、PCM、target 或 Runtime generation。正常中断 N→N+1 的同 capture 连续交接是 [T3.0 P6](T3_0_baseline_review.md) 的独立原子修复组；设备/backend 切换不享有该保留例外。

### 2.4 VP 建图、PCM 与处理状态

配置时 engine 必须停止：选择 Apple 后 enable VP，再读取实际 input/output/mixer/player 格式，按协商结果连接共享图并重新验证。配置、capture start、playback start、route rebuild 都要验证对应配置，input/output VP enabled、input bypass 未启用且 input 持续 unmuted；不依赖 muted-speech listener 或 HAL 必须可用。AGC 状态作为实际配置记录，不推断纯 AEC 增益。

Apple processed PCM 只来自该共享 engine 的 input tap，保留原生格式/声道映射与 sample 范围，再经必要的现有 converter/packetizer 转到正式边界。不能假定 16k/3ch 或声道逐样本相等；mix/downsample 规则必须固定且可追溯。render tap 使用实际 node 格式，不继续绑定旧 localFormat；它是数字供音见证，不能证明扬声器可闻声压或 Apple 内部参考逐样本一致。

Apple 路线不调用 WebRTC DSP；Cascaded 不接收 Apple PCM。Runtime 中立 `.acousticEchoProcessed` 不能隐藏具体 backend/config 事实；Native/Cascaded `.aec3Processed` 只对应真实 AEC3 路径。VP 未启用、bypass/mute 未知、时序/route 不明、转换失败或发现软件注入时不得宣称有效 Apple PCM。

将 `configured/enabled`、`engine running/tap produced`、`processing-path valid`、`acoustic effectiveness` 分开。前两类状态和格式可直接观测，第三类须批准生产者/失效规则；第四类不能由 flags 推出。状态快照不是持续内部 AEC 真值。现有 Apple disabledStats、播放期 processedRMS=0、uncertain 标签不能被借作有效状态，WebRTC 专属 linear output/ERLE/DT/confidence 记 N/A，不能填 0 或 1 假装测量成功。

## 3. 六层事实与授权协议

### 3.1 公共证据信封和时间

每项证据具有 schema/合同版本、run/source/build/profile 身份、backend/audioConfigID、设备角色的脱敏引用、capture generation、PCM sequence/sample 半开区间、candidate/evidence ID、method/version 和有效性原因。进入 Runtime 还须带当前 Session/lease/Runtime routeEpoch/generation/context、目标 turn/response；Provider 事实另带 connection/provider-session 身份。只允许在可证明的一对一绑定处补齐关联，不能借“最新快照”给旧 PCM 换新身份。

分别记录 `content time`、`callback arrival`、`PCM available`、`activity ready`、`qualification ready`、`STS proposal ingress/ready`、`Runtime confirmed`、`Host clear completed`。全部带 clock domain/单位/区间；跨域只有经登记的映射及误差边界才可比较。没有校准的物理起音/传播/处理时延记 UNKNOWN；不能把 callback 当物理起音，把回溯内容时间当 ready，或把缺时钟填零。

基线声学 observation freshness 为 500ms、融合窗口为 2s（RuntimeCore `1569–1574`；eligibility `594–596`）。保留现有限制作为上限，新增 ready-age 必须同时受界限约束；不能自动放宽来掩盖检测/网络延迟。具体同内容时间/ready 的适配属于待批准决策，未解决时拒绝，不作新增延迟 PASS 门槛。

| 层 | 生产者 → 消费者 / 身份与时间 | UNKNOWN / INVALID / 过期和切代 | 负控及不得升级条件 |
| --- | --- | --- | --- |
| 1 PCM真实性/处理状态 | Engine/Capture → Activity、Bridge；共同信封、原生/转换区间、VP/format 状态观察时间与 PCM available | 缺状态/物理来源不明=UNKNOWN；配置冲突、缺区间覆盖、注入或失连续=INVALID；旧 config/route/capture 永久拒绝 | flags=true、非零 PCM、成功转换均不等于真人；纯居民残回声仍可能是有效 processed PCM |
| 2 Activity candidate | Acoustic Host 唯一 Activity 状态 → Bridge/Runtime；candidate ID、输入支持区间、method/version、实际 ready | 缺 PCM 或窗口不完整=UNKNOWN/INVALID；过期=EXPIRED；config/route 换代清窗口，不能沿用 hangover | VAD 误报单列，不授资格；不得把 HAL、RMS、相关性作为多重串联硬 Gate；Bridge 不重检活动 |
| 3 物理近端资格 | Runtime 既有证据配对消费已登记物理支持事实；rule/version、支持/反驳 evidence、evaluation ready | 规则/支持事实缺失=UNKNOWN；身份/时钟矛盾=INVALID；旧 verdict 不转移到新 epoch | 路线曾通过负控不是本次候选真人证明；VP、Activity、STS、低相关或重复检查同一派生值均不能升级。当前判别机制缺失，DESIGN_BLOCKED |
| 4 STS语义提案 | ProviderAdapter 传语义事实 → Runtime；connection/session/turn/response/context、wire ingress/ready，非硬件内容时钟 | 模糊/附和/识别冲突保留 unresolved；旧连接/上下文/目标拒绝；不能覆盖缺声源资格 | STS 听懂居民回声或误判 interrupt 仍无授权；partial/Provider user item 可为临时事实，不自动成为 canonical 用户轮次 |
| 5 Runtime授权 | RuntimeCore → Controller/Provider command；当前 target、资格、意图、新鲜度、Decision ID、确认时刻 | 任一 UNKNOWN/INVALID/EXPIRED/不匹配均不 confirmed；重复仅幂等忽略，旧 target/epoch/generation 拒绝 | acoustic-only、semantic-only、测试 bypass 或 UI 开关均不得取消；不得直接把 sourceAttributionConfirmed 设为 true |
| 6 Cancel/Clear/N+1 | ProviderAdapter 执行 Runtime cancel；Controller/OutputHost 执行 Decision；Runtime 负责代际交接 | 旧 Decision/completion/watchdog 不触碰新播放；失败显式报告，不能重放副作用或自动多发回答 | 本地 clear 不等云端取消成功或声场尾音消失；clear 完成、cancel send/ack、下一代恢复分别记证据 |

有效性区分：UNKNOWN=资料不足；INVALID=可证明的违例；EXPIRED=曾有效但已超窗；REJECTED=有效证据反对资格；QUALIFIED=只有已批准规则才允许产生的结果。本轮没有可产生 QUALIFIED 的规则。未来/倒退时刻、同 ID 冲突、缺 sample 支持、跨 config/epoch 均不得靠重标记修复；重复同一有效证据只允许幂等消费。

可信源但意图模糊时不强制中断，不强造完整转录；澄清也须经过合法 Runtime 用户轮次/输出授权，不能由未知源触发主动追问。声学与语义到达顺序可以不同，但必须绑定同一事件和目标、均在有效期内；不可用用户标签或脚本提示事后补成真实在线 source 证据。

### 3.2 当前不能冻结为有效算法的部分

Test2 classifier 依赖旧 AEC 指标，Input Bridge 将分类派生成 nearEndDetected，并将 alignment/isolation/Gate 派生成 0/1 confidence；Runtime 重验同一关系。多次复验同一代理不能增加独立声源信息。Test2 facts 尚无后续 E 提交中的独立 attribution 字段；不得假称已存在。

可以冻结的合取约束是：当前身份/处理路径有效、Activity 支持区间有效、**逐候选物理 source 支持规则满足**、反例/失效条件均未触发、明确语义与活动正确配对，才允许 Runtime 授权。加粗部分目前没有可用因果判据；它是待证明的义务，不能把这个合取表达式当作已完成算法。

缺口登记为 **SQ-M1 / MAJOR / OPEN**：尚未确定在线可取得且能区分真人与本居民回声解释的证据及判别方法。VP-24 的有限听感、数字 render 和来源未知不能填补。路线校准/合格证书只证明过去测试条件，不能给该路线所有候选常开资格；现场/素材真值只用于评估，不作为算法输入。

关闭 SQ-M1 需要先提出具体 rule 的观测来源、因果解释、确定性映射/阈值及版本、反例和拒绝条件，独立审核其可证伪性；T3.3 才以事前固定、未用于拟合的同 route 负控/正控检验。不得一边看 CHECK 失败一边调阈值补绿，不以生物身份/声纹或新重模型框架扩张本节点。没有这样的设计时保留 DESIGN_BLOCKED，不能靠所有输入均 UNKNOWN 取得通过。

### 3.3 反例与验证方法（本轮均未执行）

| 场景 / 独立真值方法 | 应记录的层间结果 / 可证伪条件 |
| --- | --- |
| 纯居民外放：用户静音，固定正式 5 周期/音量覆盖 | Activity 可有原始误报但必须完整报告；任一错误权威资格、confirmed、cancel、clear、虚假用户轮次即失败。原 false-double-talk 计数映射另待批准，不能消失 |
| 尾部残回声：完整播放后 1 秒，覆盖 0–500ms tail | 无真人标签的残留不得利用 listening 切换取得资格；分别记录尾音内容、活动、资格和副作用 |
| 真人独讲：居民不播放，真人现场独立标记 | 检查起音/尾音、内容保留、Activity 与资格覆盖；不能因 farEnd=false 跳过资格规则；不计入 53-B 正式 10 次 |
| 持续双讲：真实空气、同轮居民实际外放和真人连续讲话的独立现场见证 | 并列记录数字供音、物理重叠支持、处理后真人内容、资格和语义；render 非零、计划窗长或输入安静不单独证明成功 |
| 正常音量弱短句：事前固定句集/音量条件，含约 400ms 研究维度 | 不按旧 RMS 门槛剔除失败样本；报告 PCM/Activity/资格/语义各层漏检；短句不替代正式实质插话，400ms 不是完整中断期限 |
| 无效设备/route/时间/VP状态或 buffer gap | UNKNOWN/INVALID，无资格/轮次/取消；恢复必须新有效 binding，不拼接坏区间 |
| 旧 generation/Runtime epoch/audioConfigID/connection 回调 | stale rejection、旧输出和副作用全零，N+1 数据不受污染；测试乱序、重复、late completion |
| VAD误报，或 STS把居民语句当真人/将附和误判为打断 | 候选与语义可错，但 source 不得由其升级；任何错误权威资格即拒绝规则，不能只看最终 cancel=0 |
| 有 source 支持但语义模糊/短附和 | 保留 unresolved/passive，不强制 cancel；未获 source 的澄清副作用为零 |

方法版本、设备角色、几何/音量、source/build、真值来源、样本选取、时钟映射、损伤判读及预算必须事前固定。真人原答、盲评与已知脚本听感分别标注；合成和 HIL 代理不能冒充真人。新录音/回放/读取均另行授权。本轮没有给出新 ERLE/SNR/识别率或总延迟数字。

## 4. 最小源码和回归白名单（仅未来设计范围）

这些路径真实存在，除特别注明的新测试候选外；表格不构成本轮或下节点实施授权。每个节点启动前再次圈定其中必要子集，不整体修改。

| 最早节点 | 源码路径 | 限定责任 |
| --- | --- | --- |
| T3.2 | `apps/macos/Aftelle/MacSpeechAudioCapture.swift` | 唯一 engine 的后端配置、unmuted、tap/格式、converter 时间、失效 token/锁顺序 |
| T3.2 | `apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift` | Apple 有效 PCM/处理事实和有界分帧，避免借用 AEC3 stats；不搬 HAL Gate/ledger |
| T3.2 | `apps/macos/Aftelle/MacSpeechAudioHost.swift` | capture/prepared 生命周期、配置绑定、路由/帧队列失效 |
| T3.2 | `apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift` | 关闭格式缓存、实际格式转换、共享 engine 委托 |
| T3.2–4 | `apps/macos/Aftelle/MacSpeechAudioOutputHost.swift` | 全空闲判据、queue/in-flight/pressure/watchdog 生命周期和 Decision clear |
| T3.2–4 | `apps/macos/Aftelle/AppController.swift` | 两条正式调用方的空闲切换准入、await 后检查、原单次 Decision 执行 |
| T3.3–4 | `apps/macos/Aftelle/MacSpeechRealtimeBrainInputBridge.swift` | backend/config 身份传递；P6 原子 handoff，不复制 Activity/资格检测器 |
| T3.3–4 | `apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift`、`apps/macos/RuntimeCore/RuntimeCore.swift` | 内部中立事实/资格拒绝、旧分类适配、融合/代际安全；不新增公共平台 API |
| T3.3–4，条件项 | `apps/macos/Aftelle/AppModels.swift` | OrchestrationKernel 现有 `submitRealtimeResidentBrainEligibleAcousticEvidence` 调用方仅作必要窄转发；无新 owner |

Qwen Adapter/composition、DR/Store、UI、项目 target、Native Provider 不在最小修改集。Realtime Output Bridge 优先使用现有关闭/binding 接口；如必需修改，先提出精确接口和扩围依据，不悄悄加入。

| 必要测试路径 | 未来回归要求 |
| --- | --- |
| `tools/speech_audio_host_tests/check.sh`、`tools/speech_audio_host_tests/MacSpeechAudioHostTests.swift` | 两后端切换、prepared 拒切、Stop/route/格式/锁边界；check.sh `85–86` 旧 mute/listener 强断言须按获批路线修订，不能保留后冒称新方案 PASS |
| `tools/speech_audio_output_tests/check.sh`、`tools/speech_audio_output_tests/MacSpeechAudioOutputHostTests.swift`、`tools/speech_audio_output_tests/FakeMacSpeechAudioOutputPlayer.swift` | prepared/completed/pressure/in-flight 拒切；close 清缓存、真实 timeout 与同 generation 旧 watchdog、clear/stale |
| `tools/mac_speech_realtime_brain_input_tests/check.sh`、`tools/mac_speech_realtime_brain_input_tests/MacSpeechRealtimeBrainInputBridgeTests.swift` | packet 支持区间、config/capture 失效、P6 连续交接/旧 pump 及反序事件 |
| `tools/realtime_interruption_evidence_tests/check.sh`、`tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift` | UNKNOWN/false/zero/stale 拒绝、source/semantic 乱序、权限 await 中 Stop 与重复 Start |
| `tools/realtime_resident_only_zero_self_interrupt_tests/check.sh`、`tools/realtime_resident_only_zero_self_interrupt_tests/RealtimeResidentOnlyZeroSelfInterruptTests.swift` | 负控零副作用、confirmed/N+1、Qwen handoff、old callback；保留获批身份和持久化安全 |
| `tools/realtime_confirmed_interruption_tests/check.sh`、`tools/realtime_barge_in_latency_stale_audio_tests/check.sh`、`tools/realtime_release_route_guard/check.sh` | 复用已有模式/静态 Release 权限语义，不能把 guard PASS 替代运行断言 |
| 条件新文件：`tools/speech_aec_host_tests/ConverterTimelineTests.swift` | 历史 D 中有此测试，本基线没有；若保留转换器才另圈定移入的时钟测试及实际入口，不假称本轮已存在/执行 |

完整 Qwen 身份/取消回归继续调用现存 `tools/qwen_realtime_resident_brain_tests/check.sh`，不需为本协议改 Adapter 或该套件来降低标准。禁止整体带入 HAL/RMS/相关 Gate、causal pause/resume、ACE3 诊断/ledger、WebRTC 声学补偿、VP CLI/实验会话。

## 5. 后续准入与冻结边界

T3.2 当前不准入：T3.0 fixture 受影响安全回归未补齐；SQ-M1 因果规则未闭合；Apple 状态/时间及 Gate 等价见证仍待主控决策；无下一节点授权。先在单独批准范围明确 fixture 来源/权限并补齐安全回归，不从旧目录复制私人 DR。本轮不测试、不改 fixture/忽略规则。

T3.2 开始前还需主控批准生命周期、最小白名单和合同适用范围，关闭影响实施的 MAJOR，显式授权该节点。机械接线仍须锁闭正式中断，不能凭接线 PASS 解除 source 锁。

T3.3 需 T3.2 冻结候选、具体可证伪 rule、同 route 反例/正控方法、预算和独立授权。全 UNKNOWN、全拒绝或负控无错误但正控不覆盖，都不是 PASS；任一纯回声错误权威资格即失败。Shadow 不执行正式 cancel/clear，不计正式 53 次数。

T3.4 完成必要清理后固定 source/artifact/profile；T3.5 使用相同候选，T3.6 只能只读。任何生产变更重新走受影响回归/required Gate。本文“冻结”仅指待审协议版本和拒绝边界，最终批准与后续执行均归主控；DESIGN_BLOCKED 不因文档齐全自动解除。
