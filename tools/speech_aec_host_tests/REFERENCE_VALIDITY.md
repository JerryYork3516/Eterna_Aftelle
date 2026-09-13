# Test 3：参考失效边界回归

2026-09-13；比较基线为 `904613c1`。本项局部修复通过下列回归，Test 3 总验收仍未通过。

## 修复边界

- 非单调 capture 时间不能提供当前帧的锁定参考；缺失证据仍使用原有退休流程。
- 已锁定路径可凭原有高置信 raw/render 相关性继续保持，不要求双讲后的 clean/linear 仍像纯回声。
- 当前参考不匹配时，在既有有界播放历史内检查 raw、clean、linear 是否都能由另一播放参考解释。
  此检查仅否决不可靠的近端判断，不直接建立、切换或延长另一参考的身份。
- 已建立回声基线后，不能仅凭不相关历史片段授予近端身份。低于既有 clean 活动门槛的线性迹象
  保留为待确认音频，不单独参与三帧近端确认。

沿用全部声学常量及三帧确认、五帧退休、十五帧缓存、二十帧关门预算。
未修改 WebRTC、语义 VAD、Runtime authority、身份隔离、Provider 或 DR/Store。

## 验证结果

| 验证层 | 结果与限制 |
|---|---|
| 当前 App Debug | Xcode BuildProject PASS；没有运行 App 或打开音频设备 |
| Host 原有回归 | 1410 checks PASS；self-replay、Host 契约和所有权检查 PASS |
| 独立时间/路径对照 | 11/11 PASS；修复前 4 PASS / 7 FAIL |
| 转换时间 | 24/24 PASS |
| Runtime | confirmed interruption 62、double-talk 163 checks PASS |
| 真实 WebRTC 合成 | 7/7 既有判据 PASS；三个完整结束段缺失/重复/超时关门均0 |
| 原连续双讲完整性 | 正常/较大缺失从 3/13 帧变为 3/3；最初三个尾音源帧仍未通过，未删除标签 |
| 8份录音 Replay | 仍3 PASS / 5 FAIL；不是全通过；逐帧比较无新增开门帧、非零输出源帧 |
| 录音正对照 | 四组非零输出源帧集合与基线相同；该事实不证明完整语音已通过 |
| secret guard | PASS |
| architecture guard | 脚本 FAIL：原有 Test3LocalAudioRunner 的 ProviderRouter 命中；该文件与基线逐字节相同 |
| SwiftFormat / SwiftLint | NOT_RUN：工具未安装；未声称格式和 lint 门禁通过 |
| 完整 A7 / 真实声场 / Qwen | NOT_RUN；未进入04，无在线调用 |

架构扫描命中位置是本地测试的 LocalProvider + NoCredentials 装配，经 ExecutionEngine、RuntimeCore、
OrchestrationKernel 和 AppController 运行；本轮没有改该入口或放宽扫描规则。当前 Host 所有权检查通过。
阶段越界人工检查 PASS：无 Runtime API / DR schema / 平台 target / Stage 8 改动。

较早较大音量纯回声的误门从306帧降到285帧，非零放行从314降到293；其余七份录音的上述主要计数
与基线相同。Replay 使用既有 AEC 输出，不重新模拟房间、WebRTC 或 Runtime 播放清除反馈。
FakeAEC 对照通过也不代表真实设备矩阵通过。

首个较宽候选虽通过11组对照和7组合成，却让最近正常纯回声误门从2帧增到39帧，已拒绝。
最终版本只用既有高置信 raw 证据保持路径，并要求 clean 活动才能给予低相关性近端确认；联合回归无上述退化。

## 复跑

```sh
bash tools/speech_aec_host_tests/check.sh
bash tools/speech_aec_host_tests/check-timeline.sh
bash tools/realtime_confirmed_interruption_tests/check.sh
bash tools/realtime_double_talk_acoustic_tests/check.sh
bash tools/test3_local_audio/silent_doubletalk/run.sh
# 使用本地已有录音包；不把用户音频加入仓库：
bash tools/test3_local_audio/replay.sh <existing-evidence-directory> ...
```

本机详细证据位于 `.build/test3-reference-validity/`。首个拒绝候选源码与日志亦保留在该目录。
剩余纯回声误门、原连续双讲三个源帧缺口和真实声场矩阵仍需后续收口，不能由本次局部改进推出 Test 3 PASS。

## 后续：历史参考的自适应资格（2026-09-13）

本轮基线 `818ce54d`。新增两个成对用例使用完全相同的变幅纯回声，唯一差异是移除一段 render 时间戳。
基线在完整参考下通过，参考缺口下错误开门并放行36个非零帧；其余11组对照不变。

已确认缺口：历史搜索结果可以在 raw 相关性不足时参与自适应能量比较，将相对旧参考的能量增长当成双讲。
首个全面拒绝历史自适应的候选使正对照少放行5/14帧，已拒绝。临时测试副本确认这些近端帧仍有
0.394/0.543的 raw 相关性，而一组纯回声误门三帧分别为0.174/0.323/0.331。
最终只要求 historicalDiscovery 具备既有 minimumTimingCorrelation（0.35）级别的 raw 支持；
没有改常量、增加确认帧数、放宽关闭预算或按设备名称放行。

- Host1410 checks、13/13时间/路径对照、self-replay和Host guards通过。
- 7组合成既有判据通过；三个完整结束段无缺失/重复/关门超时；旧连续双讲仍各缺3帧。
- 8份录音从3 PASS / 5 FAIL变为5 PASS / 3 FAIL；最近正常/较大纯回声误门2/118均归零。
- 较早较大纯回声仍285误门帧，两份较早正对照的纯回声前段仍22/104误门帧；这三份仍FAIL。
- 所有用例无新增开门或非零输出源帧，四份正对照非零输出源帧集合完全不变；88个录音输入文件SHA未变。
- Runtime中断62、双讲163 checks和当前App Debug编译通过。未调用Qwen、访问音频设备或运行完整A7。
- 本轮没有重跑未改动的转换器时间测试、仓库级architecture/secret脚本；SwiftFormat/SwiftLint仍未安装。
  上一节记录的架构扫描命中没有作为本轮PASS，也未修改扫描规则。

证据 `.build/test3-adaptive-reference/` 保留基线、拒绝候选、最终候选及逐帧差分。
Test 3总验收仍FAIL / REVIEW_REQUIRED，不进入04。剩余旧录音误门与真实声场验收仍需继续处理。
