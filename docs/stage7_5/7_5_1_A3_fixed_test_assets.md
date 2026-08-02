# Stage 7.5.1-A3 · 固定测试资产与测试配置冻结

## 1. 任务范围与结论

本任务只冻结 Stage 7.5 后续开发与验收使用的居民资产、Provider/语音配置字段、设备基线、四个测试场景和机器可读 Manifest，不实现任何实时语音功能。

**A3 状态：`BLOCKED_BY_CONFIGURATION`。** 固定居民已复制到本地稳定路径，字节、哈希、JSON 与当前 `DRLoader` 加载均通过；设备环境与四个场景已冻结。但是权威来源没有给出 Provider profile ID、Adapter ID、Provider、模型、音色、Endpoint 来源和 `key_ref`，这些字段必须保持 `UNRESOLVED`。此外，仓库安全规则通过 `.gitignore` 禁止真实 `.digital_resident` 进入 Git，因此本地 fixture 不可随提交分发。这两个阻塞项解决前不得进入 7.5.1-A4。

本次没有修改 Swift、Metal、Runtime 公共 API、Xcode 工程配置、DR 内容/schema、Studio 仓库或 `docs/03_dev_plan.md`。

## 2. 权威来源

- 规划唯一权威：`docs/03_dev_plan.md` 的 Stage 7.5 专节。
- 架构边界：`docs/stage7_5/7_5_1_A2_realtime_speech_architecture_boundary.md`。
- A2 冻结 Commit：`87bbc28415af3321452a2596b2475431141689d6`。
- 工作规则与安全边界：仓库根目录 `AGENTS.md`、`docs/stage7_forbidden_checklist.md`。
- 居民来源：用户提供的 `/Users/jerryyork/Downloads/linxuan (46).digital_resident`；身份只取自当前 loader 可确认的 manifest/metadata，不根据文件名推测。

`03_dev_plan.md` 只冻结了 `NativeSpeechProvider`、首个 STS Adapter 与 7.5.11 fallback 的阶段顺序，没有批准具体厂商、profile、Adapter ID、模型、音色、Endpoint 或凭据引用。A2 冻结厂商无关边界，也明确不决定具体供应商配置。

## 3. 固定居民信息

| 项目 | 冻结值 |
|---|---|
| 原始文件路径 | `/Users/jerryyork/Downloads/linxuan (46).digital_resident` |
| 固定 fixture 路径 | `apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident` |
| resident_id | `dr_eterna_hum_cn_xian_linxuan_0001` |
| DR schema version | `0.3.0` |
| 顶层 schema version | `0.4.0` |
| protocol version | `0.4.0` |
| revision | `1` |
| 固定文件名 | `resident_stage7_5_fixture_v1.digital_resident` |
| 文件大小 | `9,058,396 bytes` |
| SHA-256 | `f30d4b2ac33c3598918de992a8178f90b776109d54e3ac33fd88764dde7d1881` |
| 来源 Stage | `7.4`（任务指定） |
| 验收状态 | 用户指定为已通过 Stage 7.4；仓库内未检出该路径、resident_id 或 SHA 的既有验收记录 |
| 当前 DRLoader | PASS，`runtime-expression-tests: 220 checks passed` |
| Secret 检查 | 未检出 API key、Bearer token 或常见 secret 值；命中的敏感词均为策略/授权状态字段名 |

居民内容没有被修改、重新导出或重新编译。复制后 `cmp` 一致。

### 3.1 Fixture 分发限制

`.gitignore:17` 明确忽略 `*.digital_resident`，`AGENTS.md` 同时规定真实居民永不进入 Git。因此该文件当前是固定的**本地文件系统测试 fixture**，不使用 `git add -f` 绕过规则，也不加入 App bundle Resources。Manifest 通过 `fixture_distribution: local_filesystem_test_fixture` 和 `git_ignored: true` 显式记录这一事实。

这与任务要求“将真实居民作为仓库内固定 fixture 并随提交交付”存在冲突。按安全规则，本报告只记录冲突，不改 `.gitignore`、Xcode 工程或居民。若 A4 要求在新 clone/CI 自动取得该资产，主控需先批准合规的私有资产分发方式，而不是提交真实 DR。

## 4. 居民 SHA-256 校验

| 校验项 | 结果 |
|---|---|
| 原文件 SHA-256 | `f30d4b2ac33c3598918de992a8178f90b776109d54e3ac33fd88764dde7d1881` |
| fixture SHA-256 | `f30d4b2ac33c3598918de992a8178f90b776109d54e3ac33fd88764dde7d1881` |
| 文件大小 | 两者均为 `9,058,396 bytes` |
| 字节比较 | `cmp -s` PASS |
| JSON 语法 | PASS |

