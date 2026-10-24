# T3.2-A / M12-D1 · 诊断快照竞争与精确App退出修复

> 2026-10-24。OFFLINE_FIX=PASS；本轮单次A组技术流程已完成，原JSON/WAV导出成功、App正常退出。评分WAV为14.86秒，尾部覆盖PARTIAL；用户现场发声见证及试听PENDING，不宣布AEC声学PASS。第1–5节为实机前冻结记录，第6节为最终实际结果。

## 1. 身份与范围

起始HEAD/upstream/实时远端均为`a6ef72a0a10c72d38f5e095330a528b46c4950f4`；跨文件修改前回滚提交`a6e33a8`。继续使用干净隔离Worktree，原7个冲突、索引及未跟踪证据按登记摘要/stat保护。

仅修改`MacSpeechAudioCapture.swift`的DEBUG诊断快照读取及对应原Fake；新增可复现的精确PID原UI导出/退出脚本和最小离线选择测试。本轮未改`AppController.swift`任何门禁、音频Callback的更新逻辑、PCM、Converter、格式、拓扑、AGC/AEC/NS、RuntimeCore、Provider、正式Gate或时钟容差。

## 2. RED及最小修复

CONFIRMED_CODE_DEFECT：`MacSpeechNativeVoiceTiming.snapshot()`与回调update共用busy原子标记。原单次CAS在写入占用时返回nil；现有安全消费者将nil转为`runtime_diagnostics_unavailable`并停止。确定性Fixture由后台任务持有真实update标记，只有读者实际观察到竞争后的等待回调才释放写者，不依赖人工计时或循环碰运气。原获取逻辑下RED exit133，失败断言为`temporary snapshot contention must not fabricate unavailable evidence`。历史失败Run是否恰好由此触发仍HYPOTHESIS，不能反向填补未记录的失败瞬间。

修复只改变非实时snapshot获取：最多20次CAS尝试、5ms单调时间预算，尝试间隔250μs；正常无竞争仍一次成功。只在取得同一标记后复制当时完整状态，不使用旧快照缓存，不把nil或UNKNOWN判为合格。超过时间/次数预算、读时钟倒退、缺少诊断仍返回nil，由原门禁fail-closed。OS调度可能使实际调用墙钟耗时超过请求的睡眠间隔，故5ms是检查预算，不宣称硬实时期限。

实时更新仍一次CAS、失败有界计数、无等待；通知丢失仍UNKNOWN，配置变化、RunID/generation/configurationID、设备资格、VP/AGC和Stop检查均未放宽。等待发生在原控制快照路径释放lifecycleLock后，没有在音频/通知回调增加等待、HAL查询、文件I/O、动态扩容或逐帧日志。测试专用hold方法只被Fake调用，位于原DEBUG类型内。

## 3. 精确PID退出修复

新增`tools/reference_host_comparison/finish_host_original_ui.applescript`，保留原封存状态检查及JSON/WAV导出确认。它始终按unix PID查找进程；退出前核对进程名Aftelle，必须唯一匹配名为Aftelle的菜单，再唯一匹配`Quit Aftelle`、`退出Aftelle`或`退出 Aftelle`。缺失、重复或disabled均报错，不回退到Apple系统菜单、菜单位置1、前缀匹配、全局Cmd-Q或另一个App。回执记录实际选中的完整Quit标题。

离线直接加载编译后的生产AppleScript，仅调用纯exactIndex处理程序，未执行UI run handler。7项Fake验证Apple菜单在前/换序、App菜单缺失/重复、三种精确Quit标题、退出登录/其他App/Force Quit、部分名称和大小写、重复Quit及PID/原导出门禁结构。原不安全私有脚本及历史证据原样保留，禁止后续复用。

## 4. 实际验证

