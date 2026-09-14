# Test 3 本地音频自动测试

## 静音时使用

以下两个入口不启动 App、不打开扬声器或麦克风，也不访问 Qwen / Keychain。无需人在电脑前说话；系统静音不影响执行。

从已有实机四轨 capsule 重放当前 Host：

```bash
bash tools/test3_local_audio/replay.sh /绝对路径/run/evidence
```

可以传多个 evidence 目录或单个 case 目录。每次编译当前 Host 和回放器，逐项重放两遍并核对输入与结果；任一失败仍跑完其他 case。记录前后文件 SHA，保留所有原录音，输出到 `.build/test3-silent-replay/<唯一目录>/`。失败返回非零退出码，不能据“运行结束”宣布 PASS。缺失注入时间或没有播放窗口的 capsule 会报 ERROR。

这一路固定使用录音中的 AEC clean / linear 输出，验证当前 Host 的分类与门控；不能证明修改后的 WebRTC 输出、Runtime 播放清除反馈或真实 Qwen 语义。原 capsule 未编码初始设备 configure 的 backend stats，因此报告单列该元数据差异，不宣称整个 snapshot 与原设备逐字段完全相同。

无录音也能从合成输入重新执行生产 WebRTC + Host：

```bash
bash tools/test3_local_audio/silent_doubletalk/run.sh
```

该入口跑正常 / 2x 纯回声与真实同时有声的软件双讲，详见 [静默双讲说明](silent_doubletalk/README.md)。它验证已知合成信号下的回声抑制与近端保留，不替代恢复声音后的真实声场验收。两种离线结果都不能单独作为 Test 3 PASS。

## 真实设备测试（需要扬声器发声）

复用当前 Debug Aftelle 的生产音频链、真实扬声器和真实麦克风。脚本不调用 Qwen、网络或 Keychain，不修改签名、不重置系统权限，也不设置 `HOME` / `CFFIXED_USER_HOME`。

运行前正常退出 Aftelle。脚本发现同 bundle 的 App 仍在运行会停止，不会并行录音，也不会自动结束用户的 App。

```bash
bash tools/test3_local_audio/run.sh
```

默认先用当前工作区的 Xcode 工程编译 Debug，再执行无弹窗预检和本地测试。构建和测试各自最多 180 秒，预检最多 15 秒。保留工程原有签名设置；不自动申请麦克风权限。若预检不是 `authorized`，输出具体状态并停止。

若本轮已通过 Xcode 编译当前代码，可以指定该次产物：

```bash
bash tools/test3_local_audio/run.sh --skip-build --app '/绝对路径/Aftelle.app'
```

`--skip-build` 必须与 `--app` 一起使用，调用方应确保这是当前工作区刚完成的 Debug 构建。脚本仍执行 runner 协议预检，并记录 App launcher 与 `*.debug.dylib` 的 SHA256；不会回退到旧二进制。

仅做无弹窗权限及 runner 预检：

```bash
bash tools/test3_local_audio/run.sh --preflight-only
```

可用 `--resident-pcm /绝对路径/居民.pcm`、`--near-pcm /绝对路径/近端.pcm` 覆盖音频输入，两者均须为 **48 kHz、mono、Float32 little-endian** 的裸 PCM。默认读取：

- `.build/test3-local-automation/fixtures/resident-window-48k.f32le.pcm`
- `.build/test3-local-automation/fixtures/near-preplayback-mic-48k.f32le.pcm`

居民文件固定使用仓库公开测试 fixture：`apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident`。预检成功后，才将三个输入复制到 App 返回的容器临时目录下的唯一 run 目录。App runner 使用自身的隔离测试 Store；脚本不改实际用户会话目录，也不调用文件选择器。

每次输出保存在 `.build/test3-local-automation/runs/<UTC时间-唯一后缀>/`：

- `launcher-result.json`：构建方式、代码 HEAD、二进制和输入 SHA、权限、退出状态与阶段目录。
- `build.log`（执行构建时）、`preflight.json`、`preflight.stderr.log`、`app.log`。
- `evidence/result.json` 与 App 产生的各 case 证据、配置和输入副本。

失败或超时也会复制已生成的证据，原始输入和 App 阶段目录均保留。运行成功只表示 runner 完成；应查看 `evidence/result.json` 的各项判据，不能将脚本退出码 0 当成 Test 3 整项 PASS。

验收范围必须区分：

离线 `replay.sh` 的软件近端正控还会核验原 launcher 记录的注入源 SHA、
逐回调注入起点和样本数，并按现有 AEC 输出延迟检查全部有效近端源帧覆盖与重复。
有效近端沿用合成回归的 RMS ≥0.006 标签，不改变生产判定门槛。
原先“有任何近端帧放行”的结果保留在 `legacy_status`；缺帧使总结果 FAIL，
缺失注入源或无法复现起点则 ERROR，不能作为通过证据。
此检查仅证明源时间段是否通过 Gate；AEC 是否保留了有效语音仍须独立验证。

- **纯回声负对照**：居民 PCM 经真实生产播放链，由真实麦克风采集，检查该设备、位置和音量下的回声放行及自打断。
- **软件近端正对照**：已知近端 PCM 叠加于 AEC 前麦克风输入，且不进入居民远端参考，检查 AEC / Source Gate / Runtime 中断链。
- **语义提议**：本地 stub 的明确测试 fixture，不是 Qwen 的真实语音检测或转写。
- **真实声场双讲**：软件叠加不能代替第二个物理声源与麦克风共同形成的真实双讲验收。本工具的正对照不能单独证明整项 Test 3 PASS。

## App runner 协议

`Aftelle --test3-local-audio-preflight` 输出一行 JSON：`schema_version: 1`、`microphone_authorization`、布尔 `authorized`、绝对容器临时目录 `test_root`。预检不得申请权限。

`Aftelle --test3-local-audio <stage_dir>` 读取以下 `config.json`，并在同目录写入 `result.json` 和每项证据：

```json
{
  "schema_version": 1,
  "resident_file": "resident.f32le.pcm",
  "near_file": "near.f32le.pcm",
  "fixture_file": "resident.digital_resident"
}
```
