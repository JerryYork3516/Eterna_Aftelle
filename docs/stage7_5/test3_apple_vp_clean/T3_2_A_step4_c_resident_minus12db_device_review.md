# T3.2-A · Step 4-C 居民 −12 dB 电平隔离设备审核

## 1. 结果

**单次 C 组采集完成，技术证据核验通过。** Run `E2FE2473-B026-4F10-843C-275F8BFE92B9` 的实际选材为经核验的 −12 dB 固定居民副本。保存了 **744 个连续 PCM 包，共 14.88 秒**，完整覆盖 **4.266093–8.013502 秒**的居民非零 Player Render。CLOCK 拒收、采集掉包和 Playback 欠载均为 0。两份导出稳定且身份一致，App 正常退出，设备恢复空闲。男声深度衰减、持续失配及居民起音回声是否改善，待独立音频分析。

## 2. 素材处理与离线资格

基线 `5ccc60d12d8bbfa086c3e90d7b68bdc5657571aa`，冻结 App 源码 `574fc735ca239c9b334029debbdee546cda18d49`。用户单独授权在本机处理固定居民 WAV。副本 `HOST_resident_minus12dB.wav` 由原 PCM 逐样本乘 **0.251188643150958** 后就近取整成 PCM16 生成，未重采样。24 kHz、Mono、PCM16LE、114032 帧、4.751333 秒及首 24,000 个零样本全部保留。生成后复核原件身份和摘要一致。

