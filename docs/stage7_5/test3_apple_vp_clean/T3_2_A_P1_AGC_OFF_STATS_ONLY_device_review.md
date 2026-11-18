# Eterna Aftelle · T3.2-A P1 AGC-OFF＋STATS_ONLY · 设备准入审核

日期：2026-11-18（Asia/Shanghai）。本次仅执行准备与只读预检；**默认输出路线及音量不符，P1=BLOCKED，实际设备实验0次**。本报告不授予设备执行权限。

## 1. 授权、身份与范围

- 任务基线、本地 HEAD、upstream 与实时远端在准备前均为 `1f27b1d2c83edd4ac694b990eac3f37887689239`。
- 使用原 `vp-reference-host-preparation` 隔离 Worktree；本地分支 `codex/reference-host-comparison-preparation`，目标远端 `origin/Test3-AppleVP-Clean`。未切换分支或 Worktree。
- 已读 AGENTS、Stage7 Forbidden Checklist、正式 README、T3.1-R2 §8、[最新声学准入审查](T3_2_A_acoustic_qualification_readiness_review.md) §4–5、[P0](T3_2_A_acoustic_isolation_P0_research_vs_host_comparison.md) §7.1/§7.4、[AGC-OFF 实现审核](T3_2_A_acoustic_isolation_M01_agc_off_review.md) 及直接相关 DEBUG/隐私入口。
- 用户本次只授权准备，先前已免除读取范围重复确认。已报备的读取仅涉及上述合同、现有 DEBUG 控制/只读工具、冻结身份、原全零素材与必要保护元数据；未读取历史私人录音或运行统计原件。
- 新的明确设备授权**未申请、未取得、未消耗**。未启动 Aftelle、Engine、Capture、Player、Provider，未申请麦克风权限。
- 跨文件文档修改前建立空回滚点 `89bd74497c70773c562f562559617a8f8088ca40`，与基线树相同；只新增本报告并更新 README 索引。最终提交 SHA 由 Git 提交及推送交付收据绑定，不在报告内自引用。

## 2. 源码、冻结构建与历史工程收据