后续 7.5.2–7.5.13 使用前必须重新计算 fixture SHA-256；任何哈希变化都视为资产变更，必须停止并重新评审，不能原地改写。

## 5. Provider 与语音配置

| 字段 | 冻结值 | 依据 |
|---|---|---|
| capability | `native_speech` | `03_dev_plan.md` Stage 7.5 / A2 |
| provider_profile_id | `UNRESOLVED` | 无权威批准值 |
| adapter_id | `UNRESOLVED` | 无权威批准值 |
| Provider | `UNRESOLVED` | 不得自行选择厂商 |
| model | `UNRESOLVED` | 不得自行选择模型 |
| voice | `UNRESOLVED` | 不得自行选择音色 |
| language | `zh-CN` | 居民 metadata 与固定测试语言一致 |
| endpoint_source | `UNRESOLVED` | 不得将 Endpoint 写死进 RuntimeCore |
| key_ref | `UNRESOLVED` | 只允许安全引用，当前尚未批准具体引用 |
| fallback_enabled | `false` | A3 不实现 fallback |
| fallback_implementation_stage | `7.5.11` | `03_dev_plan.md` |

具体 Provider、模型、音色与 Endpoint 不得从旧 mock/TTS 文档推导，也不得联网搜索或推荐。待主控确认后，只能更新 Manifest 版本和配置字段；不得把这些具体值写进 RuntimeCore 架构或 DR。

## 6. 凭据安全边界

- Manifest、DR、日志、Trace 和 Git 中禁止出现 API Key、Token、Secret 或 Provider 私有 session token。
- Manifest 只能保存安全凭据引用，例如批准后的 `key_ref`；真实 secret 继续由 Keychain/安全凭据存储读取。
- `key_ref: UNRESOLVED` 表示配置缺失，不是实际凭据，也不应作为运行值发送给 Provider。
- A3 未申请麦克风权限，未访问 Keychain，未写 Provider 配置，未产生音频或 Provider payload。
- 对居民执行常见 secret 模式扫描未检出实际 API key/Bearer token；包含 `credential_storage`、`authorization_status` 等名称的字段属于策略/状态 metadata，不是凭据值。

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
| 前台运行 | 是 |
| 后台监听 | 否 |
| 用户数 | 单用户 |
| 居民数 | 单居民 |
| 默认语言 | `zh-CN` |
| 默认网络 | 稳定外网连接（`stable_outbound_internet`） |
| 默认噪声条件 | 安静室内（`quiet_indoor`） |

本次只读取系统与工程版本信息，没有修改系统设置、默认音频设备或权限状态。

## 8. 固定测试场景

| scenario_id | resident fixture | provider profile | 输入 / 输出 | 语言 | 预期链路 | 实现节点 | 当前可执行 |
|---|---|---|---|---|---|---|---|
| `primary_native_sts` | 固定 v1 fixture | `UNRESOLVED` | system default / system default | zh-CN | AppController → OrchestrationKernel → RuntimeCore → ExecutionEngine → ProviderRouter → NativeSpeechProvider → Concrete STS Adapter → 标准 Runtime 事件 → Session/Memory/Trace → 字幕/ParticleCore | 7.5.2–7.5.10 | 否 |
| `airpods_route` | 固定 v1 fixture | `UNRESOLVED` | AirPods Pro 2 / AirPods Pro 2 | zh-CN | Audio Host 路由变化 → AppController → OrchestrationKernel → RuntimeCore 保持 canonical interaction → 恢复当前 STS 音频输入输出 | 7.5.3、7.5.8、7.5.13 | 否 |
| `provider_unavailable` | 固定 v1 fixture | `UNRESOLVED` | system default / system default | zh-CN | NativeSpeechProvider unavailable → ProviderRouter 标准 route outcome → RuntimeCore 决定 fallback → STT+LLM+TTS 或 canonical failure close | 7.5.11 | 否 |
| `cancelled_interaction` | 固定 v1 fixture | `UNRESOLVED` | system default / system default | zh-CN | Stop/Interrupt/新请求 → AppController → OrchestrationKernel → RuntimeCore → ExecutionEngine → ProviderRouter → Provider cancel/close → 停字幕/播放 → ParticleCore idle → Session/Trace 单次收口；拒绝迟到事件 | 7.5.7、7.5.9、7.5.12 | 否 |

A3 只冻结名称、输入条件、预期链和后续节点，不执行真实语音、设备切换、fallback 或取消测试。

## 9. Manifest 字段说明

