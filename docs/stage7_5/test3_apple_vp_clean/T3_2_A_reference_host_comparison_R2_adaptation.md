# T3.2-A · R2 Minimal REF/HOST Comparison Adaptation

日期：2026-10-19。性质：派生参考的最小实现、离线验证与 SELF_REVIEW；无设备执行。

## 1. 结论

**R2_ADAPTATION=PARTIAL，READY_FOR_DEVICE_COMPARISON=false。**

已解决两个局部问题：新 REF 居民素材通过冻结的 8 秒 Float32 准入；派生 REF 在原 `observationStart`/终止路径产生有界实时事件，具有可验证的 continuous → absolute 纳秒映射。原 REF 33 项测试及新增 9 项 Swift 测试通过，外部素材/控制测试 13 项通过，旧 HOST 控制器 9 项自测通过。

但本轮发现并复现一个实际执行阻塞：**既有蓝牙控制器固定原代理素材 SHA，会在启动播放器前拒绝新 HOST 代理素材。** 其配套播放器还有冻结素材校验；本轮未能在限定范围内定位到可审核的原播放器 Swift 源码。没有删除断言、替换文件、修改二进制或新建播放器。

因此，本轮交付可重现的素材、REF 事件补丁、翻译器及离线测试，不声称完整自动执行链已就绪。没有验证蓝牙发声、系统权限、真实重叠或 AEC 效果。不是严格单变量实验；历史成功与失败结论均保留。

## 2. Git、隔离与源码保护

| 项目 | 核验 |
|---|---|
| 开始 HEAD / upstream / 实时远端 | 均为 `951bec3ba1065654c15563cfe2c7600c2080e33e` |
| 交付工作区 | 上轮干净隔离 worktree `vp-reference-host-preparation/Eterna_Aftelle` |
| 本地分支 / 远端目标 | `codex/reference-host-comparison-preparation` → `Test3-AppleVP-Clean` |
| 跨文件修改前回滚点 | `dd6cff8e25fcab07fdeb31f27ca4529026c5eac4`；显式空 checkpoint，未纳入任何旧修改 |
| 冻结 REF | `c64c7e2629ec775062fdc2ea1e4a934c73c1fa75`；124 个源文件重新导出、逐个 SHA 复核 |
| 原冲突 worktree | HEAD 保留 `28a8589eddbf59b2a8fd0c73ebdfd3e8341b7273`；7 个未解决冲突保留 |
| 原冲突 index SHA | `e4c0f51f433f4f53a3bf77e82aabd5152617f5efdbe441f05559182a56c8b952`；status/index 前后相同 |
| 生产源码 | `apps`、`brain`、`platform-macos`、`shared-protocol` 相对交接基线 diff 为空 |

原冲突 worktree 仅以 `GIT_OPTIONAL_LOCKS=0` 读取状态和摘要；未解决冲突、修改索引或读取其私人录音。ACE3 与其他研究 worktree 没有写操作。最终三方 HEAD 核验针对隔离交付工作区，不能把原冲突分支强行移动到新提交。

本报告的执行身份为上述 checkpoint + 下列补丁/文件摘要；交付 commit 由包含本报告的 Git 提交对象和最终回复给出，避免伪造自引用 SHA。

## 3. 改动与构建身份

提交范围：`tools/reference_host_comparison/` 的 7 个文件、本报告及 DEVLOG 索引。没有提交音频、构建产物、设备 UID、私人 Manifest 或原始日志。

`prepare.py` 仅从冻结 commit 导出 `FROZEN_REF` 与 `ADAPTED_REF`。原 124 文件中只有派生副本的 `VPCSession.swift` 被补丁修改；新增 `VPCComparisonEvents.swift` 及测试。`AppleEngineDriver`、`ConfigurationPlan`、`VPCWindow`、`NativePCMTap`、权限路径、原准入规则均保持原字节。

| 身份 | SHA-256 |
|---|---|
| 可重现 `ref-events.patch` | `9b66e1c8244b59dc860ee32b7e4278a5fe24301145398dd78f2aa90761641db8` |
| ADAPTED_REF Debug `apple-vp-reference` | `54d2eaf775eccdf806c82f8996a7038db4b219e4ddba60ea8914122997385ade` |
| ADAPTED_REF Sources/Tests 摘要清单的 canonical JSON SHA | `930cabbfbf45fe410dc44254b2c8f2cb72f2bc0b9aef8ffec4561c6943b7ad2d` |
| HOST Debug 主程序（重新计算） | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| HOST Debug dylib（重新计算） | `34ca1dc87ed28229fc2992503253d272eca4833dea5fdb2f7ceaf20c25267ba1` |
| HOST Release 主程序（重新计算） | `c9c209f7c7a1f5d772a4f3f5e0e384fa69ecb0897d1ada994ec283e6daef8477` |

