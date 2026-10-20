# T3.2-A · R4 REF/HOST WAV Listening Evidence

schema_version: 1。日期：2026-10-20（Asia/Shanghai）。本目录仅公开用户本次明确授权的两份R4录音副本，供GPT主控音频审核；没有重新录音或修改生产代码。

## 先区分“原始”和“处理后”

- [01 · REF_native_VP_input_ch0.wav](REF_native_VP_input_ch0.wav)：REF原生Input Tap记录的Float32样本导出。**它已经过Apple Voice Processing，不是VP之前的原始麦克风声音。** 原三声道在本次封存中逐样本bit相同，听音导出保留ch0原始Float32样本，没有归一化、降噪、重采样或增益处理。
- [02 · HOST_processed_score.wav](HOST_processed_score.wav)：HOST应用直接导出的24kHz/Mono/PCM16LE评分录音。公开副本与应用原WAV逐字节相同。
- 本轮没有保存VP之前的麦克风WAV；HOST也没有保存可另行导出的原生三声道PCM。无法恢复不存在的处理前录音。
- **REF和HOST是两个不同RunID，不是同一次录音的处理前/后对照。** 不要把编码差异或文件SHA差异解释成处理损伤。

## 文件身份

| 项目 | 01 · REF | 02 · HOST |
|---|---|---|
| RunID | D2CFBD8B-B359-4298-8861-DC8DA614CD47 | FD387D0B-6840-4702-9AE1-5A5D7ADCC998 |
| 输入来源 | 已处理的REF Native Input ch0 | 已处理的HOST最终评分PCM |
| 格式 | 16000Hz / Mono / IEEE Float32 LE（WAV tag3） | 24000Hz / Mono / PCM16LE（WAV tag1） |
| 帧数 / 时长 | 217600 / 13.6秒 | 356640 / 14.86秒 |
| 文件大小 | 870458bytes | 713324bytes |
| 原本地WAV SHA-256 | `c20dd1b313fe7c8669dd9837efb66d40c5a14edd35556912587f7dd284a7d7eb` | `6c3447aaaf639f59f000e3a9d35f51186b8c25775801a5580be92fc2f8e63e1a` |
| 本目录副本SHA-256 | `c20dd1b313fe7c8669dd9837efb66d40c5a14edd35556912587f7dd284a7d7eb` | `6c3447aaaf639f59f000e3a9d35f51186b8c25775801a5580be92fc2f8e63e1a` |
| 音频修改 | 无；现有听音WAV原字节复制 | 无；原应用WAV原字节复制 |

REF原封存容器SHA为`925352c28e47ac8b9ec3229d7d3b8d5b37e42ae0c8bd9f1c15318d9451368e27`；容器、原Manifest、设备UID、系统原始日志不在公开提交中。HOST本地统计JSON及REF元数据只用于核验本次RunID/构建/格式，不随WAV上传。

## 审核窗口和限制

完整工程报告：[R4受控设备对照](../../T3_2_A_reference_host_R4_device_comparison.md)。实际REF为单独登记的`R4_GUI_ENTRY_ADAPTED_REF`，不是历史成功的原二进制。两组实际AGC/VP均开启；代理来自小爱蓝牙音箱，居民来自Mac内置扬声器，输入TinyUSB。

| 时间项 | REF | HOST |
|---|---|---|
| WAV首样本相对观察/评分原点 | −0.165603021秒 | +0.015352833秒 |
| 共同数字分析窗[4,7.75)对应WAV位置 | 约4.165603–7.915603秒 | 约3.984647–7.734647秒 |
| 末样本结束相对观察/评分原点 | 约13.434397秒 | 约14.875353秒 |

这些来自数字内容时间模型；没有校准处理/空气/蓝牙延迟，不是精确物理发声位置。两组代理PLAY耗时和源特征偏移不同，`COMPARISON_LIMITED=true`。HOST原human_only 0–3秒在本素材方案中为代理静默，不能评价历史真人首3秒静音。

HOST评分仅14.86秒：缺首15.352833ms、尾124.647167ms，共140ms；queued0不等于15秒完整，converter partial tail仍UNKNOWN。REF formal13数字窗覆盖，不证明完整13.5秒postroll。HOST观测skip2、REF通用timestampStatus未验证等限制保留。没有补零、裁剪或对齐加工音频。

## 已有试听反馈与主控待审核项

用户对01/02的原话：

> 01能听到语音，但说的是 我们 不确定是不是居民语音，02一部分清楚。两段语音都有时有时无，忽大忽小卡顿。你再听一遍得出结论，一会提交推送时也让GPT审核

两段代理完整性/音量稳定性为`FAIL_USER_REPORTED`；居民是否可辨仍UNKNOWN。请主控分别判断居民残留、代理可懂度、消音/卡顿、音量变化，保留无法辨认的部分，不把相关性或RMS当听感真值。

没有未经VP处理的麦克风原音对照，不能直接判断Apple内部AEC/NS/AGC的独立因果；同Mac两路输出的`SOURCE_REFERENCE_ISOLATION=UNKNOWN`。本次公开文件不是声学PASS，也不改变旧真人VP-C成功或既有真人C失败记录。

## 公开授权、范围和检查

用户本次明确要求“录音也推送让GPT审核，包括原始WAV和处理后的WAV，原始WAV我也听一下”。该要求在已知PUBLIC仓库上下文中授权公开本轮两份可用WAV；不扩展到其他录音、私人Manifest/日志、DR、Session、Memory或密钥。

核验：Git三方基线`3a78838d26b8b713522d62d022d6f2919e9df917`一致，原文件SHA/RunID/格式/帧数/大小匹配，复制前后SHA一致、源文件0600未改，未覆盖旧结果。未启动App/Engine/麦克风/扬声器，未自动播放或重新测试。

Stage7 Forbidden Checklist：**PASS**。修改仅本目录两份WAV、本说明和R4报告授权补记；无代码、Runtime API、DR schema、新平台target或Stage8变更，无新增设备行为，不需要重复授权。原7冲突工作区不变。

编译、FULL_CURRENT、设备实验：NOT_RUN（仅证据提交）。本次新增CRITICAL/MAJOR/MINOR=0/0/0；原R4声学与证据问题继续OPEN。

```ini
R4_AUDIO_PUBLICATION=AUTHORIZED_BY_USER
WAV_BYTE_IDENTITY=VERIFIED
UNPROCESSED_MICROPHONE_WAV=NOT_RECORDED
REF_NATIVE_INPUT=APPLE_VP_PROCESSED
HOST_NATIVE_PCM_RECORDING=NOT_RETAINED
GPT_AUDIO_REVIEW=PENDING
COMPARATIVE_ACOUSTIC_RESULT=INCONCLUSIVE
AEC_ROOT_CAUSE=UNKNOWN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
