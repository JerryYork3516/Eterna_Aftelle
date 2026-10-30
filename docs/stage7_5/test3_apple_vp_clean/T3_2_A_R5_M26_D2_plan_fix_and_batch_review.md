# T3.2-A / R5-M26-D2：计划合同修复及新批次审核

日期：2026-10-30（Asia/Shanghai）。**计划字段缺陷已修复；新批A完成采集、封存及正常退出，但因DEBUG时间观测缺口被拒绝技术准入，B未启动。A/B声学结论为INCONCLUSIVE。**

## 1. 修复与离线验证

用户本次明确要求“修复完直接执行”，授权修复验收后执行一个新的M26 A/B批次，不复用旧授权。开始时HEAD/upstream/实时远端为`57888c7deb7d5b200d15eca5a147c9a3509d7ec7`。跨文件修改前建立空回滚提交`ef84804`；修复提交为`56b46aaf1c10ef3aa7265336696b3e0935180a53`，先正常推送并核验三方HEAD后才建立新计划和启动设备。

| 本轮文件 | 变更 |
|---|---|
| `tools/reference_host_comparison/m26_channel_allocation.py` | `check_plan`新增3行：顶层`resident`必须为字符串，且与`files.resident.path`完全一致；在原共享安全核验之前拒绝错误字段 |
| `tools/reference_host_comparison/test_m26.py` | 新增3项定点测试：缺失/空/冲突/错误类型拒绝；正确路径到达原prepare/start UI参数边界；错误SHA及原共享安全失败仍拒绝 |
| 本报告 | 仅脱敏结果，不提交私人证据 |

本机新计划显式登记两个一致的素材路径字段。没有改变`device_round`、原UI、身份验证器、M20/M22评分器、Swift音频链或任何阈值。

| 实际检查 | 结果与次数 |
|---|---|
| RED：`python3 -B -m unittest test_m26.PlanContractTests -v` | 1轮，子命令exit1：3 tests中缺失/错误路径的5个子例越过旧预检，触发Fake的`unsafe execution reached`断言；没有真实设备 |
| GREEN：同一命令 | 1轮，3 tests，exit0；错误计划无执行回调、无arm目录、无授权消费；正确路径传给原UI边界的Fake |
| 受影响Python回归 | `test_m26 test_m20 test_m20_control test_m20_fixture test_m20_identity test_m22`，1轮51 tests、exit0，含原取消、确切PID回收、批次上限及授权不可复用 |
| 三项Guard | `realtime_release_route_guard/check.sh`、`architecture_guard/check.sh`、`secret_guard/check.sh`各1轮、exit0 |
| 规范/隔离 | 两个Python文件语法与diff检查通过；没有Swift增量，SwiftFormat/SwiftLint为NOT_APPLICABLE；Swift及Release源码无差异 |
| 构建 | 本轮0次：只修改外部Python计划准入，复用批准的冻结App；launcher/dylib/居民/评分器SHA重新核验，未把旧构建当新构建 |

`M26-D1-M01`的具体字段缺陷通过RED/GREEN关闭；这不代表原实验的所有技术风险已解决。未降低旧断言或通过门槛。

## 2. 新批次、身份与设备

新批次：`27721703-279D-48FA-8326-74C3C2520AF9`。计划绑定修复提交及当前脚本SHA，顺序固定A=`TRIPLE_EQUAL`、B=`FIRST_CHANNEL_ONLY`，每臂4秒预热+15秒评分、score+3秒播放一次，最多两臂、38秒，无重试。原批次`916C1941-2986-477A-8BB8-6FEF4F16F885`的计划原件和消费标记保持不变。新批授权由本次用户指令取得，正式入口独立消费；没有复用旧批次或删除标记。

