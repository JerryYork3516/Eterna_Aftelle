# Eterna Aftelle · R3-M01 · 单次 A 时序与用户试听复审

日期：2026-10-17（Asia/Shanghai）。交付状态：**REVIEW_PENDING**。

**A=INCONCLUSIVE；ROOT_CAUSE_UNKNOWN。** 用户已实际试听并反馈未听到居民回声；“起音”的性质、影响及是否可接受仍UNKNOWN。一次未听到可辨居民回声的观察不等于稳定AEC性能或T3.2-A完整收口。前序无试听时的ACOUSTIC_RESULT=UNVERIFIED作为历史事实保留，本报告登记新增反馈，不追溯改写R2/R3失败。

## 用户试听与本次提交授权

用户原话：

> 听不到居民回声，但是有起音，起音不知道是否影响

用户明确要求“提交推送给主控审核，包括WAV”。本次限定授权仅覆盖run `EDDF62B0-D328-4C19-85E6-B98D9A6D5CEA` 的原字节WAV及脱敏审核资料，目标为当前仓库 `JerryYork3516/Eterna_Aftelle`、分支 `Test3-AppleVP-Clean`。它不授权上传其他录音、原始PCM、DR、Session、设备原始日志或密钥；不修改.gitignore及历史治理规则。最新上传授权覆盖前序仅本机保存的边界，仅限此资产。

| 层次 | 当前结论 |
| --- | --- |
| Output/Capture控制链 | PASS（本次一次运行） |
| 原native/packet时间轴 | PASS（已接纳内容范围） |
| host_timing完整性 | PARTIAL / UNKNOWN_OBSERVATION_LOSS，skippedUpdates=1 |
| 居民回声试听 | USER_REPORTED_NOT_HEARD；仅用户本次观察 |
| 起音性质/影响/可接受性 | OPEN / UNKNOWN，未替用户判定 |
| A总体与T3.2-A收口 | INCONCLUSIVE / REVIEW_PENDING；T3.2-A继续BLOCKED |

Codex未试听或分析WAV音频样本。本次只为获授权的上传执行文件头、摘要、原字节复制及对应run完整性校验，无剪辑、重采样、增强、去噪或音量处理。

## 冻结的运行身份与执行（测试时事实）

- 测试时 HEAD/upstream/实时远端：`7db839304c8c7dd575edd48fc3a6ecbb1bc72e68`。
- Debug App SHA-256：`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`。
- Debug dylib SHA-256：`81e2c6799a2ef69f2d7ecf56de5f7bf1553185d472a32b98691c746dcaabf6ad`。
- 唯一 runID：`EDDF62B0-D328-4C19-85E6-B98D9A6D5CEA`；Capture generation=1，Playback generation=1，运行配置=2。
- 通过完整 App 路径连接；启动前仅一个进程，ps/lsof 验证隔离参数和实际加载映像。前次误启动历史构建的中止记录保留，本次没有再次误启动。
- 用户明确本次 A 播放、短时采集、本地保存/导出授权，并回复“已就绪，现场安静、设备连接正常”。未再次索取相同授权。
- 目标 USB 麦克风与 Mac mini 内置扬声器，输入60%／输出55%／未静音；本轮 manifest 的设备身份在本机内存与实际默认设备比对一致，未保存硬件 UID 到本报告。
- 由 Aftelle 原权限路径检查后实际采集成功，无新系统授权弹窗；未查询外部 TCC。Microphone Mode=UNKNOWN，未调整设备、音量或 VP 配置。
- 正式 DEBUG 场景 A；选用预检 SHA 匹配的原 Tingting WAV，只播放一次。无 Provider/DR/Session 路线，无 Runtime 正式 Decision。
- 窗口配置15000000000ns；应用自动 Seal/Shutdown。原生有效14.9s、实际保留14.88s；captureStopped 是 removeTap 返回后的事件，不能将它与 Engine.start 调用前的差值当成连续录音时长。
- manifest 的 source_commit/build_identity 仍为 null；实际绑定来自本机启动前源码/二进制核验，未篡改原 manifest。

## 实际状态与原 PCM 时间轴

- Output prepared/start/completed 流程完成，playbackStartedCount=1，状态completed；Capture 实际运行后封存。manifest capture_state=capturing 是封存前快照，终态另由 Stop/Shutdown/退出和设备状态确认。
- VP input/output=true、AGC=true、bypass=false、inputMuted=false；Apple NS 无独立公开读回，不能声明其效率。
- 原生16kHz/3ch/Float32/non-interleaved：149 buffers、238400 frames；目标24kHz/Mono/PCM16LE，744包×960bytes＝714240bytes，每包20ms、序号与内容时间连续。
- native coverage_valid=true、issues=[]，content_time/native_clock等全部拒收0，drop/stale/underrun/rejected playback callback均0。
- 每原生声道peak=0.1198392138、fullScale/overScale/nonFinite=0。不能据此判断回声、人声听感或AGC质量。
- generated=744、drained=744、queued_at_seal=0；本次没有前序5个排队尾包问题的计数现象。
- 原生样本14.9s与已drain14.88s差约20ms；converter partial tail仍UNKNOWN，不能补造尾部样本数或宣称完整输入全量保留。
- 以Player Tap最后非零内容时间为参考，已drain结束晚约9.874208s；它不是物理扬声器结束见证，因此不直接等同实际声学post-roll/残回声窗口已验证。

