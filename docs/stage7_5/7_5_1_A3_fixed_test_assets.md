# Stage 7.5.1-A3 / A3R · 固定测试资产与 STS 配置冻结

## 1. 任务范围与结论

本文件记录 Stage 7.5.1-A3 固定测试资产基线，以及 A3R 对 STS 配置和本地居民分发方式的正式决议。A3R 只解除配置阻塞，不实现 NativeSpeechProvider、StepFun Adapter、WebSocket、音频、字幕、取消或 fallback。

**当前 A3 状态：`PASS`。** StepFun、模型、音色、Endpoint、音频格式、Server VAD、独立 Keychain `key_ref` 和本地 fixture 分发方式均已由主控明确。真实 API Key 未写入，连接测试未执行并归属 7.5.2，因此不影响 A3 配置冻结通过。

本次没有修改 Swift、Metal、Runtime 公共 API、Xcode 工程配置、DR 内容/schema、`.gitignore`、Studio 仓库或 `docs/03_dev_plan.md`。

## 2. 权威来源

- 规划唯一权威：`docs/03_dev_plan.md` 的 Stage 7.5 专节。
- 架构边界：`docs/stage7_5/7_5_1_A2_realtime_speech_architecture_boundary.md`。
- A2 冻结 Commit：`87bbc28415af3321452a2596b2475431141689d6`。
- A3 基线 Commit：`ec243b3158e437723c031cc6d1bde67a6146157a`。
- STS 配置权威：主控在 Stage 7.5.1-A3R 下达的固定配置决议。
- 工作与安全边界：仓库根目录 `AGENTS.md`、`docs/stage7_forbidden_checklist.md`。

A3R 的具体 Provider 配置是测试配置决议，不改变 A2 冻结的厂商无关架构：RuntimeCore 仍是逻辑语音会话唯一 owner，ExecutionEngine 仍是 Provider 副作用唯一执行门，ProviderRouter 仍是唯一能力路由点，供应商协议只能位于后续 Concrete Adapter/transport 边界。

## 3. A3R 配置决议

主控正式确定 StepFun 为 Stage 7.5 首个原生 STS Provider，冻结配置如下：

| 字段 | 固定值 |
|---|---|
| Provider | `StepFun` |
| capability | `native_speech` |
| provider_profile_id | `stage7_5_stepfun_realtime_primary` |
| adapter_id | `stepfun_realtime` |
| model | `stepaudio-2.5-realtime` |
| voice | `linjiajiejie` |
| voice_source | `stepfun_official` |
| transport | `websocket` |
| endpoint | `wss://api.stepfun.com/v1/realtime?model=stepaudio-2.5-realtime` |
| input_audio_format | `pcm16` |
| output_audio_format | `pcm16` |
| turn_detection.type | `server_vad` |
| turn_detection.prefix_padding_ms | `500` |
| language_metadata | `zh-CN` |
| fallback_enabled | `false` |
| fallback_implementation_stage | `7.5.11` |

`server_vad` 与 `prefix_padding_ms: 500` 是固定测试基线，不是最终体验参数；动态判停与 VAD 调优归属 7.5.6。A3R 未连接 WebSocket，也没有验证 Provider 可用性。

## 4. 固定居民信息与 SHA-256

| 项目 | 冻结值 |
|---|---|
| 原始文件路径 | `/Users/jerryyork/Downloads/linxuan (46).digital_resident` |
| 固定本地路径 | `apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident` |
| distribution_mode | `local_fixture` |
| resident_id | `dr_eterna_hum_cn_xian_linxuan_0001` |
| DR schema version | `0.3.0` |
| 顶层 schema version | `0.4.0` |
| protocol version | `0.4.0` |
| revision | `1` |
| 文件大小 | `9,058,396 bytes` |
| required_sha256 | `f30d4b2ac33c3598918de992a8178f90b776109d54e3ac33fd88764dde7d1881` |
| 来源 Stage | `7.4`（任务指定） |
| 当前 DRLoader | PASS，`runtime-expression-tests: 220 checks passed` |

原文件与本地 fixture 的 SHA-256 相同，`cmp -s` 字节比较通过。居民没有被修改、重新导出或重新编译。

## 5. 本地居民分发规则

Manifest 冻结以下机器可校验规则：

