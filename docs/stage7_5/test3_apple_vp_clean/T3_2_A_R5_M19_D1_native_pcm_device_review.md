# R5-M19-D1 — 真人C组Native/PCM短窗实机审核

2026-10-27。单次取证完成，用户确认居民回声可闻、仍有音量波动。声学不判PASS，T3.2-A及Formal Test3继续BLOCKED。本轮没有修复音频算法，也未追加实验。

## 1. 授权、身份与次数

预检完成后，用户本轮明确回复“授权开始M19-D1单次真人C组”。新回执绑定本轮预检标识，旧同意未复用；O_EXCL单次消耗记录保留。仅运行HOST真人C，Capture=1、Resident Playback=1、JSON Export=1、WAV Export=1；BT=0、REF=0、自动重试=0。

- 实际RunID：`4CFEAA84-950B-4F1F-93DE-141E8239D8D2`，generation=1、configurationID=2，实际App PID=48727。
- 启动前HEAD=upstream=实时远端：`2aa5a73729bed32fe7988fce7e6c59f47cf81bfc`。源码摘要与M19冻结记录一致，工作区干净。
- Debug dylib SHA-256：`dd26caa68f12e2f74531886fa16ac2e5438d2b43065ea8058ee23ae290f82f40`。
- 启动器SHA-256：`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`。
- 居民WAV SHA-256：`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`。
- 启动后按确切PID通过lsof核验实际映射的启动器与dylib路径，再核验文件SHA；没有按App名称启动其他实例。

原Manifest的`source_commit`和`build_identity`均为null，未回填伪造。版本依据是本轮外部Git/source摘要、构建回执、冻结二进制SHA及实际PID映射证据；自描述版本缺口仍保留。

## 2. 预检、合法确认与结束

默认TinyUSB输入系统60%，内置扬声器55%（标量0.5500001311）、未静音，设备在线、空闲且身份与登记一致；没有调整设备、音量、路由或Mic Mode。外部TCC只读不可得，准备时标UNKNOWN；实际经原App可见Start、本地录音及两次Export确认完成，没有代操作系统授权弹窗。

准备阶段两次`m19-only`入口分别exit 0：Native短窗354 checks；recording/STATS_ONLY原评分导出Fake通过。Debug增量构建exit 0，1.634s，两个冻结SHA均未变；Release隔离和Release Route、Architecture、Secret Guard各一次通过。未跑FULL_CURRENT。首次设备检查因JSON数值0与布尔身份比较而误报静音，失败回执保留；依据Core Audio UInt32语义纠正后通过，没有改设备设置或放宽音频门禁。

执行沿既有`integration._connected_run(... human_group="C")`，仅在Git外登记本轮身份和新授权。Prepare/素材选择、Start、JSON/WAV显式导出、确切PID的Aftelle退出菜单均exit 0。回执`APP_QUIT_MENU_SELECTED=退出 Aftelle`；控制器exit 0。进程生命周期202.574s包含UI准备及导出等待，不等于录音时长。退出后确切PID消失，默认输入/输出在提供试听前均running=0。

## 3. 两点运行态证据

两份快照绑定当前RunID/1/2，读取实际属性而非配置缓存；全部7项进程查询OSStatus均0。

| 字段 | Engine.start后 | Resident Player.play后 |
| --- | --- | --- |
| 实际进程PID前后核验 | 当前PID，一致 | 当前PID，一致 |
| 进程input/output设备数量 | 2 / 1 | 2 / 1 |
| 输入集合 | 严格共享I/O集合元数据合格 | 同左 |
| 输出集合 | 元数据匹配默认内置输出 | 同左 |
| Engine / VP Input / VP Output / AGC | 全部true | 全部true |
| bypass / inputMuted | false / false | false / false |
| active / preferred Mic Mode | Standard(0) / Standard(0) | Standard(0) / Standard(0) |
| 整体读取耗时 | 4.013167ms | 3.106084ms |
| 进程查询耗时 | 2.000000ms | 1.521917ms |
| Mic Mode getter耗时 | 0.228083ms | 0.004542ms |

