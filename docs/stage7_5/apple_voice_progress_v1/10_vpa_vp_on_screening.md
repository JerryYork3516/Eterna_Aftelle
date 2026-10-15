# Apple Voice Progress v1 · VP-A VP_ON 研究初筛

日期：2026-10-15。阶段：Stage 7.5 / VP-A_ON_RESEARCH_SCREENING。

**最终裁定：EVIDENCE_UNVERIFIED（声学结论）。** 唯一一次VP_ON正常启动、播放、采集、停止及封存；原2/8/3秒控制窗口取得双流数字样本跨度证据。播放段Input幅度较09历史VP_OFF低，具有继续研究的线索，但本次quiet段存在明显、未解释的输入信号，且两臂格式、AGC、输出处理和工具时序版本不同，不能据此宣布Apple AEC成功。本报告不改写08/09的BLOCKED结论，不执行VP_OFF、重试或VP-B/C。

## 1. Git、程序身份与现场授权

- 分支 `Apple-Voice-Progress-v1`；执行前HEAD、upstream及实时origin均为 `dd0c95218903c1f1b59d7c4c6467f93352da07f0`，工作区干净。
- 只按该基线构建Release，构建成功、warnings-as-errors；固定可执行文件SHA-256、ad-hoc签名及启动宿主，严格签名验证通过。实际运行前后文件身份一致；具体二进制摘要和启动记录保留在Git之外。两臂不是同一时序版本的可执行文件：09基于此前冻结版本，本次基于已批准的双流预热/六阶段配对版本。
- 已有262项非设备检查结果由已审核基线继承，**本轮未重跑**，也未修改源码、重签或在实际运行中更换程序。不把历史测试或Release构建替代设备证据。
- 完成准入后申请本次专门现场授权；用户明确回复“明确授权，现场条件均满足”。授权仅一次VP_ON外放、麦克风采集及本次私有离线分析。实际调用一次、无自动重试、无新VP_OFF。
- 开始前及结束后均给出中文文本提示。初稿提交时，本次结束后的现场确认尚未收到；随后用户明确回复“确认听到且可辨，无异常或现场变化”。本次约8秒居民外放可听辨性现为 **CONTENT_VERIFIED_BY_USER**，不是借用09的确认；现场无变化仅为用户确认，不替代独立声学测量或处理后Input听辨。

## 2. 素材、设备及非音频准入

复用原P4有效登记，未重新登记、覆盖登记或自动选择当前任意默认设备。既有文件仍由当前用户所有、私有父目录0700/文件0600、非symlink；设备目标和文件身份校验通过。登记及设备身份未进入本报告。

复用原历史居民素材，文件与解码native PCM双身份匹配；16kHz、mono、Float32、128000 frames、8秒，未裁剪、归一化、调增益或更换音色。非实时安全检查：峰值0.687774658，NaN/Inf、绝对值超过1、恰好满幅样本均0。逐字内容及与当前VoiceProfile的一致性仍UNVERIFIED。

| 准入/前后交叉核验 | 结果与限制 |
| --- | --- |
| 麦克风权限 | AUTHORIZED；未申请权限、修改TCC或点击系统弹窗 |
| 登记默认路由 | 目标USB输入、Built-in输出；运行前、运行中、停止后快照稳定；结束后非Engine元数据查询再次一致 |
| nominal sampleRate | USB 16kHz、Built-in 48kHz；不等同于VP客户端或最终硬件输出格式 |
| 系统输出volume scalar | 0.7619839906692505，前后及09记录一致；player/mixer volume均1 |
| Mic Mode | process级preferred/active均STANDARD，前后及09记录一致；对本Engine的完整归属仍UNVERIFIED |
| 设备使用 | 开始前和结束后的USB device-is-running-somewhere均0；无已知Aftelle运行；其他采集程序关闭、增益/物理位置/环境不变由用户在准入时确认 |
| 私有磁盘 | 开始时可用7,383,732,224 bytes，足够既有证据预算 |

同一系统音量数值不能证明相同声压、硬件增益、空气传播、房间噪声或跨日环境。本轮未改变音量、增益、设备位置、采样率或Mic Mode；未加入独立声压计或额外输入来源校验。

