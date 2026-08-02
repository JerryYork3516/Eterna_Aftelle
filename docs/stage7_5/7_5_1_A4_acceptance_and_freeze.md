# Stage 7.5.1-A4 · 整体验收、Gate 与正式冻结

> 验收日期：2026-08-02
> 验收分支：`7.5`
> 规划唯一权威：`docs/03_dev_plan.md` 的 Stage 7.5 专节
> 任务性质：只做验收与冻结；不实现实时语音功能

## 1. 任务范围

本任务对 Stage 7.5.1-A1、A2、A3/A3R 的工程盘点、架构边界、固定测试资产与 StepFun STS 配置执行整体验收，并冻结 7.5.2 的直接输入、允许范围与禁止范围。

本次不重新扫描源码，不重新选择 Provider，不修改既有 A1/A2/A3 报告或 Manifest，不执行真实 Provider 连接，不读取或写入真实 API Key。唯一变更是新增本验收报告。

## 2. 冻结基线与 Commit

| 基线 | Commit | 可追溯性 | 冻结产物 |
|---|---|---|---|
| A1 · Runtime 与接入点扫描 | `c514ad500825ca32017dbb441b0769affd6e7999` | PASS，commit 存在且为当前 HEAD 祖先 | `7_5_1_A1_runtime_architecture_inventory.md` |
| A2 · 实时语音架构边界 | `87bbc28415af3321452a2596b2475431141689d6` | PASS，commit 存在且为当前 HEAD 祖先 | `7_5_1_A2_realtime_speech_architecture_boundary.md` |
| A3 · 固定测试资产 | `ec243b3158e437723c031cc6d1bde67a6146157a` | PASS，commit 存在且为当前 HEAD 祖先 | A3 报告与 Manifest 初始基线 |
| A3R · STS 配置与本地分发收口 | `280330011c589fb6e0295a82024fe2adae478e21` | PASS，commit 存在且为 A4 验收 HEAD | A3R 报告与 Manifest `0.2.0` |

Git 基线检查结果：当前分支为 `7.5`，A4 开始前工作区干净；A1、A2、A3 报告和 Manifest 均存在。`docs/03_dev_plan.md` 没有被本任务修改、暂存或提交。

## 3. A1 验收结果

**A1 Gate：PASS。**

A1 通过源码定义与调用引用完成了现有 Runtime、Provider、取消、字幕、ParticleCore、Session/Memory/Trace 以及音频/网络现状盘点，且明确区分当前真实文字 Provider 链与同步 mock/Runtime API 兼容链。

已验收的工程事实：

- 当前真实文字链为 ContentView → AppController → OrchestrationKernel → RuntimeCore → ExecutionEngine → ProviderRouter → OpenAICompatibleAdapter → Session/Memory → 字幕 → ParticleCore。
- ExecutionEngine 与 ProviderRouter 是后续实时语音必须复用和扩展的接入骨架。
- 当前仅有取消状态、request ID 失效和迟到结果拒绝；尚无主动 Provider、播放与字幕统一取消。
- 字幕当前为整段文本三态；ParticleCore 已有 listening/thinking/speaking/idle 消费入口，但 listening 尚无生产入口。
- Session/Memory 适合复用 final-only 语义；Tool/Permission 尚不存在；Trace 尚未覆盖完整真实 Provider 主链。
- 当前工程不存在 AVFoundation、AVAudioEngine、Speech、麦克风采集、本地播放或 WebSocket 实现。

A1 没有把缺失能力伪装成已实现能力，也没有根据文件名猜测调用链，满足 A2 冻结所需的工程事实基线。

## 4. A2 验收结果

**A2 Gate：PASS。**

A2 已完整冻结 Stage 7.5 实时语音主链、降级链、逻辑 session owner、资源 owner、三类流、标准事件、主动取消与迟到拒绝双防线、Store/表现层边界及 7.5.2–7.5.13 依赖顺序。

核心冻结结论：

