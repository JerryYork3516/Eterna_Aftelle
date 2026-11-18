# T3.2-A · 真实声学资格收口准备与最小验证方案

日期为 2026-11-18（Asia/Shanghai）。范围为 Stage 7.5.11 / Test3 的只读证据审核与设备验证方案设计，审查来源为 Codex SELF_REVIEW。

**主控已接受 T3.2-A 离线工程结果。真实声学资格仍待证，推荐下一项为 P1 的一次、最多 15 秒 AGC-OFF＋STATS_ONLY 配置准入。** P1～P4 设备运行次数均为 0，所有阶段待独立批准。当前没有可确认的 AEC/CLOCK 生产根因或最小算法修复依据。

## 1. 当前工程范围与审核身份

| 项目 | 当前核验与边界 |
|---|---|
| 起始 HEAD / upstream / 实时远端 | `8db538642bd9cdc6cadf7b20be28a8d1f9ab8647`，三方一致 |
| 工作区 | 原 `vp-reference-host-preparation/Eterna_Aftelle`，本地 `codex/reference-host-comparison-preparation`，追踪 `origin/Test3-AppleVP-Clean`，开始时 clean |
| 已接受的工程候选 | 实际受测源码 `42551c1b66ed31d858fcc842b65a3dc4fa574964`，最终文档身份为本轮基线 |
| 工程证据 | FAST 8/8、独立 TEST3 7/7 与 11/11 不变量、FULL_CURRENT 21/21，原矩阵 8 项合法复用、13 项新执行。Input Bridge 32/210、M20/M22/M26 396/124/245、定向 TSan、Debug/Release、Release 隔离及三项 Guard 均有上轮实际回执 |
| 当前源码 | apps 树 `446e2ef9e63d60dd14bf5fd6d70079e6f18c0539`，tools 树 `a687af8d5095a2c1230e9f08a57cc51212243677`，与已接受候选一致 |
| M31 | 撤回锚点、当前 Capture 摘要及上轮产物隔离记录匹配，原 16 槽 Timing、身份/时间拒收、M20/M22/M26 能力保留 |
| 受保护现场 | 原 7 项冲突、index/status/unmerged 摘要及 14 项文件大小/mtime 与上次交付及本轮快照一致 |
| Fixture | 沿用上轮可信 SHA 校验收据。本轮只检查类型、所有权、0600、大小、inode、mtime/ctime 和忽略状态，未见上次校验后的修改，未打开 DR 原件或重新计算其字节摘要 |
| 本轮实际执行 | 文档、Git 与已登记保护/身份收据核查。App/Engine/设备查询、采集、播放、听音、转写、Provider、产品回归及构建均为 NOT_RUN |

主控本轮批准的 `T3_2_A_OFFLINE_ENGINEERING=ACCEPTED` 是当前工程状态。此前报告中的 REVIEW_PENDING 和历史失败按各自时点保留。本轮核对既有工程收据身份，沿用其结果。[完整工程验收记录](T3_2_A_input_bridge_dependency_and_full_regression_review.md)

本阶段声学缺口按 T3.1-R2 §8 的固定 Route 纯回声、真人独讲及双讲要求审查，P1/P2 的实验参数沿用 P0。未来 53-A～E 的原次数、Session、权威效果和时间要求仍归后续正式节点，本轮没有把它们提前设为新的设备 Gate。[T3.1-R2 正式方案](T3_1_R2_native_voice_experience_plan.md)

## 2. 证据等级与历史声学矩阵

CONFIRMED 表示已直接记录的技术事实或明确的用户反馈，用户听感的 CONFIRMED 仅确认反馈内容。SUPPORTED 表示有直接证据支持某一有限推断。HYPOTHESIS 表示尚缺因果验证的解释。UNKNOWN 表示关键事实未取得。INCONCLUSIVE 表示该次实验或比较无法给出所需结论。

下表只引用已提交的脱敏报告。原音、私人 JSON、Session 和私人讲话原文未重读，历史听感和数值未重新判分。

