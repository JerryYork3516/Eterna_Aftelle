# T3.2-A-D2-R2-M01 — Content Timeline Root Cause & Silent Validation

日期：2026-10-17。状态：`REVIEW_PENDING`。内容时间修复与本轮离线/无声检查 `PASS_RECOMMENDED`；`READY_FOR_HUMAN_TEST=true`。ENGINEERING 保持 `REWORK / DEBT_DEFERRED`。本轮不产生 AEC 声学 PASS，不执行真人有声实验。

## 1. 基线与最小范围

- Repository `JerryYork3516/Eterna_Aftelle`，branch `Test3-AppleVP-Clean`；起点 HEAD/upstream/实时远端均为 `52ba34a6d5d89a6e315cee44b52713940314a9e1`。
- 初始 staging 为空，受跟踪工作区干净；原有未跟踪 D 设备报告保留，不提交。
- 按 AGENTS 先创建空回滚提交 `500505bb2e0ff9c2883771703c9853f24599d35f`，它也是运行时 HEAD；候选生产/测试内容由下述 diff 与文件摘要绑定。
- 阅读 AGENTS、[正式计划](README.md)、[v2 相关合同](T3_1_R2_native_voice_experience_plan.md)、[D2-R2 失败报告](T3_2_A_D2_R2_real_acoustic_results.md)、代码规范、相关执行流程和 [Stage7 Checklist](../../stage7_forbidden_checklist.md)。没有全库理解扫描或改原 ACE3/研究 Worktree。

实际修改：

| 文件 | 改动 |
| --- | --- |
| `apps/macos/Aftelle/MacSpeechAudioCapture.swift` | 原 Converter 复用相邻硬件 host 时间检查，保留样本时轴、锁和 reset；无 AEC/AGC 或 Engine 拓扑修改 |
| `apps/macos/Aftelle/AppController.swift` | 仅 DEBUG：Silent A=18s、B/C=4s，有声仍15s；扩大 A 的有界元数据计数上限；无声统计设备标识输出为别名 |
| `tools/speech_aec_host_tests/ConverterTimelineTests.swift` | 16k/48k/44.1k、30s 正/负漂移及漂移后的真实不连续负控 |
| `tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift` | 4 项时长策略断言、每个 Silent 场景的脱敏统计断言 |
| 同目录 `check.sh` | D1 checks 283→290；cases=40、安全负控原样保留 |
| 本报告、README、DEVLOG | 本轮真实状态、证据与治理登记 |

未改 RuntimeCore、Qwen Adapter、Input Bridge、Provider cancel、Playback clear、Session/Memory、DR、Release 路由或 lint 配置。Cascaded 原 AEC3 路线不变，不新增 Engine、Provider、Clock Owner 或中断 Owner。

## 2. 已证实的失效机制

历史 A 的 `native_clock=0` 是关键证据：既有 `MacSpeechNativeVoiceDebugStats.recordClock` 对每个相邻 buffer 检查 sampleTime 精确连续、hostTime 增量不超过一样本误差；若缺失时间、sample 缺口或超界 host 跳变会累计 native_clock。历史这些检查均通过，但 Converter 的另一项判断仍产生 6 次 content_time 拒收。

原 `anchoredInputHostTime` 用首个 host/sample 锚点及标称采样率计算预期时间，再把**整条 run 的累计偏差**限制在一个输入样本内。历史末端 sampleTime 差 236800、标称16kHz，对应14,800,000,000ns；实际 host 差14,799,937,333ns，偏差-62,667ns，超过62,500ns。这个门槛会把相邻区间均合法的微小设备时钟偏差误判成内容缺口，并锁定无效直至 reset。

确定性重放使用原两个 Converter、Apple pass-through AcousticHost、合成常量样本，不启动设备。16kHz、每个 buffer 1600 frames；样本时间严格递增，host 相邻增量均满足原一样本条件。

