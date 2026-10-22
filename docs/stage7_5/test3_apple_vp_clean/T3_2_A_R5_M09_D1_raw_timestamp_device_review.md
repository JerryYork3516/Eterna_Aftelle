# T3.2-A · R5-M09-D1 · 原始时间戳单次实机取证

结论：**一次A组完成，历史时钟异常 NOT_REPRODUCED。** `native_clock=0`、`content_time=0`，`raw_timestamp_diagnostic`字段存在且为null；没有首次异常窗口可供根因分析。不能宣布时钟问题修复、AEC有效或T3.2-A通过。完成后不追加实验。

## 1. 授权、Git及实际身份

- 起点本地HEAD/upstream/实时远端均为 `730d96324d9efba789b52cb941c73b1fb7dea8db`。沿用登记的干净隔离Worktree；生产源码及测试代码没有修改，仅提交本报告。
- 初始任务只授权预检，已因输出75%停止。之后用户明确授权“仅将Mac mini内置扬声器音量精确设为55%，然后继续只读预检；完成后继续，无需我授权”。本轮以此**新的明确继续授权**执行一次A，不继承旧R4/M03/M07同意回执。
- 本机新建M09-D1同意与排他消耗记录，capture/playback上限各1；原系统权限、应用可见录音同意、JSON/WAV分别显式导出均保留。旧界面/ScoreControl仍显示R5_M03/A标签，标签不是本轮授权证据。
- 使用M09已有构建，未重新编译。App主可执行SHA：`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`；实际Debug dylib SHA：`5cec419639ec2a8d8a1da229a3b64c82eede47dedd6f81da826aada863c5701a`。
- 启动原DEBUG声学入口及既有A组/4秒预热模式，按确切PID核验真实App和dylib映射路径及文件SHA，未按应用名称启动其他实例。控制器只在本机精确登记本次M09 dylib期待值；原二进制校验仍执行，没有伪造Fake身份或删除校验。
- Manifest的 `source_commit` / `build_identity` 仍为null，不能冒称已有内嵌Git身份；本轮用启动前源码/产物摘要、实际进程映射和外部执行回执绑定730d963候选。

## 2. 设备、权限及准备失败记录

- 默认输入：TinyUSB；系统显示60%，HAL标量 `0.604938268661499`，原值未改。默认输出：Mac mini内置扬声器；仅按新授权从0.75设为请求0.55，实际HAL读回 `0.5500001311302185`、系统显示55%，未静音。
- 两设备在线，实验前后未运行；默认路线、目标身份及设置前后一致。Mic Mode=UNKNOWN。未启动蓝牙代理、REF、普通Aftelle或其他实验；旧常驻音频驱动进程不作为本轮采集进程，系统默认输入不是该虚拟设备。
- 外部TCC只读查询被拒，记UNKNOWN，不误报App权限被拒。原App权限流程随后允许本轮真实采集，未操作新系统权限弹窗或修改权限。
- 固定非私人居民WAV SHA：`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`；24kHz/Mono/PCM16LE、114032帧、4.751333秒，前1秒全零；未换素材、改增益或播放策略。
- 原双输出预检工具因要求小爱同时在线而exit1；只读重查保留该失败回执，未启动音频。改用本机有限Core Audio属性查询核验本任务两个目标，没有建立新采集器或HIL框架。
- 本机首次音量操作前的自检把输入HAL标量误要求为精确0.6，因0.60493827而exit1，发生在任何音量写入前；改为原有系统显示60%合同并核验实际输入值不变。未调整输入或降低原应用门禁。
- 同一PID的UI读取遇到AX属性/AppleScript变量错误，之后使用实际控件description完成；Cmd-Q未退出，改用原“退出Aftelle”菜单正常退出。没有重启或第二次Start。

## 3. 实际次数、时间及生命周期

RunID：`29B4B89A-DBE0-418D-93EE-ADF5CC8D18E7`；Capture generation=1、configurationID=2、Playback generation=1。