| 既有证据 | 真实观察与支持范围 | 限制与当前分级 |
|---|---|---|
| 原独立 VP-B / VP-C 研究 | 有限样本中真人可懂、用户未听出明显居民回声，VP/AGC 开启。旧程序有 Input/Render ready 等待和静默铺垫 | 素材、系统音量、格式、Tap 位置、排程、GUI/CLI 宿主与 HOST 不同，无法给出严格同条件改善量。研究正向，正式资格 UNKNOWN。[P0 对照](T3_2_A_acoustic_isolation_P0_research_vs_host_comparison.md) |
| R3-M01 单次 A，EDDF62B0… | 用户明确反馈“听不到居民回声，但是有起音，起音不知道是否影响”。已接纳 Native/PCM 连续 | A=INCONCLUSIVE，起音性质和可接受性 UNKNOWN。一次未听到回声只支持该次反馈。[单次 A](T3_2_A_D2_R3_M01_single_A_review.md) |
| 早期综合 C，B223A633… / 56C61C30… | 两次均反馈居民可闻。首次人声很小，复测忽大忽小。复测明确见证持续讲话并与居民物理重叠超过 1 秒，前 0–3 秒保存 PCM 仍约 −81.20 dBFS | 用户声学失败为 CONFIRMED，复测构成真人早段保留疑点。首轮实际讲话起止 UNKNOWN。早期报告没有这些局部时窗的可信 Native↔PCM 配对，近静音产生层不能确认。两次均有观测遗漏和尾覆盖限制。[综合 C](T3_2_A_comprehensive_C_real_acoustic_review.md) |
| M03 A/B/C | 用户试听“全部失败”，A 有居民模板残留和满幅。C 在 quiet 因内容时钟拒收停止 | B/C 使用同 Mac 驱动的蓝牙代理人声，真人保留资格 INCONCLUSIVE。A 残留与 C 时钟失败分别保留。[M03](T3_2_A_R5_M03_BT_ABC_acoustic_review.md) |
| M07 真人 A/B/C | 用户 A 未听到居民，B 清楚完整，C 未听到居民且有轻微忽大忽小，另见证双讲超过 1 秒 | 本批支持有限真人保留。C 在约 14.324 秒发生内容时钟拒收，维持 PARTIAL。首 3 秒约 −17.6/−17.9 dBFS，未复现早期 C 的近静音。[M07](T3_2_A_R5_M07_human_ABC_acoustic_review.md) |
| M09-D1 A 与 M10/M11 | M10 的源模板和负控支持 M09-D1 与已失败 M03 的相似残留。随后用户确认“M09-D1 A能听到居民语音，M07 A听不到” | 可闻居民残留为 CONFIRMED 用户反馈，M11 未找到确定接线或启动顺序缺陷。两次关键实现相同，实际声压和内部参考 UNKNOWN。[M10](T3_2_A_R5_M10_echo_residual_difference_review.md) · [M11 后续反馈](T3_2_A_R5_M11_device_binding_aec_reference_audit.md) |
| M12-D2 有效真人 C | 首轮未就绪、独立保留，用户新授权后有效重试。有效轮用户未听到居民，第二遍有轻微音量波动，无可闻爆音、消音或断裂，确认现场居民发声及持续双讲超过 1 秒 | 物理重叠的用户见证 CONFIRMED，精确时长未独立测量。Input 连续，Render 有一次约 100ms 观测缺口，WAV 首尾 PARTIAL，逐字完整性 UNKNOWN。M14 仅支持可疑局部衰减，未确认吞字。[M12-D2](T3_2_A_R5_M12_D2_human_doubletalk_review.md) · [M14](T3_2_A_R5_M14_same_phrase_doubletalk_review.md) |
| M19-D1 真人 C | 用户反馈可闻回声、仍忽大忽小，定位约 WAV 4–5 秒。743 个完整 20ms Native/保存 PCM 窗匹配，局部下降两路共同存在 | 差异已在 VP 后 Native 或此前环节的定位 SUPPORTED。该区间最大逐窗幅度差约 0.16431dB，无法分离真人、居民及内部处理贡献，音节损伤 UNKNOWN。[M19-D1](T3_2_A_R5_M19_D1_native_pcm_device_review.md) |
| M20 两批六轮，M21 复核 | 冻结检测为 4 ECHO_DETECTED、1 ECHO_NOT_DETECTED、1 INCONCLUSIVE。694 个有意义强度窗 Native/PCM 最大差约 0.193dB，已覆盖三个 Native 声道逐样本相等 | 输出模板残留差异 CONFIRMED。M21 已更正 D4 见证归属，六轮实体扬声器证明保留 UNVERIFIED。D4R1 全文件 99.93% 能量来自 60ms 突发，不能按大窗 RMS 推断持续回声或适应收益。[M21 §1/4](T3_2_A_R5_M21_AEC_root_cause_investigation.md) |
| M22 突发与 M24 听音 | 用户将 M22 四个限定事件均分类为非语音短促声，其中一个发生在居民播放之前 | 分类反馈 CONFIRMED，具体声源和 VP/AGC 成因 UNKNOWN。听音前后音量条件一致性 UNVERIFIED。该分类只对应这四个事件。[M24](T3_2_A_R5_M24_targeted_listening_review.md) |
| M27 三轮原始 TRIPLE_EQUAL | 同候选、素材、策略，全部技术门禁通过，分类依次 NOT_DETECTED / DETECTED / INCONCLUSIVE，NCC +0.086 / −0.451 / −0.064 | 有限筛查未取得 3/3 低残留。用户只能确认听到，轮次和地点不确定，各轮实体发声仍 UNVERIFIED。[M27 §7–10](T3_2_A_R5_M27_original_aec_stability.md) |
| M28 对 M27 的限定差分 | R2 持续模板匹配约 3.28125 秒，99.664662% 保存 PCM 能量在非零 Render 内。PCM 端点自身占能量 2.1214%，差异已存在于 VP 后 Native | 强残留与软件播放期间同步 SUPPORTED，单次爆音/满幅主导解释降级。真实声场、VP 内部状态、HOST 未观测状态仍不能区分。R1/R3 的低平均能量也含瞬态。[M28](T3_2_A_R5_M28_targeted_residual_differential.md) |

