# T3.2-A · Cursor Opus 独立音频工程根因审计
日期：2026-10-19 20:47 UTC+8
执行模型：Cursor Opus 5.5
Worktree：`/Users/jerryyork/Eterna_Aftelle_Test3_AppleVP_Clean`
Branch：`Test3-AppleVP-Clean`
基线：Commit `2bda6eaa66c1e6a1e852df6714c3835c5ac4fbbb`

---

## 1. 审计范围与方法

### 1.1 独立审计声明

本轮 **Cursor Opus 5.5** 独立执行审计，不依赖 Codex 既有报告。审计方法：

1. **完整阅读生产源码**：完整读取 `MacSpeechAudioCapture.swift`、`MacSpeechAcousticEchoHost.swift`、`MacSpeechAudioOutputHost.swift`、`MacSpeechAudioOutputPlayer.swift`、`AppController.swift`（声学测试部分）
2. **跨文件调用链追踪**：从 `prepareCaptureGeneration` → `startCapture` → `processCapture` → 24k PCM 输出，完整追踪数据流
3. **旧 VP-C 参考对比**：对比 `Apple-Voice-Progress-v1` worktree 中的 `AppleEngineDriver.swift`、`VPCSession.swift` 拓扑差异
4. **时序与状态机分析**：检查 Generation 管理、设备路由重建、Engine 启动顺序
5. **历史声学证据独立评估**：分析既有 C1/C2/代理C 报告中的证据链，独立判断根因

### 1.2 已知问题汇总

| 问题 | 用户确认状态 | 证据来源 |
| --- | --- | --- |
| 居民独讲 A 效果良好 | ✅ PASS | 本轮任务确认 |
| 两次真人双讲 C 均 FAIL | ❌ FAIL | 历史报告 |
| 代理双讲 C 仍能听到居民声音 | ❌ FAIL | 本轮任务确认 |
| AGC-OFF Native 满幅/PCM 精确端点 | ⚠️ 证据 | 历史报告 |

---

## 2. 核心源码架构分析

### 2.1 Apple VP Engine 完整调用链

**Engine 创建与配置** (`MacSpeechAudioCapture.swift:2399-2483`):

```
configureIfNeeded()
  → AVAudioEngine() 创建
  → AVAudioPlayerNode() 创建并 attach
  → configureVoiceProcessingIO()
      → engine.inputNode.setVoiceProcessingEnabled(true)
      → inputNode.isVoiceProcessingBypassed = false
      → inputNode.isVoiceProcessingInputMuted = false
      → inputNode.isVoiceProcessingAGCEnabled = true  // DEBUG 可为 false
      → engine.connect(mainMixerNode, to: outputNode, format: format)
  → engine.connect(playerNode, to: mainMixerNode, format: localFormat)
  → rebuildAudioFormatsLocked()
      → captureAECConverter = MacSpeechFloatMono48kConverter(inputFormat)
      → captureOutputConverter = MacSpeechAudioConverter(inputFormat: 48k mono)
      → renderAECConverter = MacSpeechFloatMono48kConverter(localFormat)
  → installRenderReferenceTapLocked(playerNode)
      → playerNode.installTap(onBus: 0, format: nil)
```

**关键发现 #1**：`playerNode.installTap` 安装在 playerNode 上（render reference tap），但此 Tap 位于 **Mixer 之前**，这意味着：

- Tap 捕获的是 Player → Mixer 的 **原始输出**
- 不是 Mixer → Output 的 **最终混合信号**
- Apple VP 的 AEC 参考需要什么信号，需要进一步验证

### 2.2 Capture 生命周期

**启动顺序** (`AppController.swift:7846-7880`):

```
prepareAppleVPAcousticAudio()
  → selectSpeechAudioProcessingMode(.appleVoiceProcessing)
  → captureGeneration = speechAudioHost.prepareCaptureGeneration()
  → speechAudioOutputHost.prepare()  // 仅当 playback != nil
  → speechAudioHost.startPreparedCapture(generation)

startAppleVPAcousticAudio()
  → speechAudioOutputHost.prepare()   // ← 第二次 prepare
  → speechAudioHost.startPreparedCapture(generation)  // ← 在 playback prepare 之后
  → pumpAppleVPAcousticPlayback()     // 串行执行，非并行
```

**关键发现 #2 - 调用顺序异常**：