```text
distribution_mode: local_fixture
required_local_path: apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident
required_sha256: f30d4b2ac33c3598918de992a8178f90b776109d54e3ac33fd88764dde7d1881
```

- `.digital_resident` 继续受 `.gitignore:17` 的 `*.digital_resident` 规则保护，不进入 Git。
- 不使用 `git add -f`，不修改 `.gitignore`，不将居民加入 App bundle Resources。
- 新开发机或 CI 必须在固定本地路径提供文件，并在测试前重算 SHA-256。
- 路径缺失或哈希不一致时必须停止，不得重新导出、修改或用其他居民替代。
- Manifest 是测试配置，不是 DR 的一部分，不修改 DR schema。

## 6. 凭据与 Keychain 安全边界

Realtime API 使用 StepFun 平台 API Key，鉴权语义为 Bearer。A3R 只冻结安全引用：

```text
key_ref: keychain://com.eterna.aftelle.provider.stepfun/stepfun_realtime_api_key
```

现有工程的 `key_ref` 固定为 `keychain://<service>/<account>` 形式；因此 A3R 沿用该格式，并为 StepFun Realtime 使用独立 service/account，不覆盖现有 DeepSeek LLM 的 `keychain://com.eterna.aftelle.provider.deepseek/primary-text-llm`。

- 本任务没有读取、索取、测试或写入真实 API Key。
- Manifest 的 `actual_key_written` 固定为 `false`。
- `Authorization` header 只能在后续 Adapter/transport 边界由 Keychain 读取结果构造，不能保存到 Manifest、DR、Session、Memory、Trace、日志或 Git。
- 当前 `ProviderKeychainStore` 只实现现有 LLM 引用；A3R 不修改 Swift。7.5.2 必须在不覆盖 LLM 项的前提下接入上述独立引用。
- `connectivity_test_status` 为 `NOT_RUN`，`connectivity_test_owner_stage` 为 `7.5.2`。

## 7. 固定设备环境

| 项目 | 冻结值 |
|---|---|
| 主测试主机 | Mac mini M4（Mac16,10，16 GB） |
| macOS | 26.5.2 |
| 项目 deployment target | macOS 26.5 |
| Xcode | 26.6（17F113） |
| 构建 | Aftelle Debug |
| 主输入设备 | `system_default_input` |
| 主输出设备 | `system_default_output` |
| 路由测试设备 | AirPods Pro 2 |
| 自动切换设备 | 不允许；场景必须显式声明路由 |
| 前台运行 / 后台监听 | 是 / 否 |
| 用户 / 居民 | 单用户 / 单居民 |
| 默认语言 | `zh-CN` |
| 默认网络 | `stable_outbound_internet` |
| 默认噪声条件 | `quiet_indoor` |

A3R 没有修改系统设置、默认音频设备或麦克风权限。

## 8. 固定测试场景

四个场景统一使用 `stage7_5_stepfun_realtime_primary` 和固定本地居民：

| scenario_id | 输入 / 输出 | 预期链路 | 实现节点 | 当前可执行 |
|---|---|---|---|---|
| `primary_native_sts` | system default / system default | AppController → OrchestrationKernel → RuntimeCore → ExecutionEngine → ProviderRouter → NativeSpeechProvider → StepFun Adapter → 标准 Runtime 事件 → Session/Memory/Trace → 字幕/ParticleCore | 7.5.2–7.5.10 | 否 |
| `airpods_route` | AirPods Pro 2 / AirPods Pro 2 | Audio Host 路由变化 → Runtime canonical interaction → 当前 STS 音频输入输出恢复 | 7.5.3、7.5.8、7.5.13 | 否 |
| `provider_unavailable` | system default / system default | StepFun route unavailable → ProviderRouter 标准 outcome → RuntimeCore 决定 fallback 或 canonical failure close | 7.5.11 | 否 |
| `cancelled_interaction` | system default / system default | Stop/Interrupt/新请求 → 统一主动取消 → 停字幕/播放 → ParticleCore idle → Session/Trace 单次收口；拒绝迟到事件 | 7.5.7、7.5.9、7.5.12 | 否 |

`currently_executable: false` 表示 A3R 没有实现或运行这些真实语音场景，不表示配置仍未决议。