M27/M28 确认的是固定分析合同下的跨运行输出差异及其时间结构。历史真人可闻回声属于独立的产品体验失败证据。两组事实均需保留，工程回归通过未改变其声学裁定。

## 3. 已确认问题、未确认归因与方法局限

| 问题 | 直接证据 | 当前判断 |
|---|---|---|
| 居民可闻回声 | 早期 C、M03 A、M09-D1 A 和 M19-D1 的用户反馈，部分轮有源模板/负控支持 | CONFIRMED 存在失败案例，稳定 AEC 尚未成立 |
| 真人近静音、音量突变 | 早期 C 复测的持续讲话见证及前段低能量，后续真人 C 的波动反馈 | CONFIRMED 体验或保留疑点。具体缺字、AGC 独占原因 UNKNOWN |
| 变化生成层 | M19-D1 同内容时间短窗与 M21/M28 对应窗 | SUPPORTED 已覆盖的大幅变化在 VP 后 Native 或更早。早期 C 无相应局部 Native 真值，M12-D2 的三个低谷也不能由后来的其他 Run 代证 |
| Engine、设备与配置 | P0 确认研究与 HOST 启动条件、素材、Tap、格式、音量口径不同。M28 三轮公开 VP/AGC、Standard Mic Mode、设备集合及格式相同，次序无异常 | 跨程序条件差异 CONFIRMED，跨运行具体工程因果 UNKNOWN。系统设置一致不能代替实际声压或内部处理状态 |
| 时钟拒收 | M08 对 M03/M07/F1 的 host/sample 偏差和拒收传播已确认，输入 sampleTime 连续，host 偏差约 2–3ms，原失效保持至 generation reset | CONFIRMED 安全拒收会中止后续有效交付，历史误拒收 NOT_PROVEN。来源 UNKNOWN。后续 M09-D1、M12-D2、M19-D1、M27 未复现不关闭问题 |
| 观测缺口和尾部 | 旧 skippedUpdates 与已接纳 PCM 连续可同时出现，早期 queued 尾包和各轮 PARTIAL 覆盖有记录 | 观测遗漏与实际丢包须分别判定。queued 数据需守恒及有效覆盖证据，不能补作已保存样本 |
| M31 内容工具 | 已归因新增分配，后来性能尾部及析构线程安全未验收，当前指纹、Row 和映射实现撤回 | M31_D1=BLOCKED_CLOSED_FOR_REWORK。既有统计和时间资格继续可用，Schedule→Tap 精确内容对齐仍 UNKNOWN，本路线已收口 |