| 项目 | 实际证据 |
|---|---|
| App / Capture / 居民播放 / JSON / WAV | 各1次；自动重试0，蓝牙0，REF0，B/C0 |
| Native输入 | 190 callbacks，304000帧/声道，16kHz/3ch Float32，样本计数对应19.000秒 |
| 评分 | 原4秒持续预热＋15秒评分；预热PCM留存0字节 |
| VP实际读回 | Input=true、Output=true、AGC=true、bypass=false、inputMuted=false |
| 输入首callback | 内容相对评分起点 -4.008239541s；到达 -3.876431875s |
| Player.play调用 | 相对score+3.047824875s；返回+3.065604333s |
| 真实Player Render非零 | score+4.193826001至+7.941487959s；是Player Tap内容时间，不冒充物理声压或Apple内部AEC参考 |
| Playback完成事件 | score+7.931957792s，started/completed各1，underrun/rejected callback均0 |
| Stop事件 | score+15.024749250s；原异步Stop控制事件晚于评分截止约24.75ms，不声称ADC精确在某个软件时刻关闭 |
| Seal / Shutdown / Quit | Native sealed=true、callbacksClosed=true；原退出菜单、App及控制器exit0；退出后目标设备running=0 |

M04的Engine启动后/居民开始后两份快照均绑定本RunID/代次/配置，VP状态稳定，无issue；读取耗时2.284166ms / 1.479916ms。实际I/O物理绑定仍 `UNKNOWN_UNVERIFIED_BINDING`，不因系统默认路线正确或VP=true宣称内部参考正确。读回耗时与历史2–3ms时钟偏差是不同观测量，本次无因果结论。

整个控制循环245.52秒含文件选择、同意、导出和退出等待，**不是录音时长**。JSON的capture_state=capturing为封存前采样的历史状态，不能单独作为资源泄漏依据；独立的封存、进程退出及设备未运行证据已核验。

## 4. 时钟取证结论

| 观察 | 结果 |
|---|---|
| native_clock / content_time | 0 / 0 |
| raw_timestamp_diagnostic | 字段存在，值null；正常情况按M09设计不导出滚动窗口 |
| 原始host ticks、mFlags、timestamp.sampleRate、rateScalar | **本次未触发保存，NOT_CAPTURED**，不填造数值；Native格式16kHz不能冒充timestamp.sampleRate原字段 |
| Native sampleTime | 首644、末303044；190个1600帧callback，sampleDiscontinuities=0 |
| 相邻内容时间 | 名义100ms；最大间隔100.002500ms，最大end gap 2500ns=2.5µs；hostDiscontinuities=0 |
| 到达时间 | 仅已有首末/聚合记录；没有异常前后逐callback arrival窗口，不能伪造相邻arrival差 |
| 其他时序 | missing/backwards/duplicate/stale callbacks/invalid buffers/skip均0；identityChanges=1；第二次configurationChanged发生在Stop后0.088833ms，与tearDownGraph增加配置并关闭旧观察器的源码路径一致；运行时两份快照仍为configurationID=2，routeChanged事件0 |
| 最终已保存PCM | 743包、序号202–944连续；每包20ms、960bytes，全部相邻内容时间差为20ms |

所有Native拒收计数为0，capture drop/stale为0，Manifest error/capture_error/playback_error为null。**CONFIRMED**：本次有效采样内没有重现既有拒收，保存的PCM无内部时间缺口。**UNKNOWN**：历史偏差来自何处，以及真实异常时flags/rateScalar/arrival的关系。此前M03/M07/F1的异常及失败仍保留，不能由一次未复现撤销。

## 5. WAV覆盖与有限数值检查

