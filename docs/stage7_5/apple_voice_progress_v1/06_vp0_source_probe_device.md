# Test3 · VP-0-P4 单次真实输入来源验证 · v1

本节点在 `Apple-Voice-Progress-v1`、基线 `6b48c36535aa6a04592e253668d27b5ea66c8b57` 上执行唯一一次授权的 VP_ON `source-probe`。没有修改独立工具或生产代码，没有进行录音重试、居民播放或 Test A/B/C。

最终裁定：**P4_DEVICE_BLOCKED（用户提示及刺激协议环节）**；来源：**P4_SOURCE_UNVERIFIED**。

**INPUT_PCM_PRESENT 成立。** Engine 启停、连续 7.8 秒 Input、全声道保存和封存获得真实证据；但用户反馈未收到任何提示，指定语句的现场执行与录音内容对应性未确认。因此本次不能建立 INPUT_RESPONDS_TO_STIMULUS、USB_SOURCE_SUPPORTED 或 USB_SOURCE_CONFIRMED。

上述 BLOCKED 不等于麦克风硬件、Apple AEC 或 VP 算法失败。recorder INVALID=0 与来源实验 BLOCKED 分别描述记录完整性和实验协议。

## 1. Git 基线及固定程序身份

开始时分支、HEAD、upstream符合预期，工作区干净。非设备准备阶段已运行现有 `check.sh`：160项测试全部通过（Core102、Audio58），Debug/Release、SwiftLint error0/warning0、Swift Format strict和C11检查通过。实现未再修改，固定副本未重建或重签。

| 项目 | 本次使用身份 |
| --- | --- |
| 工具源码基线 | `6b48c36535aa6a04592e253668d27b5ea66c8b57` |
| 固定Release可执行SHA-256 | `7c0021e1f40e38dcac56ccd4668479c1d98c9e0beafd3a181cd00f424dcf9f99` |
| 签名Identifier | `apple-vp-reference` |
| 签名类型 / TeamIdentifier | ad hoc / 未设置 |
| CDHash | `c754f7ef7ab85b7b9792ee2c03aa49ec21284914` |
| 签名与副本核对 | `codesign --verify --strict`通过；固定SHA未变 |
| 启动宿主 | Codex执行工具 → Python subprocess → 同一固定程序 |
| 环境 | 用户指定Mac mini M4；准备阶段观察macOS26.6.2、build25G83 |

软件SHA/CDHash仅标识程序，不是设备身份。实际TCC responsible-code未在本次重新取证，不能用宿主父链代替系统归属证明。

## 2. 权限、既有登记及执行前准备

固定程序的只读 `permission-status` 返回 AUTHORIZED。没有执行 `request-microphone`、触碰TCC或系统隐私设置。

登记来源是用户明确批准的同次历史VP_OFF `manifest.json` 和 `prepared.json`。两份文件同次运行字段一致；prepared及manifest的运行前、运行中、停止后四份路由快照完全一致，目标为USB输入和Built-in输出。历史manifest记录封存VERIFIED、INVALID/丢失/溢出/pending为0。登记准备未读取历史PCM，也未重新登记当前默认设备。

既有 `REGISTRATION_VALID` 私有文件使用 `schemaVersion=1`、两种不同的既有匿名目标身份和 `QUIET_TWO_PHRASES_V1`；文件246字节、0600，父目录0700、非symlink、位于Git之外。本次只验证并使用它，未重写。

准备阶段默认输入USB、1声道、名义16kHz；默认输出Built-in、2声道、名义48kHz。未发现Aftelle主程序。用户在现场授权中确认安静、靠近USB麦克风、其他采集程序已关闭；没有以进程名称扫描证明所有麦克风占用均不存在。运行前私有卷余量约2349MiB。

## 3. 现场授权、提示方式及执行次数

用户同意由明确终端视觉提示改为中文文本提示，并在本次启动前明确回复：**“明确同意，现在执行一次录音及私有分析”**。

仅启动一次 `source-probe`：VP_ON、计划8秒、无material、无居民或其他播放器、无Qwen/Runtime。私有attempt记录在启动前独占创建，attempt=1；没有再调用录音入口。

此前为终端显示准备的只读查看器没有用于本次录音；文本提示按探针实际stdout cue经执行工具实时转发。该转发链没有获得用户端及时显示的证据。

