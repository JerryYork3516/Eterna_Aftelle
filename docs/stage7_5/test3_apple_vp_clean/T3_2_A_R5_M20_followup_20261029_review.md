# T3.2-A / R5-M20 — 2026-10-29 续作审核

本次按用户“明天8:00继续，修复后重新执行三轮”的新授权续作。本次离线修复完成并先行推送后，使用全新批次正常执行3轮；全部技术门禁通过。冻结检测器结果为2轮 ECHO_DETECTED、1轮 ECHO_NOT_DETECTED。缺少逐轮独立物理发声见证，仍不代表声学验收通过。

## 1. Git、候选和范围

- 起始 HEAD = upstream = 实时远端：`6cddef00910fdaddd22135ebfff169f980614cc2`。
- 修改前本地回滚提交：`5f11c1882cf8e4351c2e44abcd15b2f4dedb9d4f`；只使用登记的隔离工作区。
- 原工作区7个冲突、原索引和14项未跟踪证据保留。旧 D43CA586 与 1D11273F 批次及其消耗标记不复用、不修改。
- 新 Debug launcher SHA256：`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`（未变）。
- 新 Debug dylib SHA256：`4de26c8850e670dd6be73b03ce60b29c8404b2791d154276087d34295d32433e`（本次必要 DEBUG 修改后真实重建）；仅更新 M20 身份登记。
- 居民素材 SHA256：`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`。
- `m20_echo.py` SHA256：`f9363dd62100563fe80c5693b4889dea65e60f7c99c2a36715feb8f4c46b49ae`，检测器与阈值未改。

本次代码文件：`AppController.swift`、`MacSpeechAudioCapture.swift`、`MacSpeechAudioHost.swift`、`RealtimeInterruptionEvidenceTests.swift`、`WarmupWindowStatsTests.swift`、`m20_batch.py`、`test_m20.py`、`integration.py`。没有音频素材、设备标识、私人 Manifest 或日志提交。

## 2. 已证实的故障与最小修复

**CONFIRMED_ENGINEERING_DEFECT — 最终 FIFO 收尾。** 旧控制器正常封存前没有末次 drain；普通 `MacSpeechAudioFrameBuffer.end(generation:)` 会清空 FIFO。因此不能先调用普通 Stop 再凭 queued=0 宣称完整。上一轮949包生成、944包 drain、5包 queued 与此机制相容；该历史事实不等于实际 Native 丢帧。

M20 正常完成路径新增 `finishMacAECBatchCapture` → `MacSpeechAudioHost.finishDebugCapture` → `stopAndSealNativeVoiceDebug`：沿原生命周期锁和 capture-processing 边界停止生产资格、封存 Native、移除原 Tap，随后有界 drain 已生成包，验证生成量不变、实际队列包数等于返回包数且队列归零，才调用原 `end`。返回真实包继续经过原 generation/sequence/content-time/score-window/720KB 检查，不补零、不存预热 PCM。增加 `mac_aec_final_drain` 回执，并要求 generated=drained、generation 相同；不删除 queued==0 门禁。普通 Stop、历史 C、Converter reset/EOF 未修改。

**CONFIRMED_ENGINEERING_DEFECT — DEBUG 观察排他区过长。** `MacSpeechNativeVoiceTiming.render/scheduled` 原先在共享 try-acquire 标志内逐样本扫描非零区间。确定性交错 Fixture 证明扫描期间到来的合法 Input 元数据会被记为 skipped，制造观察缺口。将现有扫描移到该标志之外，仅让有界元数据更新占用标志；PCM 值不变，没有新 Engine/Tap/观察系统。真正竞争、stale、invalid 和时钟缺口仍记录并拒绝技术资格。历史 skipped=6 是否全部由这一路造成仍为 HYPOTHESIS，不能把观察遗漏称为真实音频丢帧。

M20 审核器同时要求 final-drain 回执、包守恒、Input/Render 观察与时钟计数完整。观察异常会停止余下轮次，不能被 `ECHO_NOT_DETECTED` 掩盖。

## 3. 离线 RED / GREEN 与检查

