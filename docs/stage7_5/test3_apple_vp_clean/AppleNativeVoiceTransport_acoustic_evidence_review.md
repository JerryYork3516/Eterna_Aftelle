# AppleNativeVoiceTransport · 最小声学证据补充与首次实机执行单

2026-11-25（Asia/Shanghai）。P1–P4 与 Gemini 架构审核沿用主控 PASS。冻结回退源码 `c9838c99a5fd2d965587f5601a5c0377e1f58026`，远端冻结交付 `5b02e0e7bcd03dd27cdc6c9aab1ae8eccc9e8919`。本机待审核的证据补充源码 `7ec9ba04151b6e593b5b0180a65701ab15d22ca2`。

## 采集与封存合同

| 证据 | 记录点与内容 |
| --- | --- |
| VP 后上行 | 候选 Input Bridge 通过既有身份校验后，在原 Runtime `sendFrame` 前复制 24 kHz Mono PCM16LE，每包 480 samples／960 bytes。保存采集与提交序号、P1 内容段和采样偏移、内容 HostTime 与资格。播放身份是排出采集包时的软件状态。Runtime 返回成功或失败单独记录，封存前未观察到的结果标为 `pending`。 |
| 居民数字参考 | Controller 核对已有 Provider 事件和播放身份后，在候选 enqueue 前复制下行原幅 PCM。保存 Provider 序号与时间、turn／response、提交播放 token、Host 返回状态及返回 token。 |
| 实际回调与图 | 复用 P4 Source／Sink、格式、VP、路由、时钟和真实丢帧／欠载读回。保存读回时刻与 Scope 匹配结果。身份变化后的读回需要用当时同 Scope 的技术 JSON 补证。 |

档案身份包含配置、采集 token、Runtime generation 与 route epoch。两条音频以 Base64 保存于单个 schema 1 JSON，含运行载荷 SHA-256。证据争用、身份／格式拒绝、元数据缺失及容量截断由 `evidenceLoss` 独立计数。实际采集缺失和播放欠载沿用 P4 技术计数。下行数字参考的时间属于 Provider，物理声压和 Apple 内部参考仍为 UNKNOWN。Runtime 返回成功只证明本机调用结果，远端接收资格需要独立证据。

## 单次授权与隐私

录证默认关闭。实际能力只编入具备两项专用授权条件的 DEBUG 候选。用户在下一次会话开始前须独立选择「候选声学证据 → 授权一次采集」。授权从同意起算，每候选进程只绑定一次会话，最多 180 秒、合计 20 MiB、16,384 条及单块 256 KiB。限额、身份变化、会话结束或撤回均切断录证。录证争用时立即返回，音频链继续。撤回清除仍待封存的内存证据。已明确确认并开始写入的事务保持独占封存状态，界面据实际结果报告。

「确认本机封存」单独触发 Utility 后台任务。复用现有私有写入校验，并以原子独占提交生成一个 JSON。路径为应用本机 `Library/Caches/com.eterna.aftelle.debug-native-voice-evidence/run-<UUID>.json`，目录 `0700`、文件 `0600`。技术 JSON 和录证保存入口各自独立。本机封存、导出、试听、分析及外发各按后续授权。

## 实际文件及零实时路径改动

| 文件 | 职责 |
| --- | --- |
| `MacSpeechNativeAcousticEvidence.swift` | 专用授权宏、非等待记录、单次绑定、限额、结果及证据缺口。 |
| `MacSpeechRealtimeBrainInputBridge.swift` | 既有 Runtime 提交点记录 VP 后上行。 |
| `MacSpeechNativeRealtimeSession.swift`、`MacSpeechNativeRealtimeFacts.swift` | 绑定会话、复用实际内容坐标与技术读回、关闭及 N+1 时切断录证。 |
| `AppController.swift`、`ContentView.swift`、两份 `Localizable.strings` | 下行引用、独立授权和本机封存、复用私有写入保护。 |
| `project.pbxproj` | 既有 App target 增加一个 Swift 成员。 |
| `EvidenceCases.swift`、P3 离线入口、原离线总入口、阶段隔离 Guard | 合成链路、录证限额与身份、封存及构建隔离验收。 |

`apps/macos/NativeVoiceTransport`、RuntimeCore、Provider、Cascaded 和共享接口与冻结源码一致。C11、Source／Sink、Engine、AEC、AGC、SRC、音量、时钟及插话合同保持冻结。旧胶囊仍走原入口，候选录证使用新的同一会话档案。

## 实际离线结果