Mic Mode为`CONFIRMED_PUBLIC_API`读值，不以preferred代替active；不等于已经证明该模式对物理TinyUSB/当前VoiceProcessingIO的具体处理效果。AU绑定状态仍为`UNKNOWN_UNVERIFIED_BINDING`。进程方向集合不是物理输入唯一归属或Apple内部AEC参考证明，内部参考仍UNOBSERVABLE。

Player→Mixer bus0、Mixer→Output连接存在。Input输出、Player输出、Mixer播放器输入、Mixer输出、Output输入均16kHz/3ch Float32非交错，硬件输出侧16kHz/2ch Float32非交错；两点完整ASBD/声道描述一致，无截断。原件保留全部格式字段，未因此改变Mono/3ch策略。

Engine配置事件count=0、skippedNotifications=0，监听已关闭；host_timing.skippedUpdates=0、staleCallbacks=0、invalidBuffers=0。`identityChanges=1`为另一个诊断计数，不能等同路由变化。host_timing仍标`OBSERVED_PARTIAL_METADATA`，排程至Render内容对齐未完全建立，不能用属性正常证明AEC参考有效。

## 4. 时间线、连续性与实际覆盖

原4秒预热+15秒评分、score+3秒居民请求保持不变。观测到的Player非零Render约score+4.19294至+7.94060秒，对应WAV约4.18208至7.92974秒。它是Mixer前Render观测，不能冒充物理发声时刻。用户现场见证见第6节。

Native共189 buffers、302400frames，按16kHz为18.9秒。Input和Render各189 callbacks，sample/host discontinuity、backwards、duplicate、missingTime均0；最大相邻host起点间隔分别约100.001750/100.001791ms。所有Native拒收、drop/stale、输入/输出转换拒收均0；`raw_timestamp_diagnostic=null`，历史时钟异常本次NOT_REPRODUCED，未宣布已修复。

generated=drained=944，queued=0；预热199包不保存，边界1包和窗口外1包排除，实际评分保存743包、713280 PCM bytes。WAV 356640frames、14.86秒，距评分起点约10.862ms，距评分末尾缺约129.138ms；首尾覆盖PARTIAL。Converter partial tail未读到可靠计数，保持UNKNOWN；没有补零或借用drained总量制造完整覆盖。Manifest的`capture_state=capturing`为保存的阶段快照，不是当前仍在录音的证明；实际Stop/封存/退出和设备释放另有证据。

## 5. 核心结果：本次能量变化已在VP后Native

743个PCM20ms窗全部为`MATCHED_CONTENT_COVERAGE`：同Run/配置、时钟可信、无stream fault、Native16k每窗320样本、PCM24k每窗480样本，各窗有限且完整。没有插值、补零或借窗。

逐包核验743个序号和20ms内容时间连续，Manifest PCM SHA与实际WAV数据一致。以实际WAV每480样本重新计算RMS、Peak、零值及端点计数，全部对应导出PCM短窗；RMS最大误差为0。因此以下使用的确实是保存到WAV的样本，不是全部drained音频。

用户定位波动约WAV4–5秒。该50个短窗的Native与PCM RMS能量为−24.78268/−24.78360dBFS；逐20ms比值最大绝对差0.16431dB。以下100ms聚合仅用于展示局部变化：

| WAV区间 | Native ch0 RMS dBFS | 实际WAV PCM RMS dBFS |
| --- | ---: | ---: |
| 4.20–4.30s | −18.45167 | −18.45179 |
| 4.30–4.40s | −35.81711 | −35.81691 |
| 4.40–4.50s | −36.95752 | −36.95931 |
| 4.50–4.60s | −38.98072 | −39.03005 |
| 4.60–4.70s | −40.06190 | −40.06258 |
| 4.70–4.80s | −24.39885 | −24.39898 |

WAV4.82s的一次相邻20ms下降为Native −21.31770dB、PCM −21.33385dB。两路共同下降与恢复，未见PCM额外造成同等级衰减。该区间在观测的非零Render期内，但关联不等于因果；4–5秒内另有变化发生在首次非零Render观测之前。