| 合成输入 | 修复前 | 修复后 |
| --- | --- | --- |
| 30s 标称稳定时轴 | 0 拒收、1499包 | 0 拒收、1499包 |
| host 偏差在14.8s达到-62667ns，继续线性变化 | 首次失效 buffer148（从0计）、152次拒收、739包 | 0 拒收、1499包 |
| 149个 buffer，偏差 `-min(t/14.3×62667,62667)` ns | 首次失效 buffer143、**6次拒收、714包** | **0次拒收、744包** |
| sampleTime 第2个 buffer 起真实缺1样本 | 第2个起持续拒收 | 第2个起持续拒收 |
| hostTime 第2个 buffer 起突跳50ms | 第2个起持续拒收 | 第2个起持续拒收 |

前后重放编译/运行均 exit0；这里的 exit0 只表示重放程序执行成功，修复前的拒收是实际重放输出，不被改判 PASS。复现源码、命令和输出位于 Git 忽略的 `.build/t3_2_a_d2_r2_m01/`；长期正/负漂移与错误时轴回归进入已有版本化 ConverterTimelineTests。

**确认的是旧累计门槛误拒合法连续时轴的工程机制。** 合成曲线匹配历史端点和714包/6次拒收，不冒充历史逐次 callback 记录。历史第一次拒收的精确 callback 锚点没有保存，无法逐项恢复，保持这一证据限制。跨 buffer 的区间选择与 waveform 前缀另由实际 AVAudioConverter 对照测试验证；没有把仅端点推测直接当作完整历史轨迹。

## 3. 最小修复与不连续保护

1. sampleTime 仍须等于上个输入 sampleTime＋真实 frameLength；缺口、倒退、溢出、已经建立锚点后缺失 sampleTime，均使原有效性锁存为 false。
2. 用既有 previousInputHostTime/previousInputFrameCount 比较**相邻硬件 host 增量**，容差仍为 `ceil(1e9/inputSampleRate)`，没有扩大数值门槛；host 倒退或超过门槛的突跳拒收。
3. 内容时间仍由首 host 锚点＋连续 sampleTime 偏移生成，outputHostTime/recordInputTimeLocked 继续按实际输入支持区间和输出样本游标映射。没有重新锚定到 callback 到达时间，也没有改 PCM、填零或拼接缺口。
4. 原无 sampleTime 起始的 host-only 路径保留原相邻时间校验；已进入 sample 锚点后不能切到 host-only 来掩盖时间缺失。
5. 原 Converter lock、generation fence、失效锁存和 reset 保留；没有新增 async task、状态 Owner、估算器或第三方依赖。

新增负控在先通过17s连续漂移后，分别注入 sample gap、sample backward、host jump、host backward、缺 host、缺 sample、超过一样本的 host 增量误差；三采样率均须持续拒收，只有显式 generation reset 后恢复。旧连续性负控、跨 buffer waveform 前缀、24k/mono/PCM16LE/20ms/960bytes、旧 generation 拒收及有界队列均保留。

DEBUG Silent A 的 collection 上限18s，计数容量864000bytes；该计数仅统计处理包，不保留实际输入 PCM。B/C 上限4s；非 Silent 入口仍15s、720000bytes。Silent manifest 只输出 `default_input/default_output`；真实路线在采集前后用只读 CoreAudio 与运行内原 route fence 核验，不保存私人硬件 UID。

## 4. 离线验证与构建

最终代码冻结后执行；此前版本结果及 style 首次问题也保留在本地，没有用重复运行覆盖失败。