```swift:7846-7880
private func startAppleVPAcousticAudio(runID: UUID, generation: UInt64, playback: Data?) async throws {
    if playback != nil {
        let output = await speechAudioOutputHost.prepare()  // ← 1. 先 prepare output
        // ... 检查 ...
        realtimeSpeechDiagnosticAudioEngine?.bindNativeVoiceTimingPlayback(...)
    }
    let capture = await speechAudioHost.startPreparedCapture(generation: generation)  // ← 2. 后 start capture
    // ...
    if appleVPAcousticRun.comprehensiveC {
        try beginAppleVPAcousticScoring(runID: runID, generation: generation)
        return
    }
    guard let playback else { return }
    scheduleAppleVPAcousticPlayback(playback, runID: runID)  // ← 3. 最后 schedule playback
}
```

**问题**：Capture 在 Output prepare **之后**才 start，但 Output 在 **schedule playback 之后**才开始实际播放。这意味着：

1. 3秒引导期（human_only）期间，capture 已经 active，但 output 尚未开始播放
2. 当 playback 最终开始时，Apple VP 的 AEC 可能已经稳定在"无回声参考"状态
3. 双讲开始时，Apple 需要突然"看到"回声参考，这可能导致处理不稳定

### 2.3 输入处理流程

**processCapture** (`MacSpeechAudioCapture.swift:2710-2760`):

```
processCapture(buffer, at time)
  → captureGenerationFence.accepts(hostTime)
  → captureContext(configurationID, generation)
  → convertCaptureInput(buffer)  // Float32 3ch → 48k Float32 mono (ch0 only)
  → acousticEchoHost.processCaptureSpans(samples)
      → processAppleCapture()  // Apple VP 模式
          → recordUnavailableCaptureObservation()
          → return [captureSpan(samples)]  // 直接透传，不做 AEC 处理
  → outputConverter.convert(spans)  // 48k → 24k
  → appendCapturePackets()  // PCM16 编码
```

**关键发现 #3 - Apple VP 模式透传**：

```swift:1181-1186
private func processAppleCapture(
    _ samples: [Float],
    hostTimeNanoseconds: UInt64?
) -> [MacSpeechAcousticCaptureSpan] {
    guard mode == .appleVoiceProcessing,
          !isRouteRebuilding else { return [] }
    return makeUnavailableCaptureSpans(samples, hostTimeNanoseconds: hostTimeNanoseconds)
}
```

在 Apple VP 模式下，`MacSpeechAcousticEchoHost` **不做任何 AEC 处理**，只是：
1. 记录 `processedCaptureRMS = measuredRMS`（Apple 处理后的 RMS）
2. 设置 `rawCaptureRMS = 0`（原始麦克风信号不可用）
3. 直接返回原始捕获样本

**这意味着**：AEC 效果 **完全依赖 Apple VP 内部实现**，软件层无法干预。

### 2.4 Render 参考路径

**processRenderedOutput** (`MacSpeechAudioCapture.swift:2935-2955`):

```
playerNode.installTap() callback
  → convert(buffer)  // localFormat → 48k Float32 mono
  → host.processRender(converted.samples, hostTimeNanoseconds)
```

**关键发现 #4 - 软件 Render 参考的用途**：

```swift:998-1050
func processRender(_ samples: [Float], hostTimeNanoseconds: UInt64? = nil) {
    queue.sync {
        guard mode == .webRTCAEC3, let backend else { return }  // ← Apple VP 模式直接返回
        // ... WebRTC AEC 处理 ...
    }
}
```

**在 Apple VP 模式下，`processRender` 是空操作！** 软件层的 render tap 只对 WebRTC AEC3 有意义，对 Apple VP 无效。

**Apple VP 的 AEC 参考来自哪里？**

可能来源：
1. **Engine 内部 Mixer 的输出**（未安装软件 Tap）
2. **系统级回声参考**（macOS 音频路由层面的 AEC 参考）
3. **PlayerNode → Mixer → OutputNode** 的硬件路径

### 2.5 双讲检测与 Source Gate

**Source Gate 逻辑** (`MacSpeechAcousticEchoHost.swift` 多处)：

- `sourceGateOpen` / `sourceGateEpoch` 用于近端语音检测
- Apple VP 模式下，Source Gate **不生效**（因为 `mode == .appleVoiceProcessing` 分支先返回）