- generated=949、drained=944、queued=5；留存743包。199个预热包未留存，另1个跨边界包、1个窗外包排除。Native总包统计不能冒充WAV全部内容。
- 评分WAV实际14.86秒/713280 bytes PCM，覆盖score+0.011760459至+14.871760459s。quiet已drain覆盖3.867539667s；尾包覆盖PARTIAL，Converter partial tail=UNKNOWN。不补零、不补造15秒完整文件。
- 逐包按Manifest内容时间映射实际WAV样本，边界跨样本排除。Native表列ch0，当前各分窗三声道有限样本逐样本数值相等；不解释三个声道的物理含义。Native仍已过Apple VP。

| 评分窗口 | Native RMS / Peak | 真正WAV RMS / Peak | WAV RMS dBFS | WAV纳入样本 |
|---|---|---|---|---|
| 0–3秒 | 6.3304526e-05 / 0.00065712846 | 6.3229724e-05 / 0.00067138672 | -83.98 | 71717 |
| 3–9秒 | 0.11085927 / 0.77532899 | 0.11085625 / 0.77575684 | -19.10 | 143999 |
| 9–11秒 | 9.4214824e-06 / 4.0370098e-05 | 1.0119724e-05 / 3.0517578e-05 | -99.90 | 47999 |
| 11–15秒 | 1.1479579e-05 / 5.6972523e-05 | 1.2805084e-05 / 6.1035156e-05 | -97.85 | 92922 |

独立score4–7.75秒WAV：RMS 0.13862003（-17.16dBFS），Peak 0.77575684。Native与PCM播放窗幅度接近，本次均无满幅、非有限或PCM精确端点样本。播放时段仍有明显能量，是声学线索；未做本轮用户试听、转录或源分离，不以RMS代替AEC听感PASS，也不在本节点现场修DSP或追加实验。

## 6. 本地证据、验证与交付边界

| 本轮原件 | bytes | SHA-256 |
|---|---|---|
| JSON | 83623 | `1475a4ad1fb013a11e730062878eaef1b02a662124d1e712372464d490de83de` |
| WAV | 713324 | `a8ef35336eac18792e6e03772a1148774ea368da495bbd567a89f3f67ec1501d` |
| WAV内PCM data | 713280 | `49953e1a1a8726c72a3988d5c7f9049a09127e0d4954711c2564dea6736c65cc` |

目录0700、原件0600、当前用户所有、无symlink。67个历史Caches条目的大小/mtime/权限不变；新增仅本轮JSON、WAV及控制回执目录，不覆盖历史结果。音频、原始Manifest、设备UID和完整日志仅在本机，Git只提交本报告。

实际验证：已核验Git三方、现有M09 8/141及49/1012回执（未重跑）、源文件与实际App/dylib摘要、加载路径；Core Audio只读前后状态exit0；原控制循环exit0；本轮有限WAV/包时间分析exit0（一次）；WAV PCM data SHA与Manifest匹配；文档范围/隐私、`git diff --check`、Stage7 Forbidden Checklist通过；Secret Guard一次exit0。无生产源码改动，未重新编译或运行FAST/FULL_CURRENT/Swift回归。

五维SELF_REVIEW：范围/架构PASS；身份/控制链PASS；时间证据PASS_FOR_NOT_REPRODUCED_ONLY；隐私/历史保护PASS；声学及根因结论UNKNOWN。新增已确认代码缺陷CRITICAL/MAJOR/MINOR=0/0/0；既有时钟拒收与声学风险OPEN，尾部/实际输入归属/构建Manifest空字段等限制保留。

## 7. 下一项建议与停止

**本轮没有足以支持安全修改时钟算法的直接证据。** 不放宽容差、不以缺失快照当作修复成功，不自动再次采集。建议主控先审核本报告及本机证据；只有另行决定新的单次取证时才执行。当前不推进新的代码修复、真人/代理实验或Test3。

```ini
R5_M09_D1=COMPLETED_NOT_REPRODUCED
CLOCK_ANOMALY=NOT_REPRODUCED
RAW_ANOMALY_WINDOW=NOT_TRIGGERED
SAFE_CLOCK_FIX_IDENTIFIED=false
FURTHER_DEVICE_EXECUTION=NOT_AUTHORIZED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