1. 原生 STS 是主链，STT + LLM + TTS 只作为级联降级链。
2. RuntimeCore 是 resident/session/interaction、逻辑状态、取消、提交资格和 Session/Trace 收口的唯一逻辑 owner。
3. AppController / macOS Audio Host 只拥有授权、设备、采集、播放和平台 buffer 等本地资源。
4. ExecutionEngine 是所有 Provider 副作用的唯一执行门。
5. ProviderRouter 是 STS/STT/LLM/TTS Adapter 的唯一选择与路由点。
6. NativeSpeechProvider 是厂商无关能力边界；StepFun 专用协议只能位于 Concrete Adapter/transport。
7. RuntimeCore 不持有 AVFoundation 类型，Host 不直连 Provider。
8. Adapter 不访问 DR、Memory、Session、字幕或 ParticleCore，不决定 fallback、Tool、Permission 或最终提交。
9. 控制流、输入/输出音频流与标准事件流方向明确，均受当前 Runtime interaction 约束。
10. 主动取消负责停止成本与副作用，迟到事件拒绝负责抵御竞态；二者必须同时存在。
11. 字幕只消费 Runtime 标准 transcript/cancel/closed 事件；ParticleCore 只消费 `ResidentVisualIntent` 与 `ResidentSpeechSignal`。
12. Session 只保存最终有效文本和已完成轮次；partial、原始音频、chunk、Provider message 和播放 buffer 默认不持久化。

未发现 A1 工程事实与 A2 架构职责之间的冲突。

## 5. A3 / A3R 验收结果

**A3/A3R Gate：PASS。**

A3 固定了居民、设备环境与四个测试场景；A3R 进一步由主控正式确定 StepFun 原生 STS 配置，并将真实居民的分发方式收口为 `local_fixture`。Manifest `schema_version` 为 `0.2.0`，顶层 `status` 为 `PASS`，不存在 `UNRESOLVED`。

已冻结场景：

- `primary_native_sts`
- `airpods_route`
- `provider_unavailable`
- `cancelled_interaction`

四个场景都保持 `currently_executable: false`，因为 Stage 7.5.1 只冻结输入，不实现或运行真实语音能力。

## 6. 架构 Gate

| Gate | 结果 | 冻结依据 |
|---|---|---|
| RuntimeCore 单一逻辑 session owner | PASS | A2 第 1、5 节 |
| Audio Host 本地资源 owner | PASS | A2 第 1、5、6 节 |
| ExecutionEngine 唯一 Provider 副作用入口 | PASS | A2 第 1、3、6 节 |
| ProviderRouter 唯一路由 | PASS | A2 第 1、3、6 节 |
| NativeSpeechProvider 厂商无关 | PASS | A2 第 3、6、13 节 |
| StepFun 专用逻辑只在 Concrete Adapter | PASS | A2 第 3、6、13 节；A3R 配置不改变架构 |
| RuntimeCore 不持有 AVFoundation 类型 | PASS | A2 第 3、6、8、15 节 |
| Host 不直连 Provider | PASS | A2 第 3、6、13、15 节 |
| Adapter 不访问 DR/Memory/Session/字幕/ParticleCore | PASS | A2 第 6、12、13、15 节 |
| 控制流方向 | PASS | A2 第 7 节 |
| 输入/输出音频流方向 | PASS | A2 第 8 节 |
| 标准事件流方向 | PASS | A2 第 9 节 |
| 主动取消 + 迟到事件拒绝 | PASS | A2 第 10 节 |
| Session final-only | PASS | A2 第 9、12 节 |
| partial/原始音频/buffer 默认不持久化 | PASS | A2 第 8、9、12 节 |

架构 Gate 结论：职责单一、方向明确、Provider 专用逻辑隔离，没有发现平行 Runtime、Host 直连 Provider 或 Adapter 越权等责任冲突。

## 7. 固定资产与配置 Gate

### 7.1 固定居民

| 字段 | 冻结值 | 验收 |
|---|---|---|
| distribution_mode | `local_fixture` | PASS |
| required_local_path | `apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident` | PASS，文件存在 |
| resident_id | `dr_eterna_hum_cn_xian_linxuan_0001` | PASS |
| required_sha256 | `f30d4b2ac33c3598918de992a8178f90b776109d54e3ac33fd88764dde7d1881` | PASS，重算完全一致 |
| Git 分发 | `.digital_resident` 不进入 Git | PASS |

fixture 未被修改、重新导出或强制提交；`.gitignore` 未修改。

### 7.2 StepFun STS 配置