| 本机文件 | SHA-256 | RMS，dBFS | Peak，dBFS |
| --- | --- | ---: | ---: |
| 原固定居民 WAV | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` | −18.723752 | −3.478726 |
| −12 dB 副本 | `291e0748d5adb2c36f71bf48b8064aba5606804842740e85d190e42e7a1c9da1` | −30.723763 | −15.478088 |

两份 WAV 均长 228108 字节，PCM 各 228064 字节。实测数字 RMS 差 **−12.000011 dB**、峰值差 **−11.999363 dB**。相对理想缩放的最大量化误差 **0.499966 LSB**、RMS **0.257066 LSB**，2,662 个原非零 PCM16 样本取整为零，保持样本索引及语音内容。

使用冻结源码的实际 Envelope、Converter 和 Output Host，在不启动音频设备的条件下对比两份素材。排程出口由现有 Fake 承接，Converter 使用离线 16 kHz、三声道、非交错 Float32 synthetic 格式。

| 检查项 | 对照结果 |
| --- | --- |
| 软件可闻判定 | 同样 48 个分块，36 个标记可闻，各块标签相同。该标志只描述数字门槛。 |
| Fade | 两份素材均使用同一原 120 样本 Fade，总长度 5 ms。幅度触发的起点由输入索引 24028 移到 24136，晚 108 样本，即 **4.5 ms**。这是衰减在原门槛下产生的派生差异。 |
| Converter | 每块输出帧数相同，总计 **76,010 帧**，三声道逐样本相等且有限。转换后 RMS 差 **−12.000044 dB**；首个非零帧同为 15990，最后非零帧从 75953 到 75949，尾缘相差 4 帧。 |
| 调度 | 两份素材均共排程 48 块、228064 PCM 字节，顺序逐块匹配输入，开始和完成各 1 次、欠载 0。 |

离线裁定为 `PASS`，观测到的边缘变化来自原电平门槛和量化。扬声器实际声压未测量。 [原 Fade 与转换](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L305) · [原排程](../../../apps/macos/Aftelle/AppController.swift#L8310)

## 3. 预检、单次授权与运行证据

冻结 Debug launcher SHA-256 为 `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`，dylib 为 `e419552e1b539db52c6a971e6b703aaa695cb503fdfbf479fe20c25c5586a132`。加载映像与确切 PID 通过核验。初始系统输出读到 12%，待取得用户恢复授权后的 HAL 复检已为 55%，控制器未写入系统音量。起始前、运行监视和释放后均按 TinyUSB 输入 60%、Mac mini 内置扬声器输出 55%、未静音及既定路由核验。麦克风系统权限已开。

原综合 C、RECORDING、双端 VP ON、AGC ON、无额外预热和原 15 秒上限保持一致。原界面选定 −12 dB 副本，Readback 与原录音确认面板核验通过后，才通知 Windows 播放。用户确认同文件、同方式起播并单独授权一次采集及本机导出，随后触发原录音确认一次。Mac 侧提示前标记至录音确认派发约 **200.865 秒**，其中包含等待用户确认的时间。Windows 实际起播时刻及相对 A/B 的源相位仍未知，需要后续对齐。用户确认的起播条件作为现场见证登记。封存后已通知停止 Windows 播放。

| 运行证据 | 实测 |
| --- | --- |
| 实际选材和时序 | 导出 `playback_sha256` 与 −12 dB 副本一致。一次开始和完成。PCM 零点下软件播放为 3.145096–8.020800 秒，非零 Player Render 为 4.266093–8.013502 秒，两段都完整覆盖。实际非零窗比 B 晚约 32 ms，后续以各轮实际 Render 和同源男声窗配对。 |
| Player 与 Native | 共排程 76,010 帧，其中非零 59,677。149 个 Player Tap 回调确认同样 59,677 个非零帧。Native 为 16 kHz / 3ch，150 个回调、240,000 帧。物理扬声器声压及两声源重叠时长未独立测量。 |
| VP / AGC 与身份 | Capture / Playback Generation 1 / 1、ConfigurationID 2，两个同代读回符合 VP 双端 ON、AGC ON、bypass=false、inputMuted=false。 |
| PCM 与可靠性 | 744 个连续 20 ms 包，714240 字节。生成 749 包，封存余队列 5 包，导出 744 包，账目守恒。Native/PCM **744/744** 同内容短窗，时钟可信。Input/Player HostTime 和 SampleTime 未出现不连续；CLOCK 拒收、采集掉包、过期包、播放欠载为 0。 |
| Stop、导出、释放 | 原时限正常 Stop/Seal，监视器未触发 Stop。未见路由变化或 Engine 配置通知。导出监视器先等文件稳定，核验同 Run 身份、完整 WAV 长度及 PCM 摘要后才登记成功。App exit 0，精确 PID 消失，设备均空闲，前后路由快照一致。 |

## 4. 本机导出与交付

| 本机导出 | 字节数 | SHA-256 |
| --- | ---: | --- |
| WAV，24 kHz / Mono / PCM16LE，357120 帧 | 714284 | `75d2b9be59f8f07c593e5c26ff662f241c9fc02ed8211d898fb6e17acec07cc3` |
| 技术 JSON | 1060923 | `ded7174e763c1b9839631dc747afc020490425f24497b4a0c80b3388b52b74c7` |

两份文件权限 0600，PCM 数据摘要与 JSON 一致。WAV 和 JSON、源音频副本及过程收据仅留本机。Stage 7 Forbidden Checklist 自审 PASS，受保护的原 7 项冲突、索引和 14 项证据复核一致。仅新增脱敏报告，生产处理及阈值无改动。C 轮无重试，A/B 未重跑，正式真人 P4 与 Gate 53-C 计数为 0。历史 CLOCK 失败及导出监视器异常仍保留。 [B 轮技术证据](T3_2_A_step4_b_resident_control_device_review.md) · [A/B 归因口径](T3_2_A_step4_ab_acoustic_attribution.md)

```ini
STEP4_C_ATTENUATION_OFFLINE=PASS
STEP4_C_CAPTURE=COMPLETED_ONCE
STEP4_C_TECHNICAL_EVIDENCE=PASS
STEP4_C_EXPORT_MONITOR=PASS
STEP4_C_WINDOWS_PHASE_OFFSET=UNKNOWN
STEP4_C_NEAR_END_AND_ONSET_EFFECT=AWAITING_INDEPENDENT_AUDIO_AUTHORIZATION
STEP4_C_RETRIES=0
P4_FORMAL_53_C_RUNS=0
CLOCK_ROOT_CAUSE=UNKNOWN
AEC_ROOT_CAUSE=UNKNOWN
T3_2_A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
