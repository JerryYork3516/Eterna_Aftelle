# Test3 · VP-0-P3 输入来源验证工程 · v1

本报告对应 `Apple-Voice-Progress-v1` 分支、基线 `880b144549c762b5091a2140c8dd55447b834e47`。本节点仅实现独立工具的受控研究入口和非设备验证；未启动音频引擎、麦克风、扬声器或权限申请，未读取历史私人 PCM。

裁定：**P3_IMPLEMENTATION_PASS**。设备：**P3_DEVICE_NOT_RUN**。来源：**SOURCE_UNVERIFIED**。

实现 PASS 仅表示本节点授权的构建、源码审核、合成夹具和安全检查通过。它不证明 USB 物理输入来源、Apple AEC 效果或 Test3 PASS，也不解除普通 `record` 的设备守卫。

## 1. 已有事实及 deviceID 判断

下列设备结果引用冻结的 `04_vp0_device_preflight.md`，本节点没有重新测量或读取其私人音频：

| 项目 | 已有证据 | 本节点结论 |
| --- | --- | --- |
| VP_OFF | 7.8 秒连续 Input PCM、156 回调，丢失、溢出、INVALID 为 0，已封存 | 该轮采集事实已确认；不推广至 VP_ON |
| VP_ON 配置 | 双端 VP enabled，接图后客户端格式 16kHz、3 声道 | 配置事实已确认；声道物理角色未确认 |
| VP_ON deviceID | 两个 getter 均呈现 Built-in 输出身份；默认输入为 USB | getter 呈现已确认；不能由此证明输入错误或实际 USB 来源 |
| VP_ON 运行 | 普通设备守卫拒绝启动 | 该轮没有运行输入证据；Apple AEC 能力仍 NOT_MEASURED |

`AUAudioUnit.deviceID` 是 I/O unit 硬件设备标识接口。本次找到的公开契约没有保证：VPIO 下 inputNode 的该 getter 必须单独呈现真实物理输入设备。两个值相同也不足以证明两个 node 是同一 Audio Unit 对象，或真实输入来自 Built-in。

普通 `AudioRouteSnapshot.hasVerifiedBinding` 是保守的证据准入条件。其拒绝表示当前证据不足以接受普通采集，不应被解释为物理输入已被证伪。P3 保留该守卫，只对另一个明确标为来源未知的诊断入口建立准入规则。

| 技术命题 | 证据等级 | 依据与边界 |
| --- | --- | --- |
| AVAudioEngine 的 macOS I/O node 一般使用系统默认输入/输出 | CONFIRMED | 官方节点契约；不能单独证实特定 VP_ON 运行的物理输入 |
| VP 是双端处理，模式配置必须在 engine 停止时进行 | CONFIRMED | AVAudioIONode SDK 与 WWDC19；现有配置代码不变 |
| 两个 deviceID 相同必然代表输入错误 | HYPOTHESIS，缺乏支持 | 当前呈现也可能来自 VPIO 的内部设备关系；不作为结论 |
| 默认 USB 加上 VP enabled 即证明实际 USB 来源 | DEVICE_UNVERIFIED | 只是前置配置证据，缺少独立来源证明 |
| 当前 3 声道等于“麦克风 + 两个参考声道” | DEVICE_UNVERIFIED | 未找到适用于该 Mac/USB 路径的角色契约；禁止采用该映射 |
| Aggregate 的 Main 子设备就是全部输入来源 | 不成立的推断 | Main/clock 与有序物理 stream 成员是不同属性；沿用既有成员证据，不改 getter |

## 2. Apple 官方 API 与本机 SDK 依据

本次只审查公开 API 和本机 SDK，不尝试更换 `CurrentDevice` scope/element，不使用私有 API，也不执行设备操作。