| 命令/检查 | 实际结果 |
| --- | --- |
| `M20_RESIDENT_WAV=<登记素材> bash tools/realtime_interruption_evidence_tests/check.sh m20-only`，旧实现+5包尾部 RED | exit 133，评分保留量断言失败；没有设备运行 |
| `bash tools/speech_aec_host_tests/check.sh d1-stats-only`，扫描交错 RED | exit 133，Input 观察丢失断言失败 |
| 首次末次-drain GREEN 编译 | exit 1，Optional generation 未解包；已用显式 RunID/generation 绑定修正，未给默认值 |
| 最终 `m20-only` | exit 0，396 checks；覆盖0/5包尾部、实际回执、720KB合成字节一致及历史 C 的原 queued-tail 行为 |
| 最终 `d1-stats-only` | exit 0；profile 19 cases/51 checks，Native 16/77，warmup 26/92；含扫描交错和真正观察竞争负控 |
| `check.sh m19-only`（现有导出回归） | exit 0，device_access=ZERO |
| Python：`test_m20_identity,test_m20,test_m20_fixture,test_m20_control,test_m07,test_failure_evidence,test_original_ui,test_integration` | 最终97 tests，0 failure，0 error，exit 0；全部 Fake，无 App/设备启动 |
| Debug / Release `xcodebuild ... -scheme Aftelle -configuration Debug或Release -destination platform=macOS -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build` | 各1次，均 exit 0；独立 DerivedData，不覆盖旧候选 |
| Release `nm`/`strings` | 新停止/drain接口、DEBUG timing类型和回执键均不存在 |
| `tools/realtime_release_route_guard/check.sh`、`tools/architecture_guard/check.sh`、`tools/secret_guard/check.sh` | 三项 exit 0 / PASS |
| SwiftFormat 0.63.1 / SwiftLint 0.65.1 增量检查 | 22处修改范围通过；只在隔离目录使用固定版本，未改全局或项目依赖。Format 使用 `--disable wrapMultilineStatementBraces --commas inline` 与现行 Lint 同行花括号/无尾逗号规则一致；历史 Lint 105项保留，新增0 |
| Python AST、`git diff --check`、文件白名单及文档隐私检查 | PASS |

实际执行次数：`m20-only`共4次（RED非零退出1、Optional解包编译失败1、修正后通过1、补齐回执断言/历史尾包并冻结后通过1）；`d1-stats-only`共3次（RED1、GREEN1、测试放入既有warmup文件以避免新增长度债务后复核1，断言未降低）；Python相关回归2轮（各97通过，后轮对应新SHA登记）；M19导出回归1次；Debug/Release构建各1次；三项Guard各1次。没有无关大型回归。

Python 旧 profile 的测试身份仅在 Fake 进程内绑定当前 Fixture；正式 M20 入口仍验证真实 PID、路径、映射 dylib 和完整 SHA。未删除任何真实身份检查。离线验收阶段未执行 FULL_CURRENT、ASR、设备测试或历史音频读取；随后授权设备运行见第5节。

## 4. 并发、安全与剩余边界

新增停止/drain 仅在 DEBUG 非实时控制路径使用，原音频 callback 的处理算法不变。停止资格与 Native seal 共用既有 capture-processing 排他边界；末次真实包 drain 在 FIFO end 之前。扫描本来已有、仍有界，移出观察临界区不改变音频；后续真正观察竞争仍可能发生，出现即停止，不能承诺任意负载下零缺口。

保持 AEC/AGC/NS、AudioGraph、采样率、channelMap、Converter、时钟容差、RuntimeCore、Provider、正式 Gate 和 M18-E01 原状。Native 已经经过 Apple VP，不是 ADC Raw。尾部跨边界包与 Converter partial tail 仍不能靠补零宣称完整。没有物理扬声器独立见证时，低相关性也只能是 ECHO_NOT_DETECTED / UNVERIFIED。

Stage7 Forbidden Checklist：PASS。五维 SELF_REVIEW：范围=PASS；因果证据=仅确认工程缺陷；生命周期/并发=定点验证PASS、三轮实机技术门禁通过；隐私/Git=PASS；声学真实性=UNVERIFIED。新增 CRITICAL=0、MAJOR=0、规范 B 类=0；现有声学/时钟根因及 M18-E01 不因此关闭。

