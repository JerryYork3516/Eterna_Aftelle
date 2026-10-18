# Eterna Aftelle · T3.2-A 综合C真人声学审核 · 2026-10-18

状态：**FAIL / REVIEW_PENDING**。ChatGPT主控负责最终裁定。本报告记录首次综合C，以及用户看到首次失败后明确要求追加的一次同条件复测；两次结果分别保留。没有修改生产、测试、音频参数或正式合同。

## 1. 结论与审核材料

两次控制链和已drain PCM连续性通过。首次用户反馈居民声音仍可听见、人声很小；追加复测用户确认居民和真人均可听见，并存在忽大忽小。**T3.2-A不具备声学收口条件**，R3-M01与起音归因继续OPEN/UNKNOWN。

- [首次原字节处理后WAV：B223A633](evidence/comprehensive_c_20261018/run-B223A633-CBA1-474D-90EC-0FB68F7496BF.wav)
- [用户追加复测的原字节处理后WAV：56C61C30](evidence/comprehensive_c_20261018/run-56C61C30-1CD3-4B63-9A1D-8D7F3FD98878.wav)
- [脱敏证据清单、文件SHA与分段统计](evidence/comprehensive_c_20261018/manifest.json)

**音频身份说明：**以上两份文件都是既有DEBUG入口导出的Apple VP处理后录音，提交副本与本机原始导出逐字节一致。该入口没有保存未处理的麦克风原音，因此无法提供一组额外的处理前WAV；本次没有重新降噪、重采样、归一化、裁剪或制作另一组“处理后”版本。

## 2. Git、构建与P0

- 分支：`Test3-AppleVP-Clean`。实验源码HEAD、upstream及实时远端起点均为`70962420c0132634e8d93243d0a2c046bee65a52`。
- P0 PASS；保留既有未跟踪审核文件，其他10个Worktree的HEAD/status摘要未变。此次新增文件仅本报告、脱敏manifest及明确授权的两份WAV。
- 复用当前源码对应的FULL_CURRENT 21/21及其FAST/TEST3证据，核验3份receipt、36个日志引用/28份唯一日志、源码与测试摘要。没有重跑未变化的构建或全套回归。
- Debug主程序SHA-256：`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`。
- Debug dylib SHA-256：`28c8e694a40652055fd7747f9414cd64a9abfb3aa7c222f4fa4bdd5fb4217fba`。
- Release主程序SHA-256：`a28ddb1651f4793f2761aabc31ad8374564f58cab9075bfee83b1454337b8528`。
- 本轮只读符号检查exit0：Debug声学符号743、启动flag存在；Release声学符号0、启动flag不存在。未启动Release App。
- 实际两次App命令与加载映像均验证为上述Debug产物、参数`--apple-vp-acoustic-test`，使用`Prepare comprehensive C · Guided single run`及`RECORDING`。未使用STATS_ONLY或silent-smoke。
- 目标默认设备为USB麦克风/内置扬声器，输入60%、输出55%、未静音；未调整设备、音量或系统模式。Microphone Mode=UNKNOWN。App自身权限流程通过，未出现新的系统权限请求。
- 固定Tingting素材为24kHz/Mono/PCM16LE、114032 samples、228108 bytes、4.751333秒，前1秒全零。SHA-256：`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`。本次不额外提交参考素材。
- 源统计JSON中的`source_commit`、`build_identity`保持null；通过源码、候选diff、构建摘要及实际加载映像建立外部绑定，没有把静态字符串写入原JSON。

## 3. 授权与次数

首次分别获得“授权本轮录音及本地JSON/WAV导出，已就绪”和“授权本轮WAV的本地离线分析”。首次失败后，用户明确说“重新进行一次实验”，并另行确认“授权新增WAV本地分析，已就绪”。因此实际为**首次1次＋用户主动要求追加1次**，每个run独立App实例，没有自动重试。

第二次反馈后，用户明确要求提交推送两次音频供主控审核。本次上传例外仅覆盖上述两份原字节导出WAV及脱敏工程报告/manifest；不扩展到其他录音、DR、Session、Memory、密钥或原始设备日志。

## 4. 控制链、PCM与覆盖