| 实际命令/入口 | exit | 最终结果 |
| --- | --- | --- |
| `bash tools/speech_aec_host_tests/check.sh` | 0 | Converter **65 cases/6830 checks**；AEC **1165 checks**；原 Replay self-check与静态合同 PASS |
| `bash tools/speech_audio_host_tests/check.sh` | 0 | **178 checks**＋原所有权/权限/拓扑/路线/分包检查 PASS |
| `bash tools/speech_audio_output_tests/check.sh` | 0 | **238 checks**＋原生命周期/pressure/bit-exact等检查 PASS |
| `bash tools/realtime_interruption_evidence_tests/check.sh d1-only` | 0 | **40 cases/290 checks**；Fake A/B/C、启动/退出隔离、权限负控、安全导出及合成文件清理 PASS |
| `bash tools/speech_aec_host_tests/check.sh d1-stats-only` | 0 | **10 cases/49 checks**，设备访问 ZERO |
| `bash tools/realtime_release_route_guard/check.sh` | 0 | 原权限顺序、Stop fence、Release 入口隔离 PASS |
| `bash tools/architecture_guard/check.sh` | 0 | PASS |
| `bash tools/secret_guard/check.sh` | 0 | PASS |
| Debug build | 0 | BUILD SUCCEEDED |
| Release unsigned build | 0 | BUILD SUCCEEDED |

构建实际沿用 `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug|Release -destination platform=macOS -derivedDataPath <本轮Git忽略目录>/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build`。本轮新建派生目录，保留前序证据；Xcode 克隆缓存的陈旧绝对路径清理提示不视为生产变化。D1 编译仍有既有并发 warning，未改 Runtime 或将 warning 写成0。未执行无关 Qwen/Runtime 全套或在线测试。

## 5. 构建、路线与单次设备身份

运行时 HEAD 为上述 checkpoint；源码/测试 diff SHA-256：`37138c7520d1b20114908bbdec955e22e2f2c20849e52ba11b8f2a188ee0989b`。逐文件清单在构建、运行及提交前校验；之后文档改动不冒充相同完整工作区 diff。

| 实际 Debug 映像 | SHA-256 |
| --- | --- |
| `Aftelle` | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| `Aftelle.debug.dylib` | `98918302e7a8be058b772e1e1a498786c5ec9cb09ba7bec90a317b9bcb4c9fdf` |

输入 I-01=默认 USB 麦克风，输出 O-01=默认 Mac 内置扬声器；预检均 alive=1、hog=-1、running=0，无 Aftelle 残留进程。系统输入60%、输出55%且未静音，前后不变；Microphone Mode UNKNOWN。未切换设备、音量或系统模式。既有 Silent 入口在设备启动前实际检查授权，未授权即失败且不调用 request；三次已实际采集，没有新的权限请求。

本轮指令明确授权一次长时无声 A、再各一次 B/C；无额外录音授权推定。每项独立 App 实例、使用原正式共享 Engine/Capture/OutputHost/Converter，A/C 只排程2秒零值 PCM，B不输出。没有有声 WAV、Provider、私人 DR/历史 Session、正式 Runtime 中断。

| 场景/Run UUID | 上限/原生覆盖 | buffer/frame | generated/drained/queued | 结果 |
| --- | --- | --- | --- | --- |
| A `E3AA1A2C-A251-47AB-A5CE-7C47F38B3F64` | 18s / **17.9s**，超过至少16s要求 | 179 / 286400 | **894 / 894 / 0** | PASS |
| B `E4EBB044-CBB1-4432-89D8-B8C68990F1E7` | 4s / 4s | 40 / 64000 | **199 / 194 / 5** | PASS |
| C `DE47F35F-321F-44FD-9841-29575DE35A82` | 4s / 4s | 40 / 64000 | **199 / 194 / 5** | PASS |

三次全部：原生 Float32 non-interleaved **16000Hz/3ch**；VP input/output true、AGC true、bypass false、inputMuted false；capture generation1、configurationID2；A/C playback generation1、start1且completed，B generation0、start0且idle。配置阶段 validated，原 I/O 采样率/声道 Guard通过。处理后24kHz mono PCM16LE，每包20ms/480samples/960bytes；已 drain 的序号与内容时间严格连续。