录音后用户反馈：**“没有任何提示和开始以及结束提示音”**。记录为 **USER_REPORTED_NO_PROMPTS**。不能由此推断用户完全没有讲话，或PCM中绝对不存在某句；但现场指定刺激执行状态只能为 **UNCONFIRMED**。本协议未安排开始/结束音频提示，缺少提示音不单独构成音频实现故障。

提示生成、转发与用户可见性必须分别评价。内部cue或工具通知产生，不等于用户实际收到。可能的客户端显示/通知传递原因仍UNVERIFIED，本节点没有通过修改工具、再录一次或补写用户完成记录掩盖问题。

## 4. VP_ON实际配置和路由

| 项目 | 配置后 / 运行中 / 停止后观察 |
| --- | --- |
| input/output VP enabled | 均true |
| bypass / input mute | 均false，AVAILABLE |
| AGC | true，AVAILABLE |
| Input / mixer / output客户端格式 | 16kHz、3声道、Float32 non-interleaved；flags41、32bits、bytesPerFrame4 |
| 接图前客户端暂态 | Input16kHz/3声道；mixer/output44.1kHz/2声道；原有一次接图完成协商 |
| node硬件侧输出格式getter | 配置与运行报告16kHz、2声道 |
| HAL默认设备名义格式 | 目标USB16kHz；目标Built-in48kHz，身份快照稳定 |
| node deviceID呈现 | inputNode和outputNode均匹配登记的Built-in输出 |
| 普通绑定状态 | `UNAVAILABLE`，普通record守卫未改 |
| 研究准入 | 冻结P3独立未知来源规则接受此呈现，仅采集诊断 |
| before/running/post-stop route | 三份完整快照相等；与prepared一致 |
| 默认目标身份 | 每阶段均匹配既有登记USB输入与Built-in输出 |
| Mic Mode getter | preferred/active均STANDARD；该进程属性对本engine归属仍未独立证明 |
| engine状态 | running观测true；post-stop观测false |

node硬件侧格式读数与HAL设备名义采样率是不同观测，本次没有据此宣布物理DAC实际运行于16kHz或系统采样率已改变。VPIO下该getter的具体层次仍DEVICE_UNVERIFIED；未换getter、scope/element或主动改系统配置。

两个node的Built-in呈现未阻止这次独立诊断启动。它与有效Input并存，说明仅由deviceID不能断言“没有输入”；但仍不足以证明输入唯一来自USB，也不能据此确诊普通record存在假性拒收。

## 5. 原生PCM、覆盖和时间连续性

| 项目 | Input | Render |
| --- | ---: | ---: |
| 实际原生格式 | 16kHz / 3声道 / Float32 planar | 同左 |
| records | 78 | 78 |
| frames | 124800 | 124800 |
| 每回调frames | 1600 | 1600 |
| 连续PCM时长 | **7.8秒** | **7.8秒** |
| 原始sampleTime区间 | `[648,125448)` | `[1204,126004)` |
| sampleTime有效记录 | 78/78 | 78/78 |
| hostTime有效记录 | 78/78 | 78/78 |
| 后续sample断样 | 0 | 0 |
| 首记录continuityUnknown | 1 | 1 |
| 首/末callback，arm相对秒 | 0.279250 / 7.959843 | 0.305972 / 7.985855 |
| raw hostTime首末跨度 | 约7.699925秒 | 约7.699924秒 |

原始sampleTime保留，不改成从0开始。每流相邻有效sampleTime恰为上一记录sampleTime加frameCount，区间长度与累计frames一致。每流首条没有前驱，continuityUnknown=1；其余记录连续。原有聚合 `timestampStatus=UNVERIFIED` 保留，不用聚合状态覆盖实际有效位，也不改写时间证据。

8秒从arm起算并包含prepare/start。连续PCM7.8秒不等于完整8秒；程序墙钟耗时 **8.717373459秒** 也不是录音时长。callback tick与arm用continuous时钟计算，hostTime单独计算跨度；没有跨时钟域相减或报告绝对声学到达时延。

## 6. 三声道离线情况及语句对应

仅读取本次授权运行产生的原生证据；未读取任何历史PCM。逐record验证全部3个plane布局，各plane channels=1、bytes=frames×4，按原buffer顺序解析；没有选channel0、下混、丢弃或猜测角色。