## 3. 实际执行、Apple状态及生命周期

仅调用既有 `vp-a` 一次：显式专用授权、音频及诊断开关，VP_ON，16秒admission。未连接Qwen、Provider、Runtime或Aftelle正式音频链。

| 项目 | 观察结果 |
| --- | --- |
| 模式与VP状态 | VP_ON；配置后、运行中及停止后input/output enabled均true；bypass=false、inputMuted=false；AGC=true、可读取 |
| 接图前后格式 | 启用VP后Input为16kHz/3ch；接图前mixer/output为44.1kHz/2ch，接图后及运行/停止快照均16kHz/3ch；属于已记录的配置协商，不冒充运行中格式突变 |
| 原生Input/Render | 均16kHz、3ch、Float32、noninterleaved；formatFlags=41、每plane每frame 4 bytes |
| outputNode硬件侧格式 | 配置后、运行中及停止后均16kHz/2ch Float32；与客户端3ch及设备nominal 48kHz分别记录，不混称同一格式 |
| deviceID呈现 | 两个node仍呈现Built-in输出，node input不等于登记默认USB输入；普通结构绑定状态UNAVAILABLE |
| 研究准入 | 仅使用已批准VP-A研究政策：登记默认USB/Built-in稳定、两个node呈现登记Built-in、无未知aggregate；普通record守卫未改变 |
| 来源与资格 | `SOURCE_UNVERIFIED`；`sourceQualificationGranted=false`；不能升级为唯一USB物理来源确认 |
| 启动/播放/停止 | Engine运行状态已观察为true，单次play请求后playerPlaying=true；停止后Engine状态false |
| 控制观察 | 20次完整观察，单次最大4.249042ms，未超过既有250ms预算；不声称getter可抢占或覆盖全部瞬时时序 |
| 配置通知 | 未见导致INVALID的ConfigurationChange；没有独立通知总数，不能据此证明系统绝不发通知或所有异步TOCTOU均消失 |
| 终态 | 进程exit0，`SEALED_EVIDENCE`；无主/次阶段错误或省略错误；停止、移除Tap/监听及一次seal走既有路径，未重启掩盖异常 |

停止后设备元数据未见仍运行或路由改变，支持本次资源释放；没有独立系统级资源泄漏证明。exit0及生命周期标记均不是声学PASS。

## 4. 预热、控制窗口与六阶段局部时钟

双流预热完成：Input/Render均已有1条有效记录，然后才建立quietStart，未缩短原静默。arm至quietStart为0.316680秒；arm至停止请求为13.840726秒，未超16秒。

| 实际控制阶段 | 时长（秒） | 说明 |
| --- | ---: | --- |
| quietStart → playRequest | 2.006061 | 原2秒静默窗口，预热不计入 |
| playRequest → plannedTailStart | 8.007652 | 原8秒播放观察；不等于实测扬声器起止 |
| plannedTailStart → postRollStart | 3.003397 | 原3秒尾窗，未重选或缩短 |
| postRollStart → 正常停止边界 | 0.506905 | 固定0.5秒诊断post-roll，独立、非评分 |

六阶段 `beforeStart / quietStart / playRequest / plannedTail / postRollStart / beforeStop` 均有原始absolute/continuous tick、timebase及本地bracket。timebase为125/3 ns/tick，bracket宽依次为1/1/0/1/0/1 tick；0 tick只反映量化，不是物理零误差。保留原始时钟，不假设全程恒定跨域偏移，状态为 `EVENT_LOCAL_BRACKETS_GLOBAL_MAPPING_NOT_USED`。

**独立原始记录交叉核验：** 将manifest引用的全局recordIndex逐一对应容器中的真实stream、sampleTime、hostTime，再核对事件局部absolute外边界被前后host锚点包围及连续sample跨度。未以控制窗口结束、计数非零或sealed代替覆盖。