全WAV中，为避免近量化底/零分母比值误导，仅对Native RMS≥−60dBFS且PCM非零的455窗汇总：PCM/Native比值中位−0.000465dB，绝对差P95=0.01436dB、最大0.16431dB。该筛选仅用于数值展示，不修改DSP或验收阈值，全部743窗的覆盖和数据仍保留。4–5秒50窗全部满足此显示条件。

Native各声道满幅/超幅/非有限均0，ch0总体Peak 0.8778918；实际WAV端点样本0、Peak 0.8777771。相同通道Peak/计数不被当作逐样本相等证据。

**判断A：能量变化定位成立。** 这次局部变化已存在于VP后Native或更早阶段；不支持后级PCM转换产生主要的大幅音量波动。该结论不排除所有后级频谱/瞬态差异，也不能证明真人受损：Native仍是VP后的混合信号，居民回声混入/变化、真人发声差异和VP内部处理尚不能分离。没有VP前原音或独立固定近端真值，不能将能量谷直接认定为AGC错误、吞字或Apple算法BUG。

## 6. 用户反馈与声学裁定边界

用户本轮试听原话：“能听到居民回声，仍有忽大忽小”。补充同时询问现场持续双讲、停止提示及异常时点后，用户答：“是，大概在第4到5秒”。保留原话，按联合提问理解为肯定现场见证与按提示停止；没有独立测量精确物理双讲时长。

CONFIRMED_USER_REPORT：居民回声可闻，音量仍波动，时点约4–5秒；本次声学用户反馈FAIL。未自动听音、转录或声源分离；未取得逐字完整性证据，不能填写吞字/爆音/断裂均不存在，也不能作STS理解或正式Test3验收。

## 7. 原件、隐私、检查与结论

| 本机原件 | bytes | SHA-256 |
| --- | ---: | --- |
| JSON | 1071662 | `4ebf2d168db17c948201f7e439cd99b3f54b9f6c8e718470724e501cb486571c` |
| WAV | 713324 | `91281473310319cc719c982c7f7a919f271961bd042ed21b07c9b569352394b1` |
| WAV中PCM数据 | 713280 | `9b053dc7acde008a1d1325175b32caceed4d093cf1aac8ac2b7121e7a4873a27` |

原件在既有受控本机Cache，目录0700、文件0600；未重采样、调音量、降噪、裁剪、转录或上传。实际路径、UID、完整JSON/日志及全部20ms数值留本机。本次Git仅新增本脱敏报告，没有生产代码或录音提交；原7个冲突及14项未跟踪证据按原摘要保护。

CONFIRMED：单次运行身份与读回、743窗同内容覆盖及实际WAV一致性、4–5秒共同能量下降、无本次时钟拒收、用户回声/波动反馈。HYPOTHESIS：VP或之前的声源/处理状态可能解释波动。UNKNOWN：原始发声变化、真人/居民能量归属、Apple内部参考及AEC/AGC具体机制。NO_CONFIRMED_NEW_CODE_DEFECT。

五维SELF_REVIEW：身份PASS（原Manifest自述缺失单列）；控制与安全PASS；同窗取证PASS且首尾覆盖PARTIAL；声学FAIL_USER_REPORTED；隐私/Git范围PASS。CRITICAL=0，MAJOR=1（回声和波动未解决），MINOR=2（首尾/partial tail限制、Manifest版本自述缺失）。Stage7 Forbidden Checklist=PASS；未改Runtime API、DR schema、平台target、Stage8、正式Gate或M18-E01。

唯一下一步建议：由主控审核本次同窗定位后，单独裁定物理独立、固定近端语音源的居民关闭/开启对照准入，AGC保持ON，以区分发声变化与VP处理影响；独立声源资格须先验证。本轮不实施，也不继续修改Converter或切换AGC。

```ini
M19_D1_TECHNICAL_EXECUTION=COMPLETED
NATIVE_PCM_MATCHED_WINDOWS=743
ENERGY_CHANGE_LOCATION=VP_POST_NATIVE_OR_EARLIER
ACOUSTIC_USER_REVIEW=FAIL_ECHO_AND_GAIN_VARIATION
WORD_INTEGRITY=UNKNOWN
CLOCK_ANOMALY_THIS_RUN=NOT_REPRODUCED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=DEFERRED
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
