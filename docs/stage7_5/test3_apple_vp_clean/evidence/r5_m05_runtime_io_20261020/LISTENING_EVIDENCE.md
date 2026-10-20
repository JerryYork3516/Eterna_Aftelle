# R5-M05 · A组原导出WAV试听证据

schema_version：1。日期：2026-10-20。

用户本次明确授权：

> 让我试听一下WAV然后同时提交推送WAV让主控审核

本目录仅公开本轮M05 A组原导出评分WAV及此说明。当前仓库为PUBLIC。该授权是前一份M05报告交付后的新增公开提交授权，不是复用旧实验或旧录音授权。原始Manifest、设备标识符及日志不公开。

| 项目 | 核验结果 |
|---|---|
| 文件 | [A_resident_only.wav](A_resident_only.wav) |
| RunID | `2F4AA935-488D-4777-BC9B-94CAC163F72C` |
| 原件/上传副本SHA-256 | `710c8d0d9cd8d52345192b243a7560938febebddad1f224e4c2e004dcefde7cf`（逐字节相同） |
| 文件大小 | 713324 bytes |
| 音频 | 24kHz / Mono / PCM16LE；356640 frames / 14.86秒 |
| 运行源码commit | `f90c9272467b8af9846ce4551e354224fb7dafbf` |
| Debug dylib SHA-256 | `d53fa0568e08e98371f31399eb830078de80847fb9ed7a2c7fcb50608ae490f2` |

仅居民固定Tingting语音播放一次，不含本次蓝牙代理或真人参与；麦克风仍可能收进环境声音，后段声音来源UNKNOWN。固定播放原文为“这是一段固定语音，用来检查回声和人声。”，不是对录音的转录。

这是App原导出的**Apple VP及后级PCM处理后录音**，不是未经VP处理的麦克风原音。未重采样、降噪、归一化、裁剪、增益处理或补零；没有追加录音。4秒预热未留存。WAV内容对应score约0.013040126–14.873040126秒，尾部PARTIAL。

本轮两份运行态VP属性稳定，但真实输入物理归属仍UNKNOWN。4–7.75秒保存WAV RMS约−73.68dBFS；不能仅凭低能量或模板相关性宣布AEC通过。原有M03 A失败记录不改写。完整统计、读回口径及限制见[本轮M05审核报告](../../T3_2_A_R5_M05_runtime_io_device_review.md)。

本次只做原件身份核验及授权公开提交；没有运行App、设备、新实验或代码回归。Stage7 Forbidden Checklist=PASS：无生产代码、Runtime API、DR schema、平台target或Stage变化；原7冲突现场保留。

```ini
USER_LISTENING=PENDING
GPT_AUDIO_REVIEW=PENDING
AEC_ROOT_CAUSE=UNKNOWN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
