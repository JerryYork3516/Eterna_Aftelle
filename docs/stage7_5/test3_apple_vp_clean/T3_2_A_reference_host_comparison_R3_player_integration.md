# T3.2-A · R3 BT Player Compatibility & Execution Integration

日期：2026-10-19至20日（跨日收口）。范围：隔离派生播放器、单次执行连接、无设备离线验证。审核为SELF_REVIEW，无独立审核员。

## 1. 结论

**R3_INTEGRATION=PASS；READY_FOR_DEVICE_COMPARISON=true，仅表示离线技术准备完成。**

R2的MAJOR素材兼容/执行连接阻塞已在离线范围关闭。找到原播放器Objective-C源码及其直接依赖，使用原文件名重建后与登记二进制逐字节一致。派生副本仅增加两份固定代理素材准入；REF/HOST连接复用原SingleRun与R2时钟翻译，完成33项新增离线测试及原42/13/9回归。

**DEVICE_DISABLED=true，DEVICE_EXECUTION=NOT_AUTHORIZED。** 没有启动App、真实REF入口、NSSound播放器、AVAudioEngine、麦克风或扬声器。Foundation准入探针与Fake子进程验证不等于设备验证。没有读取私人录音、上传音频或修改生产音频代码。未确认AEC根因，T3.2-A仍BLOCKED。

## 2. Git、源码与工作区保护

| 项目 | 实际身份 |
|---|---|
| 开始HEAD / upstream /实时远端 | `e23884c44aaacd71198a2d732a1f835f53fe6174`，三方一致 |
| 干净隔离worktree | `vp-reference-host-preparation/Eterna_Aftelle` |
| 本地分支 → 推送目标 | `codex/reference-host-comparison-preparation` → `Test3-AppleVP-Clean` |
| 跨文件修改前空回滚点 | `8fc93688dd1127b06434f6d7475ed20facec3108`，未纳入其他修改 |
| 冻结REF | `c64c7e2629ec775062fdc2ea1e4a934c73c1fa75`；R2 ADAPTED_REF补丁不变 |
| 受保护原冲突worktree HEAD | `28a8589eddbf59b2a8fd0c73ebdfd3e8341b7273`；7个未解决冲突保持 |
| 受保护索引SHA-256 | `e4c0f51f433f4f53a3bf77e82aabd5152617f5efdbe441f05559182a56c8b952`，status/index前后对照 |

仅以 `GIT_OPTIONAL_LOCKS=0`读取原冲突worktree状态及索引摘要；没有stash/pop、reset/clean、分支切换、冲突解决或写入。未跟踪文件清单保持；没有读取私人文件来声称其内容已逐字节复核。其他研究worktree无写操作。

执行身份为上述checkpoint加本次明确源文件；冻结逐文件摘要留在Git忽略的 `.build/reference_host_r3/final-code.json`。本报告的交付commit由Git提交对象和最终回复给出，不伪造自引用SHA。

## 3. 原播放器来源核验

原文件位于已登记BT-Speech `synchronized-748E7DF3-6E92-4A88-A3AC-0888DCFF111B`目录；其源码为 **`bt_proxy_speech_once.m`，不是Swift**。它直接包含原BT-HIL的 `native_dual_sound.m`。本轮由原准备报告的clang命令定位到`.m`，没有从二进制字符串推断实现。R2“限定Swift搜索未定位”的历史记录保留。

| 文件 | SHA-256 |
|---|---|
| 原 `bt_proxy_speech_once.m`，4036bytes | `e1340f6a26f0b1506f81d594c258b0520264bcecf4983356e3c70b5ba338a42c` |
| 直接依赖 `native_dual_sound.m`，9075bytes | `ac40e554ff1b414a758bbb4a4949406e01b2eed6b753a4c1f3db816516146423` |
| 原二进制及同名重建二进制，75544bytes | `3f21479468417218617be4a122a417e865060a46d585b6614aa51a2537653b82` |
| 原 `sync_once.py`，9452bytes | `b81621be6448803ddb3b2c4c7bdaf57fd6cb673ec1898c525758896574692cd9` |