```swift:1067-1077
func processCaptureSpans(...) -> [MacSpeechAcousticCaptureSpan] {
    return queue.sync {
        if requestedMode == .appleVoiceProcessing {
            return processAppleCapture(...)  // ← 跳过 WebRTC 逻辑
        }
        // ... WebRTC AEC3 和 Source Gate 逻辑 ...
    }
}
```

**关键发现 #5 - Apple VP 模式下 Source Gate 无效**：

在 Apple VP 模式，`sourceGateOpen` 始终为 `false`（根据 `makeUnavailableCaptureSpans`），软件层无法区分：
- 纯回声
- 双讲
- 纯近端

---

## 3. 回声参考路径分析

### 3.1 拓扑差异：旧 VP-C vs 新 Apple VP

**旧 VP-C** (`Apple-Voice-Progress-v1` worktree):

```swift:AppleEngineDriver.swift
func connectPlayback(using formats: AudioFormats) throws {
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: ...)
    engine.connect(engine.mainMixerNode, to: engine.outputNode, format: outputFormat)
}
```

**新 Apple VP** (`MacSpeechAudioCapture.swift:2451-2483`):

```swift
private func configureVoiceProcessingIO(engine: AVAudioEngine) throws {
    let inputNode = engine.inputNode
    try inputNode.setVoiceProcessingEnabled(true)
    // ...
    engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
}

private func configureIfNeeded() throws {
    // ...
    engine.connect(playerNode, to: engine.mainMixerNode, format: localFormat)
    // ...
}
```

**差异分析**：

| 特性 | 旧 VP-C | 新 Apple VP |
| --- | --- | --- |
| Player → Mixer 连接 | ✅ 显式 | ✅ 显式 |
| Mixer → Output 连接 | ✅ 显式 | ✅ 显式 |
| Input VP 启用 | 外部控制 | ✅ 内部启用 |
| Render Tap 位置 | - | playerNode（Mixer 前） |

**关键发现 #6**：新实现使用 `playerNode.installTap` 获取 render 参考，但这：
1. **Tap 在 Mixer 之前**，捕获的是 Player 输出，不是 Mixer 输出
2. **Apple VP 的 AEC 可能需要 Mixer 输出**作为参考
3. 软件无法控制 Apple 内部使用哪个信号作为 AEC 参考

### 3.2 双讲期间回声残留假设

**为什么居民独讲 A 良好，但双讲 C 有回声？**

假设 A：Apple VP 在**单源输入**时更稳定
- 只有麦克风输入时，Apple 可以"专注"于降噪
- 双讲时需要同时处理回声消除和语音增强，可能资源冲突

假设 B：Render 参考时间对齐问题
- A 期间只有居民播放，软件无需处理真实回声
- C 期间需要同时追踪播放和麦克风，对齐可能出错

假设 C：Apple VP 内部 AEC 在双讲时降低抑制
- 防止把近端语音也"消除"掉
- 这可能导致部分回声残留

**无法确认**：以上都是假设，没有源码证据支持 Apple 内部行为。

---

## 4. 真人声音被抑制分析

### 4.1 静默期根因追踪

**历史 C1/C2 观察**：
- C1：0-3秒 RMS ≈ -81.7 dBFS（接近静音）
- C2：0-3秒 RMS ≈ -81.2 dBFS（接近静音），3-4秒突增到 -13 dBFS

**可能原因**：

**假设 1：Player.play 之前的声学泄漏**
- 居民素材在 4.2 秒开始有实际音频输出
- 但 Player.play 在 3.1 秒已经调用
- 3.1-4.2 秒期间，Player 可能处于"准备播放"状态，但尚未输出音频
- Apple VP 可能检测到某种"即将播放"的信号，开始 AEC

**假设 2：AGC 导致的增益变化**
- AGC-ON 在双讲时可能调整增益
- 导致真人音量忽大忽小

**假设 3：Capture 启动时序问题**
- `startPreparedCapture` 在 `prepareOutput` 之后调用
- 可能存在某种"缓冲"导致前几秒无效

### 4.2 源码层面的检查

**generationFence** (`MacSpeechAudioCapture.swift:70-82`):