| 字段 | 冻结值 | 验收 |
|---|---|---|
| Provider | `StepFun` | PASS |
| capability | `native_speech` | PASS |
| profile ID | `stage7_5_stepfun_realtime_primary` | PASS |
| adapter ID | `stepfun_realtime` | PASS |
| model | `stepaudio-2.5-realtime` | PASS |
| voice | `linjiajiejie` | PASS |
| voice source | `stepfun_official` | PASS |
| transport | `websocket` | PASS |
| endpoint | `wss://api.stepfun.com/v1/realtime?model=stepaudio-2.5-realtime` | PASS |
| input/output | `pcm16` / `pcm16` | PASS |
| turn detection | `server_vad` | PASS |
| prefix padding | `500 ms` | PASS |
| language metadata | `zh-CN` | PASS |
| key_ref | `keychain://com.eterna.aftelle.provider.stepfun/stepfun_realtime_api_key` | PASS，独立于现有 LLM 引用 |
| fallback | 关闭；实现归属 `7.5.11` | PASS |
| connectivity | `NOT_RUN`；归属 `7.5.2` | PASS |

配置 Gate 结论：Manifest 与主控冻结配置逐字段一致；未执行真实 WebSocket 连接。

## 8. 安全与隐私 Gate

**安全与隐私 Gate：PASS。**

- Manifest 只记录独立 `key_ref`，`actual_key_written` 为 `false`。
- 未读取、索取、测试或写入真实 StepFun API Key。
- 未构造或发送真实 `Authorization` header。
- Secret 未进入 DR、Manifest、Session、Memory、Trace、日志或 Git。
- 原始音频、音频 chunk、播放 buffer 和完整 Provider payload 均未产生或持久化。
- DR 保持只读和本地分发；未修改 DR schema、居民内容或 `.gitignore`。
- 未申请麦克风权限，未修改 entitlement 或系统音频设置。
- `secret_guard` 通过。

## 9. Build 与自动检查结果

| 检查 | 结果 | 证据 |
|---|---|---|
| Manifest JSON | PASS | `jq -e` |
| Manifest 无 `UNRESOLVED` | PASS | 文本扫描无命中 |
| Manifest `status` | PASS | 值为 `PASS` |
| fixture SHA-256 | PASS | 重算为 `f30d4b…1881` |
| DRLoader / runtime-expression | PASS | `220 checks passed`，source boundary checks ok |
| Debug build | PASS | Aftelle Debug：`BUILD SUCCEEDED` |
| Architecture guard | PASS | `architecture-guard: ok` |
| Secret guard | PASS | `secret-guard: ok` |
| Stage 7 forbidden checklist | PASS | 只新增验收文档，无功能实现或边界越权 |

Stage 7 checklist 最小输出：

```text
结论: PASS
触碰的红线: 无
修改文件列表:
- docs/stage7_5/7_5_1_A4_acceptance_and_freeze.md
是否改代码: 否
是否改 Runtime API: 否
是否改 DR schema: 否
是否新增平台 target: 否
是否进入 Stage 8: 否
是否需要停止并请求确认: 否
```

`docs/stage7_forbidden_checklist.md` 与其他旧文档仍含“Voice Input MVP / 禁止实时双向语音”的旧口径。依任务规则，这些冲突只记录、不修改；Stage 7.5 范围以 `docs/03_dev_plan.md` Stage 7.5 专节为准。本任务只做文档验收，没有实现实时双向语音，因此 checklist 仍为 PASS。

## 10. 7.5.2 允许直接使用的输入

A4 PASS 后，7.5.2 可以直接使用以下冻结输入：

1. RuntimeCore 是 resident/session/interaction 的唯一逻辑 owner。
2. ExecutionEngine 是所有 Provider 副作用的唯一执行门。
3. ProviderRouter 是 STS/STT/LLM/TTS 的唯一路由点。
4. NativeSpeechProvider 的职责是厂商无关 start/input/interrupt/stop 生命周期与标准事件。
5. 标准事件类别包括连接、语音活动、partial/final transcript、thinking、output transcript/audio、tool request、error、cancelled 和 closed。
6. 新能力必须支持主动取消；现有 request/session/cancellation guard 继续作为迟到事件拒绝防线。
7. StepFun 固定 profile：`stage7_5_stepfun_realtime_primary`。
8. StepFun Adapter ID：`stepfun_realtime`；模型 `stepaudio-2.5-realtime`；音色 `linjiajiejie`。
9. 固定 endpoint、WebSocket transport、PCM16 输入输出和 Server VAD 500ms 前缀基线。
10. 独立 Keychain 引用：`keychain://com.eterna.aftelle.provider.stepfun/stepfun_realtime_api_key`。
11. 固定本地居民路径、resident_id 与 SHA-256。
12. 首次 connectivity test 归属 7.5.2；测试不得把真实 Key 或 Provider payload 写入日志/Git。
13. 可替换注入点和测试 double 是 7.5.2 的直接验收输入。