实际重建命令：`clang <原.m> -fobjc-arc -framework AppKit -framework CoreAudio -framework Foundation -o <新隔离目录>/bt_proxy_speech_once`，exit0。Apple clang21.0.0（clang-2100.3.34.2）、SDK27.0。第一份探查重建使用不同输出文件名，SHA不同；恢复原文件名后完全一致，没有修改源码来凑摘要。

原源码可确认的行为：

- `.m:11–14`：显式 `--authorized-proxy-once`、原固定整文件SHA；`.m:19`：原11.012916…秒、无loop、UID读回；原控制器execute在Popen前也固定原SHA。
- `.m:15–18`及依赖 `Devices()`：唯一目标设备、既有蓝牙UID摘要、alive/mute、默认输入/输出路由、NSSound按真实UID绑定。原始UID及设备摘要仅留本机，不提交。
- `.m:22–36`：stdin一条PLAY，最多一次NSSound.play；STOP/EOF/错误停止；13秒播放看门狗；delegate清除。没有新增或修改音量设置。
- 原NSSound自身不申请麦克风权限。系统权限、REF实验确认及HOST采集/导出确认仍由原程序承担；控制器不能替代这些门禁。

## 4. 最小派生适配与产物

只在新Git忽略目录复制并适配原源码。直接依赖保持原字节；include改成本地相对路径。`player.patch`只添加共享准入头、以登记结果替换单SHA判断、将时长读回与所选登记时长比对。原UID/路由断言、NSSound调用、循环、增益、13秒看门狗与清理逻辑不改。两种控制窗口分别在PLAY后5/11秒停止，均在原13秒看门狗以内，不扩大播放预算。

| R3产物 | SHA-256 |
|---|---|
| `player.patch` | `45a913c3c30665e9ec4ba58488502a3e80a715e4f9c2907a165f83beb37a6f00` |
| 派生 `.m` | `f564c0ec2398f1f8b213e1586c6c59e9d2d3b481090d2402bdce802dddea947d` |
| `proxy_registry.h` | `8ce9be44e69ae138f7ebc8b2f9b98866fb55ad622255013e0c019fa2de5061b0` |
| 派生 `bt_proxy_registered` | `ff47b7a948fde6cc47c96ffdee30822563c89abc32e94419390942e213d037d8` |
| Foundation-only `registry_check` | `9bff8ded8a088d157ab3a7bd7b47b681c51aa6f21ca1e56849a8bb249f806f60` |

构建位置：`.build/reference_host_r3/candidate1/`。原二进制未覆盖，派生二进制只编译未运行；实际运行的准入探针只链接Foundation，直接使用相同准入函数，不创建NSSound或查询设备。没有把Mock结果称为真实播放器输出。

提交的6份实现/测试文件：`prepare_player.py`、`player.patch`、`proxy_registry.h`、`registry_check.m`、`integration.py`、`test_integration.py`；另提交本报告、工具README和DEVLOG索引。原设备相关源码副本、编译产物、素材、执行日志和本地receipt均不提交。

## 5. 两份素材的准入

| 登记 | 原REF代理 | HOST派生代理 |
|---|---|---|
| 固定文件名 | `REF_proxy.wav` | `HOST_proxy.wav` |
| SHA-256 | `1c7081f8271251804e01234be8a0ff8344062d09c311592634cb8fdf6b992d0a` | `4a0b85b6fa3d14f14510d3f041ff1c41ee9b0363962c28dca812ce0ae83a55e8` |
| 格式 | 24kHz / Mono / PCM16LE | 同左 |
| 帧数 / 时长 | 264310 / 11.012917s | 360310 / 15.012917s |
| 前导与内容 | 首个源样本非零；完整原字节 | 96000帧全零，然后完整原代理样本 |
| 软件控制窗 | observation [4,9) | score [0,11) |