## host_timing 时间线

以下ns为原始monotonic值。相对值仅便于读表，统一减去Engine.start前调用时间；CALL、CALLBACK_ARRIVAL、AVAudioTime_CONTENT三种含义不能互换，也不表示Apple内部延迟。

| 事件 | 语义 | monotonic ns | 相对ms |
| --- | --- | --- | --- |
| engineStartBefore | CALL | 731566173742041 | 0.000000 |
| engineStartReturned | CALL | 731566356323583 | 182.581542 |
| playerPlayBefore | CALL | 731566471627083 | 297.885042 |
| playerPlayReturned | CALL | 731566479157541 | 305.415500 |
| playbackCompleted | CALL | 731571347816375 | 5174.074334 |
| captureStopped | CALL | 731581365226833 | 15191.484792 |
| input_first_arrival | CALLBACK_ARRIVAL | 731566480989000 | 307.246959 |
| render_first_arrival | CALLBACK_ARRIVAL | 731566511183166 | 337.441125 |
| input_first_content | AVAudioTime_CONTENT | 731566349300042 | 175.558001 |
| render_first_content | AVAudioTime_CONTENT | 731566448050042 | 274.308001 |
| render_first_nonzero_content | AVAudioTime_CONTENT | 731567607419708 | 1433.677667 |
| render_last_nonzero_content | AVAudioTime_CONTENT | 731571355092458 | 5181.350417 |

- Engine.start调用182.581542ms；Player.play调用7.530458ms。这是API调用耗时，不是AEC处理延迟。
- Player.play调用早于首次已观察Input回调到达9.361917ms；另一方面，首个Input内容时间早于Player.play调用。两者说明到达与内容时间不同，不能据此确认“无Input就开始有声播放”或“VP未预热”。
- PlayerNode Tap位于Mixer之前；不代表实际Mixer输出、扬声器声压或Apple内部AEC参考。首次非零Render存在，但不能据此判AEC有效。

## 连续性与观测缺失

- Render：149 buffers／238400 frames，missing/duplicate/backwards/stale/invalid均0，sample/hostDiscontinuities均0；最大相邻内容起点间隔100.001166ms，最大end gap1166ns。
- Input观测：148 buffers／236800 frames，比原native统计少1个buffer／1600帧；sampleDiscontinuities=1、hostDiscontinuities=1，最大起点间隔199.999166ms。
- skippedUpdates=1，manifest状态UNKNOWN_OBSERVATION_LOSS。确认统计跳过一次；单次丢观测与Input统计缺一buffer相吻合。原native coverage/时钟Guard和packet序列并未报告缺口，不能把观测间隔直接定性为真实PCM丢失。
- 原生第一/末sampleTime及总帧数与149个1600帧buffer一致；第一native内容时间与首个Input观测内容时间相同。仍不把部分metadata改判无损观测。
- staleCallbacks=0、invalidBuffers=0、routeChanged次数0；identityChanges=1与captureStopped之后0.172708ms的正常配置teardown事件吻合，不作为运行中错代证据。
- scheduledFrames=76010，scheduledNonzeroFrames=59964，observed nonzeroFrames=59964；数量一致不建立完整scheduled-to-render区间映射，nonzeroCoverage继续UNKNOWN。
- Render generation来自run/capture绑定和tap configuration，不是原生callback独立playback-generation字段。

## 实际 Playback 格式

- 本次真实mainMixer localFormat见证：16000Hz、3ch、Float32、non-interleaved；commonFormat=1。
- ASBD：mSampleRate=16000，mFormatID=1819304813（lpcm），mFormatFlags=41（0x29），mBytesPerPacket=4，mFramesPerPacket=1，mBytesPerFrame=4，mChannelsPerFrame=3，mBitsPerChannel=32，mReserved=0。
- Channel Layout：tag=9633795（0x930003），bitmap=0，descriptionCount=0，descriptions=[]，descriptionsTruncated=false。
- 本次仅登记实际格式，不重跑/重判先前合成输出转换研究；原配置format guard validated。单一见证也不证明任意路由下格式不变。

## 可审核资产与完整性

