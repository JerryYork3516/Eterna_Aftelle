# Apple Voice Progress v1 · VP-A VP_OFF 时序修订后单次复验

日期：2026-10-15。节点：Stage 7.5 / VP-A_VP_OFF_RERUN。

**最终裁定：VP_OFF_BLOCKED / EVIDENCE_UNVERIFIED。** 工程采集及封存有效，本次已取得最后非零数字Render结束后超过3秒的Input/Render内容，首次的数字末端短缺已补足；原2/8/3控制评分窗的精确跨域PCM归属仍未全部确证，不能据此宣布整项协议通过。没有评价Apple AEC，没有执行VP_ON或自动重试。

本报告独立于[08历史报告](08_vpa_vp_off_device_run.md)，不改首次VP_OFF数据或BLOCKED结论。修订依据为[07第14节](07_vpa_preparation.md#14-vp-a_timing_fix_preparationproposed定点时序修订)，本次用户任务明确授权其单次VP_OFF实施；manifest仍保留原PROPOSED协议文字，不擅自修改冻结工具。

## 1. Git、程序身份及授权

工作分支 `Apple-Voice-Progress-v1`。开始时HEAD、upstream和实时origin均为 `b25ce43fd6749bf6eadcb58de0ae981f1be2c414`，工作区干净；音频调用前再次检查HEAD/upstream及工作区。未修改任何源码、素材、设备登记或已有报告，未操作原ACE3工作区。

按该源码重新构建Release（warnings-as-errors）并固定实际可执行文件SHA-256、ad-hoc签名及启动宿主。`codesign --verify --strict`通过，Info.plist及麦克风说明沿用冻结版本。启动链为Codex执行工具→Python子进程→固定Release工具。实际manifest的build身份与固定文件相同；执行后文件SHA仍相同。程序身份、签名原文、路径及配置身份仅保存在Git之外私有记录，不沿用首次运行的旧二进制身份。系统为Mac mini M4、macOS 26.6.2（25G83）。

用户本次任务已明确授权一次修订后的VP_OFF真实外放、录音和私有分析；随后确认“以上条件均满足”，包括设备位置、音量、输入增益及Mic Mode未变、现场安静、其他采集程序关闭、全程不讲话。没有再次请求系统权限，固定程序查询结果为AUTHORIZED。

执行前已在聊天显示中文开始提示，留出3秒再运行唯一命令；结束后立即显示中文结束提示。提示发布有记录，但没有将发布时间当作用户阅读时刻或声学时间。用户录后确认“确认听到且可辨，无异常或现场变化”。本次现场扬声器可听辨性由此得到支持；没有追加播放、录音或自动试听。

## 2. 既有素材、登记及非音频准入

- 使用已批准的同一历史居民8秒素材，不重新裁剪、归一化、增强、调增益或调用Provider生成。批准loader和VPAMaterialSafety实际离线核验通过：16kHz、mono、Float32、128000frames；文件SHA及native PCM SHA与既有私有登记一致，也与本次manifest一致。非有限/越界样本均0，峰值0.687774658，满幅样本0。逐字内容、当前VoiceProfile等同性及Input语音可懂度不因此升级为已验证。
- 原registration文件及父目录为当前用户所有、非symlink、0600/0700；文件摘要、USB/Built-in匿名身份与上次最终preflight及manifest相符。没有新登记、复制替代登记、改内容或自动登记当前设备。
- 既有早期fixed-inputs计划还保留AWAITING_EXISTING_PATH状态；该计划不是最终登记有效性的依据。本次用原最终preflight、实际manifest及原registration交叉核验，未把早期计划状态伪装成已更新。临时离线核验助手初次因构建目录布局找不到模块，修正编译参数后通过；冻结工具源码未变，没有任何实体实验重试。
- 默认输入为既有USB设备，默认输出为内建扬声器；与原最终准入快照相同。默认设备nominal rate分别16kHz/48kHz，不将其冒充实际客户端格式。输入DeviceIsRunningSomewhere在运行前为0；已知Aftelle App未运行，用户确认其他采集程序关闭。存在已安装驱动/扩展不等于它们被选为默认设备或正在采集。
- 系统输出volume scalar前后均为0.7619839906692505，与首次记录一致；工具player/mixer volume均1。process级preferred/active Mic Mode均STANDARD，与既有记录一致；该属性对本Engine的完整归属仍UNVERIFIED。工具未修改系统音量、增益、Mic Mode、路由或设备位置；输入增益及物理位置/环境不变由用户确认，无独立仪器测量。
- 新私有目录与首次证据分离，Git之外，父目录0700、PCM/JSON及诊断文件0600；初始可用空间约7.61GB。首次VP_OFF及其他历史采集PCM没有读取、覆盖或合并，本轮音频读取仅限获准固定居民素材和本次新产生的容器；旧运行只读了已授权的关联元数据和分析脚本。

## 3. 唯一执行及Apple配置/生命周期

仅调用一次 `vp-a --authorize-vp-a --enable-audio --arm-diagnostics --mode VP_OFF --duration 16`。素材路径、双SHA及registration从已核验私有记录读取；命令完整参数只留私有attempt记录。不调用record/source-probe、Qwen、Runtime、HAL Gate或AEC3。

| 检查 | 本次实证 |
| --- | --- |
| 请求及实际VP状态 | VP_OFF；配置后、运行中及停止后双端enabled均false，bypass=false、inputMuted=false、AGC=false |
| 路由 | 默认USB输入/Built-in输出；两node呈现aggregate，原守卫给出AGGREGATE_IO_DIRECTION_QUALIFIED；未削弱或绕过守卫 |
| 路由稳定性 | route_before、running_route、post_stop_route完整快照相等；录后只读默认设备查询仍匹配 |
| 实际Input格式 | 48kHz、mono、Float32、非交错，formatFlags=41 |
| 实际mixer/output格式 | 44.1kHz、stereo、Float32、非交错，formatFlags=41 |
| 格式稳定性 | 配置后、运行中、停止后客户端格式一致；硬件侧格式核验无失败 |
| 播放与停止状态 | playerPlayingAfterRequest=true；runningEngineObserved=true，postStopEngineObserved=false |
| 配置通知 | 没有触发配置变化INVALID或诊断；原R2通知政策未过滤、未清除。没有独立通知计数器，不能声称穷尽所有异步通知时序 |
| 控制观测 | 18次，最大14.324292ms，低于原250ms观察预算；不是音频callback中执行 |
| 停止/封存 | 原单次cleanup及seal出口；一个进程、一个容器和seal，未重启。录后输入DeviceIsRunningSomewhere=0，支持设备已释放；在途callback/observer屏障没有独立全时序追踪 |

进程wall time为16.346871秒，包含arm之前的加载、配置、文件准备及最终封存；不能与16秒arm起admission混淆。arm至stopRequest为13.741910秒，在原上限内。外层超时保护未触发，退出码0只作进程状态，不作协议PASS。

## 4. 原控制窗口与四阶段时钟配对

以下均由保存的continuous原始tick和timebase计算，未借用录后新取的时钟偏移。

| 控制阶段 | arm起秒数/持续时间 |
| --- | ---: |
| quietStart | 0.176405625 |
| playRequest | 2.192972417 |
| plannedTailStart | 10.210002333 |
| postRollStart | 13.226871625 |
| postRollEnd | 13.741892417 |
| stopRequest | 13.741910333 |
| 实际quiet控制等待 | 2.016566792 |
| 实际play控制等待 | 8.017029917 |
| 原tail控制等待 | 3.016869292 |
| 独立post-roll控制等待 | 0.515020792 |

原参数仍2/8/3及独立0.5秒，等待略超是实际控制调度/检查结果，没有结果自适应延长或缩窗。post-roll不并入原3秒评分窗。

四对原始absolute-before / continuous / absolute-after tick和timebase完整留在私有manifest，顺序为beforeStart、playRequest、plannedTail、beforeStop。timebase均为125/3纳秒每tick；连续时钟及absolute顺序正常。为不公开整机原始时间状态，下表用D表示首对保存的C−A偏移tick，不公开其绝对数值。

| 配对 | 原始bracket宽tick | 局部偏移区间tick |
| --- | ---: | --- |
| beforeStart | 0 | [D,D] |
| playRequest | 1 | [D−1,D] |
| plannedTail | 0 | [D,D] |
| beforeStop | 1 | [D,D+1] |

0/1tick对应名义bracket宽0/41.666667ns；零tick反映计时量化，不能宣称物理误差为零。区间相交、未观察到偏移变化；manifest保持 `LOCAL_BRACKETS_ONLY_GLOBAL_MAPPING_UNVERIFIED`。局部范围不约束配对点之间的所有时刻，不拟合或假定全程恒定偏移，也不报告绝对声学到达时间。

## 5. 全部原生PCM、连续性及同域数字尾段

| 项目 | Input | Render |
| --- | ---: | ---: |
| 记录块数 | 135 | 135 |
| 每块实际frames | 4800 | 4410 |
| 总frames | 648000 | 595350 |
| 按frames/rate的实际时长 | 13.500000秒 | 13.500000秒 |
| sampleTime范围（右端不含） | [0,648000) | [0,595350) |
| 后续sampleTime断样 | 0 | 0 |
| 缺sampleTime/hostTime有效位 | 0/0 | 0/0 |
| continuityUnknown | 仅首块1次 | 仅首块1次 |
| 相邻host步进相对名义块长残差 | −4.083333至0µs | −10.083333至+13.625000µs |
| callback进入间隔 | 95.791917–106.829833ms | 95.822333–106.827458ms |

没有已保存样本内部断帧；微秒级host步进残差不直接改写为样本丢失，也不证明设备时钟/物理时刻精确。每块终点以保存的hostTime及native ASBD sampleRate插值；工具没有另存AVAudioTime.sampleRate，该限制保留。sampleTime同从0开始不是两流同步证明。

以首条Render raw hostTime为零，全部声道逐样本精确检查 `sample != 0`，不设幅度阈值、不挑较大声道、不trim自然零样本。两路Render逐位相同，因此不是两路独立音频证据。

| 同一absolute hostTime域的数字事件 | 秒 |
| --- | ---: |
| Input首块起点 | −0.025770375 |
| Render首块起点 | 0 |
| Render首个非零样本起点 | 2.112178088 |
| Render最后非零样本起点 | 10.049850723 |
| Render最后非零样本结束边界 | 10.049873399 |
| Input末块名义内容终点 | 13.474127208 |
| Render末块名义内容终点 | 13.499906500 |
| 最后非零Render结束后的Input覆盖 | **3.424253810** |
| 最后非零Render结束后的Render覆盖 | **3.450033101** |

最后非零为Render全局frame443202（含），结束边界443203（不含），位于从0编号第100块、块内frame2202。以上后窗结果不依赖absolute/continuous转换，分别超过3秒约424.254/450.033ms。**DIGITAL_POST_RENDER_TAIL_COVERAGE_SUPPORTED**：首次同域复核发现的数字末端不足本次未再出现。

该数字证据不是扬声器声压或实际声学尾响时间。首末非零跨度不等于完整8秒素材映射；原素材自然零样本保留，没有拿非零范围替换预登记窗口。用户听到约8秒居民语音与Render非零相互支持实际外放，不构成逐源frame渲染证明。

## 6. 原评分窗、post-roll与残留描述的证据边界

为检视控制窗，只将四个**已观察**局部偏移范围的最小/最大端点构成描述性包络。以下换算明确依赖“待定位时刻偏移也在该包络内”的未证实条件；不将区间交集或录后单点当作全程精确映射，不把这些数值升级为无条件验收证据。

| 窗口 | 条件性描述与判定 |
| --- | --- |
| 原quiet控制窗 | Input有完整对应样本；Render起始约13.819917ms在已保存范围之前。已保存对应Render静默约2.002789秒、首个非零Render前2.112178秒均全零，支持安静前段，但不能把这段另选2秒替换原quiet起点以宣布原窗完整 |
| 原8秒play窗 | 两流有对应样本，固定素材身份、一次player请求、Render内容及用户听辨支持；精确源frame映射/声学起止仍UNVERIFIED |
| 原3秒tail窗 | 条件性换算显示完整控制尾窗结束后Input/Render仍各有约0.437481/0.463260秒；同域数字非零结束后也均超过3秒。支持末端余量有效，但原控制两边界的精确跨域PCM归属没有无条件证明 |
| 独立post-roll | 控制等待0.515021秒；条件性可选到Input约0.437479秒、Render约0.463243秒。在上述条件性映射下，距控制postRollEnd仍约有77.540/51.760ms未覆盖；是否属于Engine尚未交付的部分块仍未证实。它是诊断余量，不把它并入正式3秒，也不因其少于0.5秒单独认定原尾窗失败 |

**不能声明原2/8/3评分窗口全部满足**。尤其quietStart/postRollStart并没有自身absolute配对，四个阶段局部范围不足以无条件定位它们。后续若要求精确控制窗口的两流全覆盖，须由主控明确原静默窗的逐流覆盖含义及边界证据需求，再决定是否另立最小工程任务；本轮不补采、不改工具或重新选窗口。

全部原生声道的幅度统计如下，未归一化、重采样或下混：

| 声道 | 全程RMS | 绝对峰值 | 满幅 / 越1 / NaN、Inf |
| --- | ---: | ---: | --- |
| Input ch0 | 0.145696835 | 0.775923729 | 0 / 0 / 0 |
| Render ch0 | 0.048270075 | 0.499312758 | 0 / 0 / 0 |
| Render ch1 | 0.048270075 | 0.499312758 | 0 / 0 / 0 |

上述条件性窗口中的Input RMS约为：quiet 0.000095959、早期2秒0.173279、后期6秒0.191847、原控制tail 0.042234、post-roll可用段0.000203859。Render对应为0、0.059374、0.063489、0.006598、0（双声道相同）。这些只描述时间结构和残留，不是ERLE、物理SPL、声源身份或AEC有效性；原计划tail开始附近仍有数字Render非零，因此不把tail早段能量一概解释为房间尾响。没有试听本次Input，不宣称其中语音逐字可懂。

## 7. 容量、诊断及独立封存核验

共270条记录，PCM7354800bytes（约7.014MiB），诊断residentBytes=4473728（约4.266MiB），低于原64MiB/8MiB；arm起13.742秒低于16秒，未扩大60秒原硬限制。总进程RSS和Apple框架内部内存没有测量，不以recorder预算冒充总进程预算。

INVALID、lost、overflow、discarded、suppressed、pending均0；每流首块之外continuity未知/断样未发现，缺时间有效位0。无primary/secondary诊断，omittedSecondary=0。controlSealSucceeded、sealed及integrity VERIFIED均成立；固定Release独立 `verify` 返回container_complete=true、invalid_reasons=0、270records及相同PCM字节数。完整性核验后及分析后，prepared、manifest、容器和seal的文件内容身份均保持一致。

`coverageStatus=MINIMUM_STREAM_PRESENCE`、`timestampStatus=UNVERIFIED` 原样保留，未将程序exit0、windowsCompleted、postRollCompleted、sealed或isCompleteForReference改写为完整窗口PASS。原PCM及所有时间/声道记录仅本地保存，无私人设备摘要、素材双SHA、registration内容、原始日志或私有路径进入Git。

## 8. 三维复审与Stage 7边界

**TECHNICAL_REVIEW：ENGINEERING_VALID；数字后窗子项SUPPORTED，原控制窗归属UNVERIFIED。** VP_OFF确为双端disabled，既有aggregate结构守卫和格式核验通过，四个局部配对有效但未证明全程映射。没有据此认定USB唯一物理来源、Apple AEC成败或净算法增益。

**ENGINEERING_REVIEW：ENGINEERING_VALID。** 唯一一次生命周期、两流连续采集、预算、停止及独立封存观察通过；没有发现本次配置/路由/记录器失效。源码未变，Release本轮构建通过；Debug、231项非设备测试、Lint/Format/C11本轮未重复执行，其通过结果属于b25ce43冻结准备节点，不冒充本轮实机或物理证据。多属性快照非原子、observer在途屏障及精确停止时序的普遍保证仍未证。

**EVIDENCE_REVIEW：EVIDENCE_UNVERIFIED。** 私有容器完整、用户听到固定居民外放、最后非零Render之后两流均超过3秒已确认；完整原控制评分窗不能无条件确证，保持 **VP_OFF_BLOCKED**。这不是Apple AEC或本次数字尾段补足失败。独立审阅仅基于脱敏数值/方法复核，不冒充另一人重复读取私人PCM。

Stage7 Forbidden Checklist：**PASS**。

- 触碰六红线：无。仅新增本报告；是否改代码：否。
- Test2及此前节点、Qwen Realtime原生全双工、NativeSpeechProvider/Adapter、正式音频协议、RuntimeCore/授权/generation均未改。
- DR schema/fixture、Memory、Session、Studio、Provider、ACE3、正式Test3合同和既有07/08均未改；无新增平台target或Stage8工作。
- 原record/source-probe、AppleEngineDriver、NativePCMTap、C Recorder、VP配置及音频图未改；sourceQualificationGranted保持false，未授予正式声源资格、取消/clear权限。
- 只执行本次明确授权的一次VP_OFF；没有VP_ON、重试、调参、系统设置变化、另行试听、VP-B/C/D/E或正式Test3。
- 原ACE3工作区、SSD/quarantine未访问；除明确获准固定居民素材外，未访问其他历史私人PCM；未提交任何音频或私人身份。

## 9. 收口及主控待决项

本次足以交付“数字末端短缺已补足”的真实证据，不能把整体升级为VP_OFF_EVIDENCE_VALID。请主控分别审核原quiet逐流覆盖要求与原控制边界跨域证据是否充分；若严格要求仍未满足，另行批准最小工程方案。本轮不继续修改、不再采集、不进入VP_ON。

```text
VP_OFF engineering = ENGINEERING_VALID
VP_OFF digital post-render tail = SUPPORTED (>3 seconds, both streams)
VP_OFF overall = BLOCKED / EVIDENCE_UNVERIFIED
First VP_OFF historical result = BLOCKED (unchanged)
Speaker content audibility = CONFIRMED_BY_USER
USB unique physical source = UNVERIFIED
VP_ON = NOT_AUTHORIZED
Apple AEC = NOT_MEASURED
Test3 = BLOCKED
Test3.execution_authorized = false
```

只提交本脱敏报告，完成推送后停止，等待ChatGPT主控独立审核。