| 检查 | 结果 |
|---|---|
| RED现有`check.sh m03-only` | 1轮，exit133，编译成功后命中预期失败断言 |
| GREEN同入口 | 29 cases / 514 checks，exit0；原M12门禁4/112、诊断8/72保留 |
| 最终样式收口后的定点复核 | 29/514，exit0；没有降低或删除断言 |
| 新负控 | 持续占用、5ms预算、固定时钟的20次上限、读时钟倒退均拒绝；配置通知/关闭观察仍可见；回调更新维持单次非阻塞行为 |
| PCM及内容时钟 | 复用原M12非零合成转换正负控，样本/顺序/时间及拒收结果不变 |
| AppleScript离线选择Fake | 7/7，exit0；原UI处理程序未执行，真实音频/设备0 |
| Debug构建 | 精确隔离project/DerivedData一次，exit0，16.977秒；未借用原冲突工作区或运行App |
| Release隔离 | Capture Release投影与基线逐字节相同；未重复Release全构建 |
| Release Route / Architecture / Secret Guard | 均exit0；最终交付再次核验新报告隐私 |
| 增量规范 | 变更行SwiftFormat/SwiftLint问题0，新增B类0；两受影响Swift文件既有233项format（exit1）、22项lint（exit2）与基线相同 |
| FULL_CURRENT / REF / 蓝牙 / 实机 | 离线阶段全部0次 |

完整命令、exit、RED断言及编译警告留本机。初次联合Python测试因缺少既有R3_BUNDLE环境在加载阶段exit1，未运行用例；改用本任务独立UI选择测试后7项通过。未改integration.py或R3身份逻辑。规范初检发现7项新增format问题，均局部更正后复核，没有格式化无关代码。

主程序SHA：`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`。

新Debug dylib SHA：`efaca216eaa35ceb150cc74273119d0781651cc064699af04c4c6e33f5d83466`。

## 5. 单次实机边界与审核

用户本次指令已明确授权：离线验证、Commit+Push、重新预检通过后直接执行一次M12-D1 A组，无需重复询问。本次另建独立同意及单次消耗记录，不复用旧R4或上次失败授权。预检必须再次核实默认TinyUSB60%、内置扬声器55%、权限/路由、素材及新构建身份；不自行改变音量、路由或Mic Mode，不操作新系统权限弹窗。

计划仅一次Capture及一次固定居民播放：4秒持续预热+15秒评分，score+3播放原居民；总预算19秒，评分PCM上限720000bytes，预热PCM不保存。复用原App确认、同RunID原JSON/WAV导出及安全清理；不启动BT、REF、B/C，不自动重试。产生有效本轮WAV才提供本机试听，不上传音频或私人Manifest。

五维SELF_REVIEW（离线）：身份PASS；确定性复现及修复PASS；实时/Release边界PASS；隐私和Git保护PASS；声学效果NOT_RUN。CRITICAL=0、MAJOR=0（本轮两个工程缺陷已有离线修复）、MINOR=1（历史规范债务）；实机兼容和AEC效果仍未验证。Stage7 Forbidden Checklist=PASS：无六红线触碰，无Runtime API、DR schema、平台target或Stage8变更。

```ini
SNAPSHOT_CONTENTION_OFFLINE_FIX=PASS
EXACT_PID_APP_QUIT_OFFLINE=PASS
DEVICE_RUNS_THIS_TASK=0
DEVICE_AUTHORIZATION=CURRENT_USER_EXPLICIT_SINGLE_A
PRECHECK=NOT_YET_RUN_AFTER_COMMIT
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```


## 6. 修复交付后的唯一一次M12-D1 A组

### 6.1 提交、预检与隐私准备

先完成离线修复提交并正常推送`d0f7d82b9ea6c9ace17d438437aa9dcef579014b`，核验HEAD/upstream/实时远端一致后才重新预检。源码及二进制与第4节冻结身份一致，按确切PID核验实际映射dylib；固定素材摘要不变，没有复用旧候选或删除身份校验。

默认输入TinyUSB60%、默认内置扬声器55%、未静音，物理设备身份与登记一致，开始前空闲，没有其他音频实验。未改设备配置、系统音量、路由或Mic Mode；权限沿原App流程通过，没有操作新系统权限弹窗。Mic Mode仍UNKNOWN。

初次递归Cache预检发现**一份旧控制回执**权限0644，位于当前用户的0700目录内，因此保留BLOCKED记录。仅对这一个登记项以O_RDONLY/O_NOFOLLOW打开后fchmod至0600，没有读取内容或调用写入；inode、大小、atime、mtime均不变，操作回执留本机。未修改任何历史WAV/PCM或原冲突工作区。重新预检后受控目录全部0700、文件0600，当前用户持有、无symlink，准入通过；没有降低权限要求以取得PASS。

### 6.2 实际次数与两份运行态快照

