# Test3 · VP-A 纯居民外放 VP_OFF 单臂设备记录 · v1

日期：2026-10-15（Asia/Shanghai）。本报告只记录已授权的一次 VP_OFF，不包含 VP_ON 对照或 Apple AEC 能力评价。

**裁定：VP-A_BLOCKED / EVIDENCE_UNVERIFIED / BLOCKED_FOR_NEXT_ARM。** 已观察的配置、Engine生命周期及原生记录器子项有效；完整协议窗口尚未获证，不能授予整体 ENGINEERING_VALID 或 EVIDENCE_VALID。原始程序结果仍为 `SEALED_EVIDENCE`、`INVALID=0`，不追改原始证据。

## 1. Git、授权与固定输入

- 分支为 `Apple-Voice-Progress-v1`。开始时HEAD、upstream、实时远端均与本节点用户审核基线一致，工作区干净；该基线是本报告提交的父提交。
- 当前用户明确授权一次真实扬声器外放、USB麦克风录音及本次私有离线分析；不包含VP_ON、自动重试或其他实验。实际独立 `vp-a` 调用一次，VP_ON零次。
- 沿用准备阶段同一Release可执行文件，运行前后文件身份一致；既有ad-hoc/linker签名的 `codesign --verify --strict` 通过。启动宿主为Codex执行工具→Python子进程→固定参考工具，未重建、复制替换或重签程序。二进制及配置身份只存私有记录；未独立证明TCC系统归责进程身份。
- 原P4登记由成功轮实际 `--probe-registration` 执行记录恢复；当前用户所有、父目录0700、文件0600、普通文件、路径无symlink。原字节身份与P4成功轮prepared/manifest一致；没有重建、复制替代或修改登记。
- 固定历史居民素材仍为8秒、16kHz、mono、Float32、128000frames。再次实际调用已批准 `PCMSourceMaterial.load` 与 `VPAMaterialSafety.inspect`，文件/native PCM双身份相符，峰值约0.687775、满幅0、非有限及越界0。没有裁剪新片段、调增益或改变声音。
- 已有麦克风权限为AUTHORIZED，没有请求权限。运行前当前默认USB输入及Built-in输出匹配原登记，设备类型与名义采样率保持；可用私有磁盘空间约7399MiB。

准备阶段同一源码已通过207项非设备测试、Debug/Release、严格Swift Format、SwiftLint及C11检查。本次单臂运行没有重新修改或重跑测试来代替物理证据。

## 2. 现场与实际调用

使用批准的 `vp-a --authorize-vp-a --enable-audio --arm-diagnostics --mode VP_OFF --duration 16`；素材、双身份、原登记及新输出目录从核验后的本地私有记录读取。没有调用普通record/source-probe或其他录制入口。

执行前在聊天中发布中文“现在开始VP_OFF，请保持安静，直到已结束”，随后留出3秒提示时间，再启动唯一命令。独立提示页的data URL被浏览器安全策略拒绝；没有换协议、换浏览器或其他绕过操作，使用聊天文本提示。提示发布不是用户阅读时刻的独立测量。命令结束后立即在聊天中发出中文结束提示。

流程为启动及实际状态核验→2秒静默→一次固定8秒播放→3秒计划尾窗→停止/移除Tap/封存。进程退出码0，进程耗时13.510757秒；没有自动重试或第二臂。

用户对“是否确实听到约8秒居民语音、可听辨且适合比较，并说明异常/他人讲话/设备音量变化”的现场核验问题回复“确认”。据此记录**现场外放可听辨性由用户确认**；没有逐字转写或独立试听本次Input，素材逐字内容、当前VoiceProfile一致性和Input语音可懂度仍为UNVERIFIED。没有自动追加试听播放。

设备几何、房间声压、环境噪声没有独立仪器测量。工具未修改音量、增益、Mic Mode、系统默认路由或设备位置；系统输出volume scalar运行前后读回同为约0.761984，player/mixer volume均为1。

## 3. 配置、设备与生命周期