| 窗口 | Input/Render连续锚点跨度 | 双流覆盖结论 |
| --- | --- | --- |
| 原quiet | 各33600 frames / 2.1秒 | 覆盖原事件局部外边界；最短时长检查满足2秒 |
| 原play | 各129600 frames / 8.1秒 | 覆盖原事件局部外边界；最短时长检查满足8秒 |
| 原tail | 各49600 frames / 3.1秒 | 覆盖原事件局部外边界；最短时长检查满足3秒 |
| 可选post-roll | 没有足以包围结束边界的后续记录起点锚 | `covered=false`，不声称完整0.5秒双流交付；不加入原tail评分 |

因此本次原评分窗为 **DIGITAL_SAMPLE_SPAN_COVERED**。跨度包含边界外的buffer锚点，表中2.1/8.1/3.1秒不是扩大的评分窗口。它证明连续数字序列包围控制窗口，不证明逐样本物理声学时间、输出延迟或声压。Input可用post-roll名义样本约0.412563秒，Render约0.506938秒；有限callback批量和末端缺少锚点如实保留，不宣称所有诊断末端都已覆盖。

## 5. 原生PCM、时间与封存

| 项目 | Input | Render |
| --- | ---: | ---: |
| 记录数 / 每条frames | 136 / 1600 | 136 / 1600 |
| 总frames / frame时长 | 217600 / 13.6秒 | 217600 / 13.6秒 |
| sampleTime起点 / 末端exclusive | 648 / 218248 | 1204 / 218804 |
| 缺失sampleTime / hostTime | 0 / 0 | 0 / 0 |
| sampleTime不连续 | 0 | 0 |
| continuityUnknown | 首条1次 | 首条1次 |
| 相邻hostTime步进减名义buffer时长 | −6.208333至+1.208333µs | −6.250000至+1.458333µs |
| callback间距 | 90.710458至128.929917ms | 94.748542至128.011000ms |

没有将callback约100ms批量当作断样，也未据名义采样率抹掉原始hostTime微小差异。实际完整保存13.6秒PCM，不能冒称16秒录音。

- Input三个原生声道逐样本bitwise完全一致，仅提供一份重复信息；均保留，不猜测其内部mic/reference角色。
- Render ch0有信号，ch1/ch2全部为0；这不是三路独立播放。保留全部声道，不选择最大声道冒充输入来源或物理声压。
- Render ch0峰值与素材峰值相同、非零样本数116511，且player请求和状态存在，支持数字播放路径确有非零输出；没有因此宣称已证明逐frame素材映射或真实扬声器声压。
- 同一原始hostTime域内，最后非零Render样本结束后，Input/Render名义有效数字尾段分别为3.293225/3.391974秒，均大于3秒；这是数字Render结束，非实测房间声压归零。
- 最后非零Render结束比plannedTailStart晚约0.122734秒，因此原tail开头仍含数字播放；其能量不能全部称为房间尾响。

封存：272条记录、Input+Render PCM 5,222,400 bytes；诊断常驻预算记录4,473,728 bytes，低于64MiB/8MiB，16秒更严格admission未超。此数字不是AVFoundation或整个进程RSS；框架/总进程内存及高频getter内部开销未单独测量。

lost、overflow、discarded、suppressed、pending、缺失时间及INVALID原因计数均0。sealed=true、controlSealSucceeded=true、integrity=VERIFIED。固定Release独立verify返回容器完整、272条/5,222,400 bytes、invalid_reasons=0；离线分析前后四个原始证据文件身份未变。原通用字段 `coverageStatus=MINIMUM_STREAM_PRESENCE / timestampStatus=UNVERIFIED` 原样保留，新增VPA窗口证明不覆盖或改写它们。

## 6. 全声道幅度与quiet异常

离线读取本次授权容器全部原生Float32声道，未下混、归一化、增强、裁剪或覆盖原始数据。统计RMS为数字样本均方根，不是SPL、语音身份或AEC净增益。全部声道NaN/Inf、绝对值超过1及恰好满幅均0。

| 全程声道 | RMS | 绝对峰值 | 非零样本数 |
| --- | ---: | ---: | ---: |
| Input ch0 / ch1 / ch2（各） | 0.036242432 | 0.668304503 | 216773 |
| Render ch0 | 0.068164370 | 0.687774658 | 116511 |
| Render ch1 / ch2（各） | 0 | 0 | 0 |

