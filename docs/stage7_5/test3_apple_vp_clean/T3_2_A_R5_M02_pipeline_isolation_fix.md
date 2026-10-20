# T3.2-A / R5-M02 · Apple VP流水线隔离修复

日期：2026-10-20。范围：OFFLINE CODE FIX，等待主控审核。

## 结论与身份

**CONFIRMED_CODE_BUG，离线修复通过。** Apple VP模式曾被软件AEC3的Render转换失败或无效延迟切换至half-duplex fallback，随后合法输入被返回为空。本轮消除这两条条件性故障传播路径；没有证明历史真人C实际触发过它们，声学根因仍为UNKNOWN。

- 开始时HEAD、upstream及实时远端均为 `822ff9094ad40aff48b0bb046c5288de00065ac8`，隔离工作区干净。
- 遵守AGENTS跨文件修改前回滚要求，建立本地checkpoint：`e27a47ea66751c5aefb842bd9c0ef55a03ba5dd1`，源码与上述基线相同。测试、构建在checkpoint加下述补丁的工作区执行，不能将checkpoint单独当作修复源码身份。
- 使用已登记隔离工作区，交付目标为 `origin/Test3-AppleVP-Clean`。最终交付SHA为包含本报告的提交；推送后三方HEAD核验另附交付回复。
- 原工作区7个冲突、索引、暂存及未跟踪状态保持原样；未操作其他研究Worktree。

| 文件SHA-256 | RED | GREEN / Debug构建 |
| --- | --- | --- |
| `MacSpeechAcousticEchoHost.swift` | `52a850d90983980af7fff3d3bb1a44c113d4a5ce1ba860e1fc63ad85f0d5f973` | `4a6153bca24c5bf237247374c05b9524443371e83e7ad71811957e9bb6cde8fe` |
| `MacSpeechAudioCapture.swift`，只读 | `c2385929dcda156c45095b4cc7f52f862c77ff5b79067662527b9a4a1f496ca1` | 同左，未修改 |
| `MacSpeechAcousticEchoHostTests.swift` | `94890ea3b25ebd14ba79fba2dbb1732c95a99f04e30ae7e2cd790f32ac9b350c` | `a27d557532e5fbf12cbc43e7aae0a25c1ec83881c8a2c6733d5ea35cf8f98ee7` |

## 已确认故障与最小补丁

源码均位于 `apps/macos/Aftelle/`。行号指本轮修复候选：

1. `MacSpeechAudioCapture.swift:2943`：软件Render转换抛错，调用 `host.renderConversionFailed()`。
2. `MacSpeechAcousticEchoHost.swift:1051`：修复前无模式区分，进入 `.renderProcessingFailed` fallback。
3. 同文件 `updateDelay():1276`：修复前非有限延迟或超过500ms的软件AEC3延迟进入 `.delayInvalid` fallback。
4. `processCaptureSpans()`按固定requestedMode进入Apple分支，而 `processAppleCapture():1183`要求当前mode仍为Apple；变成fallback后返回空数组，不能靠Playback Stop/Completed恢复。

补丁只新增3行：

```swift
// renderConversionFailed()，queue.sync之前
// Apple VP owns its render reference; this failure belongs to software AEC3.
guard requestedMode != .appleVoiceProcessing else { return }

// updateDelay()，queue.sync之前
guard requestedMode != .appleVoiceProcessing else { return }
```

requestedMode是构造时固定的不可变值。只隔离Apple模式；WebRTC AEC3及原请求fallback模式的旧处理不变。没有修改通用enterFallback，也没有删除AEC3错误检查。

| 条件 | 修复前 | 修复后 |
| --- | --- | --- |
| Apple模式，正常非零输入 | 原样透传 | 原样透传 |
| Apple模式，软件Render转换失败 | fallback；随后空输入 | 保持Apple模式；样本、顺序、内容时间保留 |
| Apple模式，软件延迟600ms / 非有限值 | fallback；随后空输入 | 不适用的软件AEC3延迟不能切断输入 |
| WebRTC，Render失败 / 非法延迟 | fallback，播放时阻断输入 | 相同断言继续通过 |
| Apple routeWillRebuild | 拒绝输入直到routeDidRebuild | 仍拒绝；Stop及上述软件错误都不能绕过重建保护 |

