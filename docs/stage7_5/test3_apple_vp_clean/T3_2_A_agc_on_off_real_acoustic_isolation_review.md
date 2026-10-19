# T3.2-A · AGC ON/OFF真实声学隔离 · B组补执行审核

日期：2026-10-19。审核来源：**SELF_REVIEW**，无独立Reviewer。

**结论：B组真实AGC-OFF读回成功，控制/导出/退出完成，但幅度完整性FAIL。AGC-OFF没有消除本次满幅与突增问题，不具备声学通过结论。**

保留上一轮A，不重跑A；本次仅执行一次B。A原生每声道满幅0、PCM精确端点0；B分别为11994和10445。异常已经出现在Apple VP处理后的Native观测位置，不能仅用最终24kHz PCM16转换解释。没有未经处理Mic对照，尚不能确定异常来自输入硬件、Apple VP内部处理、声学条件或其组合，不能据此宣布Apple AGC存在BUG。

`AGC_OFF_NOT_SUFFICIENT`；`AGC_CONTRIBUTION=UNKNOWN`；`COMPARISON_LIMITED`；`SOURCE_REFERENCE_ISOLATION=UNKNOWN`。不将代理声源、相关性或控制链结果当作真人综合C/AEC验收。

## 1. 授权、范围和历史保留

用户在上一轮A完成、B未执行后明确要求“重新执行B组，然后提交推送输出结论”。承接原ON/OFF实验的本地录音、导出和有限分析授权，本次B只运行一次，不追加A、第三组或重试。不更改设备音量、路线、Mic Mode、DSP、素材或播放策略。仍经过原App播放/采集及JSON/WAV独立确认，无新系统权限请求。

本次只提交脱敏工程报告；麦克风WAV/PCM、原始Manifest、设备UID及原始日志均只留本机。未修改生产代码、测试、Runtime/Provider、Converter、AEC/AGC/NS算法或正式Human Gate。

上一轮A退出后，Codex读取已退出App的UI导致普通实例误启动，已终止；私人状态访问UNKNOWN，**原流程MAJOR保持OPEN**。本报告不覆盖其失败记录。本次退出快捷键未使原PID退出，经只读进程确认仍为同一隔离实例后，使用原菜单Quit；Quit后仅用进程和只读设备属性核验，没有再调用已退出App的UI，也没有普通实例重开。

## 2. 源码、构建与素材身份

执行源码HEAD、upstream、实时远端均为`bcfa84e96ba17fe1b314bc15f8f6a72542ae3eb5`，分支`Test3-AppleVP-Clean`。tracked工作区及staging无修改；原未跟踪D设备报告保持原SHA，其他Worktree未操作。

复用该候选已验证构建，启动前核验源码5文件冻结摘要、主程序及实际进程映射的debug dylib。没有重新编译或运行FULL_CURRENT。既有FAST8/8、FULL_CURRENT21/21、TEST3 11项不变量仅作同源码离线证据引用，不冒称本轮重跑。