CLOCK 的已测保护包括相邻 host/sample 一致性、真实 sampleTime 跳变拒收、错误锁定及旧代失效，原 RAW 时间戳诊断有界保留首次异常元数据。callback arrival 与内容时间独立记录。R2 首 sampleTime 共同少 32 样本属于跨 Run 初始偏移，M28 没有观察到相对时钟错位。实际发生拒收或错误时间覆盖时须停，不能调宽容差或自动换代抹去失败。[M08](T3_2_A_R5_M08_capture_content_clock_stability.md) · [M09-D1](T3_2_A_R5_M09_D1_raw_timestamp_device_review.md) · [M28 §6](T3_2_A_R5_M28_targeted_residual_differential.md)

R3-M01 的“起音”仍缺少确定的声音类别、影响和接受结论。Player.play 请求、首非零 Render、callback arrival 和真正扬声器/人声起音有各自时间原点。软件首段静默和数字波形统计无法恢复未记录的物理发声时刻。M24 的其他 Run 分类也不能替代该次起音验收。[R3-M01](T3_2_A_D2_R3_M01_single_A_review.md) · [M24](T3_2_A_R5_M24_targeted_listening_review.md)

### 同 Mac 代理声源的证据限制

已有 Warm-up A/B 使用同一 Mac 的 NSSound 向蓝牙设备播放代理人声，居民则走 Aftelle Player。控制同步误差得到修正，两臂都保留代理源特征，首段约 −16/−15dBFS，WARMUP_EFFECT 仍为 INCONCLUSIVE。两个源都由 Mac 发出，代理是否进入 Apple 的回声参考没有直接观测，`SOURCE_REFERENCE_ISOLATION=UNKNOWN`。其路由不同也不足以证明参考独立。[Warm-up A/B 实际记录](T3_2_A_bt_speech_warmup_sync_and_ab_review.md)

因此，代理被压低可能涉及其作为远端内容被处理，也可能涉及增益、声场及其他状态，这一机制仅为 HYPOTHESIS。代理同步或波形匹配只能支持该实验的输出传播观察。真人 B/C 的近端保留、物理重叠、语音完整性和正式 53-C 资格仍需独立证据。

同样，M20/M27 居民独讲只测远端残留，不含真人近端发声。检测器的 ECHO_NOT_DETECTED 需同轮实际外放支持才能形成有限抑制观察。公开 VP enabled、AGC 开关、AU deviceID、Process 方向设备、软件 Tap 与内部 AEC 参考分别登记。Native 位于 Apple VP 之后，没有 VP 前同源原音，ERLE 和纯 AGC 增益轨迹均无法据这些资料计算。

## 4. 所有阶段共用的前置、字段和停止合同

P1～P4 是相互独立的待审阶段。主控先批准该阶段及参数，再取得用户对应的采集/播放、保留或统计导出同意和就绪确认。P2 的两臂需覆盖配对范围并分别确认就绪，P3/P4 各自另批。历史授权、旧批次计划与消耗记录不复用。

