> Published historical report. Source: `.build/test3-apple-status-20261002/report.md`.
> Local home/device identifiers are redacted; relative artifact links are rendered as text.
> Read [README](README.md) for chronology and corrections. Referenced PCM, traces and binaries remain local and are not part of this publication.
> Statements such as "no commit/push" describe the original experiment, not this later publication.

# Test3/03 · Apple AEC 路径当前裁定

2026-10-02，仓库 `<LOCAL_WORKSPACE>`，分支 `7.5.11`，HEAD `01728b34c539c71cceeb63cd0721269580b2fad9`。保持 **Apple Voice Processing AEC**，目标设备 Timesintelli USB 麦克风＋Mac 内置扬声器；没有切换到其他 AEC 方法、28U1 或手动暂停。原有未提交修改、私人音频与测试资产均保留；无 reset、clean、commit、push。本轮没有外放或录音。

## 逐层结果

| 层／路由 | 状态 | 证据与边界 |
| --- | --- | --- |
| 旧同 binary、同目标路由纯回声实体轮 | **已验证本轮 Gate 0** | 约 10.5 秒居民完整外放，1,050 播放帧；仅一轮，不是长期零误报认证。见 `../test3-native-negative-20261001/trial-40e1aa79ab1c44fb9cec8622c760df3c/assessment.md`。 |
| 同 binary 真人长句＋约 510 ms 短句实体轮 | **失败** | 长句两段及短句 Host Gate 均 0。短句 51 帧 HAL true 0、音量合格 14、分离合格 1 且该帧音量不合格。见 `../test3-native-positive-20261001/trial-bb65665cda534210a3398bcbcb625dbc/assessment.md`。 |
| 当前 Apple 采集转换／Host 复放 | **已验证输出一致** | 原生 16 kHz 三通道按实体 108 回调复算后，以内容时间对齐的 1,079 个 Host 帧在正负两轨逐样本差 0；播放边界各主动丢弃 432 样本。当前 Host 同 PCM/到达顺序/HAL 复放各 1,079 帧判决 0 mismatch。只证明现存输入的处理链，不重建 Apple VPIO 或 HAL 硬件。见 `../test3-apple-native-converter-replay-20261002/report.md`、`../test3-apple-causal-replay-20261002/report.md`。 |
| Apple VPIO 配置／处理效果 | **运行已验证，效果未验证** | 输入/输出 Voice Processing enabled、UID、格式和回调均正常；Apple 原生三个声道在每轮内整份 PCM 相同，没有可替换的特殊声道。负控 40 个居民窗与真人轮内 6 个纯回声窗的 Apple/同麦旁录能量比中位分别 −6.60/−47.93 dB；抑制显著而不稳定，原因不能唯一归给 AEC／AGC／声学几何。旧 trace 未记录 bypass/AGC。见 `../test3-apple-acoustic-effect-20261002/report.md`。Apple 官方没有给该跨设备组合的效果保证，也没有说输入输出必须同一物理设备。 |
| Debug 处理耗时 | **离线性能问题已定位；闸门未修复** | 同实体 PCM/回调分批，Host `-Onone`→`-O` 中位约 60→5.5 ms，逐帧判决与 PCM 不变；100 ms 实体 tap 分批仍待 VPIO 实测。新完整 `-O -DDEBUG` App 已构建。见 `../test3-apple-callback-perf-20261002/report.md`、`../test3-apple-optimized-debug-20261002/report.md`。 |
| 当前目标实体路由 | **未满足** | 最新只读 preflight 的默认输入／输出是蓝牙 UID `<HISTORICAL_BLUETOOTH_UID>`；没有自动切换设备或启动采集。旧实体轨仍确认为 Timesintelli＋内置扬声器。 |
| 新 `-O -DDEBUG` App 的实体声学／正式 Runtime 中断 | **未验证／未接入** | 当前源码仅增加 Debug trace 中的 VPIO enabled、bypass、AGC 两时点快照，已全量编译与无声测试；新构建未播放、未录音，不能宣称短句 PASS。见 `../test3-apple-vpio-state-build-20261002/report.md`。 |

## 结论与唯一下一步

**Test3/03 仍 `BLOCKED`。** 旧实体正控明确失败，当前的构建、复放和优化没有使声源归属 Decision 通过。尤其 HAL=false 和短句相关性否决是两项独立阻断；不能用候选活动、纯回声一次 Gate 0、优化 CPU 或 Apple VPIO enabled 替代正式验收。没有接 Provider cancel、generation 切换或 playback clear。

**唯一下一步：先在已有 Apple 正负控 PCM 上提出一个事前固定的声源资格修法，并用因果复放证明整段纯回声 0 个 source-only 错误确认、长句不退化、短句在原活动区间内覆盖且实际决策时延合格；任一失败即停止该修法。** 当前审过的 D2、水印、AudioSeal、通用 VAD、旧整帧／固定 lag 和 250 ms shadow 均不能重包装为候选，也不为了 PASS 调阈值。若始终没有可预登记的修法，就明确保持 BLOCKED；不让用户为摸索重复录音。

只有上述离线门槛通过，再恢复 Timesintelli＋内置扬声器路由，用已封存源码／binary 身份的 App 做一次关键实体复验，读取新增 VPIO bypass/AGC 见证并核对真实回调时延。当前无需用户操作。

Stage 7 禁止项检查：**PASS**。本轮唯一产品文件变动是 macOS Host 的 Debug 观测字段；无脑／身体交叉内部依赖、Runtime API、DR schema、平台 target 或 Stage 8 扩展。正式 Runtime 决策边界保持关闭。