- `schema_version`：测试资产 Manifest 自身版本；它不是 DR schema。
- `status`：A3 总体状态，当前为 `BLOCKED_BY_CONFIGURATION`。
- `resident`：固定路径、身份、版本、大小、哈希、来源与 DRLoader 结果；`git_ignored` 说明真实 DR 的版本控制边界。
- `primary_native_speech`：厂商无关能力与后续需批准的配置值；所有未批准值显式为 `UNRESOLVED`。
- `test_environment`：主机、构建、设备、语言、网络与噪声基线。
- `scenarios`：四个冻结验收场景；`currently_executable: false` 防止 A3 被误当作已实现功能。
- `blocking_configuration_fields`：主控必须精确补齐的字段清单。

Manifest 位于 Aftelle 的 `Fixtures/Stage7_5` 资源路径，但不作为 DR 的一部分，也不修改 DR schema。JSON Manifest 可进入 Git；真实 `.digital_resident` 仍由 ignore 规则保护。

## 10. 7.5.2–7.5.13 使用规则

1. 7.5.2–7.5.13 默认使用同一路径、同一 resident_id 和同一 SHA-256 的 v1 fixture。
2. Provider、模型、音色和语言默认读取同一 Manifest；未解决字段不得被代码中的临时常量替代。
3. 后续节点不得直接修改 fixture；哈希变化必须重新评审。
4. 测试参数变化必须提升 Manifest `schema_version` 或按主控批准的版本规则更新，不得静默覆盖。
5. Secret 始终通过 Keychain/安全凭据读取，只把安全引用交给 Provider 配置边界。
6. 生产配置与测试配置必须可区分；此 Manifest 只用于 Stage 7.5 测试。
7. Manifest 不是 DR 的一部分，不修改 DR schema，不写回居民。
8. Studio 不参与 A3，也不承担 Provider 测试配置。
9. RuntimeCore 继续作为逻辑语音会话唯一 owner；ExecutionEngine 与 ProviderRouter 不可绕过。
10. 在合规资产分发方式确定前，CI/新 clone 不得假定 fixture 已由 Git 提供。

## 11. 未解决配置项

进入 A4 前需主控确认以下精确字段：

1. `primary_native_speech.provider_profile_id`
2. `primary_native_speech.adapter_id`
3. `primary_native_speech.provider`
4. `primary_native_speech.model`
5. `primary_native_speech.voice`
6. `primary_native_speech.endpoint_source`
7. `primary_native_speech.key_ref`
8. 真实 DR 的合规分发方式：继续使用每台开发机的固定本地路径、受控私有资产仓库/下载流程，或由主控批准的其他不进 Git 方案

这些字段不得从文件名、旧计划、mock profile 或供应商宣传材料猜测。`UNRESOLVED` 不能作为运行配置。

## 12. 验收结果

| 验收项 | 结果 | 证据/说明 |
|---|---|---|
| Manifest JSON 语法 | PASS | `jq -e` |
| fixture 存在 | PASS（本地） | 固定路径存在，9,058,396 bytes |
| fixture 与原文件字节一致 | PASS | `cmp -s` |
| SHA-256 可重算且一致 | PASS | 两边均为 `f30d4b…1881` |
| 当前 DRLoader 加载 | PASS | `runtime_expression_tests` 220 checks passed |
| Secret 扫描 | PASS | 无常见实际 API key/token；Manifest 无 secret |
| 资源路径/target | PASS WITH CONSTRAINT | Manifest 与真实 DR 均位于固定 filesystem fixture 路径，不加入 App bundle target/Resources；Manifest 纳入 Git，真实 DR 按安全规则不进 Git |
| Debug build | PASS | `xcodebuild` Aftelle Debug：`BUILD SUCCEEDED` |
| Stage 7 checklist | PASS | architecture guard、secret guard 均通过；无功能实现、无高危边界变更 |
| Provider/model/voice/key_ref 明确 | FAIL | 权威来源未给出，均为 `UNRESOLVED` |
| 仅修改 A3 范围 | PASS | 仅 Manifest、报告与本地 ignored fixture |
| 未触碰 `docs/03_dev_plan.md` | PASS | 本任务未修改、未暂存、未提交该文件 |

综合判定：`BLOCKED_BY_CONFIGURATION`，不得伪报 PASS，不具备进入 7.5.1-A4 的条件。

## 13. 本次变更文件

- 新增并提交：`apps/macos/Aftelle/Fixtures/Stage7_5/stage7_5_test_assets.json`
- 新增并提交：`docs/stage7_5/7_5_1_A3_fixed_test_assets.md`
- 新增但按安全规则不提交：`apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident`（被 `*.digital_resident` ignore，固定本地 fixture）

未修改任何功能代码、测试代码、Xcode 工程配置、DR 内容/schema、其他文档或 `docs/03_dev_plan.md`。