| 身份 | SHA-256 |
|---|---|
| 新计划原件 | `3750193ec04cbd4ceefe9c17d7433122a8c6e53abff4fed087ffcbbf9039cadc` |
| M26控制器 | `88765fa2328a97ba72adead916c877a27d194768a46064a34b89b78c6525c10f` |
| Debug launcher | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug dylib | `b4cc575b386443344a4eb3d09a6b6e0d990cf07d36e4b24af466714714377095` |
| 居民原素材 | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` |
| 冻结M20评分器 | `f9363dd62100563fe80c5693b4889dea65e60f7c99c2a36715feb8f4c46b49ae` |

只读预检通过：TinyUSB USB输入、系统60%；Mac mini内置扬声器、系统55%、未静音，HAL scalar=`0.5500001311302185`。在线、空闲、登记设备身份一致，无冲突实验进程。没有改变音量、路由、Mic Mode或TCC设置。实际App/PID及已加载dylib三次核验均为VERIFIED；保留原App确认、导出与精确PID Quit。

根级JSON的`source_commit`和`build_identity`为空，不能据此补造构建身份；本报告使用外部冻结计划Git身份、实际PID映射/文件SHA及同run M26 witness交叉识别。

## 3. 实际执行次数及停止原因

| 项目 | A / TRIPLE_EQUAL | B / FIRST_CHANNEL_ONLY |
|---|---|---|
| App / Capture / 居民Playback | 1 / 1 / 1 | 0 / 0 / 0 |
| JSON / WAV显式导出 | 1 / 1 | 0 / 0 |
| RunID | `6ACF12C3-A067-40D9-B239-BA7F48D735FA` | NOT_CREATED |
| 控制与退出 | CONTROL_COMPLETED_DEVICE，App exit0 | NOT_RUN |
| 技术资格 | REJECTED：时间观测缺口 | NOT_RUN |
| 回声检测/对照结论 | INCONCLUSIVE | NOT_RUN；无A/B对照 |

A已完成原Stop、Seal、导出、Shutdown及Quit；随后原`audit_capture_manifest`发现`skippedUpdates=1`，抛出`timing observation loss or invalid callback`。正式入口exit1，立即停止余下B。`BATCH_STOPPED.completed=0`表示合格结果为0，不表示没有发生采集。没有自动重试、追加实验或现场修改算法。

独立确认所持App PID已退出、默认输入/输出`running=0`、无冲突实验实例，音量和静音读回未变化。新批目录0700、文件0600，原始JSON/WAV及完整日志仅本机保存。

## 4. 本次A的有限证据

| 项目 | 实测 |
|---|---|
| M26数字分配资格 | A原分配；48 buffers、76010 frames、16kHz/3ch/Float32/planar/DiscreteInOrder，witness已关闭，RunID/代际/配置绑定一致；B实机分配未验证 |
| Capture / Playback Generation；ConfigurationID | 1 / 1；2 |
| Native | VP后16kHz/3ch Float32，190 buffers、304000 frames（19秒）；coverage_valid=true，issues为空、所有拒收为0、raw_timestamp_diagnostic=null |
| 时间见证器Input | 189 callbacks、302400 frames；skippedUpdates=1；sample/host观测缺口各1，最大结束缺口约99.999ms；status=UNKNOWN_OBSERVATION_LOSS |
| Player Render | 189 callbacks，sample/host缺口0；WAV原点下非零约4.214085–7.961755秒 |
| 队列/守恒 | generated=drained=949，queued_at_seal=0；末次drain为pending5/drained5；drop/stale/播放underrun/拒绝回调均0 |
| 实存WAV | 24kHz/Mono/PCM16LE，359040 frames、14.96秒、748个连续20ms包；718124 bytes；预热PCM保留0 bytes，未超过720000 bytes评分PCM上限 |
| Native/PCM短窗 | 748个MATCHED_CONTENT_COVERAGE；逐窗复核保存WAV的PCM RMS/Peak/样本数/内容起点，差异0；整体时序资格仍被观测缺口否决 |
| 满幅/有限性 | Native每声道满幅6、over_scale及non_finite为0；WAV端点样本10、Peak1，整体RMS约−22.81dBFS；不能据此归属声源或判定AEC |
| 首尾 | scoring_packet_coverage及tail_coverage均PARTIAL，未补零或补造尾包 |
| 两次运行态读回 | 同run/代际/配置；VP Input/Output ON、AGC ON、bypass=false、inputMuted=false、Engine running；active/preferred Mic Mode均Standard（公共App-route API） |
| 格式与路由元数据 | 两次格式一致：Input/Player/Mixer/Output client为16kHz/3ch planar Float32，硬件输出16kHz/2ch；进程input共享I/O集合资格及output默认设备元数据资格均CONFIRMED |
| Engine配置事件 | count=0，skippedNotifications=0，监听已关闭 |

上述Native/PCM和守恒证据**支持漏记一次DEBUG观察更新的解释**，不能将见证器缺口直接等同真实麦克风丢帧；但漏记原因及其完整时序仍UNKNOWN。本轮没有复现Native/content_time拒收，不能宣称历史时钟根因已修复。

不绕过技术门禁计算合格NCC：原设备执行器在评分前拒绝；本地只以`trustworthy=false`调用冻结评分器，返回INCONCLUSIVE/INSUFFICIENT_EVIDENCE，NCC及负控未计算。物理发声未取得独立见证，保持UNVERIFIED。不以高RMS、Render活动或播放完成宣称回声/AEC结果。声道分配还可能改变真实扬声器响度，未来仍须保留这一物理混杂；本轮只有A，不作差分因果判断。

本地WAV SHA：`1421798cd2fbfb01b0be009ca10b2fe618488245eccf81f72066f61daa42f63b`；JSON SHA：`f198924f87aa4f1be93ac4162c48086e5af685ce2aa61ad8d87917ebc9426749`。原始WAV未改变、未公开提交，未播放、转写或上传到云端。

## 5. 分级、SELF_REVIEW与下一步

| 证据等级 | 结论 |
|---|---|
| CONFIRMED | 原计划字段合同缺陷及最小修复；新批A真实采集/播放/导出；一次DEBUG观测更新被跳过，原门禁拒绝；B未启动；资源释放 |
| SUPPORTED | 连续Native/PCM、守恒及观察计数差支持“观察遗漏”，不支持将该记录缺口直接当作真实丢包 |
| UNKNOWN | 漏记的具体竞争原因；物理发声/声压；新A回声归属；A/B输出策略差异；Apple内部AEC参考 |

SELF_REVIEW：合同修复PASS；回归/三Guard PASS；资源清理PASS；隐私/Git仅3文件白名单；科学有效性INCONCLUSIVE。原7个冲突、索引和14项未跟踪证据在执行前后及交付后核对，不修改其他工作区。

新CRITICAL=0；MAJOR=1（实验技术资格仍因观测缺口BLOCKED，具体代码原因未确认）；MINOR=0。已确认的`M26-D1-M01`字段缺陷FIXED，既有`M18_E01`继续DEFERRED。没有确认生产AEC/AGC缺陷。

Stage7 Forbidden Checklist：**PASS**。修改仅外部M26准入、定点Fake和本报告；无新Engine/Tap/HIL，无算法、AudioGraph、Converter、时钟容差、正式Gate、RuntimeCore、Provider、DR/API、平台target或Stage8变更。

**唯一下一步：** 对现有DEBUG时间见证器的单次漏记做定点离线竞争复现，确认原因及安全修复依据；不放宽`skippedUpdates==0`或以部分连续统计冒充完整观察。完成后再由主控决定新的A/B批次，不复用当前已消耗授权。

```ini
M26_PLAN_CONTRACT_FIX=PASS
M26_D2_BATCH=STOPPED_AFTER_A
M26_AB_COMPARISON=INCONCLUSIVE
DEVICE_CAPTURES=1
RESIDENT_PLAYBACKS=1
B_DEVICE_RUNS=0
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=DEFERRED
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