| Input声道 | frames | 非零样本 | 精确零比例 | RMS（描述量） | 样本最小 / 最大 | 内容判读 |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| 0 | 124800 | 123918 | 约0.706731% | 0.000357535 | −0.01632658 / 0.01749995 | NOT_VERIFIED |
| 1 | 124800 | 123918 | 同上 | 同上 | 同上 | NOT_VERIFIED |
| 2 | 124800 | 123918 | 同上 | 同上 | 同上 | NOT_VERIFIED |

全部样本有限、无NaN/Inf。三个Input声道的全部Float32样本数值逐点相等，各对相关系数1.0；这是数据重复观察，不代表三个独立麦克风，也不证明“1 mic + 2 reference”等角色。复制原因及物理声道映射仍未知。

三个Render plane各124800样本，全部精确为0，符合本次没有播放素材的数字mixer静默输出；它不是实际扬声器声压。

非零样本、RMS、峰值及通道相关性不能证明语音、指定语句或用户身份。本次没有上传录音、调用转写Provider、部署额外ASR或进行音频重播。两句对应性、真人语音起音/尾音、安静区间的声学判读均 **NOT_VERIFIED**。不将控制cue附近的数据自动标为真人讲话。

## 7. 实际提示时刻及轮询表现

| 内部cue | 计划arm区间起点 | 实际arm相对生成秒 |
| --- | ---: | ---: |
| QUIET_INITIAL | 0 | 0.149388 |
| PHRASE_ONE | 2 | 2.049560 |
| QUIET_BETWEEN | 3.3 | 3.335530 |
| PHRASE_TWO | 4 | 4.056656 |
| QUIET_FINAL | 5.5 | 5.539726 |

程序生成5个cue，没有触发 `PROBE_STIMULUS_WINDOW_MISSED`。这些仅是内部控制时刻，不是用户实际看到的时刻、发声时刻或声学到达时间。用户未收到提示的反馈优先决定现场协议执行证据不足，不能以内部5个cue制造有效刺激。

Input callback间隔最小/中位/最大约 **88.922 / 96.654 / 130.925ms**；Render约 **95.798 / 96.006 / 128.039ms**。记录样本连续，未观察到丢记录；回调间隔波动不直接等于声学时延或PCM缺口。

控制路径计划每50ms查询，实际poll次数、单次HAL耗时、CPU/RSS峰值没有独立计量。无断样不能证明轮询完全没有开销；本节点不添加性能阈值，不把进程正常结束当作性能PASS。

## 8. 配置通知、生命周期及资源

R2冻结路径在start前注册ConfigurationChange监听。没有记录到由通知导致的INVALID或配置/格式失败；当前证据没有独立通知计数/派发时刻，不能宣布系统绝无通知。

实际running=true、post-stop=false，封存成功且子进程退出。按实际使用的冻结控制路径统一移除监听、stop和removeTap，再seal一次；没有重配、重启或清除INVALID。独立的listener/tap注销计数、晚callback完成时刻、设备句柄释放观测仍DEVICE_UNVERIFIED，未启动第二个engine验证重建。

| 诊断项目 | 结果 |
| --- | ---: |
| INVALID / lost / overflow / discarded / pending / suppressed | 全部0 |
| 写入records / PCM bytes | 156 / 2995200 |
| C-owned residentBytes | 4473728，低于8MiB |
| 记录器时间 / PCM上限 | 本探针8秒 / 64MiB |
| control seal / sealed / integrity | true / true / VERIFIED |
| primary / secondary / omitted诊断 | 无 / 空 / 0 |
| 本次源程序stderr | 0字节 |

C-owned存储量不是整个进程RSS。未扩大60秒普通上限、64MiB PCM或8MiB诊断预算，未改任何实时callback。

## 9. 封存与独立完整性核验

冻结工具的正确离线 `verify <private-evidence-directory>` 退出0：container_complete=true、invalid_reasons=0、156 records、2995200 PCM bytes。首次离线调用误传了文件而非目录，退出1；更正调用参数未启动音频，不属于录音重试，也不能将该调用错误当作证据损坏。

独立只读解析再次核对native ABI尺寸、magic/schema/byte order、每record sequence、ASBD、完整plane布局、frame/payload计数、footer快照及seal receipt。文件3056600字节；FNV-1a核对footer前内容及包含footer的receipt均匹配，无额外尾部字节。所有统计与manifest一致。

完整性验证只证明这些字节被完整记录和封存，不证明声音内容或物理来源。FNV不是声学真值或密码学身份认证。私有PCM、receipt、原始命令输出、登记及分析元数据全部留在Git之外，目录0700、文件0600；公开报告不含私人路径、设备UID/匿名摘要或音频片段。