下表使用事件局部absolute内边界、buffer原始hostTime及native sampleRate进行buffer内名义插值；不是单个录后跨域偏移。early为从playRequest起算的最初2秒，late为随后6秒，均事前定义，未选取较安静片段替代原窗。边界量化和host微差会造成约1 frame选择差异，不当作丢帧或动态改窗。

| 本次预定义观察窗 | Input各声道RMS | Render ch0 RMS | 解释 |
| --- | ---: | ---: | --- |
| quiet | 0.090898769 | 0 | 有明显的播放前数字输入信号，原因未确认 |
| full play | 0.005798786 | 0.088249081 | Input非零，尚无本次Input听辨结论 |
| early 2秒 | 0.007676580 | 0.081621582 | 不能单凭数值确定自适应状态 |
| late 6秒 | 0.005023354 | 0.090403543 | 较低幅度；不等于已证明稳定或近端无损 |
| 原tail | 0.000288835 | 0.016596165 | 前约123ms仍可能有数字Render内容 |
| post-roll可用样本 | 0.000321397 | 0 | 仅诊断，不补入评分 |

**quiet异常必须保留。** 以首个Render hostTime为0，quietStart约0.071486秒、playRequest约2.077547秒、首个非零Render约2.272174秒。Input从0.001至0.50秒的多条100ms记录RMS约0.112–0.214，之后仍有衰减信号；约1.2–1.7秒降低至0.0001–0.0002后，约1.801/1.901秒两条记录又出现RMS 0.089067/0.015844。这不是只有一个初始buffer的孤立数值；整个原quiet保持在统计中，未删除瞬态、延后quiet或重跑。

上述信号先于本工具居民Render非零，不能全部解释为本次居民扬声器回声。启动处理/AGC、环境或其他声源、输入路径/来源问题均为 **HYPOTHESIS**；不能从幅度或三声道重复判定原因，也不能证明背景实际稳定。没有确认具体工程缺陷，故不修改工具或守卫；声学归因保持UNVERIFIED。

## 7. 与09历史VP_OFF的有限描述性比较

仅引用冻结09的公开统计和此前登记元数据，**本轮未读取或重新分析09的私人PCM**，未追溯改写VP_OFF_BLOCKED。两次观察窗的early/late/tail定义相同，但09采用其当时条件性时间映射，本次采用六个事件局部bracket；不伪称严格同一时钟测量方法。

| 原生数字RMS（每有效声道） | 09历史VP_OFF Input | 本次VP_ON Input |
| --- | ---: | ---: |
| 全程 | 0.145696835 | 0.036242432 |
| quiet | 0.000095959 | 0.090898769 |
| early 2秒 | 0.173279 | 0.007676580 |
| late 6秒 | 0.191847 | 0.005023354 |
| 原tail | 0.042234 | 0.000288835 |

这是一张原生格式数值并列记录，**不能直接作为同带宽、同增益、同物理声压的配对测量**，不计算两臂相除、dB抑制量或ERLE。具体混杂因素包括：

- OFF Input为48kHz/mono、AGC=false，本次为16kHz/3ch重复、AGC=true；Apple VP整体还可能包含其他处理，不是单独开关AEC算法。
- OFF Render为44.1kHz/stereo两路相同，本次为16kHz/3ch且仅ch0非零；全程Render RMS分别为0.048270075/0.068164370、峰值0.499312758/0.687774658，不能认为实际外放能量完全相等。
- 原素材、登记和音量数值一致，仍无跨轮SPL/房间噪声/硬件增益独立校准；两轮工具时序版本不同，09原评分窗证据仍UNVERIFIED。
- 本次quiet异常与历史安静段明显不同；它不能被播放期低幅度掩盖，也不能被解释成AEC收益。