## 5. 新批次实际执行结果

- 修复提交/本次实际源码：`5077e5b22a653dd426278efed92d2ae79c1fb301`。修复推送后 HEAD=upstream=实时远端一致，之后才建立并启动新计划。
- 新批次：`9EDBABEA-69F1-4DB9-BDEF-58C70BE07CC7`；旧计划/目录/授权标记未复用。正式入口：`python3 -B tools/reference_host_comparison/m20_batch.py --plan <本批私有plan.json> --evidence <本批私有目录> --authorize-batch '授权开始M20单批3轮AEC测试'`。
- 本次新授权来源为用户预定续作，不是旧 R4 或旧 M20 回执。每轮保留原 App 可见确认、录音/导出和精确 PID 退出；没有操作新的系统权限弹窗。
- TinyUSB USB输入60%、Mac mini内置扬声器55%且未静音；逐轮前后只读核验设备空闲和身份，未改音量、路由或 Mic Mode。不运行真人C、REF或蓝牙代理。
- 实际 Capture=3、居民Playback=3、JSON Export=3、WAV Export=3；各为独立 App/PID/RunID，原计划各19秒（4秒预热+15秒评分）。没有重试/第4轮。正式执行器 exit 0，`BATCH_COMPLETE`=3。

| 轮次 / RunID | 固定检测器结果 | 匹配 abs(NCC) | 反向/安静负控 abs(NCC) | 非零Render，WAV相对秒 | 固定Render窗 PCM RMS dBFS |
| --- | --- | --- | --- | --- | --- |
| 1 / `61234E2F-14AA-4EA0-803D-ECFDEF759EB0` | ECHO_DETECTED | 0.405821 | 0.076219 / 0.030008 | 4.182068–7.929729 | -17.773 |
| 2 / `81FD7188-FEAC-4D32-973C-BA18BE1C0036` | ECHO_DETECTED | 0.357538 | 0.087200 / 0.027333 | 4.214068–7.961731 | -18.277 |
| 3 / `8808794A-E3F8-4036-A861-D84B35581351` | ECHO_NOT_DETECTED | 0.041440 | 0.078065 / 0.034964 | 4.182086–7.929753 | -65.145 |

NCC原始最佳值三轮均为负，上表遵循冻结检测器取绝对值，不修改评分。模板与Render搜索、负控和判定阈值全部保持 `M20_v0.1`；前三个相关值不能解释为ERLE或用户听感。第3轮反向负控高于源模板，但均低于固定未检出限，按原规则返回 ECHO_NOT_DETECTED，不改判据。

### 5.1 包守恒、覆盖和瞬时幅度

| 轮次 | Native覆盖秒 | generated=drained | 最后drain前→实际drain→Seal queued | WAV秒 / 实际PCM字节 | 同窗配对行 | Native满幅/声道；PCM端点 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 19.0 | 949=949 | 5→5→0 | 14.96 / 718080 | 748，全部MATCHED | 0；4 |
| 2 | 19.0 | 949=949 | 5→5→0 | 14.96 / 718080 | 748，全部MATCHED | 14；17 |
| 3 | 18.9 | 944=944 | 0→0→0 | 14.86 / 713280 | 743，全部MATCHED | 0；0 |

第1/2轮真实取得各5包末次drain回执，生成949包全部被消费；第3轮944包已全部消费，末次队列本来为0。不是通过清空FIFO制造queued=0。评分PCM均低于720000 bytes，无预热PCM留存；三轮尾部仍为PARTIAL，不补造15秒覆盖。第2轮记录14个Native满幅样本/声道及17个PCM精确端点，属于稀疏满幅观测，未触发冻结的持续满幅停止门禁，不能写成“零满幅/端点”，端点计数本身也不等同于已证实的听觉失真。三轮Native non-finite/over-scale均为0。

所有 Input/Render missingTime、duplicate、backwards、sample/host discontinuity=0；skipped/invalid/stale observation=0，Native各项拒收=0，capture drop/stale=0，raw_timestamp_diagnostic为空。历史时钟异常本批NOT_REPRODUCED，不表示已修复。Engine配置事件及skippedNotifications均为0，监听最终关闭。三个App均正常退出，进程与设备释放核验通过。