RunID：`EE7290CD-7CFE-4E8D-8CE6-14C499455A11`，generation=1、configurationID=2。App启动、原Start确认、实际Capture、居民播放、原JSON导出、原WAV导出各1次；BT、REF、B/C、自动重试全部0。保留原可见同意和显式导出确认，不复用此前失败同意。

| 实际字段 | Engine启动后 | 居民Player.play后 |
|---|---|---|
| RunID / generation / configurationID | 当前Run / 1 / 2 | 当前Run / 1 / 2 |
| 进程PID前后核验、7项HAL查询 | 均匹配、CONFIRMED、OSStatus=0 | 均匹配、CONFIRMED、OSStatus=0 |
| 输入方向 | 2项，严格共享I/O集合元数据资格 | 同一集合、同一资格 |
| 输出方向 | 1项默认内置输出，原元数据资格 | 同一设备、同一资格 |
| Engine / VP Input / VP Output / AGC | 全部true | 全部true |
| bypass / inputMuted | false / false | false / false |
| 读回耗时 | 2.717375ms（进程查询1.534125ms） | 2.598709ms（进程查询1.346167ms） |
| 格式与图 | 六处格式及连接正常，见下文 | 与启动后相同 |

五处图内格式（Input输出、Player输出、Mixer播放器输入、Mixer输出、Output输入）均16kHz/3ch Float32非交错；硬件输出侧16kHz/2ch Float32非交错。Player→Mixer bus0及Mixer→Output连接存在。AU公开输入/输出deviceID仍均指向内置输出，顶层bindingStatus仍UNKNOWN_UNVERIFIED_BINDING；进程方向集合资格不能升级成物理输入唯一来源或Apple内部AEC参考的证明。没有Aggregate资格混淆或实际路由变化证据。

Engine配置通知count=0、skipped=0，封存后监听关闭；内部configurationChanged=2是生命周期计数，不是两次Engine通知。诊断读取期间没有HAL错误或诊断不可用。未新增快照重试次数仪表，因此**不能声称本次实机一定触发过竞争等待**；确认的是修复版本可完成原流程，确定性竞争本身由离线RED/GREEN证明。

### 6.3 时间、Native与实际保存WAV

- Player.play调用约score+3.055513秒，返回约+3.066667秒。Player Render首/末非零内容约+4.194916至+7.942577秒；它是Mixer前观测，不是物理扬声器起音或内部AEC参考。
- Native Input/Player Render各189个callback；Native共302400frames（18.9秒），16kHz/3ch。Input与Render的sample/host discontinuities、backwards、duplicate、missingTime均0；全部Native拒收、drop/stale/reject及route_changed均0。raw_timestamp_diagnostic=null，历史异常本次NOT_REPRODUCED，未宣布修复时钟根因。
- 计划4+15秒。Capture启动返回至captureStopped事件实际19.0058595秒，比软件内容终点晚5.8595ms；这是控制路径Stop事件的测量值，不能声称物理麦克风恰好在19.000秒内关闭。观察到的Native内容18.9秒，未额外启动采集或扩展评分窗口；尾差独立登记，未改时钟容差。
- generated=944、drained=944、queued=0。其中预热199包未保留，跨边界1包、窗口外1包排除，实际评分留存743包/713280bytes。计数闭合，预热留存0bytes，未补零、未伪造覆盖或将drained统计冒充WAV。
- WAV为24kHz/Mono/PCM16LE，356640samples、14.86秒、713324bytes。实际内容覆盖score+0.012847至+14.872847秒；连续序号202–944，包内容时间间隔全部20ms。尾部与评分整体覆盖PARTIAL，Converter partial tail UNKNOWN，720000byte上限未变。

以下PCM只统计**实际WAV**，由原包内容时间映射回评分窗口；Native使用同Run原分窗统计，编码按满幅1统一。A组没有真人，保留旧统计字段名称不等于发生双讲。

| score窗口 | Native ch0 RMS / Peak（dBFS） | 实际WAV RMS / Peak（dBFS） |
|---|---:|---:|
| 预热 | -84.76 / -64.80 | 不保存 |
| 0–3 | -85.34 / -64.91 | -85.44 / -65.20（起点PARTIAL） |
| 3–9 | -72.95 / -42.09 | -72.96 / -42.11 |
| 9–11 | -73.75 / -60.25 | -73.77 / -59.94 |
| 11–15 | -74.00 / -59.63（尾部PARTIAL） | -74.02 / -59.68（尾部PARTIAL） |

