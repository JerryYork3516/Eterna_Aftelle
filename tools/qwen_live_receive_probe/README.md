# 有界真实 Qwen 接收链 Probe

用途：自动捕获真实 Qwen 接收异常，减少无截止条件的人工重试。当前不是整链插话验收工具，不修生产算法。

## 覆盖与不覆盖

- 复用正式 RuntimeCore → ExecutionEngine / ProviderRouter → Qwen Adapter → WebSocket。
- 输入只接受已采集的 **16 kHz / mono / signed PCM16 little-endian** 裸 PCM，0.1–30 秒；无 WAV 头。源录音不修改、不复制到仓库、不包含在报告中。
- 同一录音先作为开场用户输入；收到第一批正式音频、且 Provider response 仍 active 时，再按 20 ms 节奏重放一次。五轮分别延迟 0 / 200 / 600 / 1000 / 0 ms，每轮是独立会话。每帧按实际时间发送，超过 100 ms 调度落后则停止，禁止突发追帧。
- 测试输入声明为 prerecorded post-AEC fixture activity；它不是 production AEC 检测结果，也不是 Source Gate 正控。真实 speech-start / transcript 必须来自 Provider。
- **不播放、不打开麦克风**。不调用 internal interruption seam，不注入 acoustic evidence，不直接调用 interrupt / generation bump / clear。
- **AEC、Source Gate、正式 Input/Output Bridge、AppController、物理 Playback、confirmed/cancel/clear、N+1 连续插话：NOT_TESTED。** 不能用该程序结果声称整个有线耳机 Human Gate 通过。
- 目标只是把当前真实 `invalid_event` 收敛到可重放的 codec / Adapter 状态错误。未触发错误为 `NOT_REPRODUCED`，不是 PASS/FROZEN。

## 命令

先离线自测（不会读取 Keychain 或连接网络）：

```sh
bash tools/qwen_live_receive_probe/run.sh --self-test
```

真实测试必须明确授权录音上传和 API 用量；命令中的文件须由用户提供：

```sh
bash tools/qwen_live_receive_probe/run.sh --live --allow-audio-upload \
  --pcm /absolute/path/sample.qwen-input.pcm --attempts 5 --seconds 300
```

使用当前正式 Qwen 非密钥 endpoint/model/voice（`Tina`）以及现有 `ProviderKeychainStore.qwenKeyRef`。配置与 AppController 的一致性由 `check.sh` 检查。密钥仅在 ProviderCredentialReading → Adapter 的内存链路内使用，不接受命令行/env 明文密钥、不导出 Keychain。通过 [Apple 的非交互认证属性](https://developer.apple.com/documentation/localauthentication/lacontext/interactionnotallowed) 请求禁止交互；不修改系统 Keychain 访问控制。该属性不等于同步系统调用一定及时返回：本机实测 `SecItemCopyMatching` 曾阻塞 222.48 秒，调用栈停在 Security Keychain 内容读取，此时 Swift 异步超时无法强制中断系统调用，最终进程上限由外层 watchdog 保障。

脱敏序列离线重放：

```sh
bash tools/qwen_live_receive_probe/run.sh --replay \
  --pcm /absolute/path/the-same.qwen-input.pcm \
  --wire /absolute/path/attempt-1/wire.ndjson --seconds 300
```

重放使用 fake credential，不联网。接收序列保留单调时距、发送计数屏障、事件顺序、缺失/null/错误类型、匿名 ID 等价关系。`sequence` 包含两帧初始 handshake，`adapterSequence` 对应其后的 Adapter receiver 序号（每轮只开一次连接）。**文字、音频、工具参数被替换，因此不是 bit-exact，不保证 semantic/Runtime 行为一致**；字段深度/数组亦有限制。必须比较实际错误分支，不能把重放成功退出当作复现。只能针对 codec/state 边界使用。

## 结束和证据

- 最多五轮、总运行上限 300 秒（不含编译）。启动单独限时 60 秒；正式 session ready 后重置控制进展时钟，之后 30 秒无语音控制进展才超时。总上限始终优先，启动耗时不会被误算为语音无进展。外层进程 watchdog 为 315 秒，覆盖同步系统调用或 teardown 卡住；首次异常停止后续轮次。
- `progress.json` 在 fixture 加载、session start / ready、首帧 append begin / completed、首个 speech / transcript / audio 和 overlap 时更新 monotonic 里程碑。`diagnostics.json` 额外记录 Keychain begin/end、transport connect begin/returned，不记录认证内容。`report.json` 含阶段、耗时、已完成输入帧和实际 wire audio append 数，可区分“尚未送音”和“送音后无回复”。
- 若所用录音没有使 Provider 产生两个用户回合，或没有在 response active 时真正送入音频并收到 speech-start，则为 `INCONCLUSIVE / coverageMissing`。
- 首次 Provider 接收错误优先于后续输入 `invalidIdentity`/teardown 错误，避免根因被清理噪声覆盖。报告在关闭会话前保存。
- 私有临时目录（umask 077）包含 `summary.json`、各轮 `report.json`、`diagnostics.json`、`wire.ndjson`、build/run logs、revision/修改文件清单。
- `wire.ndjson` 仅保存脱敏入站帧，不保存出站 instruction/audio/credential；报告记录 PCM SHA-256、输入格式、覆盖情况、实际发送节奏、Provider create/cancel/clear 计数。
- 正常结束/未复现退出 0；参数/自测错误退出 1；观察到异常、超时或覆盖不足退出 2；外层 watchdog 退出 124，并保留已写出的文件。
- Runtime Session/History/Memory 位于独立 `CFFIXED_USER_HOME` 临时目录，不污染 App 的实际会话；测试 fixture DR 本身只读。临时目录中可能有 Runtime 派生的对话数据，保持私有，不提交 Git。

本工具不会自动后台运行，不是 recurring automation；只有显式执行命令才会启动。

离线验证含 5 个协议场景（包括延迟连接后正常发送录音）、9 项输入/授权拒绝检查、6 项纯 monotonic 超时边界检查。延迟仅在 Fake Transport 用于测试启动时序，不改变线上发送/判断时序。

2026-09-05 修正后一次 live 运行结果：`TIMEOUT / startupTimeout`；Keychain 222.48 秒，随后 session.updated 约 0.24 秒，输入完成帧与 wire audio append 均为 0。没有复现生产 invalid_event，也没有覆盖真实插话。五个离线场景均通过不代表本机 Keychain 或 Human Gate 通过。

2026-09-06：授权后 live 序列复现输入 item ID 在 speech-start 与 final 间变化，导致两次 wire final 只交付一次。探针现在额外保留 `audio_start_ms / audio_end_ms`、脱敏 item / role / previous_item_id 及对应控制事件，并记录 Adapter 的关联/转写交付诊断。旧脱敏序列缺少起止时间，不能补造时间后冒充真实修复正控；新关联逻辑对此仍 fail closed。

修复后取得用户对指定录音上传 Qwen 的明确授权，仅跑一次最长 120 秒的 live，37.49 秒结束。实际再次发生 id_5 → id_6，保留的 audio start/end 为 11420/15620 ms；`qwen_input_item_reassociated = 1`、Runtime accepted final = 2、response.create = 2、error = none。该次新脱敏序列离线重放得到同样关联与交付计数，不再联网。两次 outcome 均为 `NOT_REPRODUCED`，仅验证已覆盖的 Adapter 输入关联边界；未覆盖物理插话、confirmed / clear / N+1，原真人 `invalid_event` 仍未复现，Human Gate 仍 FAIL / P1。