派生播放器只读取自身旁 `assets` 中两个规范绝对路径。完整SHA、RIFF长度、fmt/data合同、帧数、前导及登记起音均检查；不提供任意SHA白名单。其他名称、嵌套/别名路径、symlink、格式/时长/内容改变全部拒绝。不通过同名替换绕过旧校验。

两个正控直接调用同一C准入函数通过。负控明确命中SHA、PCM格式、Frame count、前导、名称、路径/symlink及截断原因；不是只看到任意非零exit就计PASS。原素材及R2派生素材没有重采样、改速、增益或重写；本轮只在隔离bundle复制非私人素材，不提交新的音频。

共同数字内容仍为R2结论：代理源前5秒对应观察/评分 [4,9)；居民主要数字非零包络约 [4,7.747)。此方案HOST前3秒代理为静默，不能验证历史首3秒人声静音问题；不声称播完11秒代理全文或已证明物理双讲。

## 6. REF/HOST连接与安全停止

`integration.py`使用原SHA锁定的 `SingleRun`；REF再经原R2 `ReferenceRun`。执行循环按旧sync_once的准备、原同意等待、调度、封存等待及退出结构作有限适配，未复制测试系统或新增音频框架/Engine/Tap。

| 项目 | REF | HOST |
|---|---|---|
| 目标产物SHA | `54d2eaf775eccdf806c82f8996a7038db4b219e4ddba60ea8914122997385ade` | Debug主程序 `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`，dylib `34ca1dc87ed28229fc2992503253d272eca4833dea5fdb2f7ceaf20c25267ba1` |
| 子进程参数 | 原vp-c授权/素材/registration等参数；仅额外传事件fd环境变量 | 原隔离DEBUG参数及ScoreControl fd |
| 事件 | ADAPTED_REF真实observationStart及R2锚点 | 原ScoreControl schedule/stop |
| PLAY / STOP | observation+4 / +9 | score+0 / +11，仍要求4秒预热schedule |
| 时钟 | continuous/absolute夹取与timebase验证后转absolute ns | 原mach_absolute ns |

不把REF写入旧 `--arm A/B`，HOST不继承REF fd环境变量。启动任何子进程前核验目标可执行文件、HOST dylib及bundle；播放器ready还须匹配本组素材SHA/时长。第一次schedule固定runID，外来run、重复schedule/terminal、非法clock、缺失事件、EOF、超时及迟到拒绝。原50ms调度迟到门槛保持，不是新声学阈值；禁用Python优化模式，防止原assert被移除。

每个run一个播放器，PLAY/STOP命令最多各一次。取消或失败尝试STOP并回收两个子进程；STOP断管道、播放器已退出时如实记录投递状态。terminate后仍不退出则有界kill/wait；无法回收不能记录PASS。正常结束还检查唯一PLAY/STOP/completion回执与子进程exit。每条事件<=512bytes、缓冲<=4096bytes、记录<=64条；没有无界队列或自动重试。证据目录必须新建，结果0600、不覆盖。

**本轮执行连接只运行Fake子进程句柄与真实Unix管道。** `run()`默认在任何进程启动前拒绝；测试显式注入标记DEVICE_DISABLED的Fake工厂。模块CLI同样拒绝设备启动，没有设备启用选项；不提供现在可运行的实机命令。后续主控授权才能接入合法的实机启动调用方，仍须原系统权限和可见同意/导出流程。Fake占位设备注册参数没有被当作真实注册验证。

## 7. 实际验证与首次失败保留

下表为本轮实际执行，不引用历史PASS代替新运行。`$BUNDLE`为本轮candidate1；`$REF/$HOST`为上节登记产物；`$SOURCE/$SYNC`为原登记源码/控制器；完整绝对参数、耗时、exit和日志SHA仅留Git忽略receipt。