| 项目 | 执行前或运行时必须成立的条件 |
|---|---|
| 设备角色与 Route | P0 登记的 TinyUSB USB 输入 60%、Mac mini 内置输出 55%、未静音，固定摆位、距离、方向、遮挡及环境。设备身份和音量未来只读核验，当前实际状态 NOT_QUERIED。发现变化先停止交主控 |
| 源码及 Build | 统一固定源码、launcher/dylib 路径和磁盘 SHA，启动后绑定确切 PID 与实际加载映像。上轮工程候选的 SHA 可作核验起点，当前运行态 NOT_RUN。新构建或替换候选需独立登记与受影响准入 |
| 每 Run 身份 | 独立 RunID、Capture/Playback generation、configurationID、profile、数据模式、时间原点，Prepare 后固定。source/build 字段若原出口为空，以外部收据绑定，不能回填静态值冒充实测 |
| 权限 | 复用原 App 可见同意、Stop、显式导出及 macOS TCC。出现新的系统权限要求先停，由用户处理。P1 也需要真实麦克风及原输出同意，零值排程仍需原 Output 路径 |
| VP/系统状态 | Input/Output VP=true、bypass=false、inputMuted=false，requested 与 actual AGC 精确匹配。记录完整 client 格式/布局、公开 hardware 格式、active/preferred Mic Mode 各自值和可用性。P0 允许 Mode 不可取时保留 UNKNOWN 并限制归因，preferred 不能替代 active |
| 原观察字段 | Native 格式、帧数、coverage/issues、raw_timestamp_diagnostic、拒收原因、host/sample/arrival 时间、Input/Render 缺口、skipped/invalid/stale、设备方向/配置通知、Player 调用和非零 Render、generated/drained/queued、包序号/20ms/960bytes、评分首尾及 partial tail、Stop/Seal/Shutdown/退出 |
| Native/PCM 窗 | 有既有可信同内容区间和实际样本覆盖时才比较。格式不同分别使用各自样本数与采样率。无匹配字段或覆盖不足记 UNKNOWN，不能补零、插值或拼 Run 获得资格 |
| 本地隐私 | 新 Run 只用受控目录 0700、文件 0600、独占名称、无 symlink/覆盖或 Git 祖先。统计 JSON 导出、本地 WAV 保留、用户听音、Codex 读取新音频分析分别获得对应同意。原件仅本地，公开交付仅脱敏报告 |
| 退出 | 沿原 Stop→Seal→Shutdown→确切 PID 的 App 退出菜单，确认进程和设备资源释放，再结束该阶段。不能用旧 capturing 快照代替真实终态 |

各 15 秒均指原入口的计划采集/评分软件窗口，Engine 初始化和异步 Stop/Shutdown 耗时分别登记。软件调用前后间隔不等于实际硬件连续采样时长，不额外延长评分或语音窗口。

任何身份、权限、Route、VP/AGC 配置、格式、时钟/包连续性、观测资格、容量、隐私、导出、Stop 或释放异常，立即安全停止并保全失败证据，终止后臂及后续阶段。强烈失真、不适或用户取消同样停止。技术 FAIL 按原门禁判定，证据不足记 INCONCLUSIVE，执行前条件不符记 BLOCKED，不通过自动重试修正。

## 5. P1 · AGC-OFF 无声配置准入

**唯一推荐下一项，当前为 PROPOSED / NOT_AUTHORIZED。** 参数逐项继承 P0 §7.1/7.4，使用原 `--apple-vp-acoustic-test`、`APPLE_VP_AGC_OFF`、`Prepare comprehensive C · STATS_ONLY`，warm-up 选择 `Original C · no warm-up comparison`（nil）。原 `WARMUP_0S` 与 AGC-OFF 不兼容，4 秒预热会改变本项预算。[P0 固定方案](T3_2_A_acoustic_isolation_P0_research_vs_host_comparison.md) · [AGC-OFF 合同](T3_2_A_acoustic_isolation_M01_agc_off_review.md)

| 项目 | P1 固定条件 |
|---|---|
| 次数/时长 | 一次 Capture，最多 15 秒，总预算 15 秒。原四阶段软件时间 0/3/9/11/15 秒，保持静默，不要求真人讲话 |
| 素材/播放 | 原全零资产，24kHz / Mono / PCM16LE、114032 帧，SHA-256 `a7169f4bb25dc688e739888880d85640c9f5a0170df46bcc43ccd9c1823f96eb`，仅一次零值内容排程。未来执行前核验原件内容/格式/SHA，缺失或不符停止，不自行生成替代 |
| 同意范围 | 本次真实麦克风、原零值 Output 路径、统计及显式本地 JSON 导出。环境声音仍可能进入输入处理，STATS_ONLY 不保留整段 PCM，WAV 接口保持拒绝 |
| 配置 | OFF profile、actual AGC=false、双端 VP 开启、bypass/mute=false，实际代际/配置和格式有效 |
| 连续性 | Native coverage_valid=true，原拒收/drop/stale/rejected/underrun 均 0，已 drain 包的序号/20ms/960bytes 连续，quiet 已 drain 有效覆盖至少 1 秒 |
| 留存/覆盖 | `retained_pcm_bytes=0`、`processed_sha256=null`、WAV 不可用。skippedUpdates、queued/partial tail 如实记录，按当前原门禁核验守恒和观察资格，不把排队包算作已保存 |
| 清理 | 原 Output 各一次 prepare/start/completed，正常 Stop/Seal/Shutdown/Quit，资源释放成立 |