全部已有拒收原因计数均 **0**：content_time、native_clock、packet_clock、capture_fence、stale_context、route/configuration_changed、各 conversion/format/capacity 等均未触发。drop/stale、playback underrun/rejected callback也均0；run/capture/playback error均null、coverage_valid=true、issues为空、sealed=true。三次各声道满幅/超幅/non-finite均0，不据此判断音质。

本次 A 末端相对首锚点的实际 host/sample 偏差为 **-44292ns**，B=-23542ns、C=-3375ns。本次自然漂移幅度没有重现历史62667ns，**不声称已在设备上强制重现同等漂移**；超过旧门槛的机制由确定性重放验证，目标设备按要求单次跨过原14.8s时间边界。

### 覆盖、尾部与释放

| 场景 | 已 drain 首包起点 → 末包结束（monotonic ns，exclusive） | 已 drain 内容 |
| --- | --- | --- |
| A | 698959541262500 → 698977421262500 | 17.88s |
| B | 699036294077417 → 699040174077417 | 3.88s |
| C | 699051996544083 → 699055876544083 | 3.88s |

B/C 各5个完整排队包（100ms）未计入 drain 范围，Stop 时清理；不是隐藏为已导出内容或 packet drop。Converter partial tail均null/UNKNOWN，未补齐或填零；native coverage有效不等于所有未成包尾音都已验证。当前仅证明观测时轴、完整20ms包及明确排队区间，未来有声 run仍须验证post-roll/尾音覆盖。

三个实例先 Seal/原 Host Shutdown、再正常菜单 Quit；最终 Aftelle 进程不存在，默认 USB/内置路线仍一致，两设备 alive1/hog-1/running0。未观察到崩溃、死锁或进程内资源滞留迹象。

### 首次工具异常原样保留

- A 启动脚本在进程刚出现时的第一次 lsof 全映像断言 exit1，未记录是哪项尚未匹配；随后对**同一现存实例**检查实际 argv、主程序及 dylib路径全部正确，UI与统计均属上述A run。没有第二次 launch或重新采集。后续B/C仅对同一新PID做有界映像等待，不循环设备测试。A正式统计检查通过；未把工具首次exit1删掉。
- 第一次即时退出快照的组合断言未通过，首读分项没有持久化；不补造该瞬间的占用值。一次后续只读快照确认进程不存在、两设备空闲。组合shell后续只读命令最终exit0未被当作首个Python断言PASS；未为此重启设备或更改产品Guard。

## 6. 本地统计与隐私

只使用原受控 `~/Library/Caches/com.eterna.aftelle.debug-apple-vp-evidence/` 保存本次统计JSON，目录0700、文件0600、无覆盖。每次 silent_smoke=true、retained_pcm_bytes=0、processed_sha256=null，无对应WAV；设备标识已在现有 DEBUG manifest 生产处替换为别名，不靠事后覆盖原件。源/构建 null 字段保持真实，由本轮外部清单绑定。

| 场景 | 统计 JSON SHA-256（文件名为对应run UUID） |
| --- | --- |
| A | `93a95bc8d45c440673884d3bc951e3324957e2905feb2ba22764d62a3946633a` |
| B | `5c8a59d0226065ed1145af5b2ed779bfdb2f36573a650f0c98fe962b3d167683` |
| C | `501af5dd2f081e32d153fda6475f654406789d8b380b31e322b567ed9f4361e7` |

本轮不保存/导出实际输入PCM、录音WAV或逐帧日志；不读取历史私人音频、不上传音频。旧D2-R2失败报告、原音频及用户反馈保持原样。固定非私人TTS文件SHA仍为 `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`，本轮未播放；未来有声测试资产已就绪但须另行授权。

## 7. 增量规范与五维审核

固定 SwiftFormat0.63.1/SwiftLint0.65.1，沿用前序相同15个显式Swift文件、规则、参数。按文件/rule/reason/原始Git行映射归因，不以总数差代替新增归因。

