# T3.2-A-D2-F1-R1 — Target Route Silent Validation

日期：2026-10-17。状态：`REVIEW_PENDING`。

本轮结论：USB 麦克风＋Mac 内置扬声器上的 A/B/C 无声控制链各一次通过；`CONTROL_CHAIN_READY=true`。`READY_FOR_HUMAN_TEST=false`：实际输出音量为 0，系统静音开启。需要用户在将来的有声测试前手动解除静音、设定并确认测试音量；Codex 未修改设备、音量或系统麦克风模式。本轮没有 AEC、人声保留、双讲质量或用户试听 PASS。

## 1. Git、范围与授权

- Repository：`JerryYork3516/Eterna_Aftelle`；branch：`Test3-AppleVP-Clean`。
- 运行源码提交：`ebede59755ad799d79b974a3208259b6a212862a`。开始时 HEAD、upstream 与实时远端一致，staging 为空，受跟踪工作区干净。
- 原有未跟踪的 `T3_2_A_D_real_device_validation.md` 保留，摘要与本轮前保存身份一致，不纳入提交。
- 本轮仅新增本报告。生产源码、测试、构建配置、旧报告、README、DEVLOG 均不改。ACE3 与 Apple VP 研究 Worktree 的 HEAD、status/diff 摘要复核一致。
- 操作授权来自本轮 R1 指令：每项一次、最多 4 秒、仅无声设备控制与统计。没有新的系统权限请求；系统设置中 Aftelle 麦克风开关已开启，只读核验，未操作开关。
- 未播放有声 WAV，未要求用户讲话，未保存输入 PCM、生成录音 WAV、读取私人 DR/Session、调用 Provider 或进入 Runtime 正式中断。

权威前序：[D2-F1 根因修复与无声预演](T3_2_A_D2_F1_root_cause_and_silent_dry_run.md)、[正式计划](README.md)、[Stage7 Forbidden Checklist](../../stage7_forbidden_checklist.md)。前序 Bluetooth 结果未重跑，也未用于代替本轮目标路线证据。

## 2. 目标设备与环境

Git 文档只使用路线别名；硬件 UID、序列号、PID、原始设备枚举均不进入 Git。

| 项目 | 实际读回与边界 |
| --- | --- |
| I-01 | 当前默认输入为 USB 麦克风；设备标称 16000 Hz、单声道 |
| O-01 | 当前默认输出为 Mac 内置扬声器；设备标称 48000 Hz、双声道 |
| 路线绑定 | 每个新 run 的输入/输出身份在内存中与实际 CoreAudio 默认设备 UID 比对，均匹配；没有自动切换设备 |
| 存活/占用 | 开始时两设备 alive=1、hog mode=-1、running-somewhere=0；无独占占用迹象，这是该时刻快照 |
| 系统麦克风权限 | Aftelle 已开启；没有重新请求或代替用户授权 |
| 音量 | 预检输入 60%；输出 0%、静音开启。结束时声音设置再次读回输出 0%、静音开启；未改动 |
| Microphone Mode | `UNKNOWN`，没有可靠公开读回，不推测或继续扩展排查 |
| 最终释放 | 三个独立 App 实例均正常退出；最终两设备 alive=1、hog mode=-1、running-somewhere=0 |

静音输出可以验证本轮零值 PCM 排程控制，不能验证扬声器的有声声学行为，也不满足邀请用户进行当前配置下的有声测试条件。

## 3. Debug 构建与正式路径身份

复用 D2-F1 已验证的 Debug 构建，新增构建次数为 0。运行前后均核验 17 个相关源码/测试/脚本文件摘要与当前 HEAD blob 一致；其中 App 源文件同时与前序构建预检清单一致。每次运行核验独立进程的显式隔离参数，并用已加载映像路径确认实际主程序及 Debug dylib。

| 实际映像 | SHA-256 |
| --- | --- |
| `Aftelle.app/Contents/MacOS/Aftelle` | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| `Aftelle.app/Contents/MacOS/Aftelle.debug.dylib` | `05e7d7530ef559e35ab8440ac76bd25e7b209d832b6d993e365d4cddc0ba7a28` |

使用既有 `--apple-vp-acoustic-test --apple-vp-silent-smoke=A|B|C`，每项独立 App 实例。复用 `SystemMacSpeechVoiceProcessingEngine`、`MacSpeechAudioHost`、`MacSpeechAudioOutputHost`、原 Player/Capture/Converter；无新增 Engine、Provider 或测试框架。隔离启动路径不构造正常 Runtime/Provider/Store 依赖，不加载私人资料。

Realtime 的 Apple VP 实现未变，Cascaded 的 WebRTC AEC3 实现未变。未再次运行 Cascaded 设备测试；不能将本轮结果扩展为其新增验收。