## 10. 来源等级及异常归因

| 等级/问题 | 裁定 |
| --- | --- |
| INPUT_PCM_PRESENT | **成立**：本次真实Input原生帧已完整封存 |
| INPUT_RESPONDS_TO_STIMULUS | 未建立：刺激执行及内容对应未确认 |
| USB_SOURCE_SUPPORTED | 未建立：稳定登记路由存在，缺有效现场语句响应及内容判读 |
| USB_SOURCE_CONFIRMED | 未建立：缺可排除替代输入来源的独立同实例证据 |
| SOURCE_UNVERIFIED | **保持** |
| ENGINEERING_FAILURE | 提示交付/可见性环节按用户反馈阻塞；底层传递原因UNVERIFIED |
| DEVICE_ROUTE_FAILURE | 未观察到已知目标路由变化；VPIO物理来源仍未知 |
| DIAGNOSTIC_FAILURE | recorder无失效，结构完整；未证明全部性能/异步时序 |
| Apple AEC能力 | NOT_MEASURED；没有居民播放，不作消音结论 |

不能把用户未收到提示改写为“用户没有讲话”，也不能把三声道重复改写为错误接线或USB证明。普通record的资格拒绝仍保留；本次没有通过恢复旧Host/Gate、解除sourceAttributionConfirmed或接入Runtime完成来源判断。

## 11. 技术、工程、证据独立审核

离线格式审核者只读冻结C/Tap及相关测试源码，核对ABI和时间合同；结果审核者只读本报告及收到的脱敏配置、计数和用户反馈。两者均未读取私人PCM或操作设备。

| 审核维度 | 裁定 | 边界 |
| --- | --- | --- |
| TECHNICAL_REVIEW | LIMITED_PASS / SOURCE_UNVERIFIED | VP_ON真实启停及PCM成立；USB唯一来源、3声道角色及VPIO硬件侧格式解释未证明 |
| ENGINEERING_REVIEW | CAPTURE_AND_SEAL_GO / PROMPT_PROTOCOL_BLOCKED | 采集与封存正常；用户端文本提示未获得有效交付证据 |
| EVIDENCE_REVIEW | CONTAINER_VERIFIED / SOURCE_UNVERIFIED | 字节、帧和时间连续性可复查；刺激/语句真值缺失 |

总体 **P4_DEVICE_BLOCKED + P4_SOURCE_UNVERIFIED**。这些是研究协议与来源证据结论，不制造DEVICE_GO、AEC_PASS或Test3 PASS。

## 12. Stage7及冻结范围检查

**Stage7越界检查：PASS。** 仓库唯一新增文件为本报告，没有源码修改。独立工具、普通record守卫、AppleEngineDriver、NativePCMTap、VPRecorder/PCM协议及03/04/05历史报告保持不变。

未修改Aftelle App、Test2及此前节点、Qwen Realtime原生全双工主链、NativeSpeechProvider/Adapter、实时协议、RuntimeCore/Provider/正式授权/generation、DR/Studio/Session/Memory、ACE3冻结成果或正式Test3合同。未操作原ACE3工作区、SSD/quarantine或历史PCM；未新增平台target、进入Stage8或运行AEC/HIL实验。

私有提示/执行/离线分析辅助文件仅服务本次研究，不接入产品，不修改原生音频路径，不上传Git。正式Runtime没有任何声源资格或中断授权变化。

## 13. 后续GO / NO-GO与交付

**NO-GO：不进入Test A/B/C。** 本次唯一录音已用完，不自动重试。最小下一步是主控审核提示交付问题，先在不录音的条件下证明文本实际可见性；任何新实体采集须作为另行授权的节点。不能用这次有PCM的结果跳过有效刺激和物理来源证据。

Git交付仅包含本脱敏报告，允许保留BLOCKED/UNVERIFIED结论。发布前检查全部diff、范围和隐私；仅暂存本文件，独立commit并推送当前分支，回执核对本地HEAD、upstream及远端SHA一致、工作区干净。

最终保持：

```text
VP-0-P3 Implementation = APPROVED
VP-0-P4 Device Validation = REVIEW_PENDING
VP-0 Device Preflight = BLOCKED
VP-A/B/C = NOT_AUTHORIZED
VP-D/E = BLOCKED
Test3 = BLOCKED
execution_authorized = false
```

完成本报告交付后停止，等待主控独立审核。