| 项目 | 观察结果 |
| --- | --- |
| VP实际状态 | 配置后、运行中、停止后input/output enabled均false；OFF是disabled，非以bypass冒充 |
| bypass / input mute / AGC | 三个快照均false；属性可获得 |
| Input客户端 | 48kHz、mono、Float32、非交错，4bytes/frame |
| Mixer / Output客户端 | 44.1kHz、stereo、Float32、非交错，每声道4bytes/frame |
| 默认设备名义采样率 | USB输入16kHz、Built-in输出48kHz；不冒充Tap客户端格式 |
| 路由 | 配置前/运行中/停止后完整route快照一致，默认目标与既有登记一致；node绑定为AGGREGATE_IO_DIRECTION_QUALIFIED |
| 格式 | 配置后、运行中、停止后input/mixer/output格式一致，没有已观察到的格式变化；客户端与默认设备名义格式分列 |
| Mic Mode | preferred/active均STANDARD且快照一致；这是AVCaptureDevice进程属性，同Engine归属仍UNVERIFIED |
| 播放状态 | play后isPlaying=true；实际Render有非零PCM，用户确认听到外放；isPlaying自身不证明声压 |
| Engine | 运行时isRunning=true，停止后false；进程正常退出 |
| 配置通知 | 监听区间没有触发被记录的配置INVALID；没有过滤通知或重启Engine |

代码路径沿用已批准的监听前置、统一stop/removeTap及一次seal。运行后Engine停止、封存及进程退出均有证据；removeObserver/每次资源释放的执行次数没有独立设备追踪，不能把静态调用路径当完整异步时序证明。observer→play、在途通知和晚到callback的既有静态未知项继续保留。

## 4. 原生PCM、回调与封存

| 项目 | Input | Render |
| --- | ---: | ---: |
| 原生声道 | 1 | 2，逐位相同，分别保留与统计 |
| 记录数 | 130 | 130 |
| frames | 624000 | 573300 |
| 按frames/native rate计算 | 13.000000秒 | 13.000000秒 |
| sampleTime区间 | [0,624000) | [0,573300) |
| 后续sampleTime断样 | 0 | 0 |
| 缺失sampleTime / hostTime | 0 / 0 | 0 / 0 |
| continuityUnknown | 首条1次，其后均已知 | 首条1次，其后均已知 |
| callback相邻间隔 | 约95.8205–106.8037ms | 约95.8315–106.8162ms |

两条初始continuityUnknown表示没有前一条记录可比较，不是观测到丢帧；原始outcome仍诚实保留 `timestampStatus=UNVERIFIED`。后续sampleTime严格连续，callback tick单调；没有由此声称回调零抖动或绝对声学时延。

总计260条记录、7082400bytes原生PCM。lost、overflow、pending、discarded、suppressed和INVALID均0；CONTENTION位为0。control seal成功、sealed=true、integrity=VERIFIED。另行只读调用同一工具的 `verify` 返回0，容器完整、校验和匹配，记录数与PCM字节数一致。verify仅证明容器/receipt，不授予实验有效性。

记录器residentBytes=4473728，低于8MiB；PCM低于64MiB。16秒admission上限未超出。Engine/框架总RSS及CPU未测。单次完整状态观察16次，最长返回耗时15.985542ms，未超过批准的250ms工程观察预算；这不是对任意阻塞getter的抢占保证。

## 5. 控制窗口与实际内容覆盖

以下时刻为Mach continuous控制tick相对arm，不是扬声器声压或声学到达：

| 控制事件 | 相对arm秒 |
| --- | ---: |
| 启动验证后quiet开始 | 0.164496 |
| play请求 | 2.180679 |
| planned tail开始 | 10.190338 |
| stop请求 | 13.203570 |

quiet控制窗2.016183秒、play控制窗8.009659秒、tail控制窗3.013232秒，`windowsCompleted=true`。这些只证明控制流程完成。

Tap保存原始AVAudioTime.hostTime，控制tick属于mach_continuous_time。本轮未在录前/录中建立两域配对；离线仅以录后一次bracketed absolute/continuous读取估计偏移。偏移在该段运行期间恒定尚未独立证明。因此下列窗口定位和样本筛选是**条件性描述**，不能宣称绝对到达时间或完整协议覆盖。

在该条件映射下，Input内容约覆盖arm+[0.154433,13.154349)，Render约[0.180204,13.180110)。名义tail起点+3秒为13.190338：Input末端约短35.989ms，Render约短10.228ms；Render在quiet控制窗开头还约短15.707ms。两流完整封存与存在上述边界覆盖限制不矛盾；没有把未取得的末段称为recorded丢帧，也没有补齐、外推或放宽标准。