| 命令 / 检查 | 实际数量与结果 | exit / 耗时 |
|---|---|---|
| `python3 -B tools/reference_host_comparison/prepare_player.py --source "$SOURCE" --assets "$R2_ASSETS_DIR" --output "$BUNDLE"` | 原同名重建等字节、补丁check/apply、派生播放器构建、Foundation探针构建、2素材准入 | 0；子命令7项全部0 |
| `clang … bt_proxy_speech_once.m …`（原 / 派生） | 2个构建，空编译诊断；无播放器执行 | 0 / 0.4726s、0.3455s |
| `clang -fobjc-arc -Werror registry_check.m -framework Foundation …` | 同一准入实现，Foundation-only | 0 / 0.1931s |
| `R3_BUNDLE=… R3_REF_EXECUTABLE=… R3_HOST_EXECUTABLE=… python3 -B tools/reference_host_comparison/test_integration.py` | 33 tests PASS；正常REF/HOST及拒绝、取消、进程回收、禁用设备入口 | 0 / 0.6045s |
| `R2_ASSETS_DIR=… xcrun swift test --package-path …/ADAPTED_REF -Xswiftc -warnings-as-errors --filter 'VPCWindowTests\|VPCCommandTests\|VPAMaterialSafetyTests\|VPCComparisonEventsTests\|ComparisonMaterialTests'` | 原R2 Swift42 PASS（两个target分别20/22） | 0 / 3.4143s |
| `R2_ASSETS_DIR=… R2_ORIGINAL_CONTROLLER=… python3 -B tools/reference_host_comparison/test_control.py` | 原R2外部13 PASS，保留旧HOST派生拒绝负控 | 0 / 0.8044s |
| `python3 -B "$SYNC" --self-test` | 原控制器9 cases PASS | 0 / 0.0354s |
| Python AST / 增量规范 | 新增3份Python解析通过；无Swift变更，SwiftFormat/SwiftLint不重复运行 | 0；新增B类0 |
| `bash tools/architecture_guard/check.sh` | architecture-guard: ok | 0 / 0.1742s |
| `bash tools/secret_guard/check.sh` | secret-guard: ok | 0 / 0.1770s |
| `bash tools/realtime_release_route_guard/check.sh` | 6项PASS、禁用符号计数0 | 0 / 0.7402s |
| `clang -fobjc-arc -Werror -fsyntax-only …/bt_proxy_speech_once.m` | 派生源码及新准入头0诊断 | 0 / 0.5293s |
| FULL_CURRENT、HOST Debug/Release重建、真实设备/播放器 | 未执行；HOST和REF生产实现未改 | NOT_RUN |

新增正负控包括：REF/HOST正确窗口、两素材准入、错SHA/帧数/格式/前导/路径、错run、重复schedule/terminal/PLAY回执、时钟倒退/混用、PLAY和STOP迟到、缺ready/schedule、控制EOF、子进程非零、stdin断开、缺完成回执、取消、hung进程升级kill、无法回收不写PASS、REF环境不污染HOST、目录不覆盖、可执行文件身份不符零启动、默认设备禁止及Python-O拒绝。

保留实际开发失败：

1. 新增24项首跑exit1，两个正常路径遇到Fake时钟倒退；Fake初始下标误取末项。修正Fake时钟，不放宽生产时钟断言。
2. 第二次24项exit1，一项把已退出播放器也要求收到STOP。修正为“没有发往已退出进程的虚假STOP、已回收并明确CHILD_ALREADY_EXITED”；活进程仍须一次STOP。其余拒绝用例改为核对具体异常原因，避免错误拒绝条件冒充负控成功。
3. 加强素材拒绝原因核对后30项exit1，5个子条件被macOS临时路径别名先行挡住，未触达格式/内容门禁。此前仅检查非零exit的30项PASS不足以证明这些分支。将合成负控临时文件放到本Git忽略目录，严格验证每个预期拒绝原因后30项exit0；未修改或降低路径门禁。
4. 补充Python-O与无法回收失败证据后32项exit0；SELF_REVIEW再补充STOP后播放器异常exit须立即中止并回收音频子进程，最终33项exit0。没有隐藏上述失败，没有修改旧R2断言或自动反复设备测试。