REF 编译：Apple Swift 6.4（swiftlang-6.4.0.34.1）、Xcode 27.0（27A266a）、SDK 27.0，原 Swift tools 6.0/语言模式5、macOS14最低版本，无新增 Swift 包依赖。产物来自 `.build/reference_host_r2/final/ADAPTED_REF/.build/debug/`，只构建和运行指定测试，未启动参考工具。

最终补丁清理了一行unified-diff空白上下文表示；在新的 `patch-verified` 导出目录重新应用成功，120个Sources/Tests文件及全部素材与已测试/构建候选逐字节一致，没有因此重复整组测试。上述产物SHA仍对应相同源码。

这是**冻结源码加事件补丁后在当前工具链重建的 ADAPTED_REF**，不是历史成功实验原二进制。HOST 复用已验证的 `full_current-9w4j67qu/DerivedData`；本轮没有重新构建 HOST 或重跑 FULL_CURRENT，R1 已核验的历史 21 项 PASS 不冒充新执行。

## 4. 素材与可比较数字窗口

只读两份已登记非私人 Tingting 源文件；生成的四个文件和数值清单留在 Git 忽略目录，不接触麦克风录音。NumPy 2.0.2 / SciPy 1.13.1。

| 用途 | 格式 / 帧数 / 长度 | SHA-256 |
|---|---|---|
| HOST 居民，保持源字节 | 24k Mono PCM16LE；114032 帧；4.751333s；228108 bytes | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` |
| REF 派生居民 | 16k Mono Float32；128000 帧；8s；512058 bytes | `c47d3df54cda56d010b0b6ded27bb75f1e92d9065f390dcb39bee260f317960b` |
| REF 代理，保持源字节 | 24k Mono PCM16LE；264310 帧；11.012917s；528698 bytes | `1c7081f8271251804e01234be8a0ff8344062d09c311592634cb8fdf6b992d0a` |
| HOST 派生代理 | 24k Mono PCM16LE；360310 帧；15.012917s；720664 bytes | `4a0b85b6fa3d14f14510d3f041ff1c41ee9b0363962c28dca812ce0ae83a55e8` |

REF 居民转换：PCM16 数值除以32768，Float64 中以 `resample_poly(up=2, down=3, window=kaiser(beta=5), padtype=constant)` SRC，再转 Float32。增加16000帧前导静默、35978帧尾静默；原素材的一秒前导静默仍在。没有归一化、增益调整、降噪、语速变化或语句剪辑。Float64→Float32 最大舍入误差 `2.9781092369951523e-08`；SRC 有滤波效应，不能声称两格式样本完全等价。

| 文件 | 全文件 Peak / RMS（线性） | 数字非零样本范围，半开区间 |
|---|---|---|
| HOST 居民 | 0.6699829102 / 0.1158276853 | [24000,113915) @24k |
| REF 居民 | 0.6742768884 / 0.0891684211 | [31990,91953) @16k |
| REF 代理 | 0.7063903809 / 0.1236532180 | [0,264080) @24k |
| HOST 代理 | 0.7063903809 / 0.1059068528 | [96000,360080) @24k |

RMS因补零长度不同不可直接当作增益变化；REF Peak 的轻微差别来自 SRC，而非主动放大。

| 控制和内容 | REF（观察起点为0） | HOST（4秒预热后的评分起点为0） |
|---|---|---|
| 居民原软件播放窗 | [2,10) | [3,7.751333…) |
| 居民数字非零包络外沿 | [3.999375,7.7470625) | [4,7.746458333…) |
| 代理原软件控制窗 | [4,9) | [0,11) |
| 代理实际文件内容方案 | 立即播放源；源第5秒停止 | 先播放4秒零值，再播源；源第7秒停止 |
| 共同代理内容 | 源样本 [0,120000) | 与左侧逐样本相等，映射到 [4,9) |

共同居民内容包络外沿约 [4,7.746458333)，位于共同代理 [4,9) 内。上述非零外沿含内部停顿，**不是连续语音 VAD、物理双讲或声压证据**。REF 的0.625ms提前非零是SRC滤波边缘；仅按任务要求“约第4秒”对齐，未改变任何声学验收阈值。

完整源内容保留在派生文件内，但原控制窗会停止播放；不能宣称完整11秒代理语句都被播放。REF t=2–4 的 resident-only 提示现在对应派生素材的静默铺垫，HOST t=0–3 的 human-only 提示也对应代理静默。因此这个方案适合比较共同双讲内容，**不能复现历史REF全部声学条件，也不能验证HOST首3秒真人静音问题**。

实际准入：冻结 `PCMSourceMaterial.load` 与 `VPAAdmission.inspectMaterial` 接受 REF 派生8秒Float32；HOST原解析函数接受原居民WAV，3–6秒字节合同保持。8秒PCM16时长负控及Float32格式负控仍拒绝。代理素材不走HOST居民3–6秒准入；它受独立播放器的原SHA/时长校验约束，此处仍有阻塞。

## 5. REF 事件与时钟适配

补丁仅在派生副本的 `VPCSession.run/wait` 插入可选 `VPCComparisonEvents`。使用原 `VPCWindow` 产生的 `observationStart`，不由UI或墙钟猜起点；原Input/Render双流就绪、0/2/4/9/10/13秒cue、整段排程和13.5秒终止不变。

- 环境参数 `AFTELLE_VPC_COMPARISON_FD`；大于2的可写、非阻塞FIFO描述符。复制fd并关闭SIGPIPE影响；不接受普通文件，析构关闭自有fd。
- 一次 schedule：真实RunID、`source=ADAPTED_REF`、schema1、观察起点、near计划开始/停止、时钟锚点。
- 原成功终止后发stop；原错误路径尝试发cancel，写失败也登记错误。原设备清理、封存和权限/显式同意规则保留。
- 单条JSON不超过512bytes、一次非阻塞原子write；总事件数有界（schedule和终止）。无PCM或UID，无Tap改动，不从实时音频回调执行I/O。
- 原控制观察循环检查pipe和时钟，满管道/断开fail-closed。断开后无法保证发送cancel字节，消费者必须以EOF/子进程退出/超时停止代理，不能伪称破损管道仍保证送达。

时钟转换使用现有 `VPBClock` 的 absolute-before / continuous / absolute-after / numer / denom。用整数全宽乘除把absolute ticks转纳秒，以夹取中点作为观察原点，再加4/9秒。夹取宽度上限1ms，对应中点不确定度最多0.5ms另加整数舍入；这是控制时钟质量约束，不能解释为物理发声精度。

连续检查要求timebase不变、时钟不倒退，continuous与absolute累计差异不超过1ms。睡眠/跳变、过宽夹取、溢出、缺失时基均拒绝。没有直接混用tick和nanosecond；也不把mach_absolute与mach_continuous当成相同数值。

## 6. 外部控制兼容与剩余阻塞

既有控制器 SHA：`b81621be6448803ddb3b2c4c7bdaf57fd6cb673ec1898c525758896574692cd9`。

既有播放器 SHA：`3f21479468417218617be4a122a417e865060a46d585b6614aa51a2537653b82`。

`controller.py` 在验证原脚本SHA后仅加载 `SingleRun` 类。REF schedule先校验来源、UUID、时基、夹取和4/9秒计划，映射为原计划对象；仅该REF实例的停止点登记为near开始后5秒。HOST原11秒逻辑不动。原50ms迟到拒绝不放宽，PLAY/STOP各一次、重复/外来事件拒绝。

**确认的阻塞**：原 `sync_once.py:execute` 在 Popen 前断言代理SHA必须为 `1c7081…`，本轮HOST派生文件为 `4a0b85…`。负控调用原execute函数、拦截所有Popen，实际触发该AssertionError且进程启动数=0。测试PASS仅表示拒绝有效，不表示素材已兼容。

配套二进制可见 `Frozen speech SHA mismatch` 及 `UID/duration/loop readback mismatch` 诊断文字；其对派生素材的实际运行结果为NOT_RUN。限定的既有BT/HIL源码目录未定位到该二进制对应Swift源码，不能通过修改Python一处SHA就宣称整个播放器可用。

本轮翻译器是离线适配库，尚未接通真实REF子进程到原播放器的完整执行循环。缺失事件/取消/管道退出的验证包括原控制器执行函数的Fake子进程清理，不能冒充已完成REF实机集成。`BT_CONTROL_OFFLINE=PARTIAL`。

**唯一下一项**：定位并核验该既有播放器源码，在原播放器/执行器中有限登记这两份代理素材的SHA及预期时长，保留UID、单次播放/停止、超时和同意门禁，并接入现有REF翻译器。禁止绕过SHA、静默裁剪、修改旧播放时序或另建播放器；完成该项离线复核后再申请设备对照授权。

## 7. 实际命令、结果和失败保留

命令均在隔离工作区执行；`$R2` 为 `.build/reference_host_r2/final`，`$RESIDENT/$PROXY` 为第4节登记的原文件，`$SYNC` 为第6节登记的既有控制器。具体参数、exit、耗时与日志摘要留在各Git外receipt，复现方法见工具README。

| 实际命令 / 检查 | 数量与结果 | exit / 耗时 |
|---|---|---|
| `python3 -B tools/reference_host_comparison/prepare.py --output "$R2" --resident "$RESIDENT" --proxy "$PROXY"` | 导出124文件×2、派生素材、补丁准入、提取HOST解析器 | 0 / 1.7564s |
| `R2_ASSETS_DIR="$R2/assets" xcrun swift test --package-path "$R2/ADAPTED_REF" -Xswiftc -warnings-as-errors --filter 'VPCWindowTests\|VPCCommandTests\|VPAMaterialSafetyTests\|VPCComparisonEventsTests\|ComparisonMaterialTests'` | 42 tests PASS：旧12+8+13，新事件7、新素材2；构建完成10.66s | 0 / 13.9898s |
| `R2_ASSETS_DIR="$R2/assets" R2_ORIGINAL_CONTROLLER="$SYNC" python3 -B tools/reference_host_comparison/test_control.py` | 13 tests PASS；含派生HOST素材被旧执行器拒绝负控 | 0 / 0.5234s |
| `python3 -B "$SYNC" --self-test` | 旧9 cases PASS；device_access ZERO | 0 / 0.0384s |
| SwiftFormat 0.63.1 `--lint --reporter json --report … <3个新增Swift文件>` | 0 issues；不改lint配置 | 0 / 0.0324s |
| SwiftLint 0.65.1 `lint --strict --quiet --reporter json --cache-path … <3个新增文件及派生VPCSession>` | 0 issues | 0 / 0.0845s |
| SwiftFormat同参数检查冻结/派生 `VPCSession.swift` | 各32处原有问题；逐行映射后新增0 | 1 / 0.0514s、0.0596s |
| 最终补丁在新 `patch-verified` 目录prepare、原准入及文件等价核验 | 120个Sources/Tests及全部素材与已测候选相同 | 0 |
| `bash tools/architecture_guard/check.sh` | `architecture-guard: ok` | 0 / 0.1479s |
| `bash tools/secret_guard/check.sh` | `secret-guard: ok`；另核验本轮文档/补丁白名单 | 0 / 0.1504s |
| `bash tools/realtime_release_route_guard/check.sh` | 原路由声明、调用、权限、UI、终止检查PASS；禁用符号计数0 | 0 / 0.7644s |
| HOST构建、FULL_CURRENT、实机/蓝牙/系统权限 | 未重跑、不执行 | NOT_RUN |

Swift新测试包括真实Unix非阻塞pipe、满管道/关闭读端拒绝、非法fd、重复事件、取消、非单位timebase、溢出/睡眠/倒退/过宽夹取及原VPCWindow事件位置。Python覆盖精确内容窗口、原HOST窗口、单次PLAY/STOP、缺事件、外国RunID、非法事件、原脚本身份漂移、迟到、原执行器EOF/异常退出STOP。Fake进程完全拦截，不创建NSSound或App。

失败记录保留：

- 首次42项候选：exit1，41通过/1新增Fake失败，`EXPERIMENT_CLOCK_INVALID`。Fake cue receipt误用requested/displayed作为clock ID；改为冻结合同要求的cue ID，未改原断言。第二候选42/42 exit0；随后仅整理新增代码规范并重建最终候选，最终42/42 exit0。
- 首次增量规范：Format31条、派生Session新增2条；Lint派生Session3条。修正新增代码后曾暴露默认Format/Lint对尾逗号的冲突及新增行长/类型长度问题；通过等价的字段赋值与隔离新增helper消除，未修改工具配置或忽略规则。最终新增B类=0，旧Session32条格式问题及仓库历史C19/C23/全量lint FAIL独立保留。
- 身份收集首次假定旧SwiftPM triple目录：exit1，文件不存在。当前工具链实际使用 `.build/debug → .build/out/Products/Debug`；按真实产物路径核验，未重建来掩盖问题。
- 暂存差异首次检查exit2，报告补丁文件内一行unified-diff空白上下文。首次缩短hunk的包装尝试无法应用（prepare exit1，`patch does not apply`）；恢复双侧上下文并以空行移除/加入表示后应用成功，输出源码逐字节不变。失败导出目录保留。
- 提交范围附加扫描首次exit1：将既有DEVLOG历史绝对路径误计入本轮新增内容。修正为对该文件本轮新增行检查路径/私人载荷，同时保留全文件密钥模式检查；未修改或删除历史内容。
- 原播放器派生素材拒绝是有效未关闭阻塞，不因负控exit0改写为兼容PASS。

关键日志SHA：

| 回执 | SHA-256 |
|---|---|
| 最终Swift42项log | `1475d0d150b83e8ba4064a5084da67b6391c9cd266945999674a17233f957cce` |
| 最终Python13项log | `0774029ee936442ec3c9a5d93fa374744c56aa0e5bf78b199f339296623613ae` |
| 旧控制器9项log | `e96cf5a493d30dab0a4736040f8b8d1cdfcb85a340d5abe323fc6eca88db10dd` |
| 首次Swift失败log | `d0aa25e6061e774ac49d10b675b5198e41bc80d5f77ec25c1132699eafbbb0e0` |

## 8. 五维 SELF_REVIEW 与问题等级

| 维度 | 结论 |
|---|---|
| TECHNICAL | PARTIAL：素材原准入与REF事件/时钟离线有效；完整播放器素材/执行循环兼容未闭合 |
| ENGINEERING | 本轮新增规范问题0，三项Guard exit0；冻结文件32处Format债务保留。没有生产音频改动；原冲突现场不动 |
| EVIDENCE | PASS for offline reporting：实际构建/命令/exit/首错保留；不把Fake、软件计划和数字窗口冒充物理声学 |
| CONSISTENCY | PASS：REF冻结与ADAPTED分开；HOST生产、音频合同、原控制器安全断言保持；不修改历史结论 |
| Stage7 Forbidden Checklist | PASS：无Runtime/Provider/DR/正式Human Gate变化，无新Engine/Tap/设备实验/私人音频读取，无下一节点执行 |

- 新增CRITICAL：0。
- **MAJOR-R2-COMPAT-01 OPEN**：派生HOST代理无法通过现有控制器素材登记；对应播放器源码/有限登记和REF执行循环适配尚未完成。阻塞设备比较，不是确认的AEC或生产代码BUG。
- **MINOR-R2-EVIDENCE-01 OPEN**：共同有声范围只证实数字内容；蓝牙缓冲、实际设备音量/摆位、Mic Mode、声源/系统参考隔离、原生保存格式差异仍需独立记录。严重性不代表可跳过准入。
- 历史C19/C23及全量规范FAIL不在本轮清理；AEC根因无新增确认。

## 9. 准入与停止状态

```ini
R2_ADAPTATION=PARTIAL
REFERENCE_BUILD=PASS
REF_MATERIAL_ADMISSION=PASS
HOST_MATERIAL_ADMISSION=PASS
COMMON_VOICED_WINDOW=PASS_DIGITAL_ONLY
REF_LIVE_EVENT_INTERFACE=PASS_OFFLINE_GENERATION
CLOCK_CONVERSION=PASS_OFFLINE
BT_CONTROL_OFFLINE=PARTIAL
REFERENCE_HOST_PREPARATION=PARTIAL
COMPARABLE_PROTOCOL=LIMITED
READY_FOR_DEVICE_COMPARISON=false
DEVICE_COMPARISON=NOT_RUN
DEVICE_EXECUTION=NOT_AUTHORIZED
SOURCE_REFERENCE_ISOLATION=UNKNOWN
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
SQ-M1=OPEN
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```

提交本轮适配和脱敏报告后停止，交主控审核；不继续搜索无关目录、不启动设备、不调整测试条件。