更关键的是：Render最后一个非零样本条件性位置约为10.230066秒，超过计划tail起点约39.728ms。**计划tail窗开头仍有数字播放数据，不能把整个该窗的能量都归于房间尾响。** Render非零起止约2.292385–10.230066秒；非零样本范围不是8秒源buffer精确映射、实际播放完成回调或扬声器声压真值。

本轮因此不授予全窗口 EVIDENCE_VALID。覆盖/实际尾窗起点不足是独立证据限制，不能通过exit0、正帧数或13秒总时长制造PASS。

## 6. 全声道信号统计

数值为原生Float32数字幅度；没有归一化、增强、下混或覆盖原始PCM。全部Input/Render声道的NaN/Inf、绝对值超过1和恰好±1计数均0。

| 原生声道 | 全程峰值绝对值 | 全程RMS | 样本数 |
| --- | ---: | ---: | ---: |
| Input 0 | 0.757916093 | 0.147384302 | 624000 |
| Render 0 | 0.499312758 | 0.049189588 | 573300 |
| Render 1 | 0.499312758 | 0.049189588 | 573300 |

按第5节条件性时间映射筛选的描述性RMS如下；不可当真实声学分段或声源身份判据：

| 窗口 | Input 0 RMS | Render 0 / 1 RMS | 实际选取时长（Input / Render，按样本数） |
| --- | ---: | ---: | --- |
| quiet控制窗 | 0.000097549 | 0 / 0 | 约2.016188 / 2.000499秒 |
| play请求后前2秒 | 0.173036764 | 0.059122427 / 0.059122427 | 约2.000021 / 2.000023秒 |
| play请求后2–8秒 | 0.190411842 | 0.063552143 / 0.063552143 | 约6.000021 / 6.000045秒 |
| planned tail后名义3秒 | 0.040745526 | 0.007865668 / 0.007865668 | 约2.964021 / 2.989773秒，非完整窗 |

少量超过名义2/6秒的样本数来自各buffer hostTime步进与名义sample rate及取整的关系，不是声学超时测量。Input host步进相对名义100ms残差约−3.333µs至0；Render约−10.042µs至+13.625µs，不能将这些残差自行解释成丢帧。

固定方法取原生每buffer的约100ms RMS，仅在线性插值后的包络层按同hostTime中心对齐；129对包络相关约0.755942。没有对音频重采样、搜索有利lag或改变声道。该结果与播放期Input幅度明显升高共同支持信号随数字播放变化的描述，**不证明Input内容可听辨、唯一USB来源、真人身份或AEC能力**。Render双声道相同，不作为两路独立证据，不加总成双倍能量。

## 7. 技术、工程、证据裁定

| 审核维度 | 本轮结论 |
| --- | --- |
| TECHNICAL_REVIEW | OFF配置与路由实测一致，原生Input/Render均有合法PCM；仅观察OFF，不评价Apple AEC效果。USB唯一物理来源、声学真值及精确源frame→Render映射继续UNVERIFIED |
| ENGINEERING_REVIEW | ENGINE_CONFIG_RECORDER_OBSERVED_VALID；完整协议ENGINEERING_VALID未授予，窗口覆盖/实际tail边界证据尚不足。原始程序INVALID仍0，无已确认记录器丢失或数值破坏 |
| EVIDENCE_REVIEW | 容器/连续PCM/权限与固定输入身份证据有效；整体EVIDENCE_VALID未授予，记EVIDENCE_UNVERIFIED。现场外放可听辨性VERIFIED_BY_USER；完整CONTENT_UNVERIFIED（未逐字核验、未独立试听Input） |
| 总体 | VP-A_BLOCKED / BLOCKED_FOR_NEXT_ARM；保留本次合法原生证据，不重试、不修改程序或实验参数 |

停止原因是完整窗口与尾响判读不足，不是Apple AEC失败。本轮没有VP_ON，不存在可解释为AEC净增益的对照差值。后续须由主控审核现有证据及最小时间/覆盖问题；本节点不开发修复，不通过重新录音凑结果。

## 8. 证据安全与Stage7边界

私人Input/Render容器、receipt、prepared/manifest、原始诊断及离线分析均仅留Git之外私有目录；运行目录0700、文件当前用户所有/0600、非symlink。登记、素材身份和私人路径不进入本报告或Git。原素材、原登记、固定可执行文件运行后身份均未变。

本次独立verify及离线分析只读取本次授权PCM；P4历史仅用登记关联元数据，不读历史私人PCM、原ACE3录音或SSD/quarantine。程序、物理设备及冻结报告均未修改。

