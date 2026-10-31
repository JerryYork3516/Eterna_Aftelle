# T3.2-A / R5-M31：Player Schedule→Render内容见证可行性设计

审计开始：2026-10-31；交付：2026-11-01（Asia/Shanghai）。OFFLINE_FEASIBILITY_AND_CONTRACT_DESIGN；未实现见证器、未运行设备。

**唯一裁定：GO_DESIGN_APPROVED。** 有限、单次播放的合同可以用公开Player时间换算建立帧范围，以可组合的逐声道指纹摆脱Schedule/Tap分块差异，取得现有计数之外的信息。**这是设计可行性裁定，不是实现授权、性能安全PASS或实机READY。** 实际时间映射可用性及新增CPU耗时尚未验证；实施必须另获批准，不能以本报告直接启动开发或录音。

## 1. Git、范围与来源

开始时干净隔离Worktree的HEAD / upstream / 实时远端均为`d53c279e43708bcfe874ed05298f1e46390707f8`，本地`codex/reference-host-comparison-preparation`，目标`Test3-AppleVP-Clean`。范围先报备，沿用用户免除重复读取确认的指令；本任务仅新增本报告，不读取私人WAV/JSON。

复用未变化的[M30 §2–7](T3_2_A_R5_M30_software_integration_root_cause_audit.md)、[M25 §5–6](T3_2_A_R5_M25_reference_host_differential_audit.md)、[M26-D3 §2–3](T3_2_A_R5_M26_D3_timing_witness_fix_and_batch_review.md)、[M27最终报告](T3_2_A_R5_M27_original_aec_stability.md)。新增读取仅为Output Converter/Envelope/M26分配、时间见证器记录与三项定向测试、SDK合同，以及Controller既有JSON出口一个函数。Capture/OutputPlayer/OutputHost对起点的`git diff --exit-code`为空；源码身份沿用M30实算摘要，未构建或重新加载App。