- [本次原字节WAV](evidence/r3_m01_single_a_EDDF62B0/run-EDDF62B0-D328-4C19-85E6-B98D9A6D5CEA.wav)：714284 bytes，24kHz/Mono/PCM16LE，357120 frames，14.88秒。
- WAV SHA-256：`2cc639c31949b9c6b0f886f1f315bfc17fd74e45bf68b1f67b46012cd7d638a3`。
- WAV data区 SHA-256：`45cee88eb65281ee8d029d09556833653a4187b6d249a09777bedb6f8d4f03d5`；与本次原manifest的processed_sha256完全一致。源文件及副本摘要一致。
- [脱敏证据manifest](evidence/r3_m01_single_a_EDDF62B0/evidence_manifest.json)：含冻结源码/实际构建身份、完整ASBD/layout、时序、统计、用户原话及限定上传授权；不是原始设备JSON。
- 原始metadata JSON仅本机保留，其SHA-256为 `56168c9d2dfc2ab03d6eee0a9c1204970baf89219433deb22f7938aca753ed9e`。硬件UID、私人路径及原始设备日志未复制到Git。
- 本机原WAV/JSON保持原字节，原JSON的source_commit/build_identity=null未篡改；recorded_source_commit为外部核验身份，两者分别登记。
- 本次未再运行App、Engine、设备、Provider或A/B/C，也未读取历史录音。

## 五维 SELF_REVIEW

| 维度 | 结论与范围 |
| --- | --- |
| TECHNICAL | REWORK：原控制链/native/packet通过；观测丢失及起音影响仍待审核 |
| ENGINEERING | REWORK / DEBT_DEFERRED：历史SwiftFormat/SwiftLint FAIL及C19/C23保留；本次无生产/测试源码差异，Swift增量检查N/A，不改判历史工具PASS |
| EVIDENCE | PASS：用户原话、时间类型、摘要及原字节身份分开登记，不凭统计推断听感，不把一次结果推广为稳定性能 |
| CONSISTENCY | PASS：按最新限定授权交付该run；历史失败、原未跟踪报告和研究worktree保留；主控审批与执行边界不变 |
| Stage7 Forbidden Checklist | PASS：见下节；仅本次已授权音频例外 |

审核来源为Codex **SELF_REVIEW**，没有冒称独立Reviewer或主控批准。交付校验及实际commit/push回执在最终回复提供。

### 问题登记

- 新增CRITICAL=0、确认功能安全MAJOR=0；本次run开放MINOR两项：①观测skip使Input metadata不完整；②用户报告“起音”，性质/影响/可接受性UNKNOWN，交主控审听，不先定性为爆音、吞字或算法缺陷。
- R3-M01回声残留根因继续OPEN/UNKNOWN；本次未听到居民回声不关闭此前R3声学FAIL。未确认应修改AEC、AGC、NS或启动顺序的生产代码缺陷。
- nonzeroCoverage、converter partial tail、物理扬声器与Apple内部参考时序、内部处理效率及音质量化仍UNKNOWN；满幅0不证明起音不存在或可接受。
- 原有C19/C23和全量规范FAIL继续延期；本次不重跑未变化的构建/安全回归，不沿用旧提交豁免作为永久例外。
- 首次打包校验脚本exit1：本机Python不支持hashlib.file_digest，失败发生在复制/文档写入前。改用兼容的hashlib.sha256读取方式后，run摘要、WAV头和原字节完整性校验通过；原失败保留，不涉及App或测试标准修改。

## Stage7 Forbidden Checklist

| 项 | 结论 |
| --- | --- |
| A Stage范围 | PASS；无新平台、Stage8或多平台实现 |
| B RuntimeCore | PASS；大脑平台隔离、HostEnv和Runtime ownership未改 |
| C Host | PASS；未新增Engine、Tap、Gate、Provider或Runtime owner |
| D DR/Runtime API | PASS；无schema、fixture、API或DR写回 |
| E Provider/Secret | PASS；无真实Provider调用；仅本次明确授权的WAV及脱敏资料，无密钥/DR/原始设备日志 |
| F Memory/Trace/LiveState | PASS；Session/Memory/Store与DR边界未改，未上传私人会话 |
| G Scheduler | PASS；无新后台监听、循环或调度 |
| H UI/渲染/语音 | PASS；无生产行为、音频参数、Test2机制或正式Gate改变 |
| I 交付 | PASS；五文件白名单、摘要、脱敏及Git回执核验 |

六红线均未触碰。改生产/测试代码=否；改Runtime API=否；改DR schema=否；新增target=否；进入Stage8=否。修改范围仅本报告、该run WAV/脱敏manifest、README/DEVLOG最小记录。

## 主控复审建议与状态

请主控结合本次原WAV评估“起音”及是否影响A声学接受；Codex不预先认定A PASS，也不实施修复或追加实验。启动时序与回声的因果关系仍为HYPOTHESIS；本次提供可审听原件和客观元数据。

```text
Single A Submission = REVIEW_PENDING
A = INCONCLUSIVE
Echo Listening = USER_REPORTED_NOT_HEARD
Onset Impact = UNKNOWN / OPEN
R3-M01 = OPEN
T3.2-A = BLOCKED
ENGINEERING = REWORK / DEBT_DEFERRED
T3.2-B = NOT_AUTHORIZED
T3.3 = NOT_STARTED
SQ-M1 = OPEN
Qwen Strict Overlap = 0/3
Formal Test3 = BLOCKED
Test3.execution_authorized = false
```

正常Commit/Push并核验三方SHA后停止；不得自动开始下一次设备测试或修复。