**A．回声抑制初筛：** 播放期较低数字幅度与有限回声抑制假设相容，值得研究；尚不足以独立确认实际居民回声被正确抑制。没有试听本次处理后Input，不声称残留居民语句可懂或不可懂。全零输入、数值削波和记录断流未见，但纯居民场景不能排除语音门控、来源问题或近端损伤；P4的历史真人采集支持不能替代本轮近端保留对照。

## 8. 三维复审、正式证据与下一步

**TECHNICAL_REVIEW：VP_ON_ENGINEERING_VALID；ACOUSTIC_ATTRIBUTION_UNVERIFIED。** 双端VP启用、原生格式、研究路由政策、真实数字播放/输入及正常停止已由本次记录支持。唯一USB物理来源、内部声道角色和quiet原因仍未知；不能把Apple VP整体变化等同纯AEC净效果。

**ENGINEERING_REVIEW：ENGINEERING_VALID。** 已观察的16秒预算、双流预热、原2/8/3控制窗、六阶段配对、连续PCM、一次生命周期、封存及独立verify成立；无确认的丢样、容量或配置失败。post-roll末端锚点不足单独披露，异步瞬时变化及系统资源完全释放不作过度保证。未确认需要代码修复的缺陷。

**EVIDENCE_REVIEW：数字记录与原评分跨度EVIDENCE_VALID；声学结论EVIDENCE_UNVERIFIED。**

**B．正式VP-A协议证据：** 原2/8/3数字双流覆盖本轮已建立；这与09原窗未确证是不同结论。实际外放可听辨且无异常/现场变化已由用户在本次结束后确认；quiet异常原因仍未明，不能因现场未听到异常就忽略数字记录，且缺少独立声压及物理来源真值，故不能宣布整项声学协议通过或Apple AEC PASS。

**C．是否建议继续VP-B：** 有条件建议主控评估一个独立近端保留研究协议，以区分有用处理和近端损伤/来源问题；这比重复当前纯回声录音更有判别力。先复核本次quiet异常，并结合已收到的外放确认保留已知不确定因素，再由主控单独决定B的协议和现场授权。本轮不准备或执行B，不要求以重复Mock、改阈值、追加录音制造结论。

## 9. Stage7 Forbidden Checklist与隐私

| 范围 | 裁定及证据 |
| --- | --- |
| A：Stage范围 | PASS；仅macOS Stage 7.5独立声学研究，无新平台/Stage 8 |
| B/C：Runtime及Host | PASS；无Runtime/正式Host代码变化，无旁路正式授权 |
| D：DR/Runtime API | PASS；无schema、fixture、API或居民资产写入 |
| E：Provider/Secret | PASS；无Qwen/其他Provider、ASR或新模型调用，无密钥/设备身份公开 |
| F/G：状态/调度 | PASS；无Memory/Session/DR变更、无新后台调度或自动实验循环 |
| H：UI/音频边界 | PASS；Test2、原生全双工链、Driver、Tap、C Recorder、VP配置及音频图均未修改；未以独立研究替换正式架构 |
| ACE3及历史证据 | PASS；未操作原ACE3工作区、SSD/quarantine；07/08/09及P3/P4行为保持原样 |
| 设备授权 | PASS；唯一一次新授权VP_ON，无重试、无VP_OFF/B/C/D/E，无正式声源资格或cancel/clear |
| Git及隐私 | PASS；仅本10脱敏报告；PCM、原始日志、设备UID/身份摘要、素材摘要、登记、私有路径均留在Git之外 |

独立复审仅基于脱敏数值、方法和本报告，未冒充另一审阅者重复读取私人PCM。报告提交、推送与工程有效不等于主控声学验收。

```text
VP-A_ON Screening = EVIDENCE_UNVERIFIED
VP_ON engineering / digital original windows = VALID_BY_REPORTED_EVIDENCE
VP_OFF historical 09 = BLOCKED / EVIDENCE_UNVERIFIED (unchanged)
USB unique physical source = UNVERIFIED
Apple AEC PASS = NOT_ESTABLISHED
VP-B/C = NOT_AUTHORIZED
VP-D/E = BLOCKED
Test3 = BLOCKED
Test3.execution_authorized = false
```

完成本次单次运行及报告后停止，等待主控独立审核；不自动进入后续实验。