原统计 manifest 的 `source_commit`、`build_identity` 仍为 null；没有静态填充。上述源码清单、运行参数、实际已加载映像与两份映像 SHA 构成本轮外部绑定；未来有声 run 仍须关联其实际构建。

## 4. 单次真实设备无声 A/B/C

执行链为既有入口的 Prepare → Start → Capture/Playback → Stop → Seal → 受控统计 JSON → Shutdown；随后从 App 菜单正常退出，下一项启动前验证无 Aftelle 进程。每项 collection 上限 4,000,000,000 ns，均收到 40 个原生 buffer、64000 原生 frame（16000 Hz 下 4 秒）。没有第二轮设备尝试。

| 场景 | Run UUID | 输出控制 | 已 drain 包/元数据字节 | 生成包/停止前排队包 | 控制链 |
| --- | --- | --- | --- | --- | --- |
| A Resident-only | `D8C1454E-B3DF-4049-AC3A-CA44E1A9892C` | 2 秒零值 PCM；prepare 成功，start=1，completed | 194 / 186240 | 199 / 5 | PASS |
| B Human-only | `80440DA0-F210-436C-ADC1-C7BDBF64AAF0` | 不排程输出；start=0、idle，输出测试 N/A | 199 / 191040 | 199 / 0 | PASS |
| C Double-talk 控制 | `72D337EF-5BC4-4CD0-BA0E-8B1B280AB7C9` | 2 秒零值 PCM 与采集并行；prepare 成功，start=1，completed | 194 / 186240 | 199 / 5 | PASS |

这里的字节数是处理包长度元数据，未保存这些输入 PCM。B/C 不证明真人讲话或物理双讲发生。三项实际声学表现和用户试听均为 `NOT_RUN`。

### VP、格式及错误状态

三项共同读回：

- `configuration_debug.stage=validated`；VP input/output 均 true，AGC true，bypassed false，inputMuted false。
- VP 实际输入、输出均为 **16000 Hz / 3 ch**。输出协商前为 2 ch，协商后为 3 ch；原采样率/声道一致性 Guard 保留并通过。
- 原生采集为 Float32、non-interleaved、3 ch；原 Converter 输出为 **24000 Hz、Mono、PCM16 LE、channel[0]**。
- 每包 960 bytes / 480 samples / 20 ms，drain 序列从 1 连续递增，内容时间戳相邻差严格为 20,000,000 ns。
- capture generation=1、configurationID=2；A/C playback generation=1，B playback generation=0。run UUID 与统计 epoch 身份一致。
- capture drop=0、stale=0；全部已有 rejection 原因计数为 0；playback underrun=0、rejected callback=0。
- run/capture/playback error 均 null；没有触发错误 domain/code 分支，不能填写虚构错误码。
- `coverage_valid=true`、issues 为空、sealed=true；未观察到崩溃或死锁。`capture_state=capturing` 是关闭前统计快照，最终关闭证据来自封存后 UI、正常 Quit、进程退出及设备释放快照。

NS 使用 Apple 原生能力，没有独立公开读回；不宣称可独立量化 NS、AEC、ERLE、处理延迟或 AGC 音质。静音预演中的原生每声道 peak 为 A 0.531061、B 0.189902、C 0.196232；各声道满幅、超幅及 non-finite 均 0。这仅描述当次环境输入统计，不证明真实讲话或有声外放时不会削波。

### 内容时间、尾包与未覆盖部分

以下为已 drain 的首包内容起点、末包内容起点和末包结束（exclusive），单位 monotonic ns；不是 callback 到达时间。

| 场景 | 首包起点 | 末包起点 | 覆盖结束 | drain 内容时长 |
| --- | --- | --- | --- | --- |
| A | 695698068931917 | 695701928931917 | 695701948931917 | 3.88 s |
| B | 695843795854750 | 695847755854750 | 695847775854750 | 3.98 s |
| C | 695862768285000 | 695866628285000 | 695866648285000 | 3.88 s |

A/C 各有 5 个完整包（100 ms）在停止前队列中，随后随 Stop 清理，没有计入 drain 覆盖、drop 或保存内容。B 队列为 0。native 累计末包快照可能覆盖尚未 drain 的包，不能作为已 drain 的末端。`partial_converter_tail_samples=null`，保持 `UNKNOWN`，不推算缺失 PCM 或补造静音。本轮不声称导出完整输入尾音。未来有声测试必须预留窗口、检查实际 drain 与尾音覆盖。

### 本地统计证据