| 一手依据 | 合同定位及本轮用途 |
|---|---|
| Apple [AVAudioPlayerNode](https://developer.apple.com/documentation/avfaudio/avaudioplayernode)；SDK `AVAudioPlayerNode.h:88–128` | Buffer应与节点输出同采样率；Node/Player是不同时间线；隐式排程与Stop重置规则 |
| Apple [nodeTime(forPlayerTime:)](https://developer.apple.com/documentation/avfaudio/avaudioplayernode/nodetime(forplayertime:))、[playerTime(forNodeTime:)](https://developer.apple.com/documentation/avfaudio/avaudioplayernode/playertime(fornodetime:))；SDK `396–424` | 可互换两种时间坐标；Player不播放时可返回nil，不能Stop后补造映射 |
| Apple [installTap](https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:))；SDK `AVAudioNode.h:24–32,81–104` | Tap复制节点输出，when为该buffer采集时间；回调不保证在主线程；请求bufferSize不是Schedule边界 |
| Apple [CompletionCallbackType](https://developer.apple.com/documentation/avfaudio/avaudioplayernodecompletioncallbacktype)；SDK `AVAudioPlayerNode.h:35–76,174–186` | consumed/rendered/playedBack不同，Stop也可能调用completion；Player属性/API内部会同步，不能新增到实时回调 |
| [zlib项目组合CRC合同](https://zlib.net/manual.html#Checksum)、[CRC RevEng原始参数模型](https://reveng.sourceforge.io/crc-catalogue/17plus.htm#crc.cat.crc-64-ecma-182) | 分块CRC可按长度组合的设计依据、CRC64参数/校验向量。zlib提供的是CRC32组合，**不能调用它冒充CRC64实现**；未来64位组合必须独立验证 |

本机SDK两头文件实算SHA：`AVAudioPlayerNode.h`=`4ba9257c7e53b04c2521b280244bec03fc4d04e0f370c2967f2e164d18d69906`；`AVAudioNode.h`=`487cd8d77da3bb3099b084168d8a1a28b6889312d77e880943d5d37ce48b670f`。部分DocC正文抓取受JavaScript/Markdown响应限制，关键Apple语义以对应SDK注释复核；没有据此认定API不可用，也不迁移现有Tap API。

## 2. 实际内容路径、格式与比较点

| 位置 | 实际数据 / 变化 | 源码（`apps/macos/Aftelle/`，起点行号） |
|---|---|---|
| 原居民及分块 | 固定24kHz/Mono/PCM16LE；泵每次最多4800 bytes，即100ms，最后一块可短 | M30追踪的Controller:8297–8318；素材SHA仍为`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`，本轮未读文件内容 |
| Fade/Envelope | 仍为PCM16；根据原audible判定和Fade进度可能改样，故不能用原WAV逐字节当Schedule预期 | [OutputPlayer:326–423](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L326)、502–520；Fade进度由OutputHost:449–453维护 |
| AVAudioConverter | PCM16→localFormat；当前候选为16kHz/3ch/Float32非交错。SRC可能改变帧数、数值及尾部；采用返回buffer.frameLength，不用倍率猜样本数 | [OutputPlayer:178–274](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L178)；容量为ceil(ratio×sourceFrames)+64，不等于有效长度 |
| M26 DEBUG分配 | 严格校验16kHz/3ch/Float32/planar/DiscreteInOrder(3)。A返回原buffer；B同格式副本保留ch0、清零ch1/ch2 | [OutputPlayer:139–173](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L139)。本设计只针对原TRIPLE_EQUAL单播放，不改变分配 |
| 真正Schedule预期点 | `allocatedOutputBuffer`返回的**allocated**，不是原WAV、Fade前PCM或分配前buffer；只读frameLength范围的三路数据 | [Capture:3379–3398](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3379)、4296–4308。现有scheduled统计正是在此扫描allocated |
| Player schedule | `scheduleBuffer(allocated, completionCallbackType: .dataPlayedBack)`无显式at时间；新鲜、未play、无旧命令时首块在Player时间0，后续按排程顺序接续 | Capture:3396；SDK上述规则。start前原水位/先排后play不变 |
| 原Player Tap | Player输出bus0、format=nil；bufferSize请求480 frames，实际分块可不同。当前公开运行格式16kHz/3ch/Float32/planar，不把该历史值当未来实际Tap格式PASS | [Capture:4012–4044](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L4012)。每次必须验证真正buffer及when，不按frameCapacity读尾部 |
| Tap之后 | mainMixer→outputNode，当前client仍16kHz/3ch，公开hardwareOutput为16kHz/2ch；合法混音/设备转换不在本比较范围 | Capture:3511–3589；Player Tap不是Mixer、物理扬声器或Apple内部AEC参考 |

因此比较严格限定为**已经完成Fade/SRC/分配、实际提交的数字内容→Player Tap输出**。两侧名义格式相同排除了已知的跨采样率比较需求，但Apple公开合同不承诺所有Player内部数值表示均位级复制。禁止为取得一致而重采样、拟合增益、归一化或放宽误差。

## 3. 现有观察合同与M27覆盖

[Capture:2654–2676](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2654)明确把scheduled-to-player内容对齐写为UNKNOWN；`scheduledFrames/NonzeroFrames`与Tap时间/非零范围不包含内容指纹。[CallbackRecord:2955–2963](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2955)只有configuration/capture generation和M22播放index，**没有callback playback-generation字段**。全局snapshot的playbackGeneration不等于每次回调已证明归属。

M27三轮各48个实际分配buffer、76010 frames、相同格式，且时间/丢包/代际门禁通过；这些已支持已排程帧数、观察连续性和非零播放时段，未证明实际内容在Tap逐段完整出现。同RMS、Peak、非零计数也可对应不同内容顺序。本设计不重读M27原件，不能回填其Player时间锚点或内容指纹。

`dataPlayedBack`在正常路径包含下游处理及设备播放延迟；它不是本机听闻证明。SDK还允许Stop导致completion。原OutputHost按代次处理callback、清理后旧完成拒绝（[OutputHost:512–528、649–675](../../../apps/macos/Aftelle/MacSpeechAudioOutputHost.swift#L512)），但不能仅据完成计数推出逐样本Tap覆盖；取消必须独立标记。

## 4. 哪些关系可以验证

| 关系 | 可行性及允许结论 |
|---|---|
| EXACT_SAMPLE_MATCH | **不主张已建立。** 不保存完整PCM的有限指纹不是无碰撞证明；即使全范围摘要相等，也只报告指纹匹配。字节不同还可能涉及合法数值表示，不能自动命名损坏 |
| CONTENT_COVERAGE_MATCH | **可条件验证实际帧位置覆盖。** 要有可信Player原点、Tap sampleTime/格式/身份、连续区间和完整已提交帧数；这证明输出时间槽上有观察，不证明每个全零buffer的物理来源身份 |
| HASH_OR_DIGEST_MATCH | **可设计为分块无关的指纹证据。** 同一声道按样本顺序累计，以区间长度组合，而非Schedule块SHA对Tap块SHA。一致有新增信息；有限摘要仍有碰撞风险 |
| TIMESTAMP_ALIGNMENT | **公开API支持未来合同，当前M27证据不足。** 必须在同一Player仍播放时用Node↔Player换算建立原点。hostTime、play调用时刻、首非零位置或NCC最佳lag都不能替代它 |

限定未来profile：同一Run、Capture Generation、Playback Generation、Configuration及新鲜Player，只有一次play、一次固定素材，不允许pause/clear/restart/loop或中途改格式/速率。不是泛化到M22同Engine多遍；其他模式保持原行为，不自动启用见证器。

在原非实时Playback读回与既有Stop/Seal控制点、实际Player.stop之前，各至多取一组映射（正/逆向换算各一次）。以Player时间0的AVAudioTime确定节点帧原点P，并用逆向换算核对0；保存实际rate、有效位及节点/代际身份。两点均须可信且一致；nil、时钟字段无效、rate不一致或epoch变化一律INCONCLUSIVE，不循环重试，不在回调查询Player属性，不从Stop后的新时间线补算旧播放。WAV评分原点、Input内容时间和Player时间0也不能互相替代。

## 5. 最小合同设计（尚未实现）

### 5.1 排程流与实际Tap流

令`Ns`为本次所有实际schedule调用正常返回的`allocated.frameLength`之和。Source摘要只读取调用交付的有效数据；在既有lifecycle序列中登记顺序和提交状态，失败/取消的半提交不能冒充成功。每声道按原Float32字节顺序累计，绑定完整身份和源/构建SHA；不重新转码原WAV制造“预期”。

Tap每次在buffer仍有效时计算三声道指纹，记录原node sampleTime、frameLength、format资格、epoch和callback序号，经原16槽机制传递。不同回调分块只改变记录边界，不改变按声道串接的字节顺序。禁止在控制线程事后再读或保留可复用AVAudioPCMBuffer。

候选摘要合同固定为CRC-64/ECMA-182：width64、poly=`0x42f0e1eba9ea3693`、init/xorout=0、refin/refout=false；已知`123456789`检查值`0x6c40df5f0b497347`用于未来独立校验。各声道单独记录、导出固定16位hex，不能把TRIPLE_EQUAL的三路CRC宣称成独立192位安全，也不把CRC当密码学防伪或给任意结构化错误承诺随机碰撞概率。实现不得引入第三方音频框架或复制第三方代码。

### 5.2 不同边界下的对应

以本次epoch第一个完整合格Tap帧为R0，关闭屏障前最后一个完整合格Tap帧末端为R1，规则在观察前固定，不按匹配结果选窗。实际Tap区间必须无漏记/重复/倒序地覆盖`[R0,R1)`，并满足`R0 ≤ P`、`P+Ns ≤ R1`；所有整数/字节换算检查溢出。

每声道只在非实时导出侧按长度组合Tap记录。令`prefix=P−R0`、`suffix=R1−(P+Ns)`；预期为：

```text
已知Player空闲区间的零值前缀
  + 本次实际提交buffer的有序内容
  + 已知Player空闲区间的零值后缀
```

用CRC组合计算该预期在相同`[R0,R1)`范围内的摘要，不必存PCM、切开原Tap buffer或保持相同分块。前后缀是**已被实际Tap覆盖的静默模型**，不是给缺失观察补零：必须另外检查非零范围是否越出源范围；缺回调/起止不全/未知空闲状态时拒绝配对。合法负零等表示差异也可能使字节摘要不同，故不把差异自动判为声音损坏。

各Schedule块的累计帧范围与Tap区间可登记交叠关系，但本最小方案只给整个已限定范围的逐声道指纹，**不承诺每个20ms或每个Buffer独立通过内容校验，也不能由全局差异定位具体改坏的样本**。不为细化定位增加跨边界PCM暂存、逐样本前缀表或大量并行摘要。

只比较真正提交的`Ns`，不按原WAV帧数或SRC比例要求未提交尾音，不借机修M18-E01。首尾截断分为源范围已被完整覆盖/未覆盖；未覆盖报告PARTIAL/INCONCLUSIVE，不能搜索更好的lag或丢掉不匹配首尾。

### 5.3 身份、关闭与观测损失

Playback epoch在准备后、Capture开始前冻结，回调携带该次不可变绑定，不用导出时最新generation回填旧记录。本profile不在同一Engine内重arm另一个Playback Generation；需要新Run/生命周期。

Stop沿用原取消/换代、未发布记录处理和有界封存屏障；关闭前已接纳记录必须得到完整发布状态，新/旧回调分别计数并拒绝进入新epoch。存在无法判定的在途哈希、未发布槽、skipped/overflow、时间缺口时为OBSERVER_INCONCLUSIVE，不称内容丢失。取消即CANCELLED_PARTIAL，不因Stop触发了所有completion而改成完整匹配。不得新增回调内等待或放宽原快照预算。

## 6. 实时成本与最小实现范围

**设计能给出工作量/内存硬上限；尚没有实际CPU时间或硬实时安全PASS。** 为避免组合CRC意外进入回调，必须注意现有[enqueue/drain/apply:2974–3037](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2974)也可能在音频回调内消费最多16条记录。因此apply只允许O(1)写入预分配的数值摘要行，复杂组合、时间换算、hex/JSON及完整检查全部留到封存后的控制线程。

| 项目 | 预先设计的上限 / 成本；不是已测值 |
|---|---|
| 回调处理 | 仅登记的16kHz/3ch/Float32 planar；每回调最多8192 frames，即98304有效字节。超过立即使新见证资格无效，不能截断后仍匹配 |
| 总工作量 | Tap哈希最多4MiB/Run、最多2048条Render摘要；Source最多64次提交、1MiB有效字节。预算预留溢出后停止新哈希，计为观察失败，不扩大采集范围 |
| 常见流量 | 16k×3×4 = 192000 bytes/s；19秒约3.648MB。M27的76010已提交frames约912120字节，仅作容量依据，不代替未来实际长度 |
| 实时操作 | 不可变查表CRC逐字节更新、已有有限性/非零扫描、数值行发布；复用已有原子槽及忙标志，不加锁/等待、文件IO、同步日志、对象/数组扩容或每回调Player API |
| 内存预算 | 新增最多256KiB（待MemoryLayout/实际分配核验）：2048行、每行stride≤64bytes的预分配历史，Source元数据、CRC表256×8bytes及少量身份/映射字段。不复制完整历史作实时快照，不存PCM或AudioBuffer引用；在arm控制路径分配，原回调关闭屏障后由控制路径释放，回调不拥有最后一个存储引用 |
| 控制路径 | Source摘要可能影响生产者补给；两次Player时间查询会内部同步。须记录开销，不能宣称对播放时序无扰动。封存后原地消费摘要历史，仅导出有界汇总/错误位置 |
| 待批准的性能验收 | 实施后先纯离线测新增callback工作：各登记尺寸的额外耗时均不超过`min(1ms, buffer音频时长的1%)`；同时检查allocations、并发、Stop屏障及原5ms快照预算。此为拟议仪器预算，需主控审定；不得按失败结果调高，亦不是M20/正式Test3新阈值 |

纯查表逐字节工作量不属于大量声学处理，但实际最坏耗时、调度抢占及观察扰动均未测量。**未来若性能、内存或安全验收不能满足，应停止实施/设备准入，不能凭“有界”报性能PASS。** 不调用通用哈希对象的懒初始化或隐含分配来假装满足此表。

最小未来修改范围仅为`MacSpeechAudioCapture.swift`内现有schedule/scan/数值记录、非实时映射与Encodable摘要，以及`RealtimeInterruptionEvidenceTests.swift`的直接测试。CRC更新/组合为同文件纯辅助函数，不建立服务、插件式算法层或第二状态Owner；OutputPlayer、OutputHost、音频图及Converter无须改。若无法保持此范围，须重新审查，不能自动扩张。

为确认出口，仅补读[Controller:8982–8998](../../../apps/macos/Aftelle/AppController.swift#L8982)：现有JSONEncoder编码TimingSnapshot，可承载独立子摘要，不需改控制器。旧`OBSERVED_PARTIAL_METADATA`及`render_generation_source`说明继续描述旧时间字段，新子摘要必须独立声明其播放epoch/资格，不重写M20/M22旧合同。Release无此入口，DEBUG默认关闭且不影响普通通话。

## 7. 新判别价值及不能证明的内容

| 情况 | 允许结论 / 确认缺陷还缺什么 |
|---|---|
| 同一可信范围指纹不同 | 确认两侧指纹不同；先排除观测器/组合算法错误、旧代次、缺发布、错误格式/时间映射及合法数值处理。只有实际生产路径可重复的改样/错序/欠供及明确触发、独立内容证据，才可升级HOST传播缺陷；不能把该CRC差异直接命名AEC根因 |
| 完整覆盖且指纹相等 | 对提交点→Player Tap范围内未发生可检测改样、非零内容丢失或错序提供新支持，超出原连续性/非零计数。仍有摘要碰撞；相同内容的buffer交换、全零数据与空闲零填充的来源身份本身不可由内容摘要区分 |
| 只有计数/格式/时钟正常 | 仍非内容匹配。没有映射、指纹或完整观察时INCONCLUSIVE，不能重复旧Render连续性然后换名PASS |
| M27-R2式强残留与匹配同时出现 | 降低提交点之后、Tap之前的软件内容传播错误解释；**不能排除提交点之前的Fade/Converter内容错误**，也不能排除Tap之后的Mixer/Output、物理输出、VP参考/内部状态或未观察系统处理 |

最终术语应为`MAPPED_FINGERPRINT_MATCH`、`MAPPED_DIGEST_DIFFERENT_UNATTRIBUTED`或`INCONCLUSIVE`（含取消/观测失败原因），不是EXACT_SAMPLE_MATCH、AEC PASS或正式Test3通过。M20_v0.1分类与阈值完全不动。

## 8. 必要离线验证设计（本轮未创建或执行）

现有[M26-D3三项测试](../../../tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift#L4117)覆盖竞争、16/17槽边界、未发布记录、真缺帧、错误身份、Stop和可复用buffer；245 checks是既有报告结果，不是M31已通过。它们没有内容指纹或Player时间映射测试。

| 未来必要对照 | 必须区分的结果 |
|---|---|
| 标准向量＋独立逐bit基准；整段/逐字节/不同切分 | 校验CRC参数、长度组合与方向，不只让同一实现自证；`123456789`及空输入固定向量 |
| 单样本改变、极性/幅度改变 | 映射/观察完整时摘要差异，不用此合成错误冒充生产AEC RED |
| 丢一块或部分非零帧、换序 | 原计数/时间/摘要共同拒绝；相同全零内容的不可区分来源明确保留 |
| 同一流切成不同Schedule/Tap边界，包括跨首尾 | 指纹/覆盖应相同；不得误判重分块为损坏 |
| 可信映射、缺/错/变化映射、重复内容和长静默 | 只接受原登记时间关系；无映射即INCONCLUSIVE，不靠最佳lag、首非零或重复片段寻找对齐 |
| 首尾截断、无覆盖、提前Stop、完成回调由Stop触发 | PARTIAL/INCONCLUSIVE或取消，不伪造尾音、不把completion当完整内容 |
| 非法率/声道/layout、非有限、超帧/字节/行容量 | 拒绝资格，音频字节不被修改，不截短后报匹配 |
| 不同Run/config/capture/playback generation，旧回调 | 不进入当前统计，不借最新全局generation覆盖旧记录 |
| Reader竞争、延后发布、复用/修改原buffer、真正观察溢出 | 数值摘要必须已在回调内计算并复制；观察漏记为OBSERVER_INCONCLUSIVE，不能诊断成音频内容丢失 |
| 并发、关闭屏障、Enable/Disable/Release | 原音频输出字节及原门禁结果不变；有界/TSan/内存/性能单列，未通过不能进入设备阶段 |

## 9. 裁定、交付与唯一下一步

选择**GO_DESIGN_APPROVED**的依据：新信息是实际数字内容而非仅Render存在；公开双时间线API允许可信帧范围合同；分块可组合指纹与覆盖分离；RT工作量/存储有明确上限；实现限定现有一个见证器与原测试。**实际映射成功率、CRC代码正确性、CPU/锁竞争和声音影响均未验证。** GO不替代后续离线性能/安全验收，更不构成设备执行授权。

**唯一下步：主控审核这份单播放合同、两文件最小范围及性能预算，决定是否单独授权离线实现。** 本轮不实现、不建RED/GREEN、不创建批次、不追加录音。若主控不接受指纹证据的边界或预算，本路线在此停止，不转而扩建诊断系统。

本轮实际操作：Git三方及原工作区元数据核验；定点源码/既有测试/SDK/官方合同阅读；3份生产源码起点diff为空；文档链接/隐私/文件白名单、`git diff --check`及staged diff、Secret Guard检查PASS。一个目录名探测未找到候选路径，随即按D3报告定位到原测试；未扩大搜索或运行任何测试。Swift回归/App构建/新测试/真实设备次数均0。

仅新增本报告；原7冲突、索引、未合并记录/status及14项未跟踪size/mtime前后不变，无跨文件修改或额外回滚提交。Stage7 Forbidden Checklist前/后：**PASS**；红线无；代码、Runtime API、DR schema、平台target、Stage8均无变化；不要求额外读取确认，不请求设备授权。正常Commit+Push后核验三方HEAD，交主控审核并停止。

```ini
M30=APPROVED
M31_MODE=FEASIBILITY_DESIGN_ONLY
M31_VERDICT=GO_DESIGN_APPROVED
M31_IMPLEMENTATION=NOT_AUTHORIZED
M31_DEVICE_EXECUTION=NOT_AUTHORIZED
M31_DEVICE_RUNS=0
M31_RUNTIME_MAPPING=NOT_RUN
M31_REALTIME_PERFORMANCE=NOT_MEASURED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=DEFERRED
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