### 5.2 Native/PCM同内容窗口

使用现有M19已配对的完整20ms行，仅汇总WAV内容相对4.00–7.74秒（187行）；不切包、不插值，Native每行320样本、PCM每行480样本。Native为VP后ch0，不是Raw。按各行实际样本数汇总能量：

| 轮次 | Native RMS dBFS | WAV PCM RMS dBFS | PCM−Native dB | Native / PCM Peak |
| --- | --- | --- | --- | --- |
| 1 | -16.9047 | -16.9050 | -0.0003 | 0.99999326 / 1.00000000 |
| 2 | -17.4622 | -17.4633 | -0.0011 | 1.00000000 / 1.00000000 |
| 3 | -78.9494 | -78.9470 | +0.0024 | 0.00224173 / 0.00222778 |

每轮该区间为Native59840、PCM89760个真实样本。前两轮约−17dBFS的高能量与第3轮约−79dBFS的低能量在VP后Native已存在；最终PCM没有额外的大幅整体增益变化。这个结论只定位已保存区间的层级，不证明Apple内部AEC/AGC机制，也不代表真人语音保留。

### 5.3 实际运行态读回

每轮 EngineStarted / ResidentPlaybackStarted 两点均：VP Input/Output=true、AGC=true、bypass=false、inputMuted=false、engineRunning=true。两点及跨三轮公开client/hardware格式结构一致；进程方向设备集合一致。输入资格均为 `PROCESS_SHARED_IO_DEVICE_SET_METADATA_QUALIFIED`，输出为 `PROCESS_DEVICE_METADATA_MATCHES_DEFAULT`，不能据此确认Apple内部参考端点。

| 轮次 | 两次运行态HAL读回耗时，ms | Mic Mode active / preferred |
| --- | --- | --- |
| 1 | 4.287 / 3.060 | 0 / 0，两点一致 |
| 2 | 3.501 / 3.003 | 0 / 0，两点一致 |
| 3 | 3.699 / 2.953 | 0 / 0，两点一致 |

Mic Mode是 `AVCaptureDevice` 当前应用路由公开API读回（status=CONFIRMED_PUBLIC_API），0对应Standard；不替代物理端点/硬件DSP/Apple AEC状态证据。没有用preferred代替active。运行态属性相同仍不代表内部适应状态相同。

### 5.4 结论、等级与唯一下一步

- **CONFIRMED**：同一构建、素材、固定评分及已观测设备/VP配置下，冻结检测器在一次独立三轮批次产生2次检出、1次未检出；差异在VP后Native已出现。末次drain和DEBUG观察问题已在本批技术门禁下通过，不能把它们当作AEC根因。
- **HYPOTHESIS**：跨App生命周期的VP处理/适应状态变化可与结果相容；没有直接内部状态证据，不能确认为Apple算法或Aftelle集成BUG。
- **UNKNOWN**：每轮真实物理扬声器发声及声压、AEC内部参考、硬件/系统其他处理状态、主观听感。本批无人现场见证；软件Render、完成回执与设备在线不等于独立物理发声证明。第3轮 `physical_emission=UNVERIFIED`、`aec_acceptance=UNVERIFIED`，不得宣称AEC PASS或已确证AEC跨运行失效。
- **唯一建议**：停止加诊断/调参数；由主控另行决定是否授权一次有逐轮现场物理发声见证的同配置A组批次，优先区分“未检出源于抑制”与“实际声源覆盖不足”。本次不自动执行下一批。

五维最终 SELF_REVIEW：范围/最小性PASS；工程因果/RED-GREEN PASS；三轮控制与资源释放PASS；隐私/Git保护PASS；声学真实性UNVERIFIED。新增代码CRITICAL=0、MAJOR=0、规范B类=0；现有AEC/时钟UNKNOWN及T3.2-A BLOCKED保持。所有WAV、PCM、私人JSON/Manifest、设备UID和完整日志只存本机受控目录（0700/0600），没有音频上传、自动播放或ASR。

## 6. 保持状态

```ini
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=DEFERRED
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