旧测试曾把“Apple模式的软件Render失败后必须断流”写成期望。本轮将该错误契约替换为持续透传断言，并保留、加强route rebuild阻断检查；不是将失败样本改成静音或放宽时间容差。Apple观察仍不提供WebRTC ERL/ERLE、source eligibility或AEC有效性凭据。

## RED / GREEN实际执行

复用现有 `FakeAECBackend`、固定seed非零Float32信号及Host测试入口；新增 `--apple-pipeline-isolation`过滤模式，没有新增测试框架。默认测试入口也包含这四组回归。

| 核心case | RED | GREEN |
| --- | --- | --- |
| Apple正常透传，注入Render失败后再次输入 | FAIL | PASS |
| Apple正常透传，注入600ms、Infinity、NaN软件延迟 | FAIL | PASS |
| WebRTC原Render及Delay fallback安全对照 | PASS | PASS |
| Apple route rebuild阻断、恢复及软件故障隔离 | PARTIAL：原route保护通过，软件故障隔离失败 | PASS |

RED一次：4 cases / 52 checks，22失败，exit **1**。GREEN一次：相同4 cases / 52 checks，0失败，exit **0**。输入数组逐值、逐序比较，内容时间精确相等；未修改合成样本。

GREEN之前仅将测试main的调用汇总为一个函数，以消除新增函数长度lint问题。四组case、复用安全对照和expect核心函数与RED逐字相同，已计算函数SHA验证。没有第二次RED或第二次GREEN。

RED失败日志示例：`software render failure cannot discard Apple VP input`、`software AEC3 delay cannot change Apple VP mode`。原始日志SHA-256：

- RED：`f05851ed2f02af94e97c92377b33e8cec39aaf6c1ca14778a16ec1cae1571148`
- GREEN：`642266a58509bbc9fda5b4a2a4ac30474e310ff4e64214074f58968932c9db21`

实际argv、源码摘要、耗时、退出状态及日志保存在Git忽略的 `.build/r5_m02/`。以下命令仅将本机绝对产物路径写为等价仓库相对路径，避免公开私人路径：

```sh
swiftc -D DEBUG -parse-as-library -warn-concurrency -strict-concurrency=complete \
  -module-cache-path .build/r5_m02/module-cache -framework AVFoundation \
  apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift \
  apps/macos/Aftelle/MacSpeechAudioCapture.swift \
  tools/speech_aec_host_tests/MacSpeechAcousticEchoHostTests.swift \
  -o .build/r5_m02/red-host-tests
.build/r5_m02/red-host-tests --apple-pipeline-isolation
# GREEN使用同一编译参数，输出改为green-host-tests：
.build/r5_m02/green-host-tests --apple-pipeline-isolation

xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle \
  -configuration Debug -destination platform=macOS \
  -derivedDataPath .build/r5_m02/DerivedData \
  -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
bash tools/realtime_release_route_guard/check.sh
bash tools/architecture_guard/check.sh
bash tools/secret_guard/check.sh
```

| 执行 | 次数 | exit | 耗时（秒） | cases / checks |
| --- | --- | --- | --- | --- |
| RED编译 / 测试 | 各1 | 0 / 1 | 6.255 / 0.636 | 4 / 52，22失败 |
| GREEN编译 / 测试 | 各1 | 0 / 0 | 3.073 / 0.621 | 4 / 52，全通过 |
| Aftelle Debug目标构建 | 1 | 0 | 17.262 | BUILD SUCCEEDED；不运行App |
| Release Route Guard | 1 | 0 | 0.607 | 6项具名检查通过，3项禁止符号计数为0，汇总结论PASS |
| Architecture Guard | 1 | 0 | 0.106 | 原工具未提供总checks数，输出ok |
| Secret Guard | 1 | 0 | 0.114 | 原工具未提供总checks数，输出ok |

构建期间源码摘要前后相同。Debug产物位于上述DerivedData的 `Build/Products/Debug/Aftelle.app/Contents/MacOS/`：

| 产物 | bytes | SHA-256 |
| --- | --- | --- |
| `Aftelle`，App主可执行文件 | 40216 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| `Aftelle.debug.dylib`，包含当前实现 | 21886208 | `30112139dcac9f3e7ce847df8e2a8125e11b28c4ff9f88d6db0a58f31b6aa675` |

