# Stage 7.5.11 · 独立 AUHAL＋Direct VPIO P0-C 工程验收

## 裁定

P0-C 的候选、实时调用图与生命周期均通过离线验收。时钟、路由及系统回声参考的物理行为留待实机。审核基线 `86480a2e8e607f52b8474ca35e244f4481d020b0`，实现提交 [`91ffc37b71166f8f588845f9adc7d157278c5104`](https://github.com/JerryYork3516/Eterna_Aftelle/commit/91ffc37b71166f8f588845f9adc7d157278c5104)。该提交含 14 个工程及测试文件。报告单独归档。

此前 Chrome 已选择系统 VPAU，但在 `AudioUnitInitialize()` 返回 `'unkn'`。Aftelle 原 Direct VPIO 则完成过 TinyUSB＋Mac mini 内置扬声器试次。P0-C 保留 Aftelle 的 VPIO 协商，再将居民播放交给独立 AUHAL。 [Chromium P0 收据](https://github.com/JerryYork3516/Eterna_Aftelle/blob/86480a2e8e607f52b8474ca35e244f4481d020b0/docs/stage7_5/test3_apple_vp_clean/Stage_7_5_11_Chromium_Apple_AEC_P0_2026-11-28.md) · [原 Direct VPIO 试次](https://github.com/JerryYork3516/Eterna_Aftelle/blob/86480a2e8e607f52b8474ca35e244f4481d020b0/docs/stage7_5/test3_apple_vp_clean/Stage_7_5_11_direct_VPIO_first_human_double_talk_2026-11-28.md) · [开源对照](https://github.com/JerryYork3516/Eterna_Aftelle/blob/86480a2e8e607f52b8474ca35e244f4481d020b0/docs/stage7_5/test3_apple_vp_clean/Stage_7_5_11_Apple_AEC_open_source_comparison.md)

## 数据路径与改动范围

```text
居民 PCM → 原 Worker / 播放 SRC → 原 C11 Playback Ring → AUHAL bus 0 → 内置扬声器
                                            └─ EOS 与 clear ACK 由该消费者产生
TinyUSB → VPIO bus 1 → 原 C11 Capture Ring → 原 Worker / 采集 SRC → PCM16
VPIO bus 0 → C 静音回调（零填充并设置 OutputIsSilence）
```

| 责任 | 实现 |
| --- | --- |
| 输出单元与设备比对 | 使用公开 `kAudioUnitSubType_HALOutput`，通过 EnableIO 读回确认只启用输出。AUHAL Global/0 的实际 AudioDeviceID 与 VPIO Global/0 参考输出读回及默认输出必须相同。AUHAL Output/0 读设备格式，在 Input/0 协商同采样率的 Float32 mono。多声道设备由公开 ChannelMap 将 mono 等幅映射到设备声道。同步检查映射、格式和最大回调帧数。 [输出单元](https://github.com/JerryYork3516/Eterna_Aftelle/blob/91ffc37b71166f8f588845f9adc7d157278c5104/apps/macos/NativeVoiceTransport/NativeVoiceSplitAUHAL.swift#L26-L106) · [设备与客户端格式](https://github.com/JerryYork3516/Eterna_Aftelle/blob/91ffc37b71166f8f588845f9adc7d157278c5104/apps/macos/NativeVoiceTransport/NativeVoiceSplitAUHAL.swift#L128-L153) · [Apple AUHAL 合同](https://developer.apple.com/library/archive/technotes/tn2091/_index.html) |
| VPIO 与播放环 | 复用 Direct VPIO 的 EnableIO、输入输出设备与格式协商，维持 Apple AGC ON、Bypass/InputMuted OFF。VPIO 的采集与静音输出继续使用其匹配客户端率。会话给 Worker 的播放率取 AUHAL 的实际客户端率。只有 AUHAL 安装原 `nvt_direct_vpio_render`，VPIO 静音回调没有读环或产生 ACK 的边。 [控制接线](https://github.com/JerryYork3516/Eterna_Aftelle/blob/91ffc37b71166f8f588845f9adc7d157278c5104/apps/macos/NativeVoiceTransport/NativeVoiceDirectVPIO.swift#L113-L201) · [C 回调](https://github.com/JerryYork3516/Eterna_Aftelle/blob/91ffc37b71166f8f588845f9adc7d157278c5104/apps/macos/NativeVoiceTransport/NativeVoiceRealtime.c#L538-L579) |
| 时标与代际 | VPIO 采集与 AUHAL 播放各传递本次系统回调的 SampleTime、HostTime 和有效位。原身份、取消门限与时钟资格继续使用。静音回调不参与播放时标。EOS 与 clear ACK 保持数字消费者语义，物理完成和双设备同步未知。 [采集回调](https://github.com/JerryYork3516/Eterna_Aftelle/blob/91ffc37b71166f8f588845f9adc7d157278c5104/apps/macos/NativeVoiceTransport/NativeVoiceRealtime.c#L490-L535) · [原消费者与时标](https://github.com/JerryYork3516/Eterna_Aftelle/blob/91ffc37b71166f8f588845f9adc7d157278c5104/apps/macos/NativeVoiceTransport/NativeVoiceRealtime.c#L363-L447) |
| DEBUG 实验 | `--apple-native-voice-split-auhal-candidate` 只在原有授权 DEBUG 单参数入口中选择。保留现有 15 秒同帧窗口、固定居民素材、排程和本机 WAV 导出。诊断额外记录 AUHAL 读回设备、两种输出客户端格式和双单元释放收据。 [启动选择](https://github.com/JerryYork3516/Eterna_Aftelle/blob/91ffc37b71166f8f588845f9adc7d157278c5104/apps/macos/NativeVoiceTransport/NativeVoiceSameFrameLaunch.swift#L1-L53) · [窗口导出](https://github.com/JerryYork3516/Eterna_Aftelle/blob/91ffc37b71166f8f588845f9adc7d157278c5104/apps/macos/Aftelle/AftelleApp.swift#L522-L554) |

Xcode 只登记两个 Swift 源文件。生产 AVAudioEngine、原 Direct VPIO 的单单元接法、Worker、SRC、C11 Ring、Runtime、Provider、DR schema 及正式声源、时钟与取消门限保持原实现。Apple VP 是本候选的回声处理单元。

## 双单元生命周期

1. 控制侧占用既有 Direct VPIO 独占 slot。先协商 VPIO，再创建、绑定及协商静止的 AUHAL。两种角色共享已有 C 回调 context 与 lease。
2. 为两边安装回调，按 VPIO、AUHAL 的顺序初始化和启动。双方实际运行状态、客户端格式、最大回调容量、设备绑定与路由监听复核通过后，原传输层才激活 lease。启动阶段的回调无法交付采集或居民 PCM。
3. 单元属性变化会关闭共享 lease。C 回调先隔离代际与迟到 PCM，原传输控制再回滚两边。初始化失败、启动失败、路由或格式失配沿同一路径收尾。
4. 先关闭 lease，再尝试释放 AUHAL 与 VPIO。各自记录 Stop、监听移除、Uninitialize 和 Dispose。任一释放报告失败均保留关闭的 lease、context 本身与独占 slot，直到进程结束。健康关闭只释放一次。 [协调与释放](https://github.com/JerryYork3516/Eterna_Aftelle/blob/91ffc37b71166f8f588845f9adc7d157278c5104/apps/macos/NativeVoiceTransport/NativeVoiceDirectVPIO.swift#L183-L236) · [独立收据](https://github.com/JerryYork3516/Eterna_Aftelle/blob/91ffc37b71166f8f588845f9adc7d157278c5104/apps/macos/NativeVoiceTransport/NativeVoiceDirectVPIOCleanup.swift#L7-L69)

## 离线收据

| 检查 | 本轮结果 |
| --- | --- |
| 正常专项、TSan、ASan/UBSan | 均退出 0。每种模式执行 265 项 C 与 385 项 Swift 断言，包含 8 个独立释放故障进程。TSan/ASan 没有报告。C/ObjC++ 同时覆盖 UBSan，Swift 覆盖 ASan。 [C 专项](https://github.com/JerryYork3516/Eterna_Aftelle/blob/91ffc37b71166f8f588845f9adc7d157278c5104/tools/native_voice_direct_vpio_tests/CallbackTests.c#L137-L171) · [双单元用例](https://github.com/JerryYork3516/Eterna_Aftelle/blob/91ffc37b71166f8f588845f9adc7d157278c5104/tools/native_voice_direct_vpio_tests/SplitAUHALTests.swift#L4-L215) |
| 实时调用图 | Clang IR O0/O2 分别检查 32／16 个可达函数。VPIO 静音与 AUHAL 消费路径均纳入原约束，回调侧没有 Swift、分配或锁等待。既有 `AudioUnitRender` 是 VPIO 的系统输入边。 [调用图检查](https://github.com/JerryYork3516/Eterna_Aftelle/blob/91ffc37b71166f8f588845f9adc7d157278c5104/tools/native_voice_transport_p2_tests/audit_callbacks.py#L41-L67) |
| 同帧及受影响回归 | 同帧 150 项 Swift 断言与 C 组通过。P1 1,770 项、P2 114 项 Swift 断言及各自 C 功能用例通过。P1/P2 的完整脚本仍因历史阶段白名单在 `guard.py:48` 退出 1，原规则维持。 |
| 附加 P3/P4 | C 侧 3 组实时事实、P4 内容时间 fence 通过。Controller 试验因基线与工作树均缺少忽略的 `resident_stage7_5_fixture_v1.digital_resident`，在导入夹具断言退出 133。P3/P4 Controller 仍 BLOCKED。 |
| Debug／Release | Xcode 27.0（27A266a），arm64，独立 DerivedData，两配置均 `BUILD SUCCEEDED`。Debug 用带原设备与证据授权编译条件的构建配置验证接线。两配置均关闭 Xcode 代码签名，构建产物未运行。Debug dylib 有候选参数、`nvt_split_vpio_silence` 和原真实消费者。Release 应用及独立 Release C 对象的候选入口／符号检查通过。 |
| 其他门槛 | Architecture、Secret、Release Route Guard 与 `git diff --check` 通过。SwiftLint 0.59.1 与 SwiftFormat 0.57.2 相对固定基线未增诊断。既有格式诊断保持原样。专项脚本以项目 26.5 部署目标对应的 SDK 运行，保留 `-Werror`。 |

Debug dylib SHA-256 `1f8bd3b2bd52d446f7f91eff7441acac1d03e7d0f10f6bd2764fcad6d61fb277`。Release 可执行文件 SHA-256 `a1b18b2759ea5558523926b8165d8c7cb983b3d8a699d7f2d0c4f4a364e6a804`。

## 实机边界

现有本机同帧窗口、固定原幅 WAV 和 0/3/11/15 秒排程已经接线。实机配置仍要求 TinyUSB 60.49%、Mac mini 内置扬声器 59.86%、Standard Mic Mode、Apple AGC ON、Bypass/InputMuted OFF。实际双单元启动、绑定、AGC、采集和消费者同一试次见证要在独立授权后核对。候选离线通过不能证明 Apple 内部 AEC 参考有效或改善双讲。

Stage 7 Forbidden Checklist **PASS**。触及红线 0，新增平台 target 0，未进入 Stage 8。交付后停止，等待独立审核及实机授权。

```ini
SPLIT_AUHAL_CANDIDATE = PASS
SPLIT_AUHAL_REALTIME = PASS
SPLIT_AUHAL_LIFECYCLE = PASS
SPLIT_AUHAL_HARDWARE = NOT_RUN
SPLIT_AUHAL_ACOUSTIC = NOT_RUN
AEC_ROOT_CAUSE = UNKNOWN
CLOCK_ROOT_CAUSE = UNKNOWN
SQ_M1 = OPEN
Formal_Test3 = BLOCKED
Test3.execution_authorized = false
DEVICE_RUNS_THIS_TASK = 0
```
