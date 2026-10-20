# R5-M03 · A/B/C试听证据与播放原文

schema_version：1。日期：2026-10-20。

用户反馈及公开提交授权原话：

> 全部失败，音频提交推送让GPT审核，并给我对应的内容文本

本目录只包含这次明确授权公开的三份评分录音及本说明。仓库为PUBLIC，主控音频复审PENDING。完整工程证据见[本批审核报告](../../T3_2_A_R5_M03_BT_ABC_acoustic_review.md)。

## 1. 三份录音

| 文件 | RunID | bytes / frames / 秒 | 源文件及提交副本SHA-256（相同） |
| --- | --- | --- | --- |
| [A_resident_only.wav](A_resident_only.wav) | `F60F1D2A-4B68-4A05-8260-5BC567F71721` | 713324 / 356640 / 14.86 | `87a0e5e91db130597e02706620e0b23584018d989fa17654665cc74dd797d44c` |
| [B_bt_near_end_only.wav](B_bt_near_end_only.wav) | `44430CFD-991C-46B2-8446-E400A77A9FD1` | 713324 / 356640 / 14.86 | `ddbc4aff5073fd4d0f45498b0b757cfb8f1c293fb07dfe47da3b2c820331a9cc` |
| [C_double_talk_partial.wav](C_double_talk_partial.wav) | `DFF89229-7E56-42D9-A8AF-ECAA9EC0EBE6` | 641324 / 320640 / 13.36 | `4d61b1bfbeacfc33a02b485f86e646f6828272e02f8de9e11e8ba3e18d6b6382` |

格式均为24kHz / Mono / PCM16LE。原App导出WAV逐字节复制；未重采样、降噪、归一化、裁剪、增益处理或补零。原Manifest的RunID、分组、PCM字节数及processed SHA已在本机核验，Manifest不公开。

这些录音已经过Apple VP及后级PCM转换，不是未经处理的麦克风原音。4秒预热音频未留存；没有另一份完整Native录音可提供。WAV第一帧对应评分内容约+15ms，A/B保存至约+14.875秒，C仅至+13.376秒；均为`TAIL_COVERAGE=PARTIAL`。C因内容时钟校验失败提前停止，不可当成完整15秒评分。

## 2. 固定播放内容文本

文字与SHA来自[既有固定素材登记，第4节](../../T3_2_A_bt_speech_warmup_sync_and_ab_review.md#4-设备素材及实际运行)。这是预设播放原文；录音可能存在断续、缺字或尾段截断，没有对录音做自动语音转录。

**居民语句（Mac mini内置扬声器）**

> 这是一段固定语音，用来检查回声和人声。

源素材SHA-256：`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`。Tingting，24kHz / Mono / PCM16LE，4.751333秒，含1秒全零前导。

**代理人声（小爱蓝牙音箱）**

> 今天我想聊聊刚才的事情，窗外阳光很好，我们可以慢慢说清楚，我会继续自然讲话，等到提示出现后再安静下来。

源素材SHA-256：`1c7081f8271251804e01234be8a0ff8344062d09c311592634cb8fdf6b992d0a`。Tingting，固定rate190，24kHz / Mono / PCM16LE，11.012917秒，无R4派生素材的4秒静默前导。

## 3. 每份录音对应内容

| 录音 | 预设声源内容 | 软件时序及边界 |
| --- | --- | --- |
| A | 仅居民语句；无蓝牙代理 | score+3秒请求居民播放，实际Player非零Render约+4.197至+7.945秒 |
| B | 仅代理人声；无居民播放 | score+0秒代理PLAY，+11秒STOP |
| C | 两段语音共同出现：代理人声持续，居民从中途加入 | 代理score+0秒PLAY、+11秒STOP；居民score+3秒请求，非零Render约+4.198至+7.946秒 |

调用、Render内容时间及真实空气传播不是同一时刻。蓝牙实际起止未知，+11秒STOP不保证完整11.012917秒素材全部播放。不能按预设文本替录音补字，也不能据软件窗口证明真实声学重叠。

## 4. 供主控审核的事实与限制

- 用户将三份录音评价为“全部失败”；尚未给出分组、逐词的具体失真描述，不代替用户补写听感。
- A出现居民模板相关特征、每Native声道23个满幅值及WAV中33个PCM端点样本。
- B/C首段都有代理模板特征；C在重叠附近的代理特征较B减弱。Native/PCM大窗RMS接近，但不能据此保证局部人声完整或可懂。
- C在quiet阶段出现一次约2.18ms Input内容时钟偏差，触发拒收和安全停止；最后VP/AGC读回有效。该晚期停止不能解释此前的全部声学现象。
- 同Mac蓝牙代理的Apple内部回声参考隔离仍UNKNOWN；不将代理实验当成人类双讲验收。
- 本次上传只提供主控审核证据，不代表声学PASS或根因已确认。

```ini
USER_LISTENING=FAIL_ALL_THREE_USER_REPORTED
GPT_AUDIO_REVIEW=PENDING
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