| 最终执行日志 | SHA-256 |
|---|---|
| R3 33项 | `e086c6011dd994de782b691d5dd83ad1b3d0edd2acf265d61cdade3212fefc4f` |
| R2 Swift42 | `6e6c37e09c71c5ea22d3aa93c9c2e9d3ab1081e9f7d3d71eff105777935d4f23` |
| R2外部13 | `0774029ee936442ec3c9a5d93fa374744c56aa0e5bf78b199f339296623613ae` |
| 原控制器9 | `e96cf5a493d30dab0a4736040f8b8d1cdfcb85a340d5abe323fc6eca88db10dd` |
| 首次24项失败 | `559e0ee0c8ca279df6df916bbf1070cc365f229c00a917240854fcaa783537be` |
| 路径别名负控失败 | `69704775c26af2a67aeccc27bbfcb3b0cb1d04891ecac0958a5c1a9149615962` |

## 8. 五维SELF_REVIEW与剩余条件

| 维度 | 结论 |
|---|---|
| TECHNICAL | PASS_OFFLINE：原源码可等字节重建；两素材准入及两种事件/时钟/退出连接通过。NSSound设备绑定及播放未执行 |
| ENGINEERING | PASS_SCOPED：只增加实验适配/测试；原控制器及R2接口不改，新增B类0。历史C19/C23及全量SwiftFormat/SwiftLint FAIL继续延期 |
| EVIDENCE | PASS：实际命令/exit/首错/源码和产物SHA具备；Fake、Foundation文件检查和物理声学严格分开 |
| CONSISTENCY | PASS：原播放器/素材不覆盖，REF/HOST不混用；旧R2失败记录保留，其他worktree不写入 |
| Stage7 Forbidden Checklist | PASS：无生产DSP/Runtime/Provider/DR/正式Human Gate改动，无新Engine/Tap/平台/音频保存链，无设备执行 |

新增CRITICAL=0、MAJOR=0、MINOR=0（本轮实现/测试范围）。**MAJOR-R2-COMPAT-01=CLOSED_OFFLINE**，不代表声学问题关闭。既有MINOR-R2-EVIDENCE-01及设备条件仍OPEN：

- 后续独立设备授权；真实系统权限、REF可见实验同意、HOST原UI配置/录音/导出同意。
- TinyUSB/内置扬声器/小爱在线、正确不同UID、输入/输出音量、摆位、可读取Mic Mode及真实AGC/VP读回。不能用“未修改”证明环境相同。
- 代理同Mac输出的 `SOURCE_REFERENCE_ISOLATION=UNKNOWN`；蓝牙物理起止/覆盖和声压未校准。
- REF原预热/排程与HOST实现差异仍保留，多变量条件不是严格单变量因果实验；实际采集/尾包、真人保留、回声听感尚未验证。

唯一下一项：主控审核本离线交付，若批准再按固定REF/HOST共同内容方案分别进行一次受控设备对照；本轮不启动、不安排自动重试，也不推进真人或正式53门禁。

## 9. 状态

```ini
PLAYER_SOURCE_VERIFIED=PASS
DERIVED_FIXTURE_ADMISSION=PASS
REF_EXECUTION_INTEGRATION=PASS_OFFLINE
HOST_EXECUTION_INTEGRATION=PASS_OFFLINE
CANCEL_AND_CLEANUP=PASS_OFFLINE
OFFLINE_REGRESSION=PASS
R3_INTEGRATION=PASS
READY_FOR_DEVICE_COMPARISON=true
DEVICE_DISABLED=true
DEVICE_EXECUTION=NOT_AUTHORIZED
DEVICE_COMPARISON=NOT_RUN
SOURCE_REFERENCE_ISOLATION=UNKNOWN
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```

提交脱敏报告及必要适配/测试，正常推送并核验隔离交付HEAD=upstream=实时远端后停止。原冲突worktree不移动到新提交。
