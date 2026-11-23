# Eterna Aftelle · Stage 7.5.11 · Step 1 历史 Native 起音对比

2026-11-23（Asia/Shanghai）。指定五份原始技术 JSON 的 RunID 和 SHA-256 均与先前登记匹配。**P4 确认有约 1.42 秒的 Native 精确全零前缀，之后迅速出现满幅。其余四轮缺少可定位的 Native 短窗，跨运行起音模式、AGC 起音适应和 VP 启动瞬态的因果归属均为 UNKNOWN。**

## 1. 文件身份与比较范围

分析合同使用冻结源码 `574fc735ca239c9b334029debbdee546cda18d49`。审查起点 `8e55d69a5626d22a1907a46ec4c54745e10eeaa2` 的 HEAD、upstream 与 GitHub 实时远端一致，`apps` 树与冻结基线一致。P2 ON/OFF 的正式审核登记较早的同一 App 树 `446e2ef9e63d60dd14bf5fd6d70079e6f18c0539` 与同一 Debug 候选。P3 两轮和 P4 采用报告登记的 Fail-Fast 冻结候选。原 JSON 的 `source_commit` 与 `build_identity` 均为 null，历史构建身份取自各自审核记录。

| Run | JSON bytes | SHA-256 | 先前登记 |
|---|---:|---|---|
| P2 ON · `0CB32C68-8D62-4612-B503-532F7933D257` | 64787 | `e8bf92d5ecd38f224227205d134367cc29c9f6b07c2dca959018d37ab94b8e1f` | [P2 §7.3](T3_2_A_P2_Human_Only_AGC_ON_OFF_device_review.md#73-导出与用户试听) |
| P2 OFF · `60D8A066-0A21-48F4-A401-FC9616480203` | 64798 | `dc11cbd3a63766930efcb7dca9084bb3bfe4aae9899b9a322b56efebda0d9395` | [P2 §8.3](T3_2_A_P2_Human_Only_AGC_ON_OFF_device_review.md#83-本机导出及用户独立试听) |
| P3 CLOCK 复验 · `82D1CEC7-056F-450A-9C8A-89D8DBA783C5` | 80082 | `746afe2e8e0330c8abceee781e71365d6ae46afeaf710758f285c80900a5f126` | [R3-M01 复核 §1](T3_2_A_R3_M01_real_audio_reanalysis_review.md) |
| P3 单次通过 · `EB6534D7-671D-4118-B8D0-391B76382DA1` | 80092 | `6fd833e007953103c5ce0a98c97a3209dd40d094147768303b99ad8a45b336bc` | [P3 §12.1](T3_2_A_P3_resident_only_acoustic_device_review.md#121-同-run-技术回执用户试听及主控裁定)及同 Run 本机审核收据 |
| P4 · `5EDAAFA9-F8E3-4171-BF1B-9EF135668BA6` | 1050955 | `86eef787fb5693e430bc16f0c1ffc534bd2216ef3a6dcb4496ce4f1851d7a794` | [P4 §4](T3_2_A_P4_real_double_talk_device_review.md#4-本机证据及-git-交付) |

P3 单次通过的 Git 归档登记 RunID 和技术结果，JSON 摘要取自当次生成的 `local-review-facts.json` 的 `run_id`、`json_bytes`、`json_sha256`。该收据 SHA-256 为 `7cb60de5c02e48abcaaa9bc58f810795acd084d29a2e23b1fbb039fdc8a4f204`。原件长度、身份和摘要与其一致。

任务清单中 “历史 CLOCK 异常” 所指的 `82D1CEC7…` 实际为原故障的复验。该 JSON 和正式报告均记录 `native_clock=0`、`content_time=0`、无首次异常诊断，Fail-Fast 未触发。本轮按指定 ID 归为 **CLOCK 复验，故障未复现**。 [P3 §10.2](T3_2_A_P3_resident_only_acoustic_device_review.md#102-clock封存及覆盖)

## 2. 历史对比

以下所有时间以各自 `host_timing.input.firstContentHostNs` 为 0。五轮首个已保存包的内容时间均与该起点相同。Render 为 Player Tap 的软件内容时间，Capture Stop 为停止控制标记。实际发声及物理重叠由现场证据决定。

| Run／场景 | AGC 请求／实际 | Native 起始精确零长度 | Native 满幅数 ch0／ch1／ch2 | 满幅位置 | Native 全程峰值 ch0 | 非零 Render 区间与 Native RMS |
|---|---|---|---|---|---:|---|
| P2 ON／B 真人独讲 | ON／ON | UNKNOWN | 32／32／32 | UNKNOWN | 0.00 dBFS | 无非零 Render。时序 RMS UNKNOWN |
| P2 OFF／B 真人独讲 | OFF／OFF | UNKNOWN | 2587／2587／2587 | UNKNOWN | 0.00 dBFS | 无非零 Render。时序 RMS UNKNOWN |
| P3 CLOCK 复验／A 居民独讲 | ON／ON | UNKNOWN | 0／0／0 | 无满幅 | −15.04 dBFS | 1.258–5.006 s。前、中、后 RMS UNKNOWN |
| P3 单次通过／A 居民独讲 | ON／ON | UNKNOWN | 0／0／0 | 无满幅 | −46.44 dBFS | 1.226–4.974 s。前、中、后 RMS UNKNOWN |
| P4／综合 C 双讲尝试 | ON／ON | 1420.000–1431.6875 ms，ch0 | 21／21／21 | ch0 的 21 个样本均在 1.480–1.520 s 的两个 20 ms 窗内 | 0.00 dBFS | 4.266–8.014 s。前、中、后分别为 −17.36、−24.02、−23.54 dBFS |

五轮 Native 均为 16 kHz／3ch／Float32 非交错。各声道全程 `full_scale` 只按声道登记，样本的时序相同与否未验证。所有 Run 的 `over_scale` 与 `non_finite` 均为 0。P2／P3 的 `short_window_diagnostics.status=UNKNOWN_MISSING_STREAM`，`windows` 为空，`native.acoustic_windows=null`。普通 A/B 的导出没有综合 C 在评分入口初始化的配对 PCM 短窗，因此无法从这四份 JSON 复原 Native 起始零长度、非零满幅的时间位置或分段 RMS。Native 峰值和满幅计数取自全程汇总。 [评分短窗初始化](../../../apps/macos/Aftelle/AppController.swift#L8275) · [配对导出](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L1153)

| Run | Capture／Playback／Configuration | Input／Render 回调 | 生成／保存／队列包 | Capture Stop（s） | 末次配置控制标记晚于 Stop（µs） |
|---|---|---|---|---:|---:|
| P2 ON | 1／N/A／2 | 150／149 | 749／744／5 | 15.028711 | 66.667 |
| P2 OFF | 1／N/A／2 | 150／149 | 749／744／5 | 15.027805 | 81.458 |
| P3 CLOCK 复验 | 1／1／2 | 150／149 | 749／744／5 | 15.026085 | 94.833 |
| P3 单次通过 | 1／1／2 | 149／149 | 744／744／0 | 15.013364 | 221.083 |
| P4 | 1／1／2 | 150／149 | 749／744／5 | 15.035618 | 81.833 |

- **VP 与路线。** 双端 VP 均开启，bypass 与 inputMuted 均为 false。可用 Engine 启动、Play 后读回的公开 Mic Mode 原值均为 0／0。五份 JSON 的 Host 默认设备标识在本机比较一致，报告登记为 TinyUSB 默认输入和 Mac mini 内置默认输出。Process 输入范围都包含两个默认设备，输出只包含默认输出。AU `deviceID` 单独绑定保留 `UNKNOWN_UNVERIFIED_BINDING`。各轮可用快照中的路线一致。
- **CLOCK 与代际。** Native 全部拒收、Input/Render 主机及样本时钟不连续、routeChanged、Engine 配置通知、staleCallbacks 和 skippedUpdates 均为 0。每轮封存 `identityChanges=1`，有两次 `configurationChanged` 控制标记，末次位于停止之后。该重复时序支持正常拆图解释。全程 744 个已保存包均为连续 20 ms。P2 的 Render 回调来自原 Tap，非零帧数为 0。

## 3. P4 异常时间线和能量

Engine 启动返回的控制标记位于相对内容起点 +3.275 ms。

| 相对 Native 内容起点 | P4 的技术证据 |
|---|---|
| 0.000–1.420 s | 前 71 个完整 20 ms Native ch0 窗全部精确为零，共 22720 个样本。其后没有其他完整全零窗 |
| 1.420–1.440 s | 第 72 窗有 187 个零和 133 个非零，RMS −82.18 dBFS。连续零前缀上界为 22907 个样本，即 1431.6875 ms。该窗未存样本顺序 |
| 1.440–1.480 s | 相邻两窗 Native RMS 从 −53.88 上升到 −13.61 dBFS |
| 1.480–1.520 s | 两个窗 RMS 为 −4.08、−5.98 dBFS，满幅分别 17、4 个，合计 21。定位精度为 20 ms 窗 |
| 3.125506 s／4.266093 s | 原 `Player.play()` 调用前标记／首个非零软件 Render。零前缀和满幅窗在两者之前 |
| 8.013761 s／14.880 s | 末个非零 Render／已保存 PCM 内容末端。两者间仍有约 6.866 s 已保存内容 |

按 Native 窗 RMS 的平方作样本数加权平均，再换算 dBFS。只取完全落在各分段的窗，并单独给出 quiet 提示前的后段。

| 分段 | 纳入完整窗范围（s） | 窗数 | Native ch0 RMS | 导出 PCM 的同窗汇总 RMS |
|---|---|---:|---:|---:|
| 非零 Render 前 | 0.000–4.260 | 213 | −17.364 dBFS | −17.364 dBFS |
| 非零 Render 内 | 4.280–8.000 | 186 | −24.020 dBFS | −24.021 dBFS |
| 非零 Render 后 | 8.020–14.880 | 343 | −23.537 dBFS | −23.537 dBFS |
| Render 后至 quiet 提示前 | 8.020–11.000 | 149 | −20.998 dBFS | −20.998 dBFS |
| quiet 提示后 | 11.020–14.880 | 193 | −27.606 dBFS | −27.606 dBFS |

Render 内 Native 总体比前段低 6.66 dB。移除前段两个满幅窗作计算敏感性复核后，差仍为 5.92 dB。能量差已经出现在 VP 后 Native，同窗 PCM 跟随。原综合 C JSON 的物理发声区间和重叠时长为空，参与者报告未按引导持续讲话。各分段均只能读作已经处理的混合信号能量。 [P4 人耳记录](T3_2_A_P4_real_double_talk_device_review.md#3-同-run-真人证据与声学裁定)

## 4. 共同模式、P4 可辨别现象及置信度

| 问题 | 裁定 | 置信度与缺口 |
|---|---|---|
| 起始零窗与能量包络是否跨轮重复 | UNKNOWN | P4 的数字零前缀和急升已确认。其他四轮缺少 Native 窗，这一时序只在本表的 P4 得到实证 |
| 满幅是否与 AGC ON 形成一致模式 | 未建立 | ON 的 P2/P4 有满幅，ON 的两轮 P3 无满幅，OFF 的 P2 每声道有 2587 个。P2 ON/OFF 同为 B 且共用冻结候选，峰值事件的时间与实际近端发声强度缺失。满幅取自 VP 后数字信号，ADC 和内部处理归因未知 |
| P4 是否出现与居民播放有关的起音突发 | P4 满幅窗的顺序已确认 | 满幅窗早于本轮 `Player.play()` 和首个非零 Render。后续 Render 前中后能量不同，居民残留和人声贡献未知 |
| AGC 起音适应 | UNKNOWN，因果置信度低 | AGC 状态读回给出开关，现有 JSON 缺少动态增益轨迹、同构起音窗和 VP 前输入参照 |
| VP 启动瞬态 | UNKNOWN，因果置信度低 | P4 的零前缀从采集内容起点开始，满幅约在 1.48 s，缺少可辨实际声源与跨 Run 复现。五轮没有相应 CLOCK 或路由变化证据 |

复算使用 `native.channels[].full_scale` 与 `peak`，位置使用 `short_window_diagnostics.windows[].native`。冻结源码的 `exact_zero_samples` 由 `sample == 0` 计数。若首个混合窗有 `z` 个零，则全零前缀下界为前面全零窗的样本总数，上界另加 `z`。RMS 分段使用非零 Render 时间戳，剔除跨分界窗。源码及汇总统计足以复核上述数字，VP 前输入、内部 AEC／AGC 状态和物理发声时序仍无直接证据。 [零值和 RMS 计数](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L1470) · [软件阶段与物理字段](../../../apps/macos/Aftelle/AppController.swift#L9022)

## 5. 交付与停止

本轮只核验指定原始技术 JSON、同 Run 的既有登记和冻结源码。所有音频样本和私人原件保留在本机。Git 仅变更本报告与 [Test3 README](README.md)。空回滚点 `ac860d4f6d3e08a146bad5823fa30cdc813e1f26` 与交付基线同树，原 7 项冲突、索引和 14 项受保护条目的元数据复核一致。 `git diff --check`、Secret Guard 和 [Stage7 Forbidden Checklist](../../stage7_forbidden_checklist.md) 通过。主控可据本报告进行 Gemini 独立只读复核。

~~~ini
P3_ACOUSTIC_RESULT=PASS_LIMITED
P4_CONTROLLED_DOUBLE_TALK=INCONCLUSIVE
R3_M01=OPEN
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
T3_2_A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
DEVICE_RUNS=0
~~~