仅生成原受控 `~/Library/Caches/com.eterna.aftelle.debug-apple-vp-evidence/` 内的统计 JSON，目录权限 0700、各文件 0600；不覆盖已有证据。每项 `silent_smoke=true`、`retained_pcm_bytes=0`、`processed_sha256=null`，没有对应 WAV。新 manifest 只在本地核验，未复制完整原始 manifest 到仓库或本轮辅助摘要中。

| 场景 | 本地文件名 | 实际 JSON SHA-256 |
| --- | --- | --- |
| A | `run-D8C1454E-B3DF-4049-AC3A-CA44E1A9892C.json` | `b6d90cfcdca81632a04969877926484d09987d4e81faee5c094cdbfa06e416d6` |
| B | `run-80440DA0-F210-436C-ADC1-C7BDBF64AAF0.json` | `b550ea5cd61818f0cb8606fdac9bfd13d692daa7e41f01f1db94db20a40ba1ee` |
| C | `run-72D337EF-5BC4-4CD0-BA0E-8B1B280AB7C9.json` | `5e110aea22e5d063c193710ca292b7ab8489b3255f1e3311ea10d43a7d26cbba` |

辅助身份摘要、只读核验脚本和脱敏统计留在 Git 忽略的 `.build/t3_2_a_d2_f1_r1/`；不含输入 PCM、硬件 UID 或原始设备枚举。没有为本轮建立录音保存路径。

## 5. 首次退出核验异常及处理

设备 A/B/C 均已完成并退出后，一次辅助审计 exit 1：脚本将全局 `running-somewhere=0` 与设备存活、无独占占用一起断言。当时系统设置打开输入电平页；紧接的只读元数据快照显示 USB alive=1、hog=-1、running-somewhere=1，内置输出 alive=1、hog=-1、running-somewhere=0，Aftelle 进程不存在。首次失败断言未持久化各分项原值，故不补造该瞬间的精确值。

全局 running-somewhere 不标明使用者，不能据此归因 Aftelle 泄漏。关闭本轮打开的系统设置窗口后，仅做一次只读状态复核及剩余证据核验，exit 0：两设备 running-somewhere 均为 0，Aftelle 进程不存在。现象与输入电平页有关，但未对其内部采集行为作独立追踪，不把推断写成已证明根因。

保留首次辅助检查失败与后续读回；没有修改产品 Guard、重跑任何 A/B/C 或为通过而改变音频参数。没有发现新的目标路线初始化失败。

## 6. 已准备的有声测试资产与准入

固定非私人 macOS 离线 Tingting 样本重新核验 SHA：

`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`

位置为 Git 忽略的 `.build/t3_2_a_d2_preflight/tts_sample_v1/d2_fixed_zh_24k_mono_pcm16le_preroll1s_v1.wav`；24 kHz / mono / PCM16 LE，228108 bytes，总长 4.751333 s（含 1 s 前导静默）。文本为“这是一段固定语音，用来检查回声和人声。”本轮只核验格式与摘要，没有播放。

未来 A/C 计划至少覆盖 1 s 起始静默＋约 3.751333 s 目标语音＋至少 1 s post-roll，其中包含外放后 0–500 ms 尾音观察，最短 5.751333 s，小于既有 15 s 上限。真人实际起止、物理重叠与最终 drain 覆盖必须由未来 run 记录，不能由本轮无声包数代替。B/C 固定真人短句为“今天我想聊聊刚才的事情。”，C 需真实见证重叠超过 1 s。

受保护 Caches 目录、现有 JSON/WAV 导出功能和本地手动试听方式已具备；本轮没有调用录音 WAV 导出或试听。未来用户在各场景开始前获知安静/讲话提示，完成后从受保护目录手动打开对应 WAV 并反馈；不能将自动统计代替听感。

| 准入项 | 结论 |
| --- | --- |
| USB＋内置扬声器路线、A/B/C 无声链、VP、初始化 | PASS |
| App 退出及最终资源状态 | PASS，首次辅助审计异常保留于第 5 节 |
| 实际源码/运行映像绑定、固定样本 SHA、窗口/目录 | 本轮已核验；无待编译或待找资产 |
| 输出可用于真实外放 | **BLOCKED：输出 0%、静音开启**；用户须手动解除静音并确认测试音量 |
| 系统 Microphone Mode | UNKNOWN；允许保留，不推测，不独立阻塞本轮无声结论 |
| 真人采集、有声 A/B/C、试听授权 | 本轮没有授权或执行；将来须另行明确授权 |

`READY_FOR_HUMAN_TEST=false`。无需重新修复或编译控制链；在输出条件及后续明确授权具备前，不邀请用户立即开始有声 A/B/C，也不自行启动。

## 7. 检查结果与五维审核