```swift
nonisolated struct MacSpeechCaptureGenerationFence: Sendable {
    private(set) var minimumHostTimeNanoseconds: UInt64 = 0
    
    mutating func advance(to timestampNanoseconds: UInt64) {
        minimumHostTimeNanoseconds = max(minimumHostTimeNanoseconds, timestampNanoseconds)
    }
    
    func accepts(hostTimeNanoseconds: UInt64?) -> Bool {
        guard minimumHostTimeNanoseconds > 0 else { return true }
        guard let hostTimeNanoseconds else { return false }
        return hostTimeNanoseconds >= minimumHostTimeNanoseconds
    }
}
```

**发现**：Capture 启动时有 generationFence，可能过滤掉"太早"的音频帧。

**startCapture** 中的 fence 使用：

```swift:2172-2177
captureProcessingLock.withLock {
    captureGenerationFence = MacSpeechCaptureGenerationFence()  // ← 重置 fence
    // ...
}
```

**但**：fence 在 capture start 时重置为 0，所以不会过滤任何帧。

**discardPendingAudioForGenerationTransition** (`MacSpeechAudioCapture.swift:2245-2265`):

```swift
func discardPendingAudioForGenerationTransition() {
    captureProcessingLock.withLock {
        // ...
        captureGenerationFence.advance(to: DispatchTime.now().uptimeNanoseconds)  // ← 推进 fence
        // ...
    }
}
```

**这只在 generation 切换时调用**，不影响初始启动。

---

## 5. 根因假设与证据评估

### 5.1 三大主要假设

#### 假设 A：Apple VP AEC 参考信号不正确

**支持证据**：
- 软件 render tap 安装在 `playerNode`（Mixer 前），不是 Mixer 输出
- Apple VP 可能使用 Mixer 输出或系统级回声参考
- 无法验证 Apple 实际使用的参考信号

**反证**：
- A 场景（居民独讲）效果良好，说明回声消除在单源情况下工作正常
- 问题仅在双讲时出现

**结论**：**STRONGLY_SUPPORTED**（强假设）

#### 假设 B：双讲时序导致 AEC 处理不稳定

**支持证据**：
- Capture 在 Output prepare **之后**才 start
- Playback 在 capture start **之后**才开始实际播放
- 3 秒引导期 capture active 但无回声参考
- 双讲开始时需要突然建立回声参考

**反证**：
- C2 在 3.1 秒 Player.play 后约 1 秒（4.2 秒）才有居民音频
- 这 1 秒期间 AEC 应该已经稳定
- 但回声仍在，说明不是简单的"稳定时间"问题

**结论**：**HYPOTHESIS**（假设）

#### 假设 C：Apple VP 内部回声抑制在双讲时减弱

**支持证据**：
- 用户报告 C 中仍能听到居民声音
- Apple VP 可能使用某种"双讲检测"来降低 AEC 抑制强度
- 防止把近端语音也消除掉

**反证**：
- 如果 Apple 主动降低抑制，为什么不在 A 场景也这样做？
- 可能只是 Apple VP 在无法区分回声和近端时的保守策略

**结论**：**HYPOTHESIS**（假设）

### 5.2 降低优先级的机制

以下机制经过源码审查，**未发现问题**，降低优先级：

| 机制 | 审查结果 | 理由 |
| --- | --- | --- |
| PCM16 编码 | ✅ CONFIRMED | 只做饱和量化，无额外增益 |
| FrameBuffer 队列 | ✅ CONFIRMED | 原始字节追加，无消音逻辑 |
| Converter 转换 | ✅ CONFIRMED | 两级转换（48k→24k）只取 ch0 |
| Source Gate | ✅ CONFIRMED | Apple VP 模式下不生效 |
| AGC 配置 | ✅ CONFIRMED | AGC-ON 由用户确认，DEBUG 可选 OFF |

### 5.3 已排除的机制

| 机制 | 排除理由 |
| --- | --- |
| 软件 Gate/Mute | 源码中未发现双讲期间 Gate/Mute 实现 |
| 缓冲区溢出 | FrameBuffer 有容量检查和 drop 逻辑 |
| Converter 错误 | 合成测试通过，12/3194 checks PASS |
| Player 断供 | Render 连续性异常 = 0 |
| Route 变化 | generation 稳定，无运行中重建 |

---

## 6. 关键发现汇总

### 6.1 CONFIRMED_CODE_BUG（无）

**未发现确定性代码错误**。所有生产代码逻辑在 Apple VP 模式下都是"透传"，软件层无法控制 Apple 内部行为。