| 项目 | 首次 B223A633 | 追加 56C61C30 |
|---|---|---|
| 完整runID | B223A633-CBA1-474D-90EC-0FB68F7496BF | 56C61C30-1CD3-4B63-9A1D-8D7F3FD98878 |
| 四阶段软件偏移秒 | 0 / 3.015 / 9.001 / 11.021 | 0 / 3.001 / 9.021 / 11.012 |
| Playback prepare/start/completed | 各1次 | 各1次 |
| Playback completed，软件偏移秒 | 7.967 | 7.974 |
| Capture stopped，软件偏移秒 | 15.031 | 15.020 |
| Capture/Playback generation；configuration | 1 / 1；2 | 1 / 1；2 |
| VP Input/Output；AGC | true/true；true | true/true；true |
| bypass；inputMuted | false；false | false；false |
| 原生输入 | 16kHz / 3ch / Float32 / noninterleaved | 相同 |
| Native buffers / frames | 150 / 240000 | 150 / 240000 |
| coverage_valid | true | true |
| generated / drained / queued_at_seal | 749 / 744 / 5 | 749 / 744 / 5 |
| 已drain PCM | 744个20ms包；14.88秒 | 相同 |
| 包序号、20ms时间及960bytes检查 | 全部连续/正确 | 全部连续/正确 |
| native拒收各原因、drop/stale/rejected/underrun | 均0 | 均0 |
| quiet软件阶段已验证内容覆盖 | 3.852秒 | 3.862秒 |
| DEBUG skippedUpdates | 4 | 4 |
| Input观测sample discontinuities | 2，最大约300ms | 4，最大约100ms |
| Player Render观测discontinuities | 0 | 0 |
| Native每声道满幅/超幅/非有限样本 | 51 / 0 / 0 | 20 / 0 / 0 |
| WAV触及PCM16端点样本 | 53 | 13 |
| 结束 | Seal/Stop/Shutdown、正常菜单Quit、进程消失 | 相同 |

Input时序观测少于Native累计统计，两次均为`UNKNOWN_OBSERVATION_LOSS`。该DEBUG统计使用可跳过更新机制；已接纳包连续、Native coverage有效且拒收为0，现有证据不能把观测缺口直接解释成实际采集丢帧。

两次配置变化记录各2次：一次在Engine启动前，一次在captureStopped之后关闭资源时；没有记录运行中路由变化。导出中的`capture_state=capturing`来自停止前快照；后续captureStopped事件、Shutdown和进程消失已分别核验。

封存时5个排队包约100ms，不能视为已导出，也不直接等于丢帧。Converter partial tail为UNKNOWN，**C_TAIL_COVERAGE=PARTIAL**。没有补零、拼接或改时间戳；不宣称完整15秒全部进入WAV。

调用时间、callback到达时间与AVAudioTime内容时间分别记录。上述四阶段为软件引导时间；PlayerNode Tap位于Mixer之前，不代表物理扬声器声压或Apple内部AEC参考。物理处理延迟未校准。

## 5. 本地有限音频分析

只读本轮两份WAV及固定非私人TTS；没有自动播放、模型调用、其他私人录音访问或额外音频输出文件。两份WAV均为24kHz/Mono/PCM16LE、357120 samples、14.88秒、714284 bytes，PCM摘要与各自统计JSON一致。

| 软件引导分段RMS，dBFS | 首次 | 追加 |
|---|---:|---:|
| human_only，约0–3秒 | -81.73 | -81.20 |
| double_talk，约3–9秒 | -19.75 | -18.18 |
| human_tail，约9–11秒 | -98.05 | -29.88 |
| quiet，约11秒至WAV结束 | -96.89 | -38.23 |

- 首次满幅样本集中于约4.92–4.94秒；最长连续端点序列3 samples。追加满幅样本集中于约3.17–3.19秒；最长连续端点序列2 samples。Native和转换后样本计数分别列出，不相互替代。
- 追加用户确认从真人独讲提示一直说到停止提示，但约0–3秒处理后能量仍接近静音；这是需要主控审查的人声完整性证据缺口。未保存未处理输入，无法据此定位为AEC、AGC、NS、设备拾音或参与时序中的某一具体生产BUG。
- 现有Player Render首个非零内容在WAV内容时间轴约4.234秒。追加的显著瞬态约3.17秒更早出现；未校准物理延迟，且真人在场讲话，不能把它认定为历史80ms首字残留，也不能归因于播放启动或AGC。
- 固定参考TTS在1.000秒出现首个非零样本。使用相同的有界探索比较：12样本平均、围绕Player内容锚点±500ms、2ms搜索步长；最大绝对归一化相关性首次0.324、追加0.392。首次播放前1秒对照窗口约±0.017。混合真人、回声抑制和未知物理延迟会改变波形，相关性不作为AEC真值或验收门槛。
- 无法可靠区分每段声音的声源；历史80ms起音是否复现仍UNKNOWN。满幅及响度变化需与用户听感共同审查，不以这些统计直接宣布AGC BUG或AEC性能PASS。

## 6. 用户反馈与逐项状态

首次原话：

> 能听见居民声音，人声很小。重新进行一次实验

首次讲话时段补充：

> 记不清具体时段

追加复测原话：

> 能听到居民声音和我的人声。存在忽大忽小，确认我从“真人独讲”提示一直讲到“停止讲话”，现场听到居民发声并且同时讲话超过一秒。还是失败，提交推送后让GPT审核一下两次原始WAV和处理后的WAV