来源均为 **SELF_REVIEW（Codex，本轮运行及交付核验）**；没有宣称独立 Reviewer。命令及返回状态：

| 检查 | 返回/结果 | 范围 |
| --- | --- | --- |
| A 原启动、身份与新 manifest 采集脚本 | exit 0 / PASS | 一次设备 run |
| `python3 .build/t3_2_a_d2_f1_r1/run_once.py B` | exit 0 / PASS | 一次设备 run |
| `python3 .build/t3_2_a_d2_f1_r1/run_once.py C` | exit 0 / PASS | 一次设备 run |
| 各项正常 Quit 后 `pgrep -x Aftelle` | exit 1 / PASS | 无进程；该命令的 1 表示未找到进程 |
| 首次辅助 `audit.py` | exit 1 / FAIL 保留 | 全局占用断言，第 5 节 |
| 随后的只读占用快照 | exit 0 | USB global running=1，App 已退出；不归因泄漏 |
| 关闭设置窗口后的只读 `audit.py` | exit 0 / PASS | 三份证据、格式、时间、身份、保护 Worktree、最终占用 |
| Debug / Release / Release guard / 离线回归 | NOT_RUN | 无源码或测试变化，复用前序有效验证，不重复 Bluetooth 或无关测试 |
| SwiftFormat / SwiftLint | NOT_RUN；历史全局 FAIL 保留 | C19、C23 仍延期，未清理或改判 |
| 有声声学 / 用户试听 / 正式 53-A～E | NOT_RUN | 不在本轮授权范围 |

| 维度 | 结论 | 依据及限制 |
| --- | --- | --- |
| TECHNICAL | PASS（无声范围） | 目标实际路线、三次真实控制链、VP/格式/时间与资源证据通过；不等于声学 PASS |
| ENGINEERING | REWORK / DEBT_DEFERRED | 历史 lint FAIL、C19/C23 不变；本轮无生产/测试新增代码，没有新 B 类代码违规归因 |
| EVIDENCE | PASS（限定结论） | 真实 run、实际二进制与 JSON 身份；保留首次辅助失败、静音环境阻塞、manifest null 和 partial tail UNKNOWN |
| CONSISTENCY | PASS | Test2 安全链、Runtime 授权与正式合同未改；Bluetooth、无声控制和有声验收未混同 |
| Stage7 Forbidden Checklist | PASS | 六红线及本轮禁止项均未触碰，见第 8 节 |

问题登记：

- **CRITICAL：0** 个本轮新发现。
- **MAJOR：0** 个本轮已确认功能安全缺陷；没有将全局占用快照直接判为产品泄漏。
- **MINOR R1-ENV-01：OPEN**，输出音量 0% 且静音，阻止当前有声测试就绪；最少操作是用户手动解除内置扬声器静音并设定、确认正常测试音量。Codex 不代改。
- **R1-OBS-01：CLOSED（辅助核验归因）**，首次全局 running 断言不能证明 App 资源问题；保留失败，关闭设置窗口后最终读回空闲。不是产品修复，也未重跑设备。
- 既有 C19/C23 工程债务保持原登记；partial converter tail 与 Microphone Mode 的证据限制保持 UNKNOWN，不用本轮去关闭历史问题。`SQ-M1=OPEN`。

## 8. Stage7 Forbidden Checklist

| 红线 | 本轮判断 |
| --- | --- |
| 大脑不碰平台 | PASS；无 brain/RuntimeCore 修改 |
| Store 带版本 | PASS；无建表或 Store 修改 |
| 三层不黏连 | PASS；仅显式隔离 DEBUG Host 测试，无 Provider/Runtime Decision |
| DR 只读＋revision | PASS；未读取或写入私人 DR，无 schema 修改 |
| 逻辑/画法分层 | PASS；无粒子/Metal 修改 |
| 交互按意图 | PASS；无产品交互语义修改 |

未新增平台 target、Runtime API、Scheduler、Memory Kernel、Provider 所有权、声源 Gate、取消 owner 或并行 Engine。未触发 Test2 插话/取消/clear、Session/Memory 或正式 Human Gate。没有设备音量/模式/权限修改、自动重试、私人音频留存或上传。仅本报告进入 Git；原始统计 manifest、设备身份和本地辅助文件均不提交。

结束状态：`T3.2-A-D2-F1-R1=REVIEW_PENDING`，无声目标路线控制链 PASS；`READY_FOR_HUMAN_TEST=false`。`T3.2-B=NOT_AUTHORIZED`、`T3.3=NOT_STARTED`、`SQ-M1=OPEN`、`Qwen Strict Overlap=0/3`、`Formal Test3=BLOCKED`、`Test3.execution_authorized=false`。提交推送后停止，等待主控审核与将来的有声测试授权。