Stage7 Forbidden Checklist：**PASS**。

- 触碰红线：无；仅新增本报告，未改代码。
- Runtime API、DR schema/fixture、Test2、generation、Qwen全双工、NativeSpeechProvider/Adapter、正式音频协议、Runtime授权：均未改。
- Provider、HAL VAD/Gate、AEC3、正式声源资格、正式中断、取消/clear：均未接入或触发；工具恒为sourceQualificationGranted=false，这不等于正式纯回声零误授予已通过。
- 未新增平台target，未进入Stage8、VP_ON或VP-B/C/D/E；监听仅在本次已授权独立进程生命周期内。
- 没有重新登记、改系统设置、重签程序、重试、绕过设备/配置守卫或改变已批准音频图。

```text
VP_OFF = REVIEW_PENDING
VP_OFF overall protocol = BLOCKED / EVIDENCE_UNVERIFIED
VP_ON = NOT_AUTHORIZED
Apple AEC = NOT_MEASURED
USB unique physical source = UNVERIFIED
Test3 = BLOCKED
Test3.execution_authorized = false
```

本轮唯一授权调用已结束。提交脱敏报告后停止，等待主控独立审核。

## 9. VP-A_OFF_EVIDENCE_RECHECK：原始时间域复审（追加）

本节追加于2026-10-15，保留第1–8节及原始结论不变。审核开始时分支、HEAD、upstream和实时远端与用户指定基线一致，工作区干净。本节点只读本次VP_OFF容器、prepared/manifest和原离线分析记录，以及直接相关的Tap/时间/封存代码；没有录音、播放、权限/路由操作、VP_ON或源码/参数修改。

### 9.1 原始身份、连续性与两种时钟

重新按原生容器布局核对全部260条记录。Input仍为48kHz/mono、130块×4800frames，sampleTime为[0,624000)；Render为44.1kHz/stereo、130块×4410frames，sampleTime为[0,573300)。两流全部sampleTime/hostTime有效，流内后续sampleTime严格等于前块sampleTime+frameCount；各首块一次continuityUnknown，其后无断样。只读verify再次通过。容器、原始JSON及旧分析脚本/结果在复核前后逐字节身份一致，没有补帧、改PCM或重算覆盖原结果。

本机Apple SDK的 `AVAudioTime.h` 将hostTime定义为mach_absolute_time表示，sampleTime为特定sampleRate下的设备样本位置。`NativePCMTap.install` 原样记录两个时间值及有效位；callback进入tick另来自 `vp_recorder_now_tick()`，C实现使用mach_continuous_time。两流sampleTime都从0开始**不是同步证据**；它们属于各自48k/44.1k时间线，不能按0对齐，也不能直接拿continuous控制tick减raw hostTime。

原分析在录后取absolute-before、continuous、absolute-after，以中点估算偏移。私有结果保存的单次查询bracket为约0.708333µs，中点在**当次查询**的界约±0.354167µs；这不约束此前录制期间的偏移稳定性，也不包含睡眠/时钟域关系、硬件/转换延迟或声学误差。没有录前/录中配对证据，所以第5–6节的跨域窗口归属继续是条件性描述，不能将其误差宣称为整段仅±0.354µs。本次没有通过再取一个新的录后偏移来修补历史。

### 9.2 同一hostTime域的直接复算

以首条Render的raw hostTime为共同零点。逐块采用 `buffer.hostTime + frameOffset / nativeSampleRate`，只用Mach tick单位换算和原生格式作有理数计算，不经过continuous偏移，也不以全局sampleTime假定两流同步。原记录没有独立保存AVAudioTime.sampleRate，因此块内及末块终点插值依据保存的native ASBD；不是ADC/扬声器实际时刻。

逐声道检查精确非零样本（`sample != 0`），没有幅度阈值、降噪、裁剪或选择有利声道。两路Render逐位相同，首个非零frame为93148，最后非零frame为443202（含），结束边界为443203（不含）。最后非零位于从0编号的第100块，该块sampleTime=441000，块内frame=2202。其样本宽度约22.675737µs；必须区分最后样本起点和结束边界。

| 原生内容事件 | 相对首条Render hostTime的秒数 |
| --- | ---: |
| Input首块起点 | −0.025770375 |
| Render首块起点 | 0 |
| Render首个非零样本起点 | 2.112180963 |
| Render最后非零样本起点 | 10.049862098 |
| Render最后非零样本结束边界 | 10.049884774 |
| Input末块名义内容终点 | 12.974145208 |
| Render末块名义内容终点 | 12.999906375 |

