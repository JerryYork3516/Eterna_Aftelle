# Eterna Aftelle · T3.2-A-D2 · Real Acoustic Validation

日期：2026-10-16（Asia/Shanghai）。**首次 A 准备失败，设备操作已停止；实机声学结论未取得。** 本报告交主控复审，不批准修复、重试或后续节点。

## 1. 范围、Git 与实际环境

本轮依据主控 D2 授权，先完成固定非私人样本与构建预检，再取得用户本次设备授权。只运行现有 `--apple-vp-acoustic-test` DEBUG 入口，未用独立研究 CLI 替代正式 Host。生产／测试源码、配置与历史报告均未修改；本次 Git 交付仅为本报告。

| 项目 | 实际证据／限制 |
| --- | --- |
| Repository／Branch | JerryYork3516/Eterna_Aftelle／Test3-AppleVP-Clean |
| 运行源码 HEAD | `09c77318b3bcd3ba674790af08e68135d5246146`；启动前 HEAD、upstream、实时远端一致 |
| 运行源码 tree | `2daa2147527c5be64bf42fbd6e7ac7d56d689ef5` |
| 源码差异 | tracked diff 为空；17 项生产／测试／脚本 SHA 与 D1-R2 最终验证清单逐项一致，无未跟踪源码 |
| 工作区 | 原有未跟踪 `T3_2_A_D_real_device_validation.md` 保留且不纳入提交；本次没有覆盖它 |
| 系统 | macOS 26.6.2，build 25G83 |
| I-01 | 系统默认 USB 麦克风；设备标称 16000 Hz／Mono；具体设备身份仅保存在本机私人预检 |
| O-01 | 系统默认内置扬声器；设备标称 48000 Hz／2 channels；没有用耳机代替外放 |
| 音量 | 系统读回输出 61%、未静音，输入 60%；用户明确采用本轮输出 61% |
| 位置 | 用户确认设备就绪、摆放与 VP-C 一致；USER_CONFIRMED，未独立测距／校准声压 |
| System Microphone Mode | **UNKNOWN**；未自动切换设备、音量或模式 |

设备标称格式不是 VP 启用后原生格式的实测值。私人设备 UID、序列、PID、用户绝对路径、原始日志及录音不进入本报告或 Git。原 ACE3、Apple VP 研究 worktree 未修改。

## 2. 用户授权与固定样本

授权按步骤取得，没有把“设备就绪”当成录音授权：

1. 用户先授权使用 macOS 已安装离线语音生成非私人测试 WAV，并明确暂不授权麦克风、外放或真人录音。
2. 用户最初指定 50%；系统随后读回 61%。再次确认后，用户原话为：**“本轮明确采用当前61%”**。执行者未自动调节音量。
3. 展示实际设备、未知麦克风模式、固定文本／文件 SHA、每项至多 15 秒、A 安静／B 自然说话／C 双讲方法、受控本地导出位置和手动试听边界后，用户明确回复：**“授权本次A/B/C采集、测试播放、录音及本地JSON/WAV导出核验”**。
4. 开始 A 前再次提示保持安静。通过 DEBUG 界面 Start 及本地设备确认执行首次尝试；失败后没有继续 B/C 或重试。

固定内容为 **“这是一段固定语音，用来检查回声和人声。”**，使用系统已安装 Tingting 中文语音、rate 210。`say -o` 输出 AIFF，随后 `afconvert -f WAVE -d LEI16@24000 -c 1 --no-filler` 转换；两步 exit 0。合成进程使用本机 `sandbox-exec` 禁止网络，不调用 Provider、不下载模型、不读取 DR／会话／历史录音。未通过扬声器试听生成文件。

最终文件在 Git 忽略的 `.build/t3_2_a_d2_preflight/tts_sample_v1/` 中，文件名 `d2_fixed_zh_24k_mono_pcm16le_preroll1s_v1.wav`。在转换后的合成内容前添加准确 1 秒静默，合成内容后缀字节保持不变；此处是预登记测试材料，不是对采集结果补零。