| 产物 | SHA-256 |
| --- | --- |
| Debug主程序 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug dylib | `34ca1dc87ed28229fc2992503253d272eca4833dea5fdb2f7ceaf20c25267ba1` |
| Release主程序（只读核验，未运行） | `c9c209f7c7a1f5d772a4f3f5e0e384fa69ecb0897d1ada994ec283e6daef8477` |
| 固定居民Tingting，114032samples/4.751333秒 | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` |
| 固定代理Tingting，264310samples/11.012917秒 | `1c7081f8271251804e01234be8a0ff8344062d09c311592634cb8fdf6b992d0a` |

素材均24kHz/Mono/PCM16LE、A/B字节相同。居民保留原1秒静默前导。原同步控制器和NSSound UID播放器按字节复用，未扩展HIL。旧工具`--arm B`只表示4秒预热；实际ON/OFF身份由App profile、读回及独立runID确定。

## 3. 实际设备与配置读回

默认TinyUSB USB输入16kHz/1ch、输入60%；默认Mac mini内置扬声器48kHz/2ch、输出55%未静音；小爱蓝牙44.1kHz/2ch在线未静音、冻结UID摘要匹配，与居民设备不同。小爱音量属性UNKNOWN，未调整；Microphone Mode UNKNOWN。没有Windows、BlackHole或数字Loopback。

| 项目 | A（上一轮已取得，不重跑） | B（本次唯一执行） |
| --- | --- | --- |
| RunID | `B695F579-93A7-4E90-B696-931ADBF02F78` | `1BAF55D0-4883-442F-BD81-E486E3868B37` |
| 请求profile | APPLE_VP_AGC_ON | APPLE_VP_AGC_OFF |
| 实际AGC | true | false |
| VP input/output | true/true | true/true |
| bypass/inputMuted | false/false | false/false |
| Capture/Playback generation；configurationID | 1/1；2 | 1/1；2 |
| Warm-up / 总预算 / 评分 | 4秒 / 19秒 / 15秒 | 相同 |
| Native | 16kHz/3ch Float32 non-interleaved | 相同 |
| 最终PCM | 24kHz/Mono/PCM16LE，480samples/20ms | 相同 |
| 居民、代理播放 | 各一次 | 各一次 |
| App / 代理 / 控制器退出码 | 0/0/0 | 0/0/0 |

真实读回来自Native共享Engine属性快照，不用请求值代替。Native已经过Apple VP，不能当作未经处理原音。NS为原Apple组合处理，无独立公开读回。原Manifest的source_commit/build_identity保留null，真实源码/构建绑定来自外部运行receipt，没有静态填充。

## 4. Native与PCM分窗

下表为RMS/Peak，单位dBFS，分窗基于原内容时间。三Native声道在各有限观测窗数值相等；不推断Apple内部声道物理含义。预热PCM仅短暂处理并统计，没有保留成录音。

| 窗口 | A Native每声道 | B Native每声道 | A最终PCM | B最终PCM |
| --- | --- | --- | --- | --- |
| warmup | -81.722 / -64.327 | -44.607 / -28.127 | -81.789 / -64.734 | -44.608 / -28.131 |
| human_only | -16.114 / -1.472 | -6.631 / 0.000 | -16.115 / -1.466 | -6.640 / 0.000 |
| double_talk | -24.616 / -9.080 | -7.061 / 0.000 | -24.617 / -8.669 | -7.070 / 0.000 |
| human_tail | -24.781 / -12.517 | -5.193 / 0.000 | -24.782 / -12.444 | -5.203 / 0.000 |
| quiet | -32.837 / -14.172 | -15.296 / 0.000 | -32.815 / -14.048 | -15.279 / 0.000 |

B Native每声道满幅11994/302400：human_only3289、double_talk4650、human_tail3343、quiet712。超幅及非有限均0。最终PCM精确端点：-32768共4867，+32767共5578，合计10445，占保留样本约2.929%；253个20ms包含精确端点，单包最多149个。首末精确端点相对score为1.119195–11.325403秒。

原复用分析器的`abs(sample)>=32767`计数10709还包含-32767，**不等于**精确端点10445；两种口径不混用。各有声窗Native→PCM RMS差约-0.008至-0.010dB，说明高幅度在最终PCM之前已存在，不足以排除全部转换局部效应。

前报告21.72dB对应“相邻20ms线性RMS增量最大位置的dB差”，本报告明确区分定义：A为21.717dB@score1.094894秒，B为29.966dB@10.015487秒（-32.562→-2.595dBFS）。若直接最大化有限dB比值，A为53.106dB@0.854894秒，B为70.275dB@5.475487秒；低底噪进入有声也会产生大dB比值。零RMS→非零转换另计A6/B2次，不伪造有限值。这些是描述量，不是新增AEC验收阈值，也不能单凭其数值判AGC泵动。

score12秒后PCM RMS：A -96.796、B -73.531dBFS。quiet前部仍有端点，不能将软件STOP等同物理立即静音，也不能自动归因于AGC、环境声或某一声源。

## 5. 软件时序、相关性与对照限制

| 相对评分起点事件，秒 | A | B |
| --- | ---: | ---: |
| human_only提示 | 0.027357 | 0.008630 |
| double_talk提示 | 3.008287 | 3.024075 |
| human_tail提示 | 9.010754 | 9.026885 |
| quiet提示 | 11.013203 | 11.024372 |
| 代理PLAY调用前 | 0.002248 | 0.002542 |
| 代理STOP调用 | 11.000720 | 11.001100 |
| 首个非零Player Render内容 | 4.228991 | 4.261565 |

两组均先持续Capture/Converter/drain4秒，不重置Engine/Converter/generation；随后原15秒评分。B居民Player.play调用前/返回后约score3.110769/3.133264秒，playback completed约8.003436秒；实际完整nanosecond事件保留本机。调用事件、callback到达、AVAudioTime内容时间分别记录，不混用。

复用原差分归一化互相关和反转负控，没有改搜索范围或门槛。代理4个1秒参考片段（源0/2/5/9秒）：A |r|0.315/0.274/0.271/0.284，反转0.067/0.023/0.050/0.045；B 0.257/0.244/0.201/0.277，反转0.072/0.033/0.034/0.037。支持代理相关特征存在，不证明其可听完整性或独立近端资格。候选内容偏移A约0.810秒、B约0.745秒，不是已校准的蓝牙物理延迟。

居民两个参考片段A |r|0.157/0.080、反转0.044/0.115；B 0.178/0.079、反转0.045/0.112。后一个均未优于负控，可听残回声UNKNOWN。无自动播放、转录或用户试听，USER_LISTENING=NOT_RUN。

**COMPARISON_LIMITED**：两次不是同时运行，未测未处理Mic与外部声压；预热窗RMS本身明显不同，不能假定这是AGC单独造成或环境完全一致。软件触发接近不等于物理发声对齐，蓝牙代理未证明完整覆盖0–11秒。两路声音均由同Mac发声，可能参与系统回声参考，SOURCE_REFERENCE_ISOLATION=UNKNOWN。不能从混合RMS或相关性宣布真人保留、物理双讲或AEC PASS。

## 6. PCM覆盖、观测缺口与退出

两组均Native189 buffers/302400 frames，generated944、drained944、queued_at_seal0；保留743个20ms评分包/713280bytes/14.86秒；预热199完整包不留存，跨界排除1包、窗外排除1包。保留包序号/内容时间连续，content_time/native_clock及其余拒收、drop/stale、Playback underrun/rejected callback均0；Native coverage_valid=true。

A评分保留[0.014893917,14.874893917)秒；B [0.015486751,14.875486751)秒。quiet实际drain分别3.861691/3.851115秒。均不等于整15秒完整录音，TAIL_COVERAGE=PARTIAL，Converter partial tail UNKNOWN。queued0不代替尾部证明。

时序统计skip A2/B1；Input见证sample/host discontinuities A2/2、B1/1，B最大Input内容end gap约99.999ms。它们与Native准入coverage有效/拒收0分开报告：缺少逐次跳过/重建载荷，不能擅自认定真实PCM丢失，也不能声称整条Input见证无缺口。两组Player Render sample/host discontinuities、duplicate/backwards/missing均0；最大end gap A1459ns/B709ns。Player Tap位于Mixer之前，不代表扬声器声压或Apple AEC内部参考。

host_timing.identityChanges两组均1；configurationChanged均2次，B末次在captureStopped之后约60微秒，routeChanged0。保存计数及UNKNOWN，不据此隐去身份变化或伪称中途换代失败。原generation/configuration守卫未拒收。

B正常Seal，timing callbacksClosed=true。JSON/WAV导出后原App菜单Quit，App/代理/控制器exit均0；只读确认无残留，三目标设备running均0。未重开普通实例，未追加设备操作。

## 7. 证据身份与隐私

原受控`Library/Caches/com.eterna.aftelle.debug-apple-vp-evidence`目录0700，文件0600、当前用户所有、无symlink，独立run命名，无覆盖。每组WAV均713324bytes/356640samples；评分PCM均713280bytes，预热保留0。原始Manifest与音频仅本机，未复制进Git或上传。

| 文件 | SHA-256 |
| --- | --- |
| A `run-B695F579-93A7-4E90-B696-931ADBF02F78.json`，64993bytes | `70dc8541cb208b0887632c953ba96f478a1f6fa1cc259bfa3e78243a2c49508e` |
| A 同run WAV | `0f3dc2e4cdaa642369b673605d4794c9ea603c6c2e6abe6b0db6f0f155708c52` |
| B `run-1BAF55D0-4883-442F-BD81-E486E3868B37.json`，64682bytes | `37f40ec61260a844af3de9a00f55b1cf564030c3db7245654f313bea5b07d356` |
| B 同run WAV | `a4449ad3d5d1f4e34934a0c7c0285b4e9946a4f48297182bf6c9a8a5dddb047d` |

B的PCM数据SHA `9875a0087153d4d19a8bb320d4cb5508bb390a076a2e2b16e4bd10bca6000915`与processed_sha256一致。仅本机内存分析本对照A/B及两份指定固定非私人参考，没有读取其他私人录音。新的脱敏数值receipt保存在独立受保护Caches目录，无PCM载荷。

## 8. 实际执行与首次失败保留

- 原`native_dual_sound --preflight`：本次前后各exit0，只读属性，不打开音频流；输入增益另用CoreAudio只读属性核验。
- `python3 B_OFF/sync_once.py --arm B --executable <核验Debug路径> --fixture <固定代理路径>`：一次B，exit0；ScoreControl PLAY/STOP各一次，App与代理exit0。
- `python3 analyze_current_B.py`：exit0；仅修改既有分析器RUNS绑定及输出文件名，数值方法不变。补充精确端点、分窗与两种RMS增量定义检查exit0，无新增声学验收门槛。
- 第一次导出身份核对exit1：控制器UUID为小写、应用文件名为大写，字符串比较失败；改为UUID值比较后通过。没有改变原文件或失败记录。
- 第一次退出核对exit1：快捷键后原PID未退出；先只读确认仍为同一隔离实例，再原菜单Quit，最终核验exit0。没有对已退出App读取UI，也没有第二次Capture。
- 构建、FAST、FULL_CURRENT、SwiftFormat/SwiftLint本轮NOT_RUN：只新增报告，原源码未变；历史全量lint FAIL及C19/C23债务保留，新增Swift B类0（无Swift变更）。报告提交前执行定点隐私/格式/Git安全检查，结果见本报告末尾。

## 9. 五维SELF_REVIEW与问题登记

| 维度 | 结果 |
| --- | --- |
| TECHNICAL | FAIL（B幅度完整性）；控制链/真实读回/导出退出PASS，不代表声学PASS |
| ENGINEERING | PASS（本次执行边界及NO_CODE_CHANGE）；历史lint债务与前轮流程REWORK保持，未作生产修复 |
| EVIDENCE | PARTIAL：原生/PCM异常可复核；原音、声压、物理对齐、源/参考隔离及试听UNKNOWN |
| CONSISTENCY | PASS：保留A历史失败和B真实异常；两种端点/RMS口径明确，不冒充真人或正式Test3 |
| Stage7 Forbidden Checklist | PASS（本次范围）：单次授权B、无生产改动/Provider/私人上传/新平台/Stage8；前轮普通实例MAJOR不因本项通过而关闭 |

新增CRITICAL确认0；新增**MAJOR1：AGC-OFF时Native/PCM大量满幅，停止后续设备实验，根因及修复待主控授权**。新增MINOR说明1：前报告RMS“最大”定义补充澄清。既有Input/Render观测skip、内容首尾、partial tail、物理覆盖/参考隔离限制不关闭；上一轮执行隔离MAJOR继续OPEN。未发现可确认的生产源码缺陷，不能自动归因或修改AGC算法。

本次唯一有意改变的配置是AGC；观察到OFF没有解决满幅。由于对照限制，不给出AGC改善支持结论，也不以OFF更响/有相关语音宣布人声完整保留。下一步仅建议主控审阅该对照及Native先出现的幅度异常，确定单独节点；本轮不追加实验、改音量或修复代码。

```ini
A_AGC_ON_4S=PRIOR_COMPLETED_ONCE
B_AGC_OFF_4S=COMPLETED_ONCE_AMPLITUDE_FAIL
AGC_OFF_DEVICE_READBACK=PASS_FALSE
AGC_OFF_NOT_SUFFICIENT=true
AGC_CONTRIBUTION=UNKNOWN
COMPARISON_LIMITED=true
SOURCE_REFERENCE_ISOLATION=UNKNOWN
USER_LISTENING=NOT_RUN
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
SQ-M1=OPEN
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```

## 10. 报告提交前检查

- `bash tools/secret_guard/check.sh`：exit0，`secret-guard: ok`；原工具未提供cases数量。它排除docs，因此另外对本报告做定点隐私扫描，不能只用此Guard替代报告审查。
- 本机`python3 check_report.py`：19项定点检查，exit0；检查secret/音频载荷、私人绝对路径及LAN地址、三设备UID摘要、Markdown空白/代码围栏、runID及FAIL/锁闭状态、既有MAJOR保留、冻结源码与实际构建、进程退出、原未跟踪文件身份。
- `git diff --cached --check`：exit0；staging白名单仅本报告，没有WAV/PCM/原始JSON/日志或其他文件。没有生产Swift变更，不运行无关App构建及音频回归。

仅报告提交并推送，音频不上传。完成后停止，等待ChatGPT主控审核。
