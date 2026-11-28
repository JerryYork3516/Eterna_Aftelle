# Stage 7.5.11 · Native Voice DEBUG 同帧声学诊断

审核基线 `a9bc5ff93c62326f46ad328184046dce9d68c9c3`。本轮用合成信号和 Fake Engine 验证同帧取证能力。历史 M19 的相同通道峰值无法证明样本一致。Step 4 旧试次已观察到 VP 后混合能量变化，归因仍受声源与物理时间见证限制。[Apple VP 对照审计](Stage_7_5_11_Apple_VP_official_integration_comparison.md) · [P1–P4 冻结合同](AppleNativeVoiceTransport_P4_engineering_review.md) · [M19](T3_2_A_R5_M19_D1_native_pcm_device_review.md) · [Step 4 A/B](T3_2_A_step4_ab_acoustic_attribution.md) · [Step 4 C](T3_2_A_step4_c_abc_acoustic_attribution.md)

## 同帧证据

| 观测点 | 记录与关联 | 代码 |
| --- | --- | --- |
| VP Sink 客户端 Float32 | 沿实际协商声道数复制交错或非交错 ABL。依回调 ID、capture token、configurationID 和块内 offset 对齐。每声道统计 RMS、Peak、零值、满幅、超幅、非有限，以及与实际选中通道的逐样本位相等数、有效差值 RMS／Peak 和 Pearson 相关性。 | [Sink](../../../apps/macos/NativeVoiceTransport/NativeVoiceRealtime.c#L302) · [预分配与复制](../../../apps/macos/NativeVoiceTransport/NativeVoiceRealtime.c#L86) · [逐通道比较](../../../apps/macos/NativeVoiceTransport/NativeVoiceSameFrameDiagnostics.swift#L218) |
| 选通道后、SRC 前 | 对同一生产采集环送入 Worker 的实际 Float32 取统计。当前系统默认选声道 0。没有改通道选择规则。HostTime、SampleTime、原始 flags 和丢帧从同一 Sink 回调关联。 | [采集 Worker](../../../apps/macos/NativeVoiceTransport/AppleNativeVoiceTransportWorker.swift#L142) · [环消费与块界](../../../apps/macos/NativeVoiceTransport/AppleNativeVoiceTransportWorker.swift#L229) |
| SRC 后、量化前 | 用实际 AVAudioConverter 累计输入、实际发出的 24 kHz 范围与分段内容坐标关联，而非按 Worker 接收时间配对。报告保留延后输出、输入对应窗、读得到的 prime metadata 和尾段。量化前再按实际 480 帧分包取统计。 | [输出范围映射](../../../apps/macos/NativeVoiceTransport/NativeVoiceSameFrameDiagnostics.swift#L272) · [P1 SRC](../../../apps/macos/NativeVoiceTransport/NativeVoiceStreamingSRC.swift#L55) |
| 最终上行 PCM16LE | 对实际生成的 480 样本 PCM16LE 包解码归一化并逐样本对照同一包的量化输入。记录正负端点、偏差、包内帧数、sampleCount、时钟资格和 capture 身份。独立本地 Lab 的观测终点是 Worker 生成包。 | [组包点](../../../apps/macos/NativeVoiceTransport/AppleNativeVoiceTransportWorker.swift#L288) · [量化对照](../../../apps/macos/NativeVoiceTransport/NativeVoiceSameFrameDiagnostics.swift#L300) |

`segment` 内的原生内容区间和 24 kHz 输出区间按采样率投影。范围来自实际已经释放的输出计数，可能引用前一回调输入。滤波器可能使用窗口两侧的样本，期间只对比对应内容窗的统计，不进行跨采样率逐样本减法。等采样率没有适用的 SRC prime metadata。清空和停止沿用原规则。末端尚未转换或不足一整包的样本单独报告。不会为了导出额外冲洗正式路径。

Source 部分复用现有事实队列，保留 playback token、configurationID、真实回调采样和宿主时间、提交帧数、非零区间和数字 EOS。Sink 块保留回调进入时的播放 token，完整会话身份随报告导出。本地 Lab 的 runtimeGeneration 为 0，表示无 Runtime 会话。时标缺失计数令证据不完整。数字提交和 EOS 的观察点在 Source，物理外放和 Apple 内部 AEC 参考仍是 UNKNOWN。[Source 消费](../../../apps/macos/NativeVoiceTransport/AppleNativeVoiceTransport.swift#L213) · [事实记录](../../../apps/macos/NativeVoiceTransport/NativeVoiceSameFrameDiagnostics.swift#L316)

起止两次从非实时控制侧读取 active／preferred Mic Mode、两端 VP、AGC、bypass、输入 mute、系统默认设备、AudioUnit 当前设备及能取得的 Aggregate 活动成员。对相应方向读取 HAL 主元素及最多 32 个通道元素的电平和静音属性，同时报告截断。显式的 VP 请求值与实际节点读值分开。缺失字段表示 UNKNOWN。Ducking 只记录公开配置。[系统状态](../../../apps/macos/NativeVoiceTransport/NativeVoiceSystemEngine.swift#L177) · [设备属性](../../../apps/macos/NativeVoiceTransport/NativeVoiceHALRoute.swift#L327)

## 实时隔离与隐私

- Sink 在既有 ABL 检查后复制，每个 graph 16 槽，样本区最多 2 MiB，配套内存在激活前分配和触页。回调只增加有界内存拷贝和无锁原子操作。Worker 消费槽后归零，Source 回调逻辑无改动。
- 统计预算 16,384 条，内容映射缓存最多 32,768 个帧。满载丢弃诊断，正式 PCM 不依赖诊断队列。无 ABL 见证、旧块、映射缺口、尾段、实际传输丢帧和诊断丢失各有单独字段。关闭时若有最后一批 Sink 待消费，报告据实标记不完整。Lab 不自动重试。
- 默认关闭。只有授权 Debug 的专用入口启用。不追加 PCM 到 JSON，不保存原始诊断音频。导出需要本地保存面板确认，报告只含技术统计、身份和指定 WAV 的摘要。采集只在本地窗口得到确认和麦克风系统权限后开始。专用模式跳过正常产品初始化和 Runtime／Provider。

## 经授权后使用

1. 使用现有签名及 entitlement，在独立目录里建立 Debug。保留 `DEBUG AFTELLE_WEBRTC_AEC3 NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS APPLE_NATIVE_VOICE_P4_DEVICE_AUTHORIZED APPLE_NATIVE_VOICE_ACOUSTIC_EVIDENCE_AUTHORIZED`。C 诊断宏由 Debug project 设置提供。
2. 以唯一参数 `--apple-native-voice-same-frame-diagnostics` 调用实际 Debug 可执行文件。窗口内显式选择本地 24 kHz Mono PCM16LE WAV，最长 12 秒。保留恢复窗时选明显短于 12 秒的素材。混用已知 Lab／Shadow 或其它启动参数会拒绝此入口。
3. 获得本轮授权后点开始。实际采集包到达才显示讲话提示，提示后约 3 秒开始向现有 Worker 入队，不改变 WAV 增益。以提示为起点运行最多 15 秒，亦可手动停止。关闭后可手动导出本地技术 JSON。时序分析采用真实事实，界面提示和宿主排程只作操作提示。[入口](../../../apps/macos/Aftelle/AftelleApp.swift#L38) · [Lab](../../../apps/macos/Aftelle/AftelleApp.swift#L329)

## 判读合同

- 同一异常在所有 VP Sink 客户端声道已出现时，首次可见边界在应用选通道和 SRC 之前。Sink 之前的 HAL、物理路由及 Apple 内部处理仍需证据。
- 仅声道 0 出现时，核对该客户端声道的选择依据和相邻通道的实际内容。通道索引不能直接映射物理 ADC。
- 应用阶段出现超出转换合同的偏差时，用同内容合成输入局部复现。滤波跨窗、正常量化和已标注的截断单独解析。VP 后混合 RMS 不提供独立真人衰减量，波形统计也无法独立分离居民残余。
- 若所采证据中的应用转换符合合同，停止重复排查后级，后续由主控决定同设备 Apple VP／FaceTime 与参考宿主的对照。任何物理回放或真人资格裁定仍需独立证据。

## 本轮实际验证

| 检查 | 结果 |
| --- | --- |
| 专项普通／TSan／ASan+UBSan | 三轮分别 126 条 Swift 断言通过。每轮一组 C 并发用例提交 2,048 块，全部按接收或显式溢出计数。三轮接收／溢出分别为 1,610／438、2,033／15、2,033／15。含信号差异、实际 SRC 脉冲和尾部、时间缺失、代际、输出一致性及 Debug 参数隔离。 |
| 实时与 Release | 回调 IR 检查无诊断宏为 O0 24／O2 10 个函数，有诊断宏 O0 25／O2 10 个。Release C／C++ 预处理输出与基线逐字节匹配。Debug 和 Release Xcode 27.0 构建通过。Debug dylib 有入口和 C 符号，Release 可执行文件两者均缺失。 |
| P1／P2 | P1 4 组 C 用例，1,000,000 帧 SPSC、30,000 次 clear、2 次强制竞争，1,770 条 Swift 断言及 12 组采样率。P2 4 组 C 用例及 4 次强制竞争，114 条 Fake Engine 断言。原末尾阶段 Guard 在基线就因已归档 Lab 入口不在旧列表中退出 1，本轮保留失败。 |
| P3／P4 与 Acoustic Evidence | 三组 C 事实用例及内容时间栅栏通过。在独立临时目录补入按现有合同生成的合成 DR 后，原 P3／P4 断言分别通过 30／52 项。Acoustic Evidence 原断言通过 149 + 83 + 35 = 267 项，并跑过 8 个进程退出点。P4 Debug 准入／Release 与 Shadow 拒绝，以及 Acoustic Evidence 编译隔离均通过。脚本在共同的历史 Guard 处退出 1。隔离工作树缺少历史本地 DR，未使用主工作区的 DR。 |
| 工程边界 | Architecture、Secret、Release Route Guard 和 Xcode／本地化配置 lint 通过。未运行 FULL_CURRENT 或真机测试。 |

离线产物未签名，未启动。Debug dylib SHA-256 `fcba2391570ae2f2db0eb6fae8443377ce9dd9f117b5dca76dee38abe4c33ce2`。Release 可执行文件 SHA-256 `8fa975ed10397aee5e1ee7d7989b0905e14e18f09dd15294e2af936df253cad0`。

### Stage 7 Forbidden Checklist

- 结论 `PASS`。无红线触碰。
- 修改范围为 DEBUG Lab、Native Transport 诊断和控制侧读回、Xcode Debug 编译开关、本地化、专项测试与文档。具体文件见提交。
- Runtime API、DR Schema、Provider、正式插话安全门、生产 AEC 和平台 target 无改动。Stage 8 未进入。正式设备验证需本轮以外的明确授权。

```ini
DEBUG_SAME_FRAME_DIAGNOSTICS = PASS
AEC_ROOT_CAUSE = UNKNOWN
CLOCK_ROOT_CAUSE = UNKNOWN
SQ_M1 = OPEN
Formal_Test3 = BLOCKED
Test3.execution_authorized = false
DEVICE_RUNS_THIS_TASK = 0
```
