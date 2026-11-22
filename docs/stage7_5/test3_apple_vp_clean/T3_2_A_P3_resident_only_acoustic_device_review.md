# T3.2-A / P3 · 居民独讲声学设备审核

**执行结果为 `BLOCKED_BEFORE_CAPTURE`。** 2026-11-21 13:32（北京时间），取得本轮独立授权后启动冻结 App 一次。普通 A 准备通过，原文件选择器的打开动作未获语义核验。录音确认面板未打开，无 RunID。录音、播放、JSON 导出和 WAV 导出均为 0 次。

## 1. 授权和冻结身份

| 项目 | 核验结果 |
|---|---|
| 本轮授权 | 真实麦克风、固定素材播放最多一次、录音最多 15 秒、原界面本机 JSON/WAV 导出。新许可与 P1/P2 独立。已使用唯一 App 启动机会并关闭该尝试 |
| 源码 | 起始 `f16548479301b7fb7a5957fe7d825918c4836731`，启动前 HEAD、upstream 和 GitHub 实时远端一致。App 树 `446e2ef9e63d60dd14bf5fd6d70079e6f18c0539`、Tools 树 `a687af8d5095a2c1230e9f08a57cc51212243677` 均匹配已接受的 FULL_CURRENT 21/21。沿用该收据 |
| Debug 实际加载 | 经确切 PID `24428` 核验可执行路径及实际映像 inode/device、SHA。Launcher `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`，dylib `de8d24e6c8633da395bf29339d8e1b4887acc22c71aa95acd396a18285195df4`。唯一参数 `--apple-vp-acoustic-test` |
| 设备 | 启动前后为同一登记的默认 TinyUSB 输入 60%、Mac mini 内置输出 55%、未静音。两端在线且空闲。应用运行态设备绑定、VP/AGC 与 Mic Mode 未执行 |
| 固定源 | 原 `HOST_resident.wav`，SHA-256 `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`。24 kHz / Mono / PCM16LE，114032 帧，约 4.751333 秒，文件 228108 bytes，首 24000 帧为零。起止文件元数据及 SHA 复核一致 |
| 保护及隐私 | 原 7 项冲突、索引、14 项证据、Fixture 元数据与 M31 撤回状态均核验一致。原本机导出根目录具备 0700 资格，文件应由原导出流程以 0600 独占写入，本次无导出 |

P3 预检收据 SHA-256 `475a4d74513d2cc93604d92de8e47ab2ed63ead6b11e1e9897b2b7bcdd98c08a`，临时 AX 源脚本 SHA-256 `e384a23fb1c36364808d82a4ba9d42ffe83bc64980eebdf1fff4c739fe02ef1c`。原确认按钮 14 项和 A/文件选择 7 项离线用例均通过，适用范围是选择规则与状态校验。

## 2. 原入口和阻塞位置

1. 启动后从原界面选择 `Prepare A · Resident only`。回读 `phase=ready scenario=A`、`RECORDING`、准备 profile `APPLE_VP_AGC_ON`、素材栏空，无预热。RunID 为 `UNKNOWN`，包数和留存字节均为 0。
2. 通过原 `Select approved offline WAV…` 打开系统文件选择器，向原面板提交核验过的固定路径。原计划通过 AX 匹配唯一、启用且带有原打开文案的按钮。临时控制枚举的按钮中没有匹配项，返回 `Original file picker action unavailable`（`-2700`）。文件选择完成回执未取得。
3. 文件选择器的取消匹配也未取得回执。随后确切 PID 的原 Quit 菜单项处于禁用状态。后续只读查询确认该 PID 已消失，原进程退出方式与退出码为 UNKNOWN。默认输入和输出均复核为空闲，原 Route 与音量一致。
4. 本次唯一尝试到此关闭。原 `Start…`、`Allow local test?` 及录音确认 `AXPress` 均未调用。实际 OpenPanel 控件层级及标签未能再读回，因此只能定位到临时选择器的匹配失败，具体原因仍为 UNKNOWN。

本机阻塞摘要 SHA-256 `c9e1969c032a6e2dd59afca18bf625858a8eec6838b47c325c193f9069ef71ff`。原始 AX 记录与控制收据留本机。

## 3. 声学证据与准入