## 9. Manifest 字段说明

- Manifest `schema_version` 由 `0.1.0` 更新为 `0.2.0`，记录配置决议；它不是 DR schema。
- `status: PASS` 表示 A3 配置与资产分发规则已冻结。
- `resident.distribution_mode`、`required_local_path`、`required_sha256` 定义本地资产准入条件。
- `primary_native_speech.configuration_status: RESOLVED` 表示 Provider 配置已决议。
- `actual_key_written: false` 与 `connectivity_test_status: NOT_RUN` 明确区分“配置已冻结”和“真实凭据/连通性尚未执行”。
- `turn_detection.tuning_owner_stage: 7.5.6` 与 `fallback_implementation_stage: 7.5.11` 防止 A3R 提前实现后续节点。
- `scenarios` 继续只冻结后续验收入口，不宣称功能已完成。

## 10. 7.5.2–7.5.13 使用规则

1. 后续节点默认使用同一 fixture 路径、resident_id 和 SHA-256。
2. Provider、模型、音色、Endpoint、格式和语言统一读取 Manifest，不在 RuntimeCore 中写死。
3. 7.5.2 使用固定 profile 定义最小 NativeSpeechProvider/Adapter 边界，并负责独立 Keychain 引用接线和首次连通性测试。
4. 7.5.6 才能调优 Server VAD 和动态判停；变更测试基线需更新 Manifest 版本。
5. 7.5.11 才能实现 fallback；A3R 的 `fallback_enabled` 保持 `false`。
6. 后续节点不得修改 fixture；哈希变化必须重新评审。
7. Secret 始终通过 Keychain/安全凭据读取，生产配置与本测试配置必须可区分。
8. RuntimeCore、ExecutionEngine、ProviderRouter 和 Concrete Adapter 的 A2 边界不可绕过。
9. Studio 不参与 A3R，也不承担 Provider 测试配置。

## 11. A3R 配置收口状态

A3 中的配置阻塞项已全部收口：

- Provider profile、Adapter、Provider、模型、音色：已决议。
- Endpoint、transport、PCM16 输入输出：已决议。
- Server VAD 基线及调优节点：已决议。
- 独立 Keychain `key_ref`：已决议，真实 Key 未写入。
- fallback 状态与实现节点：已决议。
- 真实 DR 分发：已决议为 `local_fixture`，不进入 Git。

剩余的“实现、真实 Key 写入、Provider 连通性、音频与体验调优”属于 7.5.2 或后续节点，不是 A3R 配置阻塞。

## 12. 验收结果

| 验收项 | 结果 | 证据/说明 |
|---|---|---|
| Manifest JSON 语法 | PASS | `jq -e` |
| Manifest 无 `UNRESOLVED` | PASS | 文本扫描无命中 |
| fixture 路径与 SHA-256 | PASS | 固定本地文件存在，重算为 `f30d4b…1881` |
| 当前 DRLoader | PASS | `runtime-expression-tests: 220 checks passed` |
| Debug build | PASS | Aftelle Debug：`BUILD SUCCEEDED` |
| Architecture guard | PASS | `architecture-guard: ok` |
| Secret guard | PASS | `secret-guard: ok`；未出现真实 Key |
| Stage 7 checklist | PASS | 未实现实时语音或触碰 Runtime/DR/平台边界 |
| Git diff 范围 | PASS | 仅 Manifest 与本报告 |
| Provider 配置 | PASS | 主控正式决议，Manifest 已落盘 |
| 真实 API Key | PASS | 未读取、未索取、未测试、未写入 |
| `docs/03_dev_plan.md` | PASS | 本任务未修改、未暂存、未提交 |

A3R 判定为 `PASS`，具备进入 7.5.1-A4 的配置前置条件；真实 Provider 连接仍只能由 7.5.2 执行。

## 13. 本次变更文件

- 修改并提交：`apps/macos/Aftelle/Fixtures/Stage7_5/stage7_5_test_assets.json`
- 修改并提交：`docs/stage7_5/7_5_1_A3_fixed_test_assets.md`
- 保持本地且不提交：`apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident`

未修改任何功能/测试代码、Swift、Metal、Xcode 工程配置、DR、`.gitignore`、其他文档或 `docs/03_dev_plan.md`。