## 11. 7.5.2 严禁提前实现的内容

7.5.2 只允许实现最小 NativeSpeechProvider、首个 StepFun Adapter、Router/ExecutionEngine 内部接入、interaction 绑定、主动取消能力与测试 double。以下内容继续冻结到后续节点：

- 不实现 AVFoundation 或平台音频类型。
- 不申请麦克风权限，不修改 entitlement/usage description。
- 不实现真实录音与播放。
- 不实现完整 WebSocket 音频流、重连、backpressure 或 buffer 系统。
- 不实现流式字幕。
- 不实现动态判停调优；Server VAD 调优归属 7.5.6。
- 不实现插话 UI 与完整 Provider/playback/subtitle/state 取消收口；归属 7.5.7。
- 不实现 Tool / Permission；归属 7.5.10。
- 不实现 fallback；归属 7.5.11。
- 不实现完整 Trace 系统；归属 7.5.12。
- 不修改 DR、DR schema 或固定 fixture。
- 不将 StepFun、模型、Endpoint、codec 或供应商事件类型写死进 RuntimeCore 架构。
- 不建立绕过 RuntimeCore、ExecutionEngine 或 ProviderRouter 的平行语音 Runtime。
- 不让 Host 直连 StepFun，不让 Adapter 访问 DR、Session、Memory、字幕或 ParticleCore。

## 12. 已知限制

以下是已冻结且不阻塞 7.5.2 的已知限制：

1. NativeSpeechProvider、StepFun Adapter 与多能力 Router 尚未实现；这是 7.5.2 的目标。
2. StepFun 真实 connectivity test 尚未执行，状态为 `NOT_RUN`，归属 7.5.2。
3. 真实 API Key 尚未写入 Keychain；7.5.2 只能通过独立 `key_ref` 在安全边界内读取，不得覆盖现有 LLM 项。
4. 当前取消只能标记状态并拒绝迟到结果，不能主动停止 Provider Task；最小 Provider 主动取消能力从 7.5.2 开始，完整联合收口归属 7.5.7。
5. 当前没有 macOS 音频资源、权限、WebSocket 音频流、播放、流式字幕或完整 Trace 实现，分别归属后续节点。
6. 固定居民采用 `local_fixture`，不会随 Git clone 分发；运行 Gate 前必须在固定路径提供并校验 SHA-256。
7. A2 有意不冻结最终 Swift 协议形状、连接复用、平台无关帧细节、背压、状态机、播放时序、字幕 revision、fallback 策略或 Trace schema；这些由对应节点决定。
8. A1/A2 记录的旧文档口径冲突仍存在；本任务不修改冲突文档，Stage 7.5 专节继续作为规划唯一权威。

## 13. 最终状态

**A4 最终状态：`PASS`。**

PASS 条件已全部满足：A1/A2/A3R 基线完整且可追溯；Manifest 有效、无未决字段且状态为 PASS；固定居民存在且哈希一致；DRLoader、Debug build、Architecture guard、Secret guard 与 Stage 7 checklist 全部通过；未发现架构责任冲突；未修改任何功能代码；7.5.2 的直接输入与禁止范围已经明确。

Stage 7.5.1 至此正式完成并冻结，具备进入 Stage 7.5.2「NativeSpeechProvider 协议与首个 STS Adapter」的条件。

## 14. 本次变更文件

新增并提交：

- `docs/stage7_5/7_5_1_A4_acceptance_and_freeze.md`

未修改或提交：

- `docs/03_dev_plan.md`
- A1、A2、A3/A3R 报告
- Stage 7.5 测试 Manifest
- Swift、Metal、Xcode 工程配置、entitlements 或 Runtime 公共 API
- DR、DR schema、固定 `.digital_resident` 或 `.gitignore`
- 其他冲突文档