原录音入口尚未执行，因此 Capture/Playback Generation、ConfigurationID、运行态 AGC/VP、Player 调用、Render 非零内容、Native/PCM 连续性、封存尾部与收尾回执均为 NOT_RUN。没有同 Run 的物理外放见证、录音试听、起音或尾部判断。固定 WAV 的零前导仅描述文件内容。

P3 暂无声学裁定，下一阶段准入条件尚未满足。若主控另批新的 P3 尝试，应优先核验原 NSOpenPanel 的实际打开和取消控件，再走原录音确认。AEC、CLOCK 根因与 SQ-M1、R3-M01 保持当前开放状态。保留既有 P1 结果和 P2 的有限配对结论。 [声学准入 §7](T3_2_A_acoustic_qualification_readiness_review.md#7-p3--居民纯回声与起音) · [P2 审核 §8](T3_2_A_P2_Human_Only_AGC_ON_OFF_device_review.md#8-p2-agc-off-单次执行及配对审核)

## 4. 交付与状态

只新增本报告，更新 Test3 README 的当前状态索引。回滚检查点 `7ec8a68720dd99ccd17d499e4b323eecef8e32a7` 与起始提交 Git 树一致。Stage7 Forbidden Checklist 为 PASS，红线触碰为无，生产代码、测试、Runtime API、DR schema 与平台 target 零修改，未进入 Stage 8。交付 Commit 和推送核验由 Git 历史及本机交付收据绑定。

```ini
P3_PREFLIGHT=PASS
P3_USER_AUTHORIZATION=RECEIVED_ATTEMPT_CLOSED
P3_EXECUTION_RESULT=BLOCKED_BEFORE_CAPTURE
P3_APP_LAUNCHES=1
P3_DEVICE_RUNS=0
P3_PLAYBACK_RUNS=0
P3_JSON_EXPORTS=0
P3_WAV_EXPORTS=0
P3_AGC_READBACK=NOT_RUN
P3_VP_CONFIGURATION=NOT_RUN
P3_AUDIO_CONTINUITY=NOT_RUN
P3_FINAL_TAIL=NOT_RUN
P3_PHYSICAL_PLAYBACK_WITNESS=NOT_RUN
P3_LISTENING_REVIEW=NOT_RUN
P3_ACOUSTIC_RESULT=NOT_RUN
P3_PROCESS_EXIT=PID_ABSENT_EXIT_CODE_UNKNOWN
P3_MAIN_REVIEW=PENDING

P1_RESULT=OFF_READBACK_AND_CONTROL_CHAIN_SUPPORTED
P2_MAIN_REVIEW=APPROVED_WITH_LIMITATIONS
M31_WITHDRAWAL=COMPLETED_OFFLINE_VERIFIED

AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
SQ_M1=OPEN
R3_M01=OPEN
T3_2_A=BLOCKED
T3_2_B=NOT_AUTHORIZED
T3.3=NOT_STARTED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
PRODUCTION_DIFF=ZERO
```

## 5. P3 UI全链预检与真实录音入口准入

2026-11-21 取得独立的单次无音频 UI 授权，于北京时间 22:20 启动冻结 Debug App 一次。结果为 **`BLOCKED_BEFORE_FILE_PANEL`**。临时控件识别在主窗口的准备按钮处停止，录音入口准入失败。前四节保留上次声学执行尝试的独立记录。

### 5.1 执行身份

| 项目 | 实际核验 |
|---|---|
| 源码 | 执行基线 `34c512d585b145bd066a9d3fe6d636d9b19afe6d`，启动前 HEAD、upstream、GitHub 实时远端一致。App 树 `446e2ef9e63d60dd14bf5fd6d70079e6f18c0539` 与 Tools 树 `a687af8d5095a2c1230e9f08a57cc51212243677` 匹配既有 FULL_CURRENT 21/21 候选 |
| 冻结 App | 唯一启动参数为 `--apple-vp-acoustic-test`。父进程持有确切 PID 并验证实际加载路径、映像身份及 SHA-256。Launcher `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`，dylib `de8d24e6c8633da395bf29339d8e1b4887acc22c71aa95acd396a18285195df4` |
| 固定素材 | `HOST_resident.wav` 的磁盘 SHA-256 `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`，24 kHz / Mono / PCM16LE，114032 帧，约 4.751333 秒。文件核验通过，App 侧素材选择和接收未执行 |
| 只读预检 | 默认输入 TinyUSB USB 60%，默认输出 Mac mini 内置扬声器 55%、未静音，输出 HAL scalar 约 0.55000013。两端在线且空闲。基础预检收据 SHA-256 `8a49b034e23c00099e965340a98b48069570d68b41bd240b54f52072139a1143` |

### 5.2 实际界面与证据

| 步骤 | 实际结果 |
|---|---|
| 冻结 App 主窗口 | 确切 PID 下实际窗口为 `Aftelle main-window`，无模态面板。初始 `phase=idle scenario=A`，显示 `RECORDING` 及准备配置 `APPLE_VP_AGC_ON`，素材栏为空，RunID 和代际均为 `UNKNOWN`，包数和留存 PCM 字节均为 0 |
| `Prepare A · Resident only` | 观察到主窗口控件的 `AXRole=AXButton` 和启用状态。用于唯一匹配的 `AXTitle`、`AXDescription`、`AXIdentifier`、`AXHelp` 在枚举结果中均为空。识别返回 `Original control has no matching visible label (-2700)`，未按下准备按钮，未到达 `phase=ready` |
| 原 `NSOpenPanel` 与打开动作 | `NOT_RUN`。本次未请求文件选择器，未观察其实际控件层级、选中路径或打开回执。上次文件选择器的失败原因仍为 `UNKNOWN` |
| 素材加载、原 `Start…` 及 `Allow local test?` | `NOT_RUN`。未取得 App 侧素材身份，未打开录音确认面板，未调用录音确认 |
| 原 Cancel | `NOT_RUN`。无录音确认面板可取消 |
| 音频及导出 | 控制收据仅包含主窗口聚焦、准备按钮匹配失败和只读窗口检查。未触发 Capture、Playback、预热或导出。无新 RunID。采集、播放、JSON 导出、WAV 导出均为 0 次 |

### 5.3 启动偏差、退出及设备释放

为查看缺少 AX 标签的窗口而按应用名取视图时，工具启动了另一个构建的同名 App。这是一次超出本轮授权的误启动。实际共启动两个进程，其中一个为授权的冻结 App，另一个为误启动实例。误启动实例未操作音频控件。

两实例并存时，向误启动 PID 请求原退出菜单后虽收到菜单动作回执，实际先消失的是冻结 App PID。原父进程于 22:25:01 收到冻结 App 的真实退出码 0，并确认其 PID 消失。并存时的菜单回执无法与冻结 PID 的实际退出可靠绑定，故原菜单退出链保持 `INCONCLUSIVE`。

误启动实例成为唯一 Aftelle 进程后，经其确切 PID 和可执行路径复核，取得原 Quit 菜单动作回执并确认 PID 消失。该实例的真实退出码不可得。整个清理过程未使用强制终止。

22:29:06 重新只读核验，未发现 Aftelle 或冲突音频实验进程。两端默认设备身份和格式与启动前一致，均在线且空闲。TinyUSB 输入 60%，Mac mini 内置扬声器 55% 未静音。收尾收据 SHA-256 `6b0737dc5b97cb3a7882c455cab8e8b229f398930770b2eb6cfd8e762d44d009`。两次设备快照记录路由及释放状态。界面控制收据和零 PCM 读回记录本次采集入口未执行。

### 5.4 准入裁定与保护

完整 UI 预检为 `FAIL`，本次启动机会已使用。准入仍缺少原文件选择器、App 素材绑定、录音面板、安全取消及冻结 PID 原菜单退出的完整证据。未执行声学实验。运行态 VP/AGC、时钟和输出参考均无本轮新证据。既有 P1、P2 结论及 M31 撤回状态保留，交主控独立审核。

原 7 项冲突、索引及 14 项受保护证据与登记基线一致，Fixture 元数据与 M31 撤回身份一致。只追加本节并更新 Test3 README 索引。回滚检查点 `f6044ba2e3de36d5d3c2fc3e1809302539fdb7e2` 的 Git 树与基线相同。生产源码与正式测试差异均为零。`git diff --check` 和 Secret Guard 通过。Stage7 Forbidden Checklist 本轮执行裁定 `REWORK`，偏差为按应用名操作触发额外启动。代码红线、Runtime API、DR schema、平台 target、Stage 8 均无改动。后续任何 UI 尝试或真实录音均须另行批准。原始 AX、收据、设备身份及本机细节留本机。

```ini
P3_BASIC_PREFLIGHT=PASS
P3_UI_AUTHORIZATION=RECEIVED_ATTEMPT_CLOSED
P3_UI_APP_LAUNCHES=1
P3_UI_UNINTENDED_APP_LAUNCHES=1
P3_UI_TOTAL_APP_LAUNCHES=2
P3_UI_EXECUTION_RESULT=BLOCKED_BEFORE_FILE_PANEL
P3_UI_FILE_PANEL=NOT_RUN
P3_UI_FILE_SELECTION=NOT_RUN
P3_UI_ASSET_LOADED=NOT_RUN
P3_UI_RECORDING_CONFIRMATION=NOT_RUN
P3_UI_SAFE_CANCEL=NOT_RUN
P3_UI_PROCESS_EXIT=INCONCLUSIVE
P3_UI_FROZEN_APP_EXIT_CODE=0
P3_UI_DEVICE_RELEASE=IDLE_AND_UNCHANGED
P3_UI_AUDIO_CAPTURE_COUNT=0
P3_UI_PLAYBACK_COUNT=0
P3_UI_JSON_EXPORTS=0
P3_UI_WAV_EXPORTS=0
P3_UI_PREFLIGHT=FAIL
P3_PRECAPTURE_READY=false
P3_MAIN_REVIEW=PENDING
P3_DEVICE_RUNS=0
P3_ACOUSTIC_RESULT=NOT_RUN
P3_EXECUTION_AUTHORIZED=false
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
SQ_M1=OPEN
R3_M01=OPEN
T3_2_A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
PRODUCTION_DIFF=ZERO
FORMAL_TEST_DIFF=ZERO
```

## 6. P3 无音频 UI 全链复检（重新授权）

**本次 UI 预检通过，文件选择由用户协助完成。** 2026-11-21 取得新的单次无音频 UI 授权。北京时间 22:54:35 启动冻结 App 一次，23:00:35 正常退出。前五节保留之前两次尝试的原始结论。

### 6.1 冻结候选与 PID 绑定

| 项目 | 证据 |
|---|---|
| 源码 | 启动前 HEAD、upstream、GitHub 实时远端均为 `0cc469b225219774f53b9cebdd4c7be7bdfe24dc`。App 树 `446e2ef9e63d60dd14bf5fd6d70079e6f18c0539`、Tools 树 `a687af8d5095a2c1230e9f08a57cc51212243677` 与已接受的 FULL_CURRENT 21/21 候选一致 |
| 冻结 App | 唯一启动参数为 `--apple-vp-acoustic-test`。原父进程持有子进程，核验实际加载映像、可执行路径和 SHA-256。Launcher `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`，dylib `de8d24e6c8633da395bf29339d8e1b4887acc22c71aa95acd396a18285195df4` |
| 固定素材 | 原 `HOST_resident.wav`，SHA-256 `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`，24 kHz / Mono / PCM16LE，114032 帧，约 4.751333 秒。启动前、选择后和退出后复核 SHA 及文件元数据 |
| 本机控制 | 以 `AXUIElementCreateApplication` 绑定原子进程 PID，核验父子 PID、启动时间、可执行路径及目标控件所属 PID。打开与取消面板的本机临时工具复核同一父子身份和实际加载映像。21 项离线选择规则通过，变更父或子进程启动时间的负控均拒绝操作 |
| 设备 | 默认 TinyUSB USB 输入 60%，Mac mini 内置输出 55% 且未静音。退出后两端身份、格式、音量及静音读回与启动前一致，两端均在线且空闲 |

### 6.2 原界面执行记录

| 步骤 | 实际结果 |
|---|---|
| Prepare A | 实际标准窗口内通过 `AXDescription` 读到唯一、启用的 `Prepare A · Resident only` 按钮，执行一次。随即核验 `phase=ready scenario=A`、`RECORDING`、准备态 `APPLE_VP_AGC_ON`、无 warm-up、无 RunID、零包及零 PCM |
| 原文件选择器 | 从确切 PID 的普通 A 窗口仅发出一次 `Select approved offline WAV…` 操作。AX 未返回成功回执，随后只读观察在返回控件的 PID 边界处以 `AX_PID_MISMATCH` 停止。该控件未被点击。完整选择器树、打开按钮字段和自动点击资格仍未知 |
| 用户选择与 App 接收 | 用户确认已在原选择器从指定的完整目录打开 `HOST_resident.wav` 并回到主窗口。同一 PID 的只读回读确认面板已关、`file=HOST_resident.wav`、`ready/A`、无 RunID、零 PCM。选择证据来自用户精确路径见证、固定 SHA 和 App 状态 |
| 素材证据边界 | 原 `NSOpenPanel` 的成功选择将 URL 直接交给 `selectAppleVPAcousticPlaybackURL`，公开状态显示文件名。本轮核验原界面接收选定素材，App 内部完整 URL 无直接读回，WAV 解码和播放资格留待另行授权执行 |
| 原录音确认面板 | 从普通 A 主窗口只打开一次 `Start…` 外层面板。同一 PID 的 `AXSheet` 显示 `Allow local test?` 和原 A/C 说明。两个启用的 `AXButton` 分别以 `AXDescription` 暴露 `Use microphone, local capture and test playback` 和 `Cancel` |
| Cancel | 仅向已核验的 Cancel 发出一次 `AXPress`。AX 未返回成功回执，随后的同 PID 快照确认面板关闭，仍为 `ready/A`，授权未挂起，无 RunID、代际、采集包或留存 PCM。取消以实际状态转换核验 |
| 原菜单退出 | 模态面板关闭后，确切 PID 的原 Quit 菜单动作返回成功。原父进程得到真实退出码 0，随后确认 PID 消失并复核设备空闲 |
| 音频与导出 | 采集、播放、音频预热、JSON 和 WAV 导出各 0 次。运行态 VP/AGC、内容时钟、Render、声学及试听均未执行 |

关键本机证据 SHA-256。启动预检 `305e35e0561460dc1ed97330d86528e75ba17f199836fac85eaa5fe5f9b237c2`，素材路径见证与读回 `98cb93cd1f1a084bd2b24d5778e3db6a0228ed542d98297fc78cbb7ace3c9e31`，面板快照 `6d41a1047ab57555aa1a5064677cb7b117296b032751176451271395a6c3d12a`，取消后快照 `4847ebb8812ebd4ebff572e3761b1ac1403e02d58096c8606432ed9fe0676533`，Quit `778effb5625d2581f46ba59ab3a5e4752fd002992f21cdbe688089add765ea61`，设备收尾 `b179e7f7f2178e516ffd7a80e9d03a52d620a580bd134cd757937bc8385d4b81`。

### 6.3 裁定与交付

原文件选择器接受人工协助，录音确认和取消具备真实界面证据，菜单退出及设备释放成立。该流程可进入主控审核。文件选择自动化仍缺少同 PID 控件资格。正式声学运行需独立授权。既有 AEC、CLOCK、SQ-M1、R3-M01 和 T3.2-A 证据边界保持。

Stage7 Forbidden Checklist 本轮为 `PASS`。代码红线、Runtime API、DR schema、平台 target 和 Stage 8 无变更。原 7 项冲突、索引、14 项受保护证据、Fixture 元数据及 M31 撤回身份均核验一致。回滚检查点 `d7ec29d3d278e7eb1307ce3c23bf4077e6efb730` 与执行基线 Git 树相同。仅追加本节并更新 Test3 README。原始 AX、设备身份、局部工具及本机路径留本机。

```ini
P3_BASIC_PREFLIGHT=PASS
P3_UI_AUTHORIZATION=FRESH_UI_ONLY_ATTEMPT_CLOSED
P3_UI_APP_LAUNCHES=1
P3_UI_UNINTENDED_APP_LAUNCHES=0
P3_UI_FILE_PANEL=PASS_WITH_USER_HANDOFF
P3_UI_FILE_SELECTION=PASS
P3_UI_FILE_SELECTION_AUTOMATION=AX_PID_MISMATCH
P3_UI_ASSET_LOADED=PASS
P3_UI_ASSET_EVIDENCE=MANUAL_PATH_WITNESS_AND_PID_BOUND_APP_READBACK
P3_UI_WAV_DECODING=NOT_RUN
P3_UI_RECORDING_CONFIRMATION=PASS
P3_UI_SAFE_CANCEL=PASS_BY_POST_STATE
P3_UI_CANCEL_AX_ACK=UNKNOWN
P3_UI_PROCESS_EXIT=PASS
P3_UI_FROZEN_APP_EXIT_CODE=0
P3_UI_DEVICE_RELEASE=IDLE_AND_UNCHANGED
P3_UI_AUDIO_CAPTURE_COUNT=0
P3_UI_PLAYBACK_COUNT=0
P3_UI_JSON_EXPORTS=0
P3_UI_WAV_EXPORTS=0
P3_UI_PREFLIGHT=PASS
P3_PRECAPTURE_READY=true
P3_MAIN_REVIEW=PENDING
P3_DEVICE_RUNS=0
P3_ACOUSTIC_RESULT=NOT_RUN
P3_EXECUTION_AUTHORIZED=false
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
SQ_M1=OPEN
R3_M01=OPEN
T3_2_A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
PRODUCTION_DIFF=ZERO
FORMAL_TEST_DIFF=ZERO
```

## 7. 正式 P3 设备执行与时钟拒收复核

**正式 P3 技术结果为 `FAIL_NATIVE_CLOCK_CONTENT_TIME`。** 2026-11-22，用户独立批准正式 P3，并在两次界面监视中断后分别要求或明确授权重新执行。全部尝试使用同一个冻结 App，均在原可见录音面板发出一次确认，各自分配 RunID。第三次走完整个原 15 秒采集窗口并由 App 自行封存，Native 共 240000 帧。有效导出 PCM 为前 2.68 秒。用户在现场听到完整、正常的外放，在局部 WAV 中听到了居民「这」字的起音。

### 7.1 身份、授权及各次结果

执行基线 `4f2e08f343c02d7f9885bb57b020e0a2859052c4`。启动前及两次重新准备前复核 HEAD、upstream、GitHub 实时远端和原隔离工作区。App 树 `446e2ef9e63d60dd14bf5fd6d70079e6f18c0539`、Tools 树 `a687af8d5095a2c1230e9f08a57cc51212243677` 均与已接受的 FULL_CURRENT 21/21 候选一致。实际映像的 launcher SHA-256 为 `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`，dylib 为 `de8d24e6c8633da395bf29339d8e1b4887acc22c71aa95acd396a18285195df4`。唯一启动参数为 `--apple-vp-acoustic-test`。原父进程持续持有同一冻结 PID `51862`，所有操作核验其身份。

普通 A 为 `RECORDING`、AGC-ON、无 warm-up，每次上限为 15 秒及 720000 PCM bytes。TinyUSB USB 输入 60%，Mac mini 内置输出 55% 且未静音。用户在原选择器手动选中登记目录的 `HOST_resident.wav`，同一 PID 读回文件名。重新准备经原 `Discard result?` 面板执行，先核验旧证据已经导出，原准备逻辑保留所选 URL。三份 JSON 都读回原素材 SHA-256 `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`。固定素材为 24 kHz / Mono / PCM16LE、114032 帧、4.751333 秒，含一秒零前导。

| 尝试与 RunID | 启动和封存 | 本次 Player 事件 | 本机导出 |
|---|---|---|---|
| 1 · `06F4FADD-682E-4648-99F0-81A45ABF89D8` | Capture generation 1 / configuration 2。实时界面 `AXValue` 读回失败，外部控制脚本发出原 Stop。Native 0 帧，PCM 0 包，`cancelled` | `Player.play` 0 次，非零 Render 0 帧 | JSON 21931 bytes。原 WAV 按钮禁用 |
| 2 · `99C3D5E3-8D5C-40E7-AA31-B17544F22208` | Capture generation 2 / Playback generation 3 / configuration 5。读到运行态后，外部监视在 `AXRole` 收到 `-25202`，发出原 Stop。Native 11200 帧，29 个连续 PCM 包、0.58 秒，`cancelled` | `Player.play` 1 次，完成事件 0，非零 Render 0 帧 | JSON 39104 bytes，WAV 27884 bytes |
| 3 · `1CBF4340-9F8D-4096-BE49-B894D692E6D6` | Capture generation 3 / Playback generation 5 / configuration 8。外部监视取得 starting、running、sealed，无 Stop 请求。App 原流程封存，`native_coverage_unverified` | `Player.play` 1 次，完成事件 1，非零 Render 59964 帧。进程累计播放启动计数为 2 | JSON 54124 bytes，WAV 128684 bytes |

### 7.2 本机监视整改

前两次由外部 AX 监视器停止，封存错误为 `cancelled`，它们均无 Native 或 PCM 时钟拒收。首轮监视器在状态刷新中读取旧 AX 节点的一项值失败即触发 Stop。第一次整改对可恢复的值读取失败做有界只读复取。第二次实际错误明确为 `kAXErrorInvalidUIElement (-25202)`，发生在角色读取。

第二次整改将监视限制在确切 PID 的主测试窗口和关键文字状态。已失效的非关键旧节点可丢弃，每次有效读回仍须包含唯一的 phase、RunID、错误、VP、AGC、丢包和计数等字段。关键字段缺失时限时重新获取快照，持续失读、PID 不符或实际技术异常仍触发原停止规则。离线验证覆盖过期节点、缺失关键字段、重复 RunID、身份变化及技术错误保留。同一 PID 的 6 次空闲读回通过。第三次设备执行取得 36 次状态读回，遇到 1 个过期节点且关键字段完整，未发出 Stop。整改只存在本机忽略目录，原音频实现及门禁未改。

### 7.3 第三次实际运行与拒收链

| 项目 | 实际证据 |
|---|---|
| VP、AGC、Mic Mode | Engine 启动与居民播放启动两点的实际读回身份相符。VP Input/Output 均开启，要求及实际 AGC=true，bypass=false、inputMuted=false。两次 active/preferred Mic Mode 均为 0（Standard）。16 kHz/3ch Float32 非交错 client 格式，硬件侧输出 16 kHz/2ch，读回一致 |
| 设备及释放 | 两点的输入为 `PROCESS_SHARED_IO_DEVICE_SET_METADATA_QUALIFIED`，输出为 `PROCESS_DEVICE_METADATA_MATCHES_DEFAULT`。Engine 运行期配置通知、跳过通知与 Route 变化为 0；监听已关闭。原 Stop/Seal/Shutdown、确切 PID 的 Quit、父进程退码 0 及空闲设备核验均取得。输入输出、音量及静音与启动前一致 |
| Native 与首个异常 | 150 个 buffers、240000 frames，帧量 15.000 秒。首个拒收出现在第 28 个 callback（零基序号 27），约为有效 PCM 起点后 2.702 秒。相邻 sampleTime 增量为 1600 帧；host 间隔由名义 100.000000 ms 变为 102.412958 ms，偏差 2.412958 ms，高于 16 kHz 的一采样周期 0.0625 ms。该处有完整五行 raw timestamp 诊断 |
| 内容时间与连续性 | `native_clock=18`、`content_time=123`，其它拒收为 0。Input/Render 各观测到 18 次 host 不连续，sample 跳变、缺时、重复、倒退及见证器跳过均为 0。冻结的 `continuousInputHostTimeLocked` 在越界后令该代际 `sampleTimeContinuityValid=false`，后续无法给出有效内容时间，与剩余 123 个回调及 PCM 停止生成相符。硬件或系统为何产生该时间跳变仍待查明 |
| 已存 PCM 与尾部 | 134 个完整 20 ms 包从序号 1 到 134，连续 128640 bytes、2.68 秒。generated/drained/queued 为 134/134/0。Converter partial tail 字段为 null。有效存储为前缀，缺失由时间资格拒收解释，完整居民播放末端及其后静音均无 PCM 覆盖。Native/PCM 短窗为 `UNKNOWN_MISSING_STREAM` |
| Render | 软件非零 Render 相对有效 PCM 起点约为 +1.226 至 +4.976 秒。该时间关系受 host 不连续限制。Render 软件完成及非零帧数用于说明播放链事件；用户现场观察单独登记。Apple 内部 AEC 参考不可直接观测 |

### 7.4 外放、试听及审核边界

用户确认在 Mac 旁完整听到内置扬声器的居民语音，现场听感正常。用户独立试听第三次导出的局部 WAV，反馈其余听感正常，能辨认居民「这」字大约几十毫秒的起音。时长是用户的主观估计，未进行音频样本分析或字词定时。该回报支持本次现有片段中存在可闻居民起音。完整回声、录音尾部的声学资格及 R3-M01 仍待完整证据。正式 P3 的总体声学结果为 `INCONCLUSIVE`，技术结果为 `FAIL_NATIVE_CLOCK_CONTENT_TIME`。

本机证据均通过原界面确认导出，目录 0700、文件 0600。WAV 只核验格式头、大小、SHA 和与 JSON 的 PCM 摘要一致性。原 WAV、JSON、设备身份、完整 AX 记录及本机路径留本机。

| 证据 | SHA-256 |
|---|---|
| 尝试 1 JSON | `c373c39048555db2e9b0d5adfbd28fc4306c7c3430e8cb1ab0afc54e8785773c` |
| 尝试 2 JSON / WAV | `dc565726d0176f9ee244840f70bb773886ce892cb39eab005ab1091755789f7d` / `bd98680576ec6a6657bb6db477867e6264d94877cb3fce9d549bac47177c777b` |
| 尝试 3 JSON / WAV | `26bc59f836ca9f2706dfba0b8e59e47e0a0efbbd9599164636ec286ed4d2f165` / `06386cc4754548d30f41908092705de90e856e624b0c597cbb452e5d839e91ed` |
| 退出和设备释放 | `cedf7b27742c094d27ea953ffc1b5c02856e995f52a50e5008a1b03034dd56c1` / `c305001bcbb98108cc9d509a7fa16695e3483051de1455326b0d5c40f8049a64` |

唯一建议下一步为使用本次已封存的五行时间戳元数据做定向离线 CLOCK replay，复核既有 Converter 时间映射拒收，保持原时钟容差，交主控裁定新的工程范围。P4 及 Human Gate 尚未准入。

仅追加本报告，更新 Test3 README 索引。回滚检查点 `cc07cf2fd5d557786f2b14dc623a313d605fca15` 与执行基线的 Git 树相同。原 7 项冲突、索引、14 项保护证据、Fixture 元数据及 M31 撤回身份一致。Stage7 Forbidden Checklist 为 `PASS`，代码红线、Runtime API、DR schema、平台 target 及 Stage 8 无变化。

```ini
P3_PREFLIGHT=PASS
P3_USER_AUTHORIZATION=RECEIVED_AND_CONSUMED_PER_ATTEMPT
P3_APP_LAUNCHES=1
P3_DEVICE_RUNS=3
P3_PLAYBACK_RUNS=2
P3_PLAYBACK_COMPLETED_RUNS=1
P3_JSON_EXPORTS=3
P3_WAV_EXPORTS=2
P3_AGC_READBACK=TRUE_CONFIRMED
P3_VP_CONFIGURATION=IO_ON_BYPASS_FALSE_MUTED_FALSE
P3_UI_MONITOR_FIX=OBSERVED_ON_RUN_3
P3_AUDIO_CONTINUITY=CONTIGUOUS_PCM_PREFIX_ONLY
P3_FINAL_TAIL=NOT_COVERED_CLOCK_REJECTION
P3_PHYSICAL_PLAYBACK_WITNESS=ON_SITE_COMPLETE_NORMAL_RUN_3
P3_LISTENING_REVIEW=USER_REPORTED_AUDIBLE_RESIDENT_ONSET_IN_PARTIAL_WAV
P3_TECHNICAL_RESULT=FAIL_NATIVE_CLOCK_CONTENT_TIME
P3_ACOUSTIC_RESULT=INCONCLUSIVE
P3_MAIN_REVIEW=PENDING
P3_EXECUTION_AUTHORIZED=false
P1_RESULT=OFF_READBACK_AND_CONTROL_CHAIN_SUPPORTED
P2_MAIN_REVIEW=APPROVED_WITH_LIMITATIONS
M31_WITHDRAWAL=COMPLETED_OFFLINE_VERIFIED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
SQ_M1=OPEN
R3_M01=OPEN
T3_2_A=BLOCKED
T3_2_B=NOT_AUTHORIZED
T3.3=NOT_STARTED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
PRODUCTION_DIFF=ZERO
FORMAL_TEST_DIFF=ZERO
```