| 验收项 | 首次 | 追加复测 |
|---|---|---|
| C_CONTROL_CHAIN | PASS | PASS |
| C_CAPTURE_CONTINUITY | PASS，已接纳PCM；DEBUG观测有缺口 | 相同 |
| C_PLAYBACK | PASS，软件完成；居民声音用户报告可听见 | PASS，软件完成及用户现场确认 |
| C_HUMAN_VOICE_RETENTION | PARTIAL，人声很小且实际讲话窗口UNKNOWN | PARTIAL，真人可听见；首尾/全阶段完整性未证实 |
| C_RESIDENT_ECHO | FAIL，用户可听见居民声音 | FAIL，用户仍可听见居民声音 |
| C_ONSET | UNKNOWN | UNKNOWN |
| C_GAIN_STABILITY | PARTIAL，满幅证据；首次无单独稳定性确认 | FAIL，用户确认忽大忽小 |
| C_PHYSICAL_OVERLAP | UNKNOWN | PARTIAL，用户见证超过1秒，未独立测量 |
| C_TAIL_COVERAGE | PARTIAL | PARTIAL |
| C_USER_LISTENING | FAIL | FAIL |

这些结果属于T3.2-A工程声学验证，不累计正式53-B/53-C次数。没有Provider插话取消、声源资格或Runtime授权验收。

## 7. 五维SELF_REVIEW与问题登记

本轮没有独立Reviewer；以下全部为Codex SELF_REVIEW。

| 维度 | 结果 | 依据 |
|---|---|---|
| TECHNICAL | FAIL_ACOUSTIC；控制链PASS | 两次用户报告回声，追加报告增益不稳；PCM/VP/生命周期证据保留 |
| ENGINEERING | REWORK / DEBT_DEFERRED；本次提交范围检查PASS | Swift/测试/配置增量0；没有新Owner/Engine/Tap或音频行为改动；历史全量SwiftFormat/SwiftLint FAIL及C19/C23不变，不重跑或改判 |
| EVIDENCE | PARTIAL | 原字节、摘要、实际构建及用户原话绑定；观测skip、尾部、物理时长和起音UNKNOWN如实保留 |
| CONSISTENCY | PASS | 首次失败保留；追加来自用户新指令，分析另获授权；本次音频提交也有用户明确例外；没有推进后续节点 |
| Stage7 Forbidden Checklist | PASS | 六红线均未触碰；未改Runtime/Provider/DR/Store/粒子/Intent边界 |

- CRITICAL：0。
- MAJOR-C01：声学不达标的新证据OPEN。两次可听居民声音；真人完整保留未获证实。尚未定位具体生产代码根因。
- MAJOR-C02：追加复测响度不稳OPEN。用户明确报告忽大忽小，并有满幅样本；不把观察直接等同于AGC缺陷。
- 既有MINOR：DEBUG观测skip/时间见证不完整；5个queued尾包及Converter partial tail未知，均继续OPEN。源JSON身份字段null由外部源码/构建绑定说明，不伪造补齐。
- 历史R3-M01/起音归因继续OPEN/UNKNOWN；不改写R2/R3或先前单次A的历史结论。

## 8. 交付检查与停止边界

本轮P0、加载映像、文件/PCM摘要、分包、权限与本地分析命令均exit0；两次LaunchServices `open`均exit0。正常退出后`pgrep -x Aftelle`返回1且无PID，表示进程不存在；LaunchServices未提供直接App退出码，不能改写为App exit0。期间若干UI操作被工具因窗口变化拒绝，均先刷新状态再操作，发生于Prepare/文件选择/Start确认之前，没有额外启动采集。

提交前核验文件白名单、Markdown链接、JSON schema、两份WAV格式/摘要/原字节一致性、敏感文本及Secret Guard。既有Debug/Release、Release/Architecture Guard、FULL_CURRENT均明确复用当前代码证据；不声称本次重新执行。Swift增量为0，新增B类代码问题0；历史规范FAIL不改判，无新规范配置或永久例外。

本次提交仅包含两份明确授权的音频和脱敏材料。没有提交原统计JSON、机器绝对路径、私有设备标识、密钥、DR、Session/Memory或其他实验音频；本机旧结果未覆盖。文件SHA见manifest，公共提交访问范围遵循该仓库权限，原Caches的0700/0600不等同于Git仓库访问权限。

本轮停止，不再设备复测或实施修复。最终状态：R3-M01=OPEN；Onset Attribution=UNKNOWN；T3.2-A=BLOCKED；T3.2-B=NOT_AUTHORIZED；T3.3=NOT_STARTED；SQ-M1=OPEN；Qwen Strict Overlap=0/3；Formal Test3=BLOCKED；Test3.execution_authorized=false。两次音频供ChatGPT主控复审后另行裁定。