因此，在同一数字内容hostTime域中，最后非零Render**结束边界**之后仅保留Input约2.924260435秒、Render约2.950021601秒，距3秒分别约差75.739565ms、49.978399ms。该相对结果不依赖录后continuous偏移；两个流的hostTime起点相差约25.770375ms，不能忽略。

这只是数字播放活动之后的记录覆盖，不是扬声器真正停止或声学尾响时间。它不取代原预登记planned-tail起点、不构造新评分窗口，也不将末尾零样本裁掉。第5节相对“planned-tail+3秒”的条件性短缺约35.989/10.228ms，与这里相对“最后非零样本结束+3秒”的75.740/49.978ms参照不同，不能混用或说成历史算术错误。没有把任何小缺口自动视为可忽略。

### 9.3 原协议各窗口的判定

| 要求 | 本次复核判定 |
| --- | --- |
| 启动核验后静默2秒 | 原控制流2.016183秒已确认。共同hostTime中，首个非零Render前有约2.112181秒已记录数字静默，Input从其首样本到该点约2.137951秒；支持有安静前段，但不替代原quiet控制窗两边界的跨域配对，也不证明环境绝对静音 |
| 固定8秒居民播放 | 原素材身份/128000frames、控制等待8.009659秒、Render非零活动和用户实际听到的确认保留。已记录区间包含全部已观察非零Render；非零范围不等于完整8秒buffer的精确源frame映射，后者仍未独立建立 |
| 计划尾窗3秒及完整采样覆盖 | 3.013232秒控制等待成立；原控制窗完整PCM对齐仍未确证。共同hostTime又显示，连最后已见数字非零样本结束后的3秒内容也未完整保留，不能声称完整数字播放后尾窗或完整声学尾响 |

没有选择新的有利评分段，没有把原3秒缩为约2.9秒。整体协议窗口仍不能获证，保持BLOCKED。

### 9.4 缺失、批量边界、控制误差与证据不足

- **已保存PCM内部丢帧：未发现。** C记录器对流内sampleTime跳变设置DISCONTINUITY；本次后续跳变0、lost/overflow/pending/INVALID均0，封存校验通过。不能将覆盖不足追改为原记录器丢失或INVALID。
- **未取得的末端覆盖：存在明确限制。** 实际每块约100ms，虽Tap请求bufferSize=1024，保存的实际块为4800/4410frames。原流程按控制等待结束后stop/removeTap；seal只等待已进入的callback和writer，不会取得Engine内部尚未交付的部分块。整块交付终止边界与所见现象相容，但具体Apple内部机制只是HYPOTHESIS，不能直接认定“正常”或确定实现Bug。
- **控制与内容边界不同：已确认。** 2/8/3控制等待有少量超出，play请求不是数字起播完成证明；原计划tail开始后仍有Render非零活动。请求到信号的差值还可能包含源自然静默、转换和缓冲，不能全部称为调度延迟。
- **跨域与物理真值：仍不足。** 每块hostTime相对名义100ms步进仅有微秒级差异，不是整段跨时钟映射的误差上界；也不证明硬件/声学时延。当前同域复算已避开共同偏移，但不能补出未录制数据或提供扬声器声压真值。

### 9.5 最小修正建议（仅建议，未实现、未授权实验）

1. **需要补足末端采集证据。** 在独立VP-A控制路径中，保留原2/8/3评分定义，另外提出有界的末端采集余量，供主控批准；继续受原16秒admission、64MiB/8MiB限制。余量只用于取得末块，不改变声音、计分窗或安全门槛。不能从本轮约100ms块长或最大回调间隔直接发明“再等100/200ms必过”的标准；仍须离线核对两路实际内容终点，达不到则BLOCKED，不自动重试。
2. **需要记录跨时钟配对。** 在有限的控制阶段边界增加bracketed absolute/continuous配对及不确定度，至少覆盖录前和停止前后；保留原始时间，遇配对关系变化或不充分就标UNVERIFIED。只做少量控制元数据，不把IO、字符串、锁或分析加到实时callback，不重写Tap/C recorder。
3. **分列计划tail与数字播放完成证据。** 后续实现/协议审核需明确评分目标是原planned-tail窗，还是另有数字播放完成后的观察要求；两个概念不能静默替换。若要证明后者，须有可复查的数字终点及足够的后续采样；任何player完成状态仍不是实际扬声器声压或声学终点。当前不得回溯选择新窗口恢复PASS。