| 工具 | 起点 | 首轮 | 中间 | 最终 |
| --- | --- | --- | --- | --- |
| SwiftFormat | 20856 / exit1 | 20859 / exit1 | 20856 / exit1 | **20856 / exit1，FAIL，新增B0** |
| SwiftLint strict | 384 / exit2 | 385 / exit2 | 386 / exit2 | **384 / exit2，FAIL，新增B0** |

首轮新测试type长度、格式和两工具相反的多行brace要求均在新增局部真实修复；新方法放入该文件原有extension，用单行条件解决brace冲突，无 disable 或规则变更。最终只有4个**既有C指标增长**：Capture文件2407→2419、R81测试文件3458→3468、Controller文件8229→8243、Controller类型6742→6746。没有新增函数长度/复杂度违规。C19/C23保持分登记，这4项不是额外4个独立新债务或可直接相加的总数；ENGINEERING不改判PASS。本次按当前节点“B0、历史债务延期、安全验证通过后自动提交”授权交付，不修改04规范或创建永久例外。

审核来源全部为 **SELF_REVIEW（Codex）**，无独立Reviewer冒称。

| 维度 | 结论 | 依据 |
| --- | --- | --- |
| TECHNICAL | PASS_RECOMMENDED（本轮范围） | 累计门槛失效机制可复现、负控不退化、长时目标A及B/C均一次通过 |
| ENGINEERING | REWORK / DEBT_DEFERRED | 最小原Owner内修复，无重复Engine/状态；B0，保留全量工具FAIL和既有结构增长 |
| EVIDENCE | PASS | 区分合成轨迹与历史事实、自然设备偏差与重放边界、已drain/queued/partial、首工具失败及声学未验 |
| CONSISTENCY | PASS | Test2原链/Release/Cascaded边界不改，有声15s不改；不推进后续节点或正式Gate |
| Stage7 Forbidden Checklist | PASS | 六红线及A–H当前禁止项未触碰 |

CRITICAL新增0；功能安全MAJOR新增0。原R2-M01建议按本轮验证结果由主控审核关闭，不自行宣称主控APPROVED。工具时序/首快照异常为已登记的证据限制，未靠第二次设备运行消除。

剩余：原起音音量变化 **OPEN**，未修改AGC；有声A/B/C、真实post-roll/partial tail等仍待后续授权验证。SQ-M1 OPEN，原规范债务继续延期；本轮无声结果不证明AEC、人声保留或物理双讲PASS。

## 8. Stage7检查与最终准入

六红线逐项PASS：大脑不碰平台、Store带版本、三层不黏连、DR只读/revision、粒子逻辑/画法分离、Intent语义均无改变。Checklist A–H：仅现有macOS Host；无新target、Runtime API、DR schema、Stage8、Provider/Memory/Scheduler/Interrupt所有权或声源Gate；无未授权设备/私人数据访问。

Checklist I：代码变更为“是”，范围仅上述两生产Swift及必要测试；Runtime API/DR schema/新增平台/Stage8均为“否”。原ACE3/研究Worktree与旧未跟踪报告核验保留；提交白名单不含PCM/WAV/DR/密钥、私人设备标识或原始日志。

**READY_FOR_HUMAN_TEST=true**：本轮根因机制与修复已验证，离线检查通过，目标路线长时Silent A及B/C全部通过、进程已退出；不需要用户等待编译或排障。此状态只表示可安排后续独立授权的有声测试，起音音量问题仍须观察，不等于T3.2-A整体收口。

最终状态：M01 `REVIEW_PENDING`；ENGINEERING `REWORK/DEBT_DEFERRED`；T3.2-B `NOT_AUTHORIZED`、T3.3 `NOT_STARTED`、SQ-M1 `OPEN`、Qwen Strict Overlap `0/3`、Formal Test3 `BLOCKED`、Test3.execution_authorized=false。完成正常commit/push并核验同步后停止，不自动开始真人有声实验。
