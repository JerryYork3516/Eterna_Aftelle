# R5-M07 · 真人A/B/C试听证据

本目录只含本轮三份Apple VP处理后的评分WAV。它们不是VP前原音，也不是Native三声道原始录音。源文件和公开副本逐字节相同，无重采样、裁剪、补零、归一化或增益修改。

用户在本轮试听后明确授权：“提交推送三份WAV让GPT审核”。当前GitHub仓库为PUBLIC；授权仅覆盖本次A/B/C三份，不包括私人Manifest、设备UID、完整日志或其他录音。

| 场景 / 文件 | RunID | bytes / 秒 | 源文件及副本共同SHA-256 |
|---|---|---:|---|
| A / [A_resident_only.wav](A_resident_only.wav) | `6732FC36-F824-4835-8EC9-05145C972BAB` | 713324 / 14.86 | `7cfad67e6c5655aefee9b0b17358aef0cf231144db98199bf528a0b45ffcbef0` |
| B / [B_human_only.wav](B_human_only.wav) | `2924502E-9463-4CE8-A8C7-CA797EE39C7A` | 713324 / 14.86 | `6bb216f73f03c06073c2236ed3e0f16ac3d196d9fcaae64adf087a3b8ca2be7a` |
| C / [C_human_doubletalk.wav](C_human_doubletalk.wav) | `1686FD38-F0AD-49DE-9F9B-B00A2F4CE324` | 679724 / 14.16 | `23b60b6cd52be694e7dcfb1da32938daeeee795a57d0545c0f8f15e8120b0da2` |

A：用户保持安静，居民在score+3秒请求播放一次。B：真人独讲，居民不播放。C：真人持续讲话并播放居民。三组均使用AGC-ON、4秒持续预热；预热PCM留存0。没有蓝牙代理或REF运行。

固定居民原文：“这是一段固定语音，用来检查回声和人声。”真人自然讲话，本轮没有自动转录，不提供臆造的逐字文本。

用户试听原话：
> A听不到居民声音，B清楚完整，C无居民声音，但是真人声音有轻微忽大忽小。没有其他问题。提交推送三份WAV让GPT审核

A/B保存14.86秒，均有首尾未留存部分。C在score约14.324秒因内容时钟校验失败安全停止，只保存14.16秒；不是完整15秒。三组TAIL_COVERAGE=PARTIAL，Converter partial tail=UNKNOWN。B包含5个PCM16精确端点样本。用户没有单独确认实际讲话起止及物理双讲超过1秒，不能由软件阶段代替。

试听支持本轮A回声抑制及B人声保留的有限结论；C仍有轻微增益波动及独立时钟失败。本次提交不宣布声学根因已解决，不计正式53门禁。

AEC_ROOT_CAUSE=UNKNOWN；T3.2-A / Formal_Test3=BLOCKED；Test3.execution_authorized=false。详见[本轮报告](../../T3_2_A_R5_M07_human_ABC_acoustic_review.md)。