TECHNICAL_REVIEW：同域原始时间复算成立，最后Render非零样本边界已逐声道确认；精确声学时刻和源frame映射仍UNVERIFIED。ENGINEERING_REVIEW：原配置/生命周期/记录器观察子项保持；整协议窗口未获证，批量边界原因未定，不认定AEC或C记录器故障。EVIDENCE_REVIEW：新增不依赖continuous映射的数字后窗不足证据，保持 **VP-A_BLOCKED / EVIDENCE_UNVERIFIED**。

Stage7 Forbidden Checklist：PASS；仅追加本节，无源码/参数/音频图/历史结论修改，无新设备操作，无VP_ON或下一阶段。此节点为文档和只读证据复审，应用构建/单元测试NOT_RUN；验证采用原始字段、同域算术、容器只读verify、原文件身份保护、追加范围及隐私检查。提交后停止，等待主控审核。


## 10. 后续VP-A_TIMING_FIX_PREPARATION说明（PROPOSED，未补跑）

本节追加于2026-10-15，第1–9节及其历史数据、归因和BLOCKED结论保持原样。主控仅批准在独立VP-A中准备定点工程修订，起点为 `f6a29a1fad10603bf77abcb33ad315a75ea89f65`。候选实现及完整协议见[07报告第14节](07_vpa_preparation.md#14-vp-a_timing_fix_preparationproposed定点时序修订)，仍待主控独立复审。

**PROPOSED修订**：保留原2秒静默、8秒播放、3秒计划尾窗，在其后另加固定0.5秒非评分post-roll。16秒arm起总预算、64MiB PCM/8MiB诊断缓冲不变，不根据结果延长；不足即BLOCKED。四次有界absolute-before/continuous/absolute-after配对位于start前、播放请求附近、planned-tail附近及正常stop前，保存raw、timebase和局部偏移区间/不确定度。配对异常、观察到偏移区间变化或总预算超限走原INVALID/stop/seal路径；原始失败不被覆盖。早期失败保留部分配对，不在清理中补采掩盖原因。

该准备并未取得新的PCM、时钟或声学证据；局部配对相交也不能证明全程偏移恒定。新增0.5秒不能补回历史末端数据，不能把本次已记录约2.924/2.950秒数字非零结束后覆盖改写成3秒，也不能证明未来一定完整。下一次获准运行仍须分别核对原评分窗、数字非零终点、实际两路采样及物理真值限制，不能静默重选窗口或把控制完成标记当作PCM覆盖PASS。

完整非设备 `check.sh` 通过：原207项未改，新24项，共231项（Core 134、Audio 97），Debug/Release、SwiftLint 0 error/0 warning、Swift Format strict、C11、独立性与默认拒绝设备路径检查均通过。覆盖窗口/预算、时钟异常及漂移线索、INVALID后停止、一次stop/seal和旧模式隔离。配对后的最终预算检查也覆盖局部配对合规但总16.1秒失败的情况；检查至真实stop的调度/阻塞API仍DEVICE_UNVERIFIED，没有声学/真实线程PASS。

TECHNICAL_REVIEW：PASS（定点候选实现），历史时钟/声学证据限制保留。ENGINEERING_REVIEW：PASS（非设备检查与源码复核），实际0.5秒末块交付和设备生命周期未测。EVIDENCE_REVIEW：PROPOSED诊断准备，历史 **VP-A_BLOCKED / EVIDENCE_UNVERIFIED** 不变。该新构建未来须重新固定实际二进制/签名身份，不能复用旧运行的程序身份。

Stage7 Forbidden Checklist：PASS；本轮只改独立VP-A控制/测试及07，08只追加本节；Driver、Tap、C Recorder、音频图、record/source-probe、正式App、Qwen/Runtime/Test2/ACE3、正式Test3合同均未改。无新录音/外放/Engine/权限或私有资产访问，未进入VP_ON或VP-B/C/D/E。

```text
VP-A timing revision = PROPOSED_REVIEW_PENDING
VP-A_DEVICE_NOT_RUN (本节点)
VP_OFF = BLOCKED
VP_ON = NOT_AUTHORIZED
Apple AEC = NOT_MEASURED
Test3 = BLOCKED
execution_authorized = false
```

仅提交准备修订；完成后停止，等待主控复审及独立现场授权。