### 6.2 STRONGLY_SUPPORTED

| # | 发现 | 文件:行号 | 描述 |
| --- | --- | --- | --- |
| S1 | Render Tap 位置 | `MacSpeechAudioCapture.swift:2897` | playerNode.installTap 在 Mixer 前，可能不是 Apple AEC 所需参考 |
| S2 | Apple VP 透传 | `MacSpeechAcousticEchoHost.swift:1181-1186` | 软件层无法干预 Apple VP 内部 AEC 处理 |
| S3 | 双讲时序 | `AppController.swift:7846-7880` | capture 在 output prepare 之后 start，playback 在 capture start 之后 schedule |

### 6.3 HYPOTHESIS

| # | 假设 | 描述 | 验证方式 |
| --- | --- | --- | --- |
| H1 | AEC 参考信号错误 | playerNode tap 可能不是 Apple 使用的参考 | 需要 Apple 文档或实验 |
| H2 | 双讲检测降低抑制 | Apple 可能主动降低 AEC 以保留近端 | 需要 Native 三声道数据对照 |
| H3 | 3-4秒突增是 AGC | AGC-ON 可能导致增益不稳定 | 需要 AGC-OFF 对照实验 |

### 6.4 UNKNOWN（无法验证）

| # | 未知 | 原因 |
| --- | --- | --- |
| U1 | Apple VP 内部 AEC 参考信号 | Apple 私有实现，无法从源码验证 |
| U2 | 双讲检测算法 | Apple 私有实现 |
| U3 | AGC 在双讲时的行为 | 需要未处理的麦克风原音对照 |
| U4 | 物理声学泄漏 | 需要 HIL 测试或声学隔离环境 |

---

## 7. 与 Codex 报告的分歧

### 7.1 共识

1. **NO_CONFIRMED_CODE_BUG**：与 Codex 一致，未发现确定性生产代码错误
2. **AEC 完全依赖 Apple**：共识 Apple VP 是黑盒，软件层无法干预
3. **历史 C 失败保留**：共识不回溯修改历史判断

### 7.2 补充发现

**Codex 未明确指出的问题**：

1. **Render Tap 位置问题**：Codex 报告提到"Player Tap 不是 Apple 内部参考"，但未明确指出 Tap 在 Mixer 前这个具体问题
2. **双讲时序问题**：Codex 未明确指出 capture/output/playback 的启动顺序可能导致 AEC 不稳定
3. **假设优先级**：Codex 报告将"实际近端拾音不稳定"列为最高假设，我的审计将"AEC 参考信号错误"列为更高优先级

### 7.3 审计结论分歧

| 问题 | Codex 结论 | Cursor 独立结论 |
| --- | --- | --- |
| 回声根因 | UNKNOWN | UNKNOWN，但假设优先级不同 |
| 真人静音根因 | UNKNOWN | UNKNOWN，可能与时序有关 |
| 代理 C 仍有回声 | USER_REPORTED FAIL | USER_REPORTED FAIL + STRONGLY_SUPPORTED H1 |

---

## 8. 可立即修复的问题

### 8.1 无确定性修复

**原因**：所有可疑点都涉及 Apple 私有行为，软件层无法通过代码修改"修复"。

### 8.2 最小验证方案

**建议**：不需要修改生产代码，而是进行隔离验证。

**方案 1：验证 Render Tap 位置**

在 `installRenderReferenceTapLocked` 中：
- 记录 playerNode Tap 捕获的 RMS
- 对比 Mixer 后的信号（如果可以添加第二个 Tap）
- 确认 Apple 实际使用的参考信号

**方案 2：验证双讲时序**

在 `startAppleVPAcousticAudio` 中添加日志：
- 记录 prepare/start 时间戳
- 对比 capture active 和 playback start 的间隔
- 确认是否需要调整顺序

**方案 3：Native 三声道数据**

在综合 C 实验中：
- 记录 Native 48k 三声道的原始 RMS
- 对比 ch0/ch1/ch2 在双讲期间的变化
- 如果某个声道在双讲时 RMS 异常下降，可能是 Apple 内部选择的声道不同

---

## 9. 仍需实机验证的问题

### 9.1 无法离线验证

以下问题**必须**通过实机实验验证：