- `bash tools/native_voice_transport_p3_tests/check.sh evidence` 通过 **32 项**。覆盖 Fake Controller／Provider PCM 字节、结果、身份、限额、争用、撤回与关闭、私有权限及同名拒绝。
- 标准 Debug、Release 与专用未签名 DEBUG 实际编译通过。普通产物无录证器，专用产物保留录证代码。三份产物均无 Shadow／离线注入符号。编译器拒绝四种设备授权或离线宏冲突。
- Architecture、Secret、Release Route、阶段隔离 Guard 与 Stage 7 Forbidden Checklist 通过。新增 Swift 经 Apple Swift Formatter 校验，四份候选及测试 Swift 的严格 SwiftLint 通过。FULL_CURRENT 本轮重跑 0。
- 两棵受保护工作树、7 项冲突、14 份证据、3 份 fixture、349 份历史文件及 P4 的 66 份收据与基线相符。过程中发现并修正了测试 Home 路径、重复封存拒绝口径和结束原因编码。终版及过程收据位于 `.build/apple_native_voice_acoustic_evidence_20261125/evidence/`。实机、真实 Provider 请求与私人音频采集及分析次数均为 0。

## 更新后的首次实机执行单

下列是另行授权后的签名构建命令。现有 App 仅用于工程隔离核对。实际运行载荷将重新登记。

~~~bash
set -euo pipefail
umask 077
export GIT_OPTIONAL_LOCKS=0
cd /Users/jerryyork/.codex/worktrees/vp-reference-host-preparation/Eterna_Aftelle
evidence_source=7ec9ba04151b6e593b5b0180a65701ab15d22ca2
git merge-base --is-ancestor "$evidence_source" HEAD
git diff --exit-code "$evidence_source" HEAD -- apps tools brain shared-protocol third_party
test -z "$(git status --porcelain)"

run_dir="$(mktemp -d /private/tmp/aftelle-native-first.XXXXXX)"
xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath "$run_dir/DerivedData" \
  -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=YES \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG AFTELLE_WEBRTC_AEC3 APPLE_NATIVE_VOICE_P4_DEVICE_AUTHORIZED APPLE_NATIVE_VOICE_ACOUSTIC_EVIDENCE_AUTHORIZED' \
  build >"$run_dir/build.log" 2>&1
app="$run_dir/DerivedData/Build/Products/Debug/Aftelle.app"
exe="$app/Contents/MacOS/Aftelle"
payload="$exe.debug.dylib"
test -f "$payload" || payload="$exe"
codesign --verify --deep --strict "$app"
nm -j "$payload" >"$run_dir/symbols.txt"
rg -q 'MacSpeechNativeAcousticEvidence' "$run_dir/symbols.txt"
if rg -q 'setShadowEvidence|acousticMetricsForTesting|holdLockForTesting|hasCompletedUplinkForTesting' "$run_dir/symbols.txt"; then exit 1; fi
{
  printf 'source=%s\n' "$evidence_source"
  shasum -a 256 "$exe"
  if [ "$payload" != "$exe" ]; then shasum -a 256 "$payload"; fi
} >"$run_dir/build-identity.txt"
printf '%s\n' "$app"
~~~

1. 获授权后复核签名、麦克风 entitlement、无冲突实例及实际加载 SHA。唯一启动参数为 `open -n -a "$app" --args --apple-native-voice-candidate` 中的候选开关。只读确认 TinyUSB 与 Mac mini 内置扬声器，以及实际音量和静音。历史登记输入 60%、输出 55% 未静音。维持双端 VP、AGC ON、原幅居民输出与原音量，无额外 warmup。
2. 准备就绪后，由用户在候选 DEBUG 面板单独授权录证，再点击「实时全双工语音 → 开始」。当前入口先创建 Runtime／Provider 会话，再启动候选音频图。核验实际 Source／Sink、格式、VP 和路由。
3. 同一 Engine 与配置下依次观察居民独讲、用户独讲、自然双讲和持续多轮。用户按自然交流节奏操作，现场记录实际外放、真人发声和重叠。独立近讲参考只按另外授权采集。
4. 停止语音会话，再单独确认本机封存并导出技术 JSON。登记同 Run 的载荷、录证摘要及见证窗口，退出指定 PID 并确认设备释放。回退使用原冻结源码和标准构建，专用产物留在独立目录。
5. 同一会话证据覆盖四项时判定本轮听感与链路。明显居民回声、明显压制／吞字、异常居民音量或持续链路异常记失败。自然重叠不足或关键证据缺失记 `INCONCLUSIVE`。严重异常、设备变化、身份失效或撤回立即停止。

待明确授权分别覆盖签名构建与启动、单次实机输入／输出、真实 Provider 请求与上行传输、两条数字证据与独立人声参考的私人采集、封存及后续试听／分析。外发依另行授权。

## 停止线

P1–P4 = PASS，ARCHITECTURE_AUDIT = PASS。补充工程待主控复核。实际签名候选启动、应用沙盒缓存读写及声学效应待单独授权。

~~~text
DEVICE_RUNS = 0
SQ_M1 = OPEN
AEC_ROOT_CAUSE = UNKNOWN
CLOCK_ROOT_CAUSE = UNKNOWN
Formal_Test3 = BLOCKED
Test3.execution_authorized = false
~~~
