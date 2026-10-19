# T3.2-A · Mainline A/C Listening Evidence · 2026-10-19

本目录供ChatGPT主控审核本轮A/C音频。两份WAV均为Apple VP处理后的原始导出文件，**不是未经处理的麦克风原音**。本次仅逐字节复制，未重采样、降噪、归一化、裁剪、压缩、修改音量、补零或重新生成音频。

## 1. RunID与文件

| 场景 | 文件 | RunID |
| --- | --- | --- |
| A：Resident-only | [A_resident_only.wav](A_resident_only.wav) | `A174EB2F-E134-496A-924A-811EDADE0D6C` |
| C：Proxy Double-talk | [C_proxy_doubletalk.wav](C_proxy_doubletalk.wav) | `145757A4-51C0-4166-80AA-97CFC8417555` |

## 2. 源WAV SHA-256

| 文件 | 原受控Caches源文件SHA-256 |
| --- | --- |
| A_resident_only.wav | `3b8daf6a9fb93e100905e7470dbeba56957d3929c070941a6da73583530e1931` |
| C_proxy_doubletalk.wav | `143178151d5513ccb2b30ec51a6760cdfa5bfa07a7622033d10a46e086cb4601` |

## 3. 上传副本SHA-256

| 文件 | 仓库副本SHA-256 | 原字节一致性 |
| --- | --- | --- |
| A_resident_only.wav | `3b8daf6a9fb93e100905e7470dbeba56957d3929c070941a6da73583530e1931` | PASS |
| C_proxy_doubletalk.wav | `143178151d5513ccb2b30ec51a6760cdfa5bfa07a7622033d10a46e086cb4601` | PASS |

## 4. 大小、格式与原Manifest身份

两份均为RIFF/WAVE、24000Hz、Mono、PCM16 Little Endian，仅含fmt和data区块。源文件与原Manifest的run_id、场景、RECORDING模式、格式、留存字节数及PCM数据SHA-256逐项匹配。原Manifest仅本机核验，不上传。

| 文件 | WAV bytes | PCM bytes | samples | 实际时长 |
| --- | ---: | ---: | ---: | ---: |
| A_resident_only.wav | 714284 | 714240 | 357120 | 14.88秒 |
| C_proxy_doubletalk.wav | 713324 | 713280 | 356640 | 14.86秒 |

## 5. 评分场景

A使用原Resident-only入口，Mac内置扬声器播放固定Tingting居民语音，无近端代理播放，不要求真人讲话。C使用AGC-ON、4秒持续处理预热后15秒综合C评分；小爱蓝牙音箱播放固定模拟近端语音，Mac内置扬声器按原第3秒触发居民素材。C不保留4秒预热PCM。C是代理诊断，不是真人综合C；HUMAN_C=NOT_RUN。

## 6. 已知声学风险

[本轮工程审核报告](../../T3_2_A_mainline_acoustic_validation_echo_double_talk_review.md)保留原结论：A输出低能量，居民参考相关性未优于反转负控，不能据此认定可听回声消失。C存在代理参考特征，也存在居民相关残留假设，未证明完整可懂的人声保留。两路声音来自同Mac，SOURCE_REFERENCE_ISOLATION=UNKNOWN；蓝牙物理起止、实际重叠和声源分离真值尚未证实。两run本次满幅及PCM精确端点计数均0，不关闭历史音量突变、人声保留和回声问题。

## 7. 尾部覆盖

TAIL_COVERAGE=PARTIAL。A留存744个20ms包，封存时另有5个排队包，约100ms未进入WAV。C留存743包，queued=0，但跨界及窗外包不留存，评分实际覆盖约[0.015023083,14.875023083)秒。两份均不是完整15秒导出；Converter partial tail=UNKNOWN。没有补零或修补覆盖。

## 8. 本次公开提交授权

用户在本次任务明确知悉当前GitHub仓库为PUBLIC，并明确授权公开提交上述两份指定原始测试WAV，供ChatGPT主控音频审核，无需再次申请授权。授权范围仅此两份WAV与本说明；其他录音、原Manifest、设备UID、系统日志、DR、Session及Memory不在本次提交范围。

## 9. 试听状态

USER_LISTENING=NOT_RUN。用户尚未对这两份本轮WAV完成试听反馈；本次文件身份核验不等于听感审核，不将统计或相关性改写为声学PASS。

## 10. 阶段状态

AEC_ROOT_CAUSE=UNKNOWN。T3.2-A=BLOCKED。Formal_Test3=BLOCKED。Test3.execution_authorized=false。公开音频交付不构成声学验收或下一节点授权。