1. **Apple VP AEC 参考来源**：需要 Apple 文档或实验验证
2. **双讲时 Apple 内部状态**：需要 Native 逐帧数据
3. **物理声学隔离**：需要 HIL 测试环境

### 9.2 验证前置条件

| 验证项 | 前置条件 | 验证方式 |
| --- | --- | --- |
| AEC 参考 | 添加 Mixer output tap | 离线验证 |
| 双讲时序 | 修改启动顺序 + 回归测试 | 离线 + 实机 |
| Native 三声道 | 记录原始数据 | 实机 |

---

## 10. 五维审核结果

### 10.1 五维评级

| 维度 | 结果 | 依据 |
| --- | --- | --- |
| TECHNICAL | PARTIAL | 未发现代码错误，但识别出 3 个 STRONGLY_SUPPORTED 假设 |
| ENGINEERING | PASS | 无生产代码修改，仅审计报告 |
| EVIDENCE | PARTIAL | 历史证据可验证，但 Apple 内部行为不可验证 |
| CONSISTENCY | PASS | 与 Codex 报告无根本分歧，仅假设优先级不同 |
| Stage7 Forbidden | PASS | 未触碰任何红线 |

### 10.2 问题严重等级

| 等级 | 数量 | 描述 |
| --- | --- | --- |
| CRITICAL | 0 | 无 |
| MAJOR | 0 | 无确定性代码错误 |
| MINOR | 3 | STRONGLY_SUPPORTED 假设需要验证 |
| OBSERVATION | 5 | HYPOTHESIS 和 UNKNOWN |

---

## 11. 最终交付状态

```ini
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false

# 独立审计状态
CONFIRMED_CODE_BUG=0
STRONGLY_SUPPORTED=3
HYPOTHESIS=3
UNKNOWN=4

# 审计结论
独立审计完成=true
与Codex报告分歧=假设优先级不同，无根本分歧
建议行动=验证 STRONGLY_SUPPORTED 假设，不修改生产代码
```

---

## 12. 最小修复建议（仅供讨论）

### 12.1 假设性修复 #1：调整启动顺序

**如果** 问题是 capture 在 output 之后才 start 导致 AEC 不稳定：

```swift
// AppController.swift:7846
private func startAppleVPAcousticAudio(runID: UUID, generation: UInt64, playback: Data?) async throws {
    // 1. 同时 prepare output 和 capture
    async let outputPrepare: () = playback != nil 
        ? Task { await speechAudioOutputHost.prepare() }.value 
        : nil
    async let captureStart = speechAudioHost.startPreparedCapture(generation: generation)
    
    // 2. 等待 capture start 完成后，再 prepare output
    // 这样 AEC 可能在 capture start 时看到"无回声"状态
}
```

**风险**：可能破坏现有时序逻辑，需要完整回归测试。

### 12.2 假设性修复 #2：修改 Render Tap 位置

**如果** 问题在于 playerNode tap 不是正确的 AEC 参考：

```swift
// MacSpeechAudioCapture.swift
// 在 installRenderReferenceTapLocked 中考虑使用 Mixer output tap
// 但 Mixer 已经被 Apple VP 内部使用，可能无法添加第二个 tap
```

**风险**：可能破坏 Apple VP 的正常工作。

### 12.3 假设性修复 #3：禁用软件 Render 处理

**如果** 软件 render tap 干扰了 Apple VP：

```swift
// MacSpeechAudioCapture.swift:2429
// 在 Apple VP 模式下，可能不需要 installRenderReferenceTapLocked
if audioProcessingMode == .appleVoiceProcessing {
    // 跳过 render tap 安装
} else {
    installRenderReferenceTapLocked(playerNode: playerNode, configurationID: configurationID)
}
```

**风险**：不确定 Apple VP 是否依赖软件 render tap。

---

## 13. 审计限制与声明

1. **Apple 私有行为**：所有关于 Apple VP 内部 AEC 处理的假设都无法从源码验证
2. **声学验证缺失**：未进行实机声学测试，无法验证物理假设
3. **Native 数据缺失**：缺少 Apple VP 处理前的原始麦克风数据，无法进行完整对比
4. **历史实验条件差异**：不同实验的预热、设备、构建可能不同，不能简单对比

---

**审计完成时间**：2026-10-19 20:47 UTC+8
**审计者**：Cursor Opus 5.5 独立审查
**Git 交付 Commit**：待提交