| 资料 | 支持的结论 | 不支持的结论 |
| --- | --- | --- |
| [AVAudioIONode](https://developer.apple.com/documentation/avfaudio/avaudioionode)，SDK `AVAudioIONode.h` 103–104、155–186 | 默认设备语义；停止时配置 VP；VP 客户端输入/输出格式约束；客户端与硬件格式不同层 | 特定 VP_ON 的 USB 物理来源及 3 声道角色 |
| [AUAudioUnit.deviceID](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/deviceid)，SDK `AUAudioUnit.h` 1271–1283 | I/O unit 使用的硬件 device 标识 | VPIO 下该值必然是独立物理输入设备标识 |
| [WWDC19: What's New in AVAudioEngine](https://developer.apple.com/videos/play/wwdc2019/510/) | 在真实 I/O engine 中启用 VP；双端关系及停止状态配置 | 本机 USB/Built-in 组合的输入来源保证 |
| SDK `AUComponent.h` 290–296 | Voice Processing I/O 的 duplex bus 0 输出、bus 1 输入 | 特定客户端声道的声学来源映射 |
| [kAudioOutputUnitProperty_CurrentDevice](https://developer.apple.com/documentation/audiotoolbox/kaudiooutputunitproperty_currentdevice)，SDK `AudioUnitProperties.h` 2426–2431、2448–2454 | CurrentDevice 的 Global 属性；EnableIO 有自身 input/bus 规则 | 将 EnableIO 的 scope/element 规则移用于 CurrentDevice |
| [Aggregate FullSubDeviceList](https://developer.apple.com/documentation/coreaudio/kaudioaggregatedevicepropertyfullsubdevicelist)，SDK `AudioHardware.h` 474–477、1650–1667 | 默认设备属性；Full/Active 成员及其顺序，可与物理 stream 方向一起审查 | 单凭 aggregate/Main/default ID 排除所有替代输入来源 |

Apple 开发者论坛的类似呈现仅是线索，不作为官方保证。iOS 的 VP 示例也不证明 macOS 当前三声道布局。来源确认仍需独立、可复查的物理证据或适用于同一运行实例的官方路由依据。

## 3. 研究入口与普通 record 的隔离

新增命令 `source-probe`，不改变普通 `record` 的 session、设备守卫、播放器或配置路径。

必须同时提供 `--enable-audio`、`--arm-diagnostics`、`--authorize-source-probe` 和私有 `--probe-registration`。任何缺项在解析/请求验证时拒绝，尚未读取权限或创建 engine。探针仅接受 VP_ON、恰好 8 秒、无播放素材；普通 `record` 不接受探针参数。

运行前依次核对：

1. 请求与输出目录条件合法，研究授权显式成立。
2. 麦克风已 authorized；探针不会申请权限。
3. 私有登记文件合法、目标身份明确。
4. 默认输入与登记的目标 USB 相符，默认输出与登记的 Built-in 相符；读取前后无已知默认路由变化。
5. 使用原有停止状态 VP 配置流程，双端 enabled、bypass=false、输入不 mute、客户端格式及硬件格式符合原有契约。
6. 接图后的默认路由与配置前登记快照一致。
7. 普通绑定证据成立，或仅出现已知的“双 node 均呈现登记 Built-in 输出、无 aggregate 对象”的未知来源呈现。第三设备、虚拟/不支持路由及其他未知 aggregate 呈现拒绝。

第 7 条只是独立诊断准入，不授予声源资格。即使普通绑定条件成立，探针结果也保持 `SOURCE_UNVERIFIED`；没有从 default/deviceID 自动生成 CONFIRMED 的路径。

探针使用同一 AVAudioEngine 的原有 input tap 和 mixer render tap，保留原生格式及所有声道。player 节点保持静默，不调度素材，不调用 `play()`。麦克风不回接扬声器；不叠加 AEC3、HAL VAD、Host/Gate、Qwen、Runtime 或 Provider。

## 4. 修改文件与关键函数

以下位置使用仓库相对路径，均在独立工具范围；本节点另新增本报告。原有测试文件保持字节不变。

| 文件 | 函数/位置 | 作用 |
| --- | --- | --- |
| `Sources/VPReferenceAudio/SourceProbe.swift` | `run` :11、`readDefaults` :56、`capture` :75、`invalidateOnFailure` :111、`window` :118、`observe` :150、`finish` :185 | 单次研究流程，失效、停止与封存；直接用于实际命令 |
| `Sources/VPReferenceAudio/SourceProbeRoutePolicy.swift` | `validateEngineState` :5、`validate` :11 | 诊断准入及实际 running/stopped 检查 |
| `Sources/VPReferenceAudio/SourceProbeRegistrationFile.swift` | `load` :9 | 有界、只读私有登记加载 |
| `Sources/VPReferenceAudio/SourceProbeEvidence.swift` | 固定来源字段与有界 cue 记录 | unknown 来源、无资格、无角色猜测及运行/停止状态 |
| `Sources/VPReferenceCore/SourceProbeRequest.swift` | `validate` :15 | 显式研究授权、VP_ON、无素材、恰好 8 秒 |
| `Sources/VPReferenceCore/SourceProbeRegistration.swift` | `validate` :17、`validateDefaults` :26 | 目标匿名身份和刺激协议一致性 |
| `Sources/VPReferenceCore/SourceProbeWindow.swift` | `capture` :12、`run` :25 | 实际生命周期包装、5 个提示、有限控制循环及失约拒绝 |
| `Sources/VPReferenceCore/CommandLinePlan.swift` | `parse`、`audioCommand`、`parseOptions` | 独立参数分派；不向 record 开放探针参数 |
| `Sources/VPReferenceAudio/ReferenceTool.swift` | help 与 `.sourceProbe` 分支 | 唯一探针入口；控制台仅输出脱敏状态/计数 |
| `Sources/VPReferenceAudio/RecorderOwner.swift` | `init(configuration:maximumSeconds:)` | 探针给 C recorder 的时间上限为 8；普通默认仍为 60 |
| `Sources/VPReferenceAudio/AudioRunManifest.swift` | 可选 `source_probe`；探针时钟/快照描述 | 原有 PCM/时间容器不变；普通默认文本不变 |
| `Sources/VPReferenceCore/EngineeringDiagnostic.swift` | ENGINE_STOP 及三个 PROBE 错误码 | 运行状态、时钟与刺激窗口失约诊断 |
| `README.md`、`check.sh`、`check_sources.py` | 协议与非设备检查 | 研究使用条件、默认关闭和源码隔离检查 |

新增测试文件：`SourceProbeCommandTests`、`SourceProbeRegistrationTests`、`SourceProbeWindowTests`、`SourceProbeEvidenceTests`、`SourceProbeRouteTests`、`SourceProbeRegistrationFileTests`、`SourceProbeLifecycleTests`，以及仅含合成数据的 `SourceProbeFixture`。

未修改：`VP0AudioSession`、`AppleEngineDriver`、`NativePCMTap`、`VPRecorder.c`/header、普通 route/configuration plan、03/04 历史报告。

## 5. 原生 PCM、时间和来源等级

所有 Input 原生声道由原有 recorder 保存，原始 sampleTime/hostTime 有效位、callback tick、样本数量/连续性、格式及封存规则不变。没有 channel 0 选择、mono 下混、声道角色分配、能量最大声道归属或在线语音分析。

新增 `source_probe` 固定记录 `SOURCE_UNVERIFIED`、`sourceQualificationGranted=false`、声道角色 `DEVICE_UNVERIFIED`、登记文件 SHA256、配置前默认设备快照、5 个控制提示时刻及 engine 运行/停止观测。设备匿名身份及登记内容只进入本地私有证据，不进入公开报告或 Git。

若已写入 Input 帧，仅标 `INPUT_PCM_PRESENT`；静默也可以是合法 PCM。该标志不证明内容、完整 8 秒覆盖、真人活动或物理来源。封存统计仍须单独检查每声道/每流有效帧、采样率、连续区间、失效终态和实际 PCM 覆盖。

| 等级 | 所需证据 | 本实现是否自动生成 |
| --- | --- | --- |
| INPUT_PCM_PRESENT | 原生 Input 实际写入帧；仍须审查完整性 | 仅依据计数记录观察 |
| INPUT_RESPONDS_TO_STIMULUS | 封存有效后，逐声道内容/顺序与已登记刺激、安静区间可复查对应 | 否；后续离线审核 |
| USB_SOURCE_SUPPORTED | 响应证据、稳定目标 USB 默认路由、无软件注入及独立现场采集上下文 | 否；人工证据裁定，不能排除全部替代来源 |
| USB_SOURCE_CONFIRMED | 独立且可重复的同实例官方路由或物理证据，能排除替代输入来源 | 否；单次讲话响应本身不充分 |
| SOURCE_UNVERIFIED | 来源证明不充分，或尚未运行设备 | 固定默认及终态来源 |

Render 是数字 mixer 输出，可能包含合法静默，不是扬声器声压；探针无居民素材，不要求 Render 非空。VP_OFF 不称为 ADC 原始真值。跨轮 PCM 不能直接相减作为来源或 AEC 净效果。

## 6. 实时安全、预算和故障处理

不改 Tap callback/C recorder。callback 不增加 IO、JSON、字符串、网络、等待锁、复杂分析或无界任务。登记解码、SHA、HAL/格式读取、控制提示和 manifest 写入均在非实时控制路径。

普通 recorder 的 60 秒、64MiB PCM、8MiB 诊断 resident 上限不变；探针传入更严格的 **8 秒 admission 上限**。时间原点在 prepare/start 前 arm，启动开销属于这 8 秒，因此不得声称获得完整 8 秒 PCM。控制窗口使用单调时钟、最多 162 次迭代及至多 5 个提示；HAL 查询或调度阻塞不能靠测试证明绝对 OS 停止时刻，真实开销仍 DEVICE_UNVERIFIED。

每次控制检查重读路由、VP/格式、硬件输出和 `isRunning`；不重新配置、不重启、不改变系统音量、增益或 Mic Mode。已知配置通知、状态/格式/路由错误、时钟失约或 recorder INVALID 立即终止研究路径。启动/窗口异常先 invalidate C admission，再执行统一 listener removal、stop/removeTap，保留原始诊断。

R2 observer 仍在 start 前注册，退出一次移除。实际窗口使用原有 `PlaybackLifecycle`，`play` 闭包为空。清理一次，随后一次 seal；原有 lost/overflow/contention/discarded/pending/write/seal 检查保留。封存不完整、不含合法 Input 或写入失败不得成为有效实验；次级 seal/write 失败不覆盖原始原因。

登记文件必须在 Git 之外：当前用户拥有的 0700 父目录、0600 普通 JSON 文件、非 symlink，最大 4096 字节。字段为 schemaVersion=1、两个不同的 64 位匿名 SHA256 身份和 `QUIET_TWO_PHRASES_V1`。它用于预先限定目标，不是新来源真值。使用已有合法私有登记或在另外授权的准备阶段获得目标身份；不得临场把任何默认设备自动登记为目标。

所有新测试只使用临时合成 PCM/匿名夹具；实际私人素材、设备 UID、原始设备日志或私人路径未加入 Git。

## 7. 非设备回归结果

本节点最终运行独立工具的 `check.sh`，退出 0。

| 检查 | 结果 |
| --- | --- |
| 原有测试 | 116/116 保留且通过，原测试文件字节不变 |
| 新增 Core 测试 | 22/22：命令 10、登记 5、窗口 7 |
| 新增 Audio 测试 | 22/22：证据 6、路由/状态 5、登记文件 6、生命周期 5 |
| 总测试 | **160/160，0 failures**；Core 102、Audio 58 |
| Debug / Release | 均成功，warnings-as-errors |
| SwiftLint | strict；0 error、0 warning，无新增规则豁免 |
| Swift Format | strict 通过 |
| C11 | `-Wall -Wextra -Werror -fsyntax-only` 通过 |
| 静态隔离/默认关闭 | 通过；无参数仅 help，缺授权的探针被 parser 拒绝 |

新增测试覆盖：record 拒绝研究参数；缺显式研究授权/音频 flags/登记拒绝；ON/8 秒/无素材约束；登记设备和 transport 矛盾拒绝；running/stopped 异常拒绝；来源未知永不升格；真实 C recorder 三声道 metadata/payload 原样封存；8 秒 admission 及普通 60 秒不退化；INVALID/写入失败/无 Input 终态；实际使用的生命周期、真实 NotificationCenter observer、失败前关 admission、一次 stop/seal、owner 释放。

控制时钟回退、冻结、超过上限、观察开销后的提示时刻和跳过整个刺激窗口均有确定性测试。不能及时呈现某个区间时标失约，不补发一串提示制造有效刺激。

新增生命期测试调用实际 `SourceProbeWindow.capture`、`SourceProbe.invalidateOnFailure` 和 `SourceProbe.finish`，同时使用真实 C recorder；没有创建 AVAudioEngine 或查询真实 TCC。构建和合成成功不等于 Apple 运行行为成功。

`check.sh` 的 CLI 检查仅执行无参数或故意缺必要参数的负向命令；均在分派前拒绝，没有执行合法 record/inspect-route/request-microphone/source-probe 设备动作。真实设备并发、回调负载、HAL 延迟、8 秒停机表现和异步 Apple 行为仍 NOT_MEASURED。

## 8. 后续受控一次设备协议（未执行）

必须先经主控独立源码审核，再获得用户**本节点另外明确的现场录音授权**。此前 P1 权限/预检授权不自动授权 P3 讲话采集。

使用现有目标 USB 麦克风和 Built-in 输出，保持位置、系统音量/增益/Mic Mode，不拔插或制造设备变化。关闭其他采集程序；确认安静环境、预登记目标身份、私有目录、单一已审核可执行版本与签名。仅一次 VP_ON、最长 8 秒、无居民素材、不接 Qwen/Runtime，不进入 A/B/C，不重试。

| arm 相对计划区间 | 用户刺激 |
| --- | --- |
| 0–2 秒 | 安静 |
| 2–3.3 秒 | “苹果测试，一二三” |
| 3.3–4 秒 | 安静 |
| 4–5.5 秒 | “现在确认，蓝色七” |
| 5.5–8 秒 | 安静 |

终端仅给视觉提示。提示时间是控制时钟记录，不是声学到达、用户实际起音或录音绝对时延。启动/调度过慢而错过任何完整阶段时 INVALID；现场未遵循刺激也不能算有效来源试验。实际 PCM 覆盖、用户刺激执行记录与时间不确定度需要单独审查。

获得授权后的调用形式（本节点未执行）：

```text
source-probe --authorize-source-probe --probe-registration <private-json>
  --enable-audio --arm-diagnostics --mode VP_ON --duration 8
  --study-id <non-private-alias> --output-dir <new-private-directory-outside-Git>
```

封存通过后才允许针对该新授权证据离线逐声道分析：有效帧、安静/刺激区间、起尾音、语句对应和通道相似性。保留所有通道，不选最大能量声道代表 USB。不确定到达时间就不报告绝对到达时延。独立现场上下文与路由依据应分别列出；若不能排除替代来源，保持 SOURCE_UNVERIFIED，最多支持性结论，不能 DEVICE_GO。

## 9. 三维审核及 GO / NO-GO

| 维度 | 裁定 | 限定范围 |
| --- | --- | --- |
| TECHNICAL_REVIEW | LIMITED_PASS | 独立未知来源探针及公开 API 使用成立；真实 USB 来源和声道角色 DEVICE_UNVERIFIED |
| ENGINEERING_REVIEW | PASS | 授权、路由准入、运行状态、有限窗口、原 recorder/生命周期和离线测试通过；实机语义待测 |
| EVIDENCE_REVIEW | P3_DEVICE_NOT_RUN | 本轮仅构建/静态/合成证据；未得到新的真实设备或声音来源证据 |

实现交付可提交：授权范围内源代码、报告、全部非设备回归与隐私审查通过。后续设备启动仍 NO-GO，直到主控审核及新现场授权成立。

任何权限、已知路由、配置通知、VP 状态、格式、engine 生命周期、容量/时钟、丢失/overflow/contention、写入或封存异常均立即停止，保存 INVALID；不清除通知，不选有利 getter，不重启或修改守卫来取得 PASS。

剩余未知项：HAL 多次属性读取非原子；通知与控制观察之间存在异步 TOCTOU；真实启动通知、Tap 停止及晚到 callback 语义；频繁控制查询开销；C recorder 真实设备并发负载；3 声道物理角色；VPIO inputNode 的唯一 USB 来源。本轮不声称消除这些异步或物理未知项。

若一次研究采集仅证明 Input 有信号，不能继续声学性能实验。最小下一步是审核其全声道响应与独立来源证据；不足则保持阻塞，向主控提出所缺依据，不自动新增设备实验或架构。

## 10. 独立性、Stage 7 与冻结检查

**Stage 7 越界检查：PASS。** 全部改动仅在独立工具和本新增报告。原有 116 项测试、普通 record session、AppleEngineDriver、NativePCMTap、C recorder、route/configuration plan 及 03/04 历史报告保持不变。PCM 容器/时间 schema 和 60 秒/64MiB/8MiB 普通限制不变，探针增加 8 秒更严格准入。

未修改或接入：Aftelle App、Test2、Qwen Realtime 原生全双工主链、NativeSpeechProvider/Adapter、实时协议、RuntimeCore/正式授权/generation、DR/Studio/Session/Memory、ACE3 冻结成果、正式 Test3 合同。探针不生成 sourceAttributionConfirmed、用户轮次、Provider 请求或中断/播放取消，没有权限使正式 Runtime 接受声源资格。

未访问原 ACE3 工作区、SSD/quarantine 或历史私人 PCM；没有运行设备、权限申请、声学刺激、HIL 或 A/B/C/D/E。

最终保持：

```text
Apple VP-0 Engineering Baseline = FROZEN
VP-0-P3 = REVIEW_PENDING
VP-0 Device Preflight = BLOCKED
VP-A/B/C = NOT_AUTHORIZED
VP-D/E = BLOCKED
Test3 = BLOCKED
execution_authorized = false
```

提交推送只交付独立研究实现，完成后停止，等待主控独立源码审核。