三声道在已登记各窗的全部有限样本逐样本等于ch0；边界外119frames不在该相等性证据内，不解释Apple内部物理声道含义。各声道满幅、超幅、非有限均0；WAV精确端点0。整体WAV RMS -74.32dBFS、Peak -42.11dBFS。固定4–7.75秒窗RMS -76.15dBFS、Peak -43.15dBFS；实际非零Render对应窗约-76.12dBFS。Native与PCM同窗大幅度一致，未显示后级转换的大窗能量损伤。

最大20ms RMS相邻上升约20.65dB，发生在score+4.352847秒；整体绝对峰值仍仅-42.11dBFS。底噪附近的相对变化不能定为AGC BUG、过大声压或可听爆音。没有VP前原音，未计算或声称ERLE。相比此前主控登记M03/M09高能量A，此次能量明显更低，但没有因此解释运行间AEC差异，未重新读取历史录音。

### 6.4 原UI退出、文件身份与结果边界

修正后的脚本实际回执为`APP_QUIT_MENU_SELECTED=退出 Aftelle`，唯一匹配确切PID的Aftelle菜单；原JSON/WAV导出均经原确认。控制器exit0，App操作系统exit0，PID消失；默认设备/物理身份、音量和静音状态前后一致，设备running=0。没有按App名称启动其他实例或执行系统退出登录。本次控制总耗时60.541秒含UI准备、导出和退出，不能作录音时长。

| 本机文件 | bytes | SHA-256 |
|---|---:|---|
| 原JSON | 90707 | `e34387be42fb399b1cb115e377e6b4f72ee477171342786b8a2d0dfaf9f810f2` |
| 原评分WAV | 713324 | `f10e3646f04767bb2bcd910e90e357adb3c55bfac41ac3c5ce92edca29957e53` |

仅在本机有限读取本次新WAV及对应元数据，无转录、无播放第二次居民、无音频上传。已将本次WAV提供本机试听，并询问“现场是否确实发声”“WAV能否听到居民及有无异常”；尚未获得本轮反馈，USER_LISTENING=PENDING、PHYSICAL_SPEAKER_WITNESS=PENDING。不能以数值分析冒充试听或声学PASS。

原136项Cache条目stat保持本次收紧权限后的预检基线不变；新增仅本轮控制结果、原JSON及WAV，目录0700、文件0600。原7个冲突、索引、HEAD、冲突文件内容及14项未跟踪stat不变。Git仅提交脱敏报告及已提交的最小修复/测试，不提交录音、私人Manifest、UID或完整日志。

CONFIRMED：确定性竞争路径及离线修复、精确Quit修复、本次两份运行态读回与技术流程、PCM计数/连续性、进程正常退出及设备释放。HYPOTHESIS：此前诊断不可用正由快照竞争触发；本次低残留可能与系统处理状态有关。UNKNOWN：Apple内部AEC参考、历史AEC差异根因、历史时钟根因及本次用户听感。

最终五维SELF_REVIEW：身份PASS；离线复现/回归PASS；单次技术流程PASS_WITH_PARTIAL_SCORE_COVERAGE；隐私/清理/原冲突保护PASS；声学裁定PENDING。CRITICAL=0、MAJOR=0（仅本轮工程修复）、MINOR=2（既有规范债务；评分尾部及Stop调度尾差）。不能把此分级当成T3.2-A声学验收通过。Stage7 Forbidden Checklist=PASS，正式阶段状态不变。

唯一下一项：主控结合本次WAV、两份运行态快照和用户现场/试听反馈审核；本轮结束，不自动追加实验或修改DSP。

```ini
SNAPSHOT_CONTENTION_OFFLINE_FIX=PASS
EXACT_PID_APP_QUIT_DEVICE=CONFIRMED_THIS_RUN
M12_D1_TECHNICAL_EXECUTION=COMPLETED
DEVICE_RUNS_THIS_TASK=1
RESIDENT_PLAYBACK=1
JSON_EXPORT=1
WAV_EXPORT=1
AUTOMATIC_RETRIES=0
SCORE_COVERAGE=PARTIAL
USER_LISTENING=PENDING
PHYSICAL_SPEAKER_WITNESS=PENDING
CLOCK_ANOMALY_THIS_RUN=NOT_REPRODUCED
NEXT_DEVICE_RUN=NOT_AUTHORIZED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