| 样本属性 | 实际值 |
| --- | --- |
| 格式 | 24000 Hz／Mono／PCM16 Little Endian，标准 WAV |
| 合成源 PCM 时长 | 3.751333 秒；不是去静音后的有声区间或声学实测起止 |
| 总长度 | 4.751333 秒／114032 frames，含 1 秒前导静默 |
| 文件大小 | 228108 bytes，低于现有入口 720 KB 限制 |
| WAV SHA-256 | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` |
| PCM payload SHA-256 | `7fd9318b95233f4f188b3d186aaf3befc8b7fd64b21f24b7674e1004e12d3960` |
| 源样本统计 | peak 21954／32768，满幅样本 0；**仅属合成源，不能证明采集／AGC／AEC 质量** |

方法发现阶段的 `say --help` exit 1、`afconvert -h` exit 2 保留在本机；改读本机 man 后采用上述有效命令。它们不是生成成功结果或设备测试结果。

## 3. 实际 Debug 构建与 run 绑定

复用 D1-R2 已验证 Debug 构建，不重复构建未改变源码。启动前与失败后均复算最终清单的 17 项 SHA；实际可执行文件与 debug dylib 均复算 SHA。通过实际进程参数及 loaded images 核对，运行的是该构建的隔离 DEBUG 入口，不是其他 Aftelle 或研究工具。

| 绑定 | 实际值 |
| --- | --- |
| Debug executable SHA-256 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug dylib SHA-256 | `b70106f5eb8322294f4f3eea674ad9bd8874576ca05a679ed3acc880f112387c` |
| Configuration | Debug；已加载两项构建镜像均与上述身份一致 |
| 场景／尝试 | A／第 1 次；B 0 次、C 0 次、重试 0 次 |
| run UUID | `2DE786B3-1F7C-463E-8F0D-67294CA039A0` |
| 导出 JSON SHA-256 | `d98b62b45d92961bf899a4d9ff601009c44736be93a0f673933e3f75fe6a16bf` |
| JSON 内源码／构建身份 | `source_commit=null`、`build_identity=null` **原样保留**；本表由外部预检、进程及 run 文件交叉绑定，不宣称 manifest 已内嵌这些身份 |

源码确认隔离模式不构造正常 Runtime／Provider／Store 依赖，不加载书签 DR、历史 Session、Provider 配置或 Keychain；实际界面显示隔离入口和正式中断 DISABLED。复用正式唯一共享 Engine、原 Capture／OutputHost／Player；未新建第二音频链，Cascaded 原 AEC3 路线未改。预启动单点观察 IP sockets 为 0；它不构成全程系统网络审计。本次未执行真实 Provider 动作。

## 4. A/B/C 实际结果与首次失败

| 场景 | 控制／集成结果 | 声学结果 | 实际执行 |
| --- | --- | --- | --- |
| A Resident-only | **FAIL — PREPARATION_FAILURE** | **NOT_RUN** | Output 准备失败，封存 `playback_failed`；没有取得可评价 PCM |
| B Human-only | NOT_RUN | NOT_RUN | 按停止条件未继续 |
| C Double-talk | NOT_RUN | NOT_RUN | 按停止条件未继续；物理重叠时长 UNKNOWN |

唯一 A run 的封存事实：

| 字段 | 实际值／含义 |
| --- | --- |
| Run state／error | sealed／`playback_failed` |
| Output state／error | failed／`output_unavailable` |
| Playback generation／started count | 0／0 |
| Capture state／generation | ready／1；准备了 generation，**不表示已经采集** |
| Native buffers／frames | 0／0 |
| Processed packets／PCM bytes | 0／0 |
| Configuration ID／native format | UNKNOWN／UNKNOWN |
| Coverage valid | false |
| JSON／WAV | 显式导出失败 JSON；未生成 WAV |

源码顺序对应 [AppController.startAppleVPAcousticAudio](../../../apps/macos/Aftelle/AppController.swift)：先 `speechAudioOutputHost.prepare()`，失败 guard 抛出 `playback_failed`，后面的 `startPreparedCapture` 未执行。VP 配置内部曾尝试设备初始化，不能把“未进入 Capture.start”写成“设备从未被访问”。实际固定语音没有进入成功播放，不能声称通过正式 Render 完成了 A 的回声实验。

失败后立即停止设备操作，没有重复 Start，没有准备 B/C；保留同 run 的 sealed JSON，随后通过 App 原生 Quit 退出。最终进程不存在，未观察到 App 崩溃或死锁；不将进程退出扩大解释为对所有系统音频服务的完整资源审计。

## 5. Apple VP 实际读回与根因边界

| 要求 | 本次取得情况 |
| --- | --- |
| Input／Output VP enabled | UNKNOWN：没有形成同 run 的成功 validated snapshot |
| bypass=false／inputMuted=false／AGC 实际状态 | UNKNOWN：源码设置与部分初始化日志不等于完整成功读回 |
| VP 后原生采样率／声道 | UNKNOWN；不套用研究工具格式或设备标称值 |
| 转换后格式 | 目标合同仍 24 kHz／Mono／PCM16LE／20 ms（480 samples／960 bytes）；没有实际输出包验证 |
| AEC／NS／AGC 声学效果 | NOT_RUN；没有伪造 ERLE、linear output、confidence、降噪 dB、延迟或效果百分比 |

**已确认的故障位置是 Output prepare；精确根因仍 `ROOT_CAUSE_UNVERIFIED`。**

- [OutputHost.prepare](../../../apps/macos/Aftelle/MacSpeechAudioOutputHost.swift) 可能因设备不可用或 Player prepare 失败返回错误；[Player.prepare](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift) 把 `audioEngine.prepareOutput()` 的任意异常压为 `output_unavailable`，本地格式／输出 Converter 失败也使用相同错误。
- 同一 App 尝试的系统日志出现 VP aggregate channel-layout `-10877` 诊断，其后仍有初始化活动与 bypass／AGC 设置记录。不能单凭该日志锁定最终 Swift throw，也不据此认定 Apple AEC 算法失败。
- [共享 Engine configureIfNeeded](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift) 要求 VP input/output 采样率和声道一致，这是值得定点检查的格式约束。**它是否实际触发只是 HYPOTHESIS**；本次没有失败点实际格式与原始 NSError，不得直接删除 guard 或声称根因已证实。
- 调换 Output／Capture 准备顺序可能只是把同一配置失败移到另一入口；本轮没有尝试该修改。

## 6. PCM、时间窗口、增益与削波

预登记方案为：1 秒静默预留＋完整 3.751333 秒源语音＋至少 1 秒 post-roll，最短 5.751333 秒，可放入现有 15 秒 collection 上限。B/C 真人句子预定为“今天我想聊聊刚才的事情”；C 要求实际物理双讲超过 1 秒，不能用调度时长代替见证。

本次在准备阶段失败，以下全部没有获得：真人／居民实际起止、物理重叠、外放后 0–500 ms 尾音、至少 1 秒实际 post-roll、drain 完整包首末区间及 converter partial tail 覆盖。不能把预登记预算写成实际完整窗口。

FrameBuffer drop、stale、reject 等已导出计数为 0，但 native／processed 数据也为 0；这是 **零观测，不是连续性 PASS**。原生各声道 peak、满幅／超幅、AGC 稳定性及起尾音完整性 **UNKNOWN／NOT_RUN**，没有数据支持把这些指标填 0。VP-C 历史每声道 35 个满幅样本风险本次未能复核，保持未验证。

## 7. 本地导出与用户试听

按用户明确授权，通过界面显式触发 JSON 导出并确认受控目标；仅生成对应 run 的 JSON，文件 0600、专属 Caches 目录 0700，未使用自由 NSSavePanel 目录或覆盖既有文件。只读取本次新 run 的必要字段，不读取其他私人录音、居民或旧 run。

没有有效 PCM，因此没有生成或播放处理后 WAV。**USER_LISTENING = NOT_RUN**；A 居民回声、B 人声完整、C 双讲清晰、音量突变／失真均没有用户试听结论。未将自动统计替代试听，未上传任何原始音频、设备日志或私人 JSON。

本机证据索引（全部留在 Git 外）：`.build/t3_2_a_d2_preflight/` 下的 `source-build-preflight.private.json`、`app-runtime-binding.private.json`、`device-authorization.private.json`、`A-first-failure.private.json`、`A-process-log.private.json`、`post-failure-exit.private.json`；同 run JSON 留在应用专属受控 Caches。完整源资产路径与私人设备身份仅在本机登记，不写入 Git。

## 8. 验证范围与历史证据

| 检查 | 本轮实际结果 |
| --- | --- |
| Git 起点／upstream／实时远端／源码身份 | PASS；只读核验，相关命令 exit 0 |
| 固定非私人样本生成与格式核验 | PASS；生成／转换 exit 0，样本 hash 与 run playback hash 一致 |
| Debug 构建身份／实际载入镜像核验 | PASS；复用原构建、实际载入文件匹配 |
| 首次 A | **FAIL**；GUI sealed 错误，不以 shell exit 0 代替运行结果 |
| B/C／真实 PCM／用户试听 | NOT_RUN；不为取得 PASS 自动重试 |
| Debug／Release build、Host／Playback／AEC／安全离线回归 | 本轮 NOT_RUN；生产／测试源码未变，保留 D1-R2 已通过的历史证据，不冒充本轮重跑 |
| Release／Architecture／Secret Guard 脚本 | 本轮 NOT_RUN；历史结果不覆盖本次设备失败；提交前另外检查本次文档 diff 与敏感内容 |
| SwiftFormat 0.63.1／SwiftLint 0.65.1 | 本轮 NOT_RUN；D1-R2 最终历史结果分别 **FAIL 20856／exit 1**、**FAIL 384／exit 2** |

本轮没有新增 Swift 行或测试改动。历史新增 B0、C19 独立延期登记保持不变，不把 C19 与旧 C23 相加；ENGINEERING 仍 REWORK／DEBT_DEFERRED。前次单次提交例外不转为永久豁免，本轮只交付脱敏失败文档。**真实 Output 准备失败是新的功能阻塞，不能归入规范债务延期。**

## 9. 五维审核与问题登记

实际来源：`/root` 执行设备预检、唯一 A 尝试、导出／退出、Git 与身份检查并撰写报告，作者判断标 SELF_REVIEW；`/root/d2_preflight_review` 独立只读审核正式源码调用链、样本格式／身份及失败定位；`/root/d2_failure_evidence_review` 独立只读复算导出／二进制摘要，检查授权、失败／零观测、运行身份与证据措辞。独立 Reviewer 未执行第二次设备测试或真人试听。

两名 Reviewer 已分别逐行复核本报告：技术／工程与 Stage7 结论、证据／一致性及脱敏均无新增阻塞文档问题。合成源 PCM 时长措辞的 MINOR 建议已修正；D2-F1 功能 MAJOR 保持 OPEN。

| 维度 | 结论 | 依据与限制 |
| --- | --- | --- |
| TECHNICAL | **REWORK** | 正式 Output prepare 真机失败；没有完成采集／播放，声学效果未验证 |
| ENGINEERING | **REWORK** | 新功能阻塞 OPEN；历史规范 REWORK／DEBT_DEFERRED 分开保留，本轮不修源码 |
| EVIDENCE | PASS | 保留首次失败、无重试、零观测／UNKNOWN、外部绑定与内嵌 null、试听 NOT_RUN 分别记录 |
| CONSISTENCY | PASS | 仅本次授权设备尝试与报告，不改 Test2／旧合同；历史报告／README 是当时快照，本报告记录 D2 实际结果 |
| Stage7 Forbidden Checklist | PASS | 受限 macOS DEBUG 验证，没有绕过 Runtime、接 Provider、修改 DR 或提前执行正式 Gate |

| 严重度／ID | 状态 | 问题与关闭条件 |
| --- | --- | --- |
| CRITICAL | 0 已确认 | 不等于未测试范围风险清零 |
| MAJOR D2-F1 | **OPEN／BLOCKING** | 实际 `output_unavailable` 阻止 A 及 D2 声学闭环；根因未定。另经主控批准定位／最小修复，完成受影响离线验证及重新授权实机验证后才能关闭 |
| MAJOR D1-E1（历史） | OPEN／DEBT_DEFERRED | 全局 lint FAIL 与 C19 延期，保留旧 C23 独立登记；非 D2 新增功能问题 |
| MINOR D2-E1 | OPEN | 原始配置失败阶段／错误被压缩，缺少终止点实际格式，无法区分设备、VP 配置、格式或 converter 分支 |
| MINOR D1-m4（历史） | PARTIAL／OPEN | 已取得本轮外部源码／构建／样本／run 绑定；系统 Mic Mode、成功 VP snapshot、真实窗口／物理双讲／用户试听仍缺，不假关闭 |
| SQ-M1（历史） | OPEN | 本轮不研究声源 Gate，不计作新增 lint 问题，不以本次结果关闭 |

### Stage7 Forbidden Checklist

Checklist A–H 逐项结论均 PASS：仅 macOS 单机；RuntimeCore 平台隔离不变；Host 不拥有 Provider／Scheduler／Memory；DR／fixture／Runtime API 未改；无真实 Provider／Keychain／secret 旁路；不写真实 Session／Memory／DR；无后台监听／唤醒词；UI 经 Controller 的已授权 DEBUG 本地入口，未产生 Runtime Decision 或正式 53 次数。macOS 本地 TTS 仅生成固定测试材料，不成为正式 Speech Route。

| 六条红线 | 本轮检查 |
| --- | --- |
| 大脑不碰平台 | PASS；未改 brain／RuntimeCore |
| Store 带版本 | PASS；无 Store／schema 变更 |
| 三层不黏连 | PASS；无 UI 直连 Provider 或新 Runtime owner |
| DR 只读＋revision | PASS；未读取私人 DR 或写回居民文件 |
| 逻辑／画法分层 | PASS；无粒子／Metal 改动 |
| 交互按意图 | PASS；产品逻辑未改，GUI 自动化操作不进入应用业务逻辑 |

结论 **PASS**；触碰红线：无。修改文件：仅本报告。是否改代码／Runtime API／DR schema／新增 target／进入 Stage8：均否。已因实际运行失败停止设备操作；不要求继续设备操作或修复的授权来完成本次失败报告交付。

## 10. 收口建议与停止状态

**不建议 T3.2-A 实机完整收口，不建议进入 T3.2-B。** A 的 FAIL 属正式 Host 真机准备链路的实际失败，尚不足以归责为已确认的具体源码 Bug，更不能归责为 Apple VP 算法限制。B/C 不补跑。

供主控决定的最小后续范围：先保留既有 Owner／音频图，只在共享 Engine 配置失败点增加有界 DEBUG 阶段、实际格式、原始错误 domain／code，并在 Player 的错误压缩边界与 DEBUG manifest 保留必要原因；候选文件限 `MacSpeechAudioCapture.swift`、`MacSpeechAudioOutputPlayer.swift`、`AppController.swift` 对应 DEBUG 字段及必要 Fake 测试。只有证据指向 OutputHost 的设备分支时才考虑该文件。此为**未授权提案**，本轮未实施；不创建第二 Engine，不动 Test2 中断、Qwen、Input Bridge、Runtime／取消／Session，不投机删除格式检查或改变启动顺序。根因确认后再确定实际最小修复，而不是预先承诺上述全部文件都需要改。

下一次设备尝试必须另经主控批准并确认用户设备授权范围、实际构建、设备模式／音量与 A/B/C 窗口；本次同意不用于自动重复至 PASS。

```text
T3.2-A-D2 = REVIEW_PENDING / PREPARATION_FAILED
A Integration = FAIL
A Acoustic = NOT_RUN
B/C = NOT_RUN
USER_LISTENING = NOT_RUN
T3.2-A Device Closure = BLOCKED
Further Device Attempts = STOPPED / REQUIRE_MAIN_AUTHORIZATION
ENGINEERING = REWORK / DEBT_DEFERRED (historic lint only)
T3.2-B = NOT_AUTHORIZED
T3.3 = NOT_STARTED
SQ-M1 = OPEN
Qwen Strict Overlap = 0/3
Formal Test3 = BLOCKED
Test3.execution_authorized = false
```

交付仅提交本脱敏失败报告；所有私人 JSON、WAV／PCM、原始日志、完整设备身份留在 Git 外。完成提交推送与 Git 身份核验后停止，不继续音频、Provider 或下一节点。