PASS 仅登记 `OFF_READBACK_AND_CONTROL_CHAIN_SUPPORTED`，表示该 Run 的配置与控制链证据成立。错误读回、非零 PCM 留存、WAV 可导出、技术异常或清理失败为 FAIL。必要时间锚/覆盖/读回不可核验为 INCONCLUSIVE 并停止。任一结果均交主控复核，P2 仍待新批准。

当前源码确认普通 OFF＋STATS_ONLY、nil warm-up 组合仍被允许，原同意和退出路径保留。绑定 M20/M22/M26、human/BT batch 或 score-control 的专用启动参数会引入其他合同，P1 使用普通原入口。界面和参数约束是本次静态核验，当前硬件 AGC-OFF 读回仍 NOT_RUN。[ContentView Prepare/选择器](../../../apps/macos/Aftelle/ContentView.swift#L837) · [Controller Prepare](../../../apps/macos/Aftelle/AppController.swift#L7906)

普通 A/B 不经过综合 C 的评分初始化，当前该调用点没有为其初始化 PCM 短窗统计对象，`short_window_diagnostics` 不保证取得双侧配对 PASS。P1 的 STATS_ONLY 也没有可核对的保存 WAV。需要配对时只使用实际已有字段和覆盖，缺失即 UNKNOWN。若主控要求每个阶段强制证明逐 20ms Native/PCM 同窗，则普通 A/B 现有出口存在缺口，应先 BLOCKED 并另审最小方案，不能通过改为 4 秒预热或新增见证器暗中补齐。[现有评分初始化](../../../apps/macos/Aftelle/AppController.swift#L8262) · [短窗出口](../../../apps/macos/Aftelle/AppController.swift#L8930)

## 6. P2 · 真人独讲 Human-only ON/OFF 配对

P1 经主控接受后，另行批准两臂。完整继承 P0 §7.2～7.4，**固定 ON→OFF，两臂各一次、各最多 15 秒，合计 30 秒**。P1＋P2 累计上限 45 秒，其中真人最多 30 秒。

| 项目 | 两臂共同条件与唯一处理变量 |
|---|---|
| 入口 | `Prepare B · Human only`，comprehensiveC=false，RECORDING，普通原入口 |
| AGC | 第一臂 APPLE_VP_AGC_ON / actual=true，第二臂 APPLE_VP_AGC_OFF / actual=false。双端 VP 保持开启，bypass/mute=false |
| 生命周期/预热 | 同一固定构建，每臂独立 App/Engine，完整清理。两臂 W=0，含义为不增加有意等待，看到 phase=running 后自然开始。实际首 Input、界面显示、真人起音间隔分别保留，不能写作实测 0ms |
| 真人条件 | 同设备、位置、距离、朝向、自然音量及提示方法。沿 P0 原公开测试句完整自然说一次，约 5 秒内结束，随后安静。实际发声/改词/起止与计划分别由用户确认，原句或转写不公开 |
| 居民/Output | 不选居民、不准备或播放 Output。Playback generation、Player.play、非零 Render 为 N/A |
| 录音及审核 | 原 24kHz Mono PCM16LE、20ms 包、每臂 15 秒/720000 bytes 上限，独立 JSON/WAV。用户每臂先确认实际完整发声，再试听首尾、内容可懂度、消音、突增/变小、失真。Codex 新音频读取和有限分析须另获对应授权 |
| 尾覆盖 | 最后有效语句须在至少 1 秒已 drain 内容覆盖之前结束。实际覆盖不足标 PARTIAL，queued/Converter partial tail 保留，不补造音频 |

每臂技术资格通过，用户确认保存语句首尾完整、可懂且无异常抑制/剧变，才可记该臂有限人声观察 PASS。用户明确缺字、异常消音、强失真或无法听清为 FAIL，根因另记 UNKNOWN。未确认实际原句、声音起止、听感或关键覆盖则 INCONCLUSIVE/PARTIAL。

配对仅在同构建、设备、实际格式/模式与 AGC 读回可比、自然发声及时间证据具备有限可比性时判读。ON 异常而 OFF 改善可支持 AGC 参与的假设，顺序效应、自然重读、声压与 VP 内部状态仍是限制。两臂正常记本次 NOT_REPRODUCED。两臂异常表示关闭 AGC 未足以解决本例。格式/Mode/声源起止不可比则 `COMPARISON_LIMITED / INCONCLUSIVE`。

第一臂出现预登记的轻微声学失败时，保留该结果。只有事前主控批准明确覆盖配对、技术资格有效且用户另确认 OFF 就绪，才可继续第二臂。强烈失真、权限、配置、连续性或取消触发共用停止规则。P2 的任何结果均不自动进入 P3。

## 7. P3 · 居民纯回声与起音

**后续候选，须单独批准后才生效。** 最小建议为普通 `Prepare A · Resident only`，AGC-ON、双端 VP 开启，warm-up=nil、不新增等待，一次 Capture / 一次原固定居民播放，计划最多 15 秒。该时间策略沿普通 A，不能悄悄替换为 M20 的 4＋15 秒批次。

- 素材为原 24kHz Mono PCM16LE、114032 帧、4.751333 秒居民 WAV，SHA-256 `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`，包含 1 秒零前导。许可包括本次居民实际外放、麦克风、录音/本地导出及单独的试听/分析。
- 真人保持静默，用户需对本轮 Mac 内置扬声器实际发声作现场见证。只确认远程听闻或无法绑定该 Run 时，物理发声仍 UNVERIFIED。
- 保存既有 Player 调用、非零 Render 内容范围、完整格式/设备、Native/PCM 统计、包时钟、短促突发、首尾和 quiet 覆盖。用户分别报告可辨居民回声、起音类别/影响、播放尾部及异常。数字统计与听感各自登记。
- 软件时刻、匹配候选偏移及公开 PresentationLatency 不当作实测物理传播延迟。普通 A 的现有证据未满足冻结 M20 输入协议时，自动评分资格 INCONCLUSIVE，不能修改验证器或阈值来适配。

同 Run 技术通过、现场外放明确、用户听音无可辨居民残留且明确接受起音/尾部，最多登记该次 A 的有限观察 PASS。清楚可辨居民残留、明显有害起音/尾音或强失真为 FAIL。起音性质或可接受性未定、外放未证、关键覆盖不足为 INCONCLUSIVE。单次 PASS 不满足跨运行稳定性或正式 53-A 的次数/场景合同，追加轮次须新的目的和授权。

## 8. P4 · 真人持续双讲

**后续候选，须单独批准。** 最小建议为原 `Prepare comprehensive C · Guided single run`，AGC-ON、nil warm-up、RECORDING，一次 Capture、一次居民播放、原 15 秒上限。原 0–3 真人、3–9 双讲引导、9–11 真人尾段、11–15 quiet 的软件分段继续使用，score+3 秒只表示播放请求。P3/P4 各一次 15 秒均是本报告候选，并未扩展 P0 的 45 秒预算。

真实用户自然持续讲话至停止提示，居民从同一路线实际外放，两源物理重叠超过 1 秒。记录用户是否现场听到居民、是否持续讲话并重叠、何时停止及其不确定度。软件 3–9 秒标签、TTS 1 秒零前导、Render 首非零及播放完成都不能代填物理双讲秒数。

复用原 JSON/WAV 及已有 Native/PCM 字段，用户试听确认真人可懂度、首尾和关键词是否保留，居民回声、短暂消音、突然增大/变小、爆音或断裂分别记录。没有可靠原文或逐词依据时完整性 UNKNOWN，不能以能量或 ASR 成功补足。关键语句须有可信共同内容覆盖，尾部或观测不足保持 PARTIAL。

技术资格通过、同 Run 的真实双讲见证充分、真人内容可懂且未报告缺失/错误抑制/异常增益，居民回声与起音也满足已批准的单次判据，最多记本次工程声学观察 PASS。明确人声损伤、可闻残留或异常增益为 FAIL。未证明物理重叠、未得到用户试听、语句或时间覆盖不充分则 INCONCLUSIVE，按共用规则停。

P4 属于 T3.2-A 声学观察。正式 53-C 的同 Runtime/Provider Session 连续样本、至少三次物理双讲和权威效果计数，仍按 T3.1-R2/原正式 Gate 保留。

## 9. 尚缺证据、参数冻结与主控裁定

| OPEN 项 | 尚缺什么 | 所属处理范围 |
|---|---|---|
| AEC 声学资格 | 同候选/Route 的实际居民外放见证、纯回声/真人/双讲中的可解释处理结果、起尾接受及跨运行稳定性的有限证据 | P3/P4 的独立方案及主控裁定，既有失败继续保留 |
| 真人保留/AGC 参与 | 当前候选实际 OFF 配置准入，以及同构建真实 Human-only ON/OFF 比较。原实际发声、可懂度和首尾证据不足 | 先 P1，再单独批准 P2 |
| R3-M01/起音 | 特定起音的实际声音、影响与用户/主控接受结论，不能套用其他 Run 的突发分类 | P3 单次观察，无法归属保持 OPEN |
| CLOCK | 历史 host/sample 偏差来源、首次异常原始时间戳有效性及影响 | 若未来触发则原安全停止并保全 bounded diagnostics，独立授权调查，不调容差 |
| SQ-M1 | Apple 处理结果与既有声学资格/活动接口的安全兼容、事实和 Runtime 权威边界，以及正式合同等价映射 | T3.3 安全验收、T3.4 正式开放、T3.5 Human Gate 的单独授权。P1～P4不能关闭 SQ-M1 |
| M31/输出参考边界 | 精确 Schedule→Tap 内容映射与 Apple 内部 AEC 参考真值仍未知，当前没有已验收的 M31 见证器 | 保持撤回，本次不立项新诊断 |
| 独立声场参照 | 现有设备未具备已验证独立参照，不能追溯恢复过去声压 | M29 路线已关闭，本方案不以新购设备或替代 Fake 声场作为前置 |

P0 继承的 P1/P2 次数、15 秒窗口、零素材 SHA、ON→OFF 顺序、W=0、独立生命周期、普通原入口及隐私条件已明确列出。当前代码支持普通 OFF＋STATS_ONLY/nil 组合，`WARMUP_0S`、`WARMUP_4S` 和后来的批次各有自己的合同。改变预热、模式、AGC顺序、时长、素材或场景需主控另批。现有界面未提供真人起音的精确物理锚，P2 的严格因果比较有限，不能为补齐这项证据自行加诊断。

**唯一推荐下一次授权项为 P1_OFF_STATS_ONLY_1X15S。** 主控需先审定本报告，再独立批准 P1 的源码/Build、目标设备只读预检、原零素材身份检查和一次真实采集/零值输出/统计 JSON 导出范围。用户该次明确同意和就绪后才执行。P2 两臂、P3、P4 及任何新音频读取、试听、公开提交均保留各自授权条件。当前 `NEXT_DEVICE_EXECUTION=NOT_AUTHORIZED`。

## 10. 本轮交付检查与状态

实际文件仅新增本报告并追加正式 README 当前索引。生产/测试/门禁、DR、既有报告及历史失败没有改动。Stage7 Forbidden Checklist 前后结论 PASS，六条红线未触碰，Runtime API、DR schema、Store、粒子/Intent、Provider、Owner、Engine、Tap、平台 target 与 Stage8 均无增量。原工程测试、构建与 Guard 沿用已接受证据，本轮设备运行和产品测试均为 NOT_RUN。

本轮 Git diff、授权文件范围、链接/数值引用与敏感文本核查结果由交付收据记录。预检收据 SHA-256 为 `933abbff392d8c29bfb38f1ff2029085fd441c588ae87c7007c56a1d154714fb`，原受保护状态在交付前后复核。本地空回滚点 `cf7ee5ebecbc47bd58ee34f5882e472af24aa0a9` 与任务基线 Git 树相同，最终文档 Commit 及 Push 三方身份由交付核验给出。

```ini
T3_2_A_OFFLINE_ENGINEERING=ACCEPTED
ACOUSTIC_READINESS_REVIEW=COMPLETED_REVIEW_PENDING
NEXT_DEVICE_PLAN=P1_OFF_STATS_ONLY_1X15S_PROPOSED
NEXT_DEVICE_EXECUTION=NOT_AUTHORIZED
DEVICE_RUNS=0
M31_WITHDRAWAL=COMPLETED_OFFLINE_VERIFIED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
SQ_M1=OPEN
R3_M01=OPEN
T3_2_A=BLOCKED
T3_2_B=NOT_AUTHORIZED
T3.3=NOT_STARTED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
PRODUCTION_DIFF=ZERO
```
