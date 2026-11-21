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
