# T3.2-A / R5-M10 · 居民回声残留差异离线审核

schema_version：1。模式：OFFLINE ONLY。

**结论：M09-D1的高能量包含明确的固定居民模板特征，与已判回声失败的M03 A高度相似；它不是仅凭RMS得出的判断。M05/M07没有同等强度的匹配。尚未发现能解释差异的已确认配置或接线错误，也没有安全修改DSP的依据。AEC_ROOT_CAUSE及CLOCK_ROOT_CAUSE均UNKNOWN。** M09-D1尚无本轮用户试听，不能用本报告代替听感裁定。

## 1. 身份、范围与SHA

本轮开始时，干净隔离Worktree的HEAD、upstream、实时远端均为 `741114c4336ac15cb8da3dc6192fdb0a3f5fefe7`，推送目标为`Test3-AppleVP-Clean`。读取白名单由用户明确确认。只新增本报告；分析程序及数值回执留在Git忽略目录。没有生产源码、设备配置或正式授权状态变更。

下列7份WAV均重新计算完整文件SHA、检查文件头/长度；仅在内存中处理，未播放、复制、修改、重采样或另存音频。均为24kHz / Mono / PCM16LE。五份历史录音均是已提交的公开副本；本轮不再上传。

| 证据 | RunID / 身份 | 本轮实算SHA-256，与登记相同 |
|---|---|---|
| 固定居民源 | 114032 frames，228108 bytes，4.751333s | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` |
| [M03 A](evidence/r5_m03_bt_abc_20261020/A_resident_only.wav) | `F60F1D2A-4B68-4A05-8260-5BC567F71721` | `87a0e5e91db130597e02706620e0b23584018d989fa17654665cc74dd797d44c` |
| [M03 B，无居民负控](evidence/r5_m03_bt_abc_20261020/B_bt_near_end_only.wav) | `44430CFD-991C-46B2-8446-E400A77A9FD1` | `ddbc4aff5073fd4d0f45498b0b757cfb8f1c293fb07dfe47da3b2c820331a9cc` |
| [M05 A](evidence/r5_m05_runtime_io_20261020/A_resident_only.wav) | `2F4AA935-488D-4777-BC9B-94CAC163F72C` | `710c8d0d9cd8d52345192b243a7560938febebddad1f224e4c2e004dcefde7cf` |
| [M07 A](evidence/r5_m07_human_abc_20261020/A_resident_only.wav) | `6732FC36-F824-4835-8EC9-05145C972BAB` | `7cfad67e6c5655aefee9b0b17358aef0cf231144db98199bf528a0b45ffcbef0` |
| [F1 A，居民先讲、随后真人](evidence/r5_m07_f1_human_onset_20261021/A_resident_first.wav) | `2EA7AF35-7D1B-4512-8059-E65B3B091B8B` | `454bb244aa2b04b76a9696c9ae088cc251b07b8a7ff5ab8474f7c04024f64446` |
| M09-D1 A，仅本机 | `29B4B89A-DBE0-418D-93EE-ADF5CC8D18E7` | `a8ef35336eac18792e6e03772a1148774ea368da495bbd567a89f3f67ec1501d` |

六份录音均713324 bytes、356640 frames、14.86s。固定源前24000帧严格全零，精确非零样本范围为源文件[1.000000, 4.746458)s；“非零”不等于物理可听起止。

**M09-D1 Manifest独立核验：** 83623 bytes，SHA `1475a4ad1fb013a11e730062878eaef1b02a662124d1e712372464d490de83de`。顶层/Native/timing的RunID一致，generation=1、configurationID=2；playback SHA等于上表固定源；WAV内713280 bytes PCM SHA为 `49953e1a1a8726c72a3988d5c7f9049a09127e0d4954711c2564dea6736c65cc`，与Manifest相同。743包序号及20ms内容时间连续。

历史私人Manifest不在本轮读取范围内，**没有重新哈希或读取**。其公开登记摘要只用于追溯，不能写成本轮原件复核通过：M03 A=`99978f967dc9767b1c0d3c33178c062b3fd7cbc4a336ed90208ce463876b51f2`；M05 A=`b16b65f5029c7b567ca283e951a33e4d6a8fcc261add18168d6bf531966d8764`；F1 A=`231689fb2ec03983e53dbe5ba0d878b2ceb902eccf76ba8ac2a7f17b8bfc4885`。M07 A公开报告/索引未列JSON摘要，本轮记NOT_AVAILABLE，不扩搜私人目录。

## 2. 固定分析口径与负控

- 实际WAV样本按`int16 / 32768`计算RMS/Peak。M09-D1使用原包内容时间；历史使用公开内容起点：M03 A/B分别+0.015198/+0.014724s，M05 A +0.013040126s，M07 A +0.011493s，F1 A +0.012082s。历史微秒级舍入保留为限制，未读取其私人包表。只纳入完整落在窗口内的样本；4–7.75s各89999个，与旧90000样本口径相比，所列两位小数RMS不变。
- 固定居民源[1,4.75)s，90000样本。去均值归一化互相关（NCC）在录音score起点3.9–5.0s逐样本搜索，取绝对峰值，并保留符号。没有调阈值或新增声学PASS门槛；搜索峰值不是统计显著性检验。
- 反向模板使用同一90000样本倒序、相同搜索范围。静默负控把原模板放在score 9.0–10.1s的候选起点搜索，长度及搜索宽度相同；M09-D1该段为极低能量。其他场景“计划安静”不等于已证明物理静默，F1及B不作为纯静默负控。
- 无居民负控使用已公开M03 B，同样搜索3.9–5.0s；其相同Tingting声线代理仍在讲话，可以揭示一般语音相似性误匹配。
- 辅助指标在波形峰值给出的同一位置计算：20ms Hann窗、10ms hop、1024点FFT；80Hz至10240Hz半倍频带，功率下限固定1e-12，逐频带去时间均值后计算log-band时间相关；另算20ms RMS包络相关。没有另找一个更宽松的时频峰值。低能量/量化噪声会限制这些指标，不能直接当作声源分离或AEC效果。
- 数值自检仅用固定源在内存中已知位移的副本：定位误差<1样本、NCC约1；全零候选返回UNDEFINED，不假装取得相关性或AEC PASS。未写出音频Fixture。

## 3. 同口径结果

| 录音 | score 4–7.75s RMS / Peak，dBFS | 居民绝对NCC峰值 | 反向负控 | 场景限制 |
|---|---:|---:|---:|---|
| M03 A | −17.03 / 0.00 | 0.41143 | 0.09321 | 用户/主控已判回声失败；WAV端点33个 |
| M05 A | −73.68 / −42.74 | 0.01585 | 0.01846 | 本轮不补造其用户听感 |
| M07 A | −57.83 / −26.79 | 0.08959 | 0.04232 | 用户确认听不到居民；弱峰不能解释成完全零残留 |
| F1 A | −20.12 / −0.35 | 0.04328 | 0.03522 | **包含真人，不是居民独讲A** |
| M09-D1 A | −17.16 / −2.21 | **0.44481** | **0.08852** | 用户试听PENDING；WAV端点0 |
| M03 B，无居民 | −24.42 / −9.81 | 0.07156 | 0.06490 | 代理语音负控，不作声学基线 |

M09-D1静默负控NCC=0.02697，M03 A同类负控=0.02819。M09-D1正向模板的包络相关=0.64943、时频相关=0.79411；M03 A分别0.56693/0.66101；无居民B为−0.00773/−0.10164。M05/M07没有这些同等强度的共同时间特征；不能据其低值宣布AEC达标，也不能用低能量下的时频负相关解释Apple算法。

M03 A与M09-D1峰值均为负相关（−0.41143/−0.44481）；绝对NCC允许整体极性差，不把符号当BUG。模板首样本的最佳录音位置分别为score 4.361615/4.365677s；按各自这个位置对齐两份录音，3.75s波形Pearson相关为**0.87581**。这是经过模板定位的有限交叉复核，不是独立真值或两次物理条件相同的证明。

### M09-D1高能量是否随居民出现

| 内容窗口 | 实际WAV RMS，dBFS |
|---|---:|
| score 0–3s | −83.98 |
| score 3–9s | −19.10 |
| score 9–11s | −99.90 |
| score 11–实际保存终点 | −97.85 |
| Player最后非零Render后0–500ms | −31.23 |
| 再后500–1500ms | −98.42 |

Player非零Render为score 4.193826–7.941488s；**约99.999978%的整份WAV平方能量位于这个窗口至其结束后500ms内**。模板最佳录音位置比Player非零起点晚约171.85ms。该差包含输入/输出缓冲、VP及报告时间基准等因素，不能命名为纯空气传播延迟或混响时间；结束后前500ms也不能全部算作异常长尾回声。

**CONFIRMED：** M09-D1处理后信号具有固定居民内容的波形、包络、时频及时序特征，明显高于本轮负控；与M03失败A的录音相似。**HYPOTHESIS（证据较强）：** 主要高能量是未被充分抑制的居民声残留，而非随机环境声单独造成。**UNKNOWN：** 可听程度、声学验收结论、泄漏机制及Apple内部AEC参考。没有Pre-VP原音，不能计算ERLE或虚构回声衰减量。

### F1和环境声的比较边界

F1 A约score+5.506s才提示真人开始讲话，其4–5.5s WAV RMS为**−79.48dBFS**，5.5–7.75s为−17.90dBFS。后者有真人，不能把全窗−20.12dBFS叫作强居民回声；提示时刻也不是精确物理起音。用户原话仍是“A听不到居民声音……A没有吞字消音和忽大忽小”。

M07 A的0–3s反而有−30.94dBFS能量，来源UNKNOWN，故不能声称该次全程环境完全安静或只是整个输入被静音。M05的9–11s为−51.26dBFS、明显晚于居民Render结束，来源同样UNKNOWN。未转录、推断讲话内容或把这些声音自动归给居民。

## 4. 配置、设备及损伤层级

历史信息来自对应[M03第9节](T3_2_A_R5_M03_BT_ABC_acoustic_review.md#9-再次授权后的单批次实机结果试听前交付记录)、[M05](T3_2_A_R5_M05_runtime_io_device_review.md)、[M07](T3_2_A_R5_M07_human_ABC_acoustic_review.md)、[F1](T3_2_A_R5_M07_F1_human_onset_device_review.md)。本轮只对M09-D1原JSON直接复核；没有以重读私人历史Manifest冒充新证据。

| 项目 | 有证据的相同点 / 差异 | 结论边界 |
|---|---|---|
| 外部目标 | 各A报告均TinyUSB输入60%、Mac内置输出55%、未静音，4秒预热、score+3请求同一居民WAV；A没有BT播放 | 名义条件相同，不证明实际声压/摆位相同 |
| 实际音量 | M09-D1输入HAL 0.6049382687、输出0.5500001311；M07/F1亦在用户授权下将当时不同输出值设回55%后才运行 | 历史目标百分比不能冒充各次精确标量及物理增益一致 |
| VP实际属性 | 各报告Input/Output=true、AGC=true、bypass=false、inputMuted=false；M09两次JSON读回直接确认 | VP=true不证明内部参考或AEC有效 |
| 格式/图 | M09两次六处格式完全相同：Input输出/Player输出/Mixer输入/Mixer输出/Output输入均16kHz/3ch非交错Float32，Output输出端口16kHz/2ch；M05/M07/F1报告相同，HAL硬件枚举48kHz；连接存在 | 端口格式不是物理硬件stream格式；未发现能解释强弱变化的新格式差异。M03缺这套完整运行态快照 |
| I/O getter | M09两份JSON均actualInput.id=actualOutput.id=defaultOutput.id，另有不同的defaultInput.id；非Aggregate，Aggregate列表空；与M05/M07/F1报告的关系一致 | `bindingStatus=UNKNOWN_UNVERIFIED_BINDING`；共享I/O getter不能直接判输入错接，物理输入来源仍UNKNOWN |
| Render非零区间 | M03 4.197262–7.944915；M05 4.195110–7.942773；M07 4.225577–7.973246；F1 4.194162–7.941831；M09 4.193826–7.941488s | 数十毫秒偏移保留；搜索已覆盖，不能直接解释约40–57dB输出能量差；不是物理声压证据 |
| 两次HAL读取ms | M05 2.052/1.583；M07 2.343/1.602；F1 2.482/1.546；M09 2.284/1.480 | 高/低能量均有相近读回耗时，未证实读回引发回声差异 |
| 观测/时钟 | M09 drop/stale及Native全部拒收0，异常诊断null；M07 A DEBUG skip5，Native仍190 buffers、接纳PCM连续、时钟拒收0 | 观测skip不等同真实丢帧。其他C/F1失败的时钟问题独立OPEN，不能归因本次回声 |
| Mic Mode/声学条件 | 所有Mic Mode UNKNOWN；实际物理声压、距离/遮挡、硬件DSP状态及内部参考未获同步证据 | “未修改”不等于证明状态相同 |

各次实际构建也不同：M03 dylib `6f81387668c4…`，M05 `d53fa0568e08…`，M07实机为 **`f1339555b1de…`**（不是后来交付但未实机运行的`094ce973dc6f…`），F1 `ecf6a86f4f05…`。完整SHA见上述各报告。M09-D1使用730d963候选、dylib完整SHA `5cec419639ec2a8d8a1da229a3b64c82eede47dedd6f81da826aada863c5701a`。不能据跨构建的声音差直接证明某次代码变更造成改善或回退。

M07 A“录音听不到居民”不单独证明其A运行中扬声器已经充分物理发声；另组C的现场听到居民/双讲见证不能跨RunID替A背书。原用户正向反馈保留，但低输出究竟来自有效抑制还是源声/物理路径较弱，仍缺独立输入声压证据。M05同样缺该证据。

M09同RunID、score 3–9s：Native ch0 RMS **−19.10456dBFS**，实际WAV **−19.10480dBFS**，差约−0.00024dB；Native Peak0.775329、WAV Peak0.775757。各Native声道的逐样本数值相等计数与比较数一致，不只是Peak相同；不推断Apple内部声道含义。M03/M05/M07/F1也已有大窗Native/PCM接近的证据。因此**后级PCM大幅整体增益损伤优先级降低**；Native只是VP后信号，不是VP前原音，现有大窗统计仍不能逐字排除全部局部转换损伤。

## 5. 原因排序与唯一下一步

1. **CONFIRMED：变化已存在于VP后的Native大窗能量，且M09/M03录音保有居民模板。** 最值得解释的是“居民声传播至VP输出”这一段的运行条件差异；本轮没有确认代码根因。
2. **HYPOTHESIS：Apple VP实际参考/适应或系统处理状态不同。** 正确属性与相同图格式没有覆盖内部参考，故合理但未证实；没有依据调整Mono/3ch、AGC、NS、AEC或新增Gate。播放前M07 A已有不同输入能量，但M05前窗也很安静且居民残留弱，不能把某一前窗能量直接定为适应成败的原因。
3. **HYPOTHESIS：实际声压、物理输入/设备状态或环境不同。** 名义音量一致而物理来源/声压/Mic Mode未知，不能排除。M09的强模板与播放期集中性使“仅随机环境干扰”解释不足，但不能排除同时叠加的环境声。

**是否需要立即再做设备实验：否。** 当前证据已证明输出行为有差异，再无控制地重复A不能区分上面两项假设。**唯一推荐动作：主控安排用户对既有M09-D1 A与M07 A作相同试听输出设置下的对照试听，记录是否可闻居民残留，再裁定M09-D1声学结果。** 不产生新录音；本任务不播放或自动安排试听，不预授权下一节点。即使听感确认失败，仍需另行审核能补足物理来源/声压或参考状态的受控取证，不能直接修DSP。

## 6. 实际检查、失败记录及隐私

| 执行 | 结果 |
|---|---|
| Git三方及7冲突保护元数据复核 | 开始时exit0；冲突7、索引/冲突文件/状态及14个未跟踪条目的stat均匹配原保护回执；交付后再核验 |
| 限定7 WAV / 1 JSON完整SHA、格式、字节数及M09同run身份核验 | exit0；历史私人Manifest未读，限制见第1节 |
| `python3 -B .build/r5_m10/analyze_m10.py` | 1轮，exit0；同窗、延迟搜索、三类负控及内存数值自检完成 |
| 两个已定位高能量WAV的有限对齐复核；M09运行态角色关系复核 | 各1次，exit0；仅输出数值/角色关系，不公开设备标识符 |
| 补充元数据打印错误 | 首次命令exit1：把JSON的`input_device`字符串误作对象调用`.get()`；保留失败，按真实字段类型复核exit0。主数值分析此前已exit0且未受影响，无音频或产品代码修正 |
| `bash tools/secret_guard/check.sh` | 1次，exit0，`secret-guard: ok`；另对新增报告单独查路径/标识符/秘密及文件白名单 |
| 文档、Git与Stage7边界 | 新增报告白名单、相对证据链接、`git diff --cached --check`及隐私检查；Stage7 Forbidden Checklist前后PASS |

数值脚本SHA `16d282e19dcb278ff493d2dc7fc21e06e939bfe5aca980baf84778f7cbd3e58b`；命令/退出回执及数值JSON只在本机Git忽略目录，未包含新音频载荷。所有输入文件在交付前再次核对SHA、大小、mtime和权限不变。M09-D1私人原件维持0600；原目录0700。报告不含私人绝对路径、设备UID/ID值、Token、原始Manifest或完整日志。

本轮设备采集/播放/App启动/Swift测试/构建/FULL_CURRENT均**0次**。没有扩大Raw/HIL/诊断基础设施，没有音频或生产源码进Git；原7冲突现场保护，未stash/reset/clean/强推。所有录音尾部PARTIAL保留，M09评分仅保存到score+14.871760s；未补零或虚构完整15秒。

五维SELF_REVIEW：范围/架构PASS；身份PASS（历史Manifest未复核单列）；数值方法PASS_FOR_LIMITED_COMPARISON；隐私/Git保护PASS；结论边界PASS（听感、ERLE、物理归属、内部参考及因果不冒充已证实）。新增确认产品代码缺陷CRITICAL/MAJOR/MINOR=0/0/0，不等于证明产品无缺陷；既有声学稳定性阻塞、时钟风险、尾包及观测限制继续OPEN。

Stage7 Forbidden Checklist：PASS。红线触碰无；仅新增本报告；不改代码、Runtime API、DR schema或平台target，不进入Stage8/Test3下一节点，无需扩大读取或设备授权。

```ini
R5_M10=COMPLETED_OFFLINE
M09_D1_RESIDENT_TEMPLATE_FEATURES=CONFIRMED
M09_D1_AUDIBLE_ECHO=UNKNOWN_USER_LISTENING_PENDING
CONFIGURATION_DIFFERENCE_CAUSALITY=UNKNOWN
NEW_DEVICE_RUNS=0
CONFIRMED_CODE_ROOT_CAUSE=NONE_IDENTIFIED
CLOCK_ROOT_CAUSE=UNKNOWN
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