| 项目 | 本次核验结果 |
|---|---|
| 当前 App 源码树 | `446e2ef9e63d60dd14bf5fd6d70079e6f18c0539`，与已接受工程候选相同 |
| 当前 tools 树 | `a687af8d5095a2c1230e9f08a57cc51212243677`，未修改 |
| Capture 源文件 SHA-256 | `f8cf47b0de2205e7e70177db6c16ceb0a615730892d4ae605e6fdee9cc45d49c`，匹配已登记身份 |
| Debug launcher SHA-256 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`，磁盘文件存在且匹配 |
| Debug dylib SHA-256 | `de8d24e6c8633da395bf29339d8e1b4887acc22c71aa95acd396a18285195df4`，磁盘文件存在且匹配 |
| 既有构建路径 | `.build/t3_2_a_validation/full_current-vu90au84/DerivedData/Build/Products/Debug/Aftelle.app` |
| 已接受 FULL_CURRENT 收据 | SHA-256 `d39f1141f26590c1df8ec56848a6aed179dbb6bf5cb8cb6de541ad30ca11ff2f`；21项 PASS/exit0，测试源码为 `42551c1b66ed31d858fcc842b65a3dc4fa574964`，App 源码树与当前一致 |
| 当前实际加载 PID/dylib | **NOT_RUN**；磁盘 SHA 不冒充运行态加载证明 |
| 本轮构建/产品回归/TSan | **NOT_RUN**；仅核验已接受历史收据及当前文件身份，未冒称重新执行 |
| M31 撤回 | 保持 `COMPLETED_OFFLINE_VERIFIED`；源码身份未变化，未恢复内容指纹、Row 或相关诊断 |
| 固定 DR Fixture | 仅核对前次已验身份的 size/mode/inode/device/mtime/ctime 元数据，完全相同；本轮未读取 DR 内容 |
| 可用磁盘空间 | 只读核验约11.1GB；本轮无构建、音频文件写入或清理 |

上述历史 FULL_CURRENT 结果仅保留离线工程接受范围，不构成 P1 运行态、声学或正式 Test3 验收。

## 3. 原全零素材：身份核验通过

在原登记的 P2 预检资产目录找到原文件 `p2_zero_24k_mono_pcm16le_114032.wav`，未创建替代文件、未复制或改写原件。

| 字段 | 实测 |
|---|---|
| SHA-256 | `a7169f4bb25dc688e739888880d85640c9f5a0170df46bcc43ccd9c1823f96eb`，完全匹配 |
| 文件字节 | 228108 |
| 编码 | WAV / PCM16LE，未压缩 |
| 采样率/声道 | 24000Hz / Mono |
| 帧数/样本数据字节 | 114032 / 228064 |
| 全零检查 | 全部样本字节为0 |
| 文件资格 | 原件为普通文件，非符号链接；未播放、裁剪、增益处理或转写 |

原全零资产的读取只用于本次授权的素材准入；没有读取其他 WAV/PCM。

## 4. 只读设备预检与停止原因

设备读回时间为 `2026-11-18T12:42:53Z`（北京时间20:42:53）。复用既有 `readonly_default_io`：只查询默认输入/输出、设备属性、方向、在线/占用与音量；未枚举其他进程音频对象，未启动设备。

该工具原编译记录 exit0；当前源码 SHA `65896bb4b3d4449861fa2e5d0f890712162a76124541d53ad500d400a7893be9` 与登记一致，当前可执行文件 SHA `f0ae5c2cfcebd0902f49e199d6d876129b7130112f43c540bcdb40d7e1ac72e6`。静态审查及导入符号只见 AudioObject Get/Has 查询，没有 setter、AudioDeviceStart、AudioUnit 初始化或 Engine/Player 入口。系统音量另以原只读 `osascript -e 'get volume settings'` 查询一次。

| 准入项 | 冻结要求 | 本次实际 | 裁定 |
|---|---|---|---|
| 默认输入 | TinyUSB USB 麦克风 | `TinyUSB DFU runtime`，USB，输入方向成立 | PASS |
| 系统输入音量 | 60% | 60% | PASS |
| 默认输出 | Mac mini 内置扬声器 | **小爱音箱**，非内置传输类型 | **BLOCKED** |
| 系统输出音量 | 55% | **50%** | **BLOCKED** |
| HAL 输出音量 scalar | 0.55 | **UNKNOWN**，当前输出未提供可确认 scalar | **不满足准入** |
| 静音 | 未静音 | 系统与 HAL 均未静音 | PASS |
| 在线/空闲 | 两设备 online、running=0 | 两设备在线且 running=0 | PASS；仅为读回时状态 |
| 冲突实验 | 无其他 Aftelle/REF/代理实验实例 | 既有进程名规则未发现匹配实例 | PASS；不证明所有其他客户端不存在 |
| 目录资格 | 0700/0600，无符号链接或 `.git` 祖先 | 原导出根目录与新准备收据通过对应检查 | PASS；尚未执行 App 导出 |
| 当前 App 麦克风权限、Mic Mode、VP/AGC | 授权运行时读取，不触发新权限 | **NOT_RUN** | 不预填 PASS |

**失败原因明确为默认输出路线及音量不符，并且 HAL scalar 无可靠读回。** 检查后立即终止设备准备；未切换到内置扬声器、未调音量、未修改 Mic Mode，也未重试查询或实验。没有 P1 RunID、Capture/Playback Generation 或配置运行快照。

## 5. 原入口合同及未执行项目

源码只读核对确认，原普通入口仍能表达：

- 唯一启动参数 `--apple-vp-acoustic-test`，processing profile `APPLE_VP_AGC_OFF`。
- `Prepare comprehensive C · STATS_ONLY`，warm-up 为 `Original C · no warm-up comparison`，即 nil；不使用 WARMUP_0S/4S、silent-smoke、Score Control 或 M20/M22/M26 批次。
- 原阶段0/3/9/11/15秒；最多一次15秒，用户不讲话，只排程一次已核验全零素材，不新增等待或采集窗口。
- 原 Start 仍需麦克风/外放可见同意；STATS_ONLY 无整段 PCM 留存，原 WAV 数据、URL 与导出入口均拒绝该模式，JSON 仍需显式同意及 sealed/安全路径资格。
- RunID/generation/configuration、实际 AGC-OFF 与 VP/bypass/mute、Native/Converter/Packet 连续性、quiet 至少1秒有效 drain、Output prepare/start/completed 各一次、Stop/Seal/Shutdown/确切 PID Quit，均须在另行授权的唯一运行中实际证明。

这些是静态合同核查，**不是本次运行结果**：

| 必需实测 | 本轮状态 |
|---|---|
| input/outputVP=true；requested/actualAGC=false；bypass/inputMuted=false | NOT_RUN |
| coverage_valid、连续20ms/960bytes已 drain 包及有效内容时间 | NOT_RUN |
| drop/stale/rejected/underrun与其他时间安全拒收 | NOT_RUN，不能填写0 |
| skippedUpdates、queued、partial tail、quiet有效覆盖 | NOT_RUN，不能把 queued 当作已 drain |
| retained_pcm_bytes=0、processed_sha256=null、WAV运行态拒绝 | NOT_RUN；仅静态边界已核查 |
| Output prepare/start/completed | 0次；未执行 |
| Stop/Seal/Shutdown/正常退出及运行后资源释放 | NOT_RUN；App从未启动 |
| 导出本次运行统计 JSON | 0份；只有本轮本机预检收据 |

P1 即使未来通过，也最多支持 `OFF_READBACK_AND_CONTROL_CHAIN_SUPPORTED`；不证明 AEC 消音、AGC 音质、真人保留或 T3.2-A 正式 PASS。

## 6. 证据、隐私与交付检查

- 只读设备预检汇总收据 SHA-256：`d13bcf5737e55668e2533ece8c709f051f2e254e7a0bf5491e6b6e4d2780e56a`。新准备收据在既有 Git 忽略目录，目录0700、文件0600；原始读回、UID摘要、路径细节仅本机保存。
- 保护基准收据 SHA-256：`8677169189c5a2ab05d5236c4e9cc854677d8a3447a668baa24818944abb04a0`。本轮只读重算原工作区 HEAD、status/unmerged/index摘要及14项未跟踪文件 size/mtime，完全一致；仍为7项冲突/14项证据。未读取这些私人文件内容，未 stash/reset/clean 或处理冲突。
- 公开范围仅本报告及 README 索引；无生产、测试、正式 Gate、DR/Runtime API 或评分器修改，无新 Engine/Tap/Owner，未执行设备实验或 Provider 调用。
- 文档白名单、链接和新增文本敏感信息检查 PASS；`git diff --check` exit0，原 `bash tools/secret_guard/check.sh` exit0（`secret-guard: ok`）。原始 JSON、音频、Fixture、设备 UID、Token、日志及构建产物不进入 Git。
- Stage7 Forbidden Checklist：**PASS**。触碰红线：无；修改文件：本报告、README；改代码/Runtime API/DR schema/平台 target：均否；进入 Stage8：否。设备预检阻塞要求本轮停止，不申请运行授权。最终三方 HEAD、完整暂存 diff 与保护状态另以本机交付收据绑定。

## 7. 裁定与唯一下一步

**P1_PREFLIGHT=BLOCKED**。阻塞发生在新设备授权及 App 启动之前；未获得运行态证据，不能裁定控制链 PASS 或 FAIL。

唯一下一步：由用户确认恢复冻结的默认输出条件（Mac mini 内置扬声器、55%、未静音），之后另行只读复检；复检全部通过后，再申请本次 P1 所要求的完整明确授权。本轮不代为调整，不继续复检或启动 P1，更不进入 P2/P3/P4。

```ini
P1_PREFLIGHT=BLOCKED
P1_USER_AUTHORIZATION=NOT_REQUESTED
P1_DEVICE_EXECUTION=NOT_AUTHORIZED
P1_DEVICE_RUNS=0
P1_AGC_OFF_READBACK=NOT_RUN
P1_VP_CONFIGURATION=NOT_RUN
P1_AUDIO_CONTINUITY=NOT_RUN
P1_STATS_ONLY_PRIVACY=NOT_RUN
P1_SHUTDOWN=NOT_RUN
P1_RESULT=BLOCKED
T3_2_A_OFFLINE_ENGINEERING=ACCEPTED
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