App主可执行文件是Debug装载器，SHA相同不能单独证明实现相同，必须同时绑定dylib与上述源码摘要。构建日志SHA：`b8d1df5926141b51490f9b9f250a15c3a8c44e9f2f5bba154039a9697df044dd`。构建仍报告未修改文件中的actor相关警告及AppIntents提示；未为消除这些警告扩大修复范围。Release整App构建、FULL_CURRENT、HIL、设备矩阵均NOT_RUN。

## 增量规范与失败记录

使用已登记的SwiftFormat和SwiftLint，无工具升级。实际参数为 `swiftformat --lint --swift-version 5 --cache ignore --reporter json --report <本地报告> <两个Swift文件>`，以及 `swiftlint lint --strict --quiet --no-cache --reporter json <两个Swift文件>`；基线使用上述Git基线导出的同两份文件。

| 检查 | 基线 / 最终finding数 | 实际exit | 结论 |
| --- | --- | --- | --- |
| SwiftFormat | 1615 / 1615 | 1 / 1 | 全文件历史FAIL保留；新增finding及改动行finding均0 |
| SwiftLint | 52 / 52 | 2 / 2 | 全文件历史FAIL保留；新增finding及改动行finding均0 |

每工具：基线一次、候选一次、测试main结构修正后的最终候选一次。首次候选SwiftLint为53项、exit2，其中新增main长度53行；汇总测试调用后该新增错误消除。最终增量比较未排除新的规则，仅将原有file/type长度诊断中的现有行数变化归为同项债务。历史C19/C23及原文件/type长度债务继续登记，不宣称全量lint PASS。新增B类问题为0。

## contentTimeValid只读风险核查

位置：`MacSpeechAudioCapture.swift:592,630,645–690,726–734`；调用方 `processCapture():2747–2757`。

- 缺少/零内容时间，或与累计输入样本推算值偏离超过一个输入采样周期向上取整的容差，会使contentTimeValid=false并清空packetizer，返回空数组。
- converter未消费输入、累计输出超过允许SRC比例，也会置false；这些分支抛conversionFailed。生成的时间戳非有限、溢出等分支置false并返回空数组。
- requireContentTime路径下，之后即使时间戳恢复合法，仍返回空数组；需要resetForGenerationTransition或重建converter。现有Capture Start、Stop及generation切换有reset调用。
- 调用方用try?捕获抛错时，DEBUG可记录output_conversion拒绝；但时间校验返回空数组时被视为一次成功转换，没有专门的失效原因通知。存在持续无输出而无该项拒绝计数的可观测性风险；不能宣称历史实际发生过未报告丢包。
- 本轮未修改此逻辑、容差或恢复方式。此前真实C已接纳PCM连续，因此没有证据把它定为前三秒近静音的根因。

## SELF_REVIEW、范围与后续

| 维度 | 审核 |
| --- | --- |
| 功能正确性 | PASS，限四组离线故障注入及样本/时间精确透传；实机未验证 |
| 架构与安全 | PASS；无新增Engine、Tap、Gate、DSP、状态Owner；WebRTC fallback及route安全保护保留 |
| 回归与证据 | PASS于授权定点范围；保留RED exit1、全文件规范FAIL和未运行项目，未重跑无关回归 |
| 隐私与设备 | PASS；真实运行/采集/播放0次，私人音频读取0次，无权限、路由、音量或Mic Mode操作 |
| Git与交付范围 | 仅Host、现有定点测试、本报告；原冲突现场保留，正常推送，不包含音频、Manifest、UID或秘密 |

Stage7 Forbidden Checklist：任务前/后 **PASS**。六红线无新增触碰；改代码=是；Runtime API、DR schema、平台target、Stage8、正式Gate改动均=否；无需扩大授权。

问题分级：修复一项 **MAJOR条件性代码缺陷**（两个触发入口）。新增CRITICAL=0、MAJOR=0、MINOR=0。遗留时间戳失效可观测性风险、既有规范/actor债务及真实声学问题保留，交主控裁定。

唯一下一项建议：主控先审核本补丁及RED/GREEN证据，再决定是否独立授权一次真人声学验证；本任务不执行。软件诊断隔离成功不等于Apple VP真实AEC、人声保留、回声或增益问题已经解决。

```ini
R5_M02_OFFLINE_FIX=GREEN_REVIEW_PENDING
DEVICE_EXECUTION=NOT_RUN
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
