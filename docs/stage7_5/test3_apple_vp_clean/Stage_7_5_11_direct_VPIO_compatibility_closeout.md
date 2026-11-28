# Stage 7.5.11 · Direct VPIO 兼容性与资源释放收口

审核基线 `0d78cca260648de50183e158aa3be500e778e4ab`。[原候选设计及离线工程报告](Stage_7_5_11_direct_AUVoiceProcessingIO_candidate.md)

## 双向 EnableIO

基线在格式协商前强制写入两端 EnableIO。现在分别读取 Input scope / element 1 和 Output scope / element 0 的 `UInt32` 实值。读到 `1` 就继续，读到 `0` 才尝试写入并在成功后重读。读取或写入错误保留 OSStatus，错误字节数、非布尔值或重读仍为 `0` 都会在启动前阻断。原有启动前后双端校验继续执行。[Direct VPIO 协商](../../../apps/macos/NativeVoiceTransport/NativeVoiceDirectVPIO.swift#L108) · [Apple EnableIO](https://developer.apple.com/documentation/audiotoolbox/kaudiooutputunitproperty_enableio)

本机 SDK `AudioUnitProperties.h` 定义两端的 scope、element 和数据类型。Chromium 的 macOS `OpenVoiceProcessingAU` 在实例化后直接配置设备，未在该处无条件写入 EnableIO。这提供了兼容性对照，候选仍以逐端成功读回为准。[Chromium VPIO 初始化](https://chromium.googlesource.com/chromium/src/+/lkgr/media/audio/apple/audio_low_latency_input.cc#501)

## Audio Unit 关闭

基线丢弃了 Stop、反注册与 Uninitialize 的结果。若 Dispose 在安装回调前失败，重复关闭还可能释放独占 slot。现在每个实例只关闭一次。先关闭 lease，再依次执行适用的 `AudioOutputUnitStop`、逐项 `AudioUnitRemovePropertyListenerWithUserData`、`AudioUnitUninitialize` 和 `AudioComponentInstanceDispose`。每步保存实际 OSStatus，界面注明跳过的步骤。启动回滚采用同一顺序，并保留原始启动失败与释放收据。[关闭入口](../../../apps/macos/NativeVoiceTransport/NativeVoiceDirectVPIO.swift#L186) · [释放收据](../../../apps/macos/NativeVoiceTransport/NativeVoiceDirectVPIOCleanup.swift#L49) · [Apple Dispose](https://developer.apple.com/documentation/audiotoolbox/audiocomponentinstancedispose(_:))

所有适用步骤都成功时释放回调存储、lease 和 slot。任一步失败后仍完成其余适用步骤，已关闭的回调上下文和独占 slot 保留至进程退出。后续单元在创建前被拒绝，重复关闭保持原收据。此处理以 Chromium 在释放或 Stop 出错后仍可能收到回调的处理为依据。[Chromium 关闭路径](https://chromium.googlesource.com/chromium/src/+/lkgr/media/audio/apple/audio_low_latency_input.cc#1341)

现有 DEBUG 窗口读取控制侧收据并展示各项结果。发生释放失败时，技术导出使用 `outcome=cleanup_failed`，窗口报错并禁止同进程重启。故障发生在图就绪前时，窗口仍能显示释放收据。应用音频回调不读该收据。[DEBUG 导出与状态](../../../apps/macos/Aftelle/AftelleApp.swift#L528)

## 实际离线验收

| 检查 | 结果 |
| --- | --- |
| Direct VPIO normal、TSan、ASan/UBSan | 各退出 0，各含 241 项 C 断言及 244 项 Swift 断言。TSan 和 ASan/UBSan 未报告错误。Swift 运行 ASan，C/Objective-C++ 同时运行 ASan/UBSan。 |
| Fake 双向 EnableIO | 每端覆盖 7 个场景。包括只读且已启用、可写且未启用、只读且未启用、初读失败、重读失败、写入成功但仍为 `0`、非法值。 |
| Fake 关闭 | 正常关闭后可继续启动。6 个独立故障进程覆盖 Stop、逐监听器反注册、Uninitialize、Dispose、回调安装前 Dispose 失败与 Start 失败后的 Stop 失败，校验回滚、迟到回调、重复关闭和独占 slot。 |
| 同帧诊断 normal | 退出 0。150 项 Swift 断言与 1 组 C 用例通过。 |
| P2 受影响功能回归 | 4 组实时用例、4 个强制边界竞态、114 项 Swift 会话断言通过。完整脚本因既有阶段白名单断言退出 1。 |
| 实时与产物隔离 | Direct VPIO LLVM IR 调用图 O0/O2 通过。Release C object 无候选符号。Debug 与 Release 均在 Xcode 27.0（27A266a）构建成功。Debug dylib 包含候选参数、收据和回调符号，Release 可执行文件无这些标记及符号。 |
| 其他检查 | Architecture、Secret、Release Route Guard 通过。SwiftLint、SwiftFormat 相对基线无新增诊断。 |

阶段白名单 `tools/native_voice_transport_tests/guard.py:48` 在修改前已失败，本轮完整 P2 脚本仍在该处失败。白名单及历史记录保留。[阶段白名单](../../../tools/native_voice_transport_tests/guard.py#L48) · [Fake 用例](../../../tools/native_voice_direct_vpio_tests/DirectVPIOCloseoutTests.swift)

## Stage 7 Forbidden Checklist

**PASS**。改动限于 Direct VPIO、共享 DEBUG 窗口、Xcode 源文件登记、专项用例与本报告，触碰红线为零。生产 AVAudioEngine 后端、AEC、AGC、SRC、Ring、Runtime API、DR schema、Provider、正式插话与 SQ-M1 均沿用基线。未新增平台 target，未进入 Stage 8。结束后等待独立审核及实机授权。[Checklist](../../stage7_forbidden_checklist.md)

本轮仅构建及运行离线用例。真实 HAL EnableIO 的返回值、设备组合及声学结果待授权验证。

```ini
DIRECT_VPIO_COMPATIBILITY = PASS
DIRECT_VPIO_RESOURCE_LIFECYCLE = PASS
AEC_ROOT_CAUSE = UNKNOWN
CLOCK_ROOT_CAUSE = UNKNOWN
SQ_M1 = OPEN
Formal_Test3 = BLOCKED
Test3.execution_authorized = false
DEVICE_RUNS_THIS_TASK = 0
```
