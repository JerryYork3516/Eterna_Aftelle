# REF/HOST R2–R4 对照适配

这是冻结 VP-C 的派生素材、事件补丁和验证。R3默认禁止设备；R4另有必须明确同意的单次入口。
R2历史状态为 `PARTIAL`。R3已找到原Objective-C播放器源码，并通过同名重建得到原二进制的相同SHA；新增有限素材登记及REF/HOST单次连接的Fake验证。旧播放器、旧控制器和R2失败证据保持原样。

## R3播放器与执行连接

原播放器是 `bt_proxy_speech_once.m`，直接包含 `native_dual_sound.m`；不是Swift。`prepare_player.py`只接受报告登记的两份源码、原二进制、原控制器及两份代理素材SHA。先重建并比对原二进制，再在新的Git忽略目录应用 `player.patch`。原文件不修改。

```bash
python3 -B tools/reference_host_comparison/prepare_player.py \
  --source "$ORIGINAL_PLAYER_SOURCE" \
  --assets "$R2_ASSETS_DIR" \
  --output .build/reference_host_r3/new_player

export R3_BUNDLE="$PWD/.build/reference_host_r3/new_player"
export R3_REF_EXECUTABLE="$PWD/.build/reference_host_r2/final/ADAPTED_REF/.build/debug/apple-vp-reference"
# R3_HOST_EXECUTABLE指向报告登记的已验证Debug主程序；不会执行它。
python3 -B tools/reference_host_comparison/test_integration.py
```

`proxy_registry.h`登记 `REF_proxy.wav` / `HOST_proxy.wav`：只允许播放器同目录 `assets` 内的这两个规范绝对路径；校验整文件SHA、RIFF、24k/Mono/PCM16LE、264310/360310帧、0/96000帧前导及登记起音。拒绝其他文件、路径别名和symlink；不接受调用方自定义SHA。Foundation-only `registry_check`复用完全相同的准入函数，不链接AppKit/CoreAudio，也不创建NSSound。

`integration.py`复用原SHA锁定的 `SingleRun` 和R2 `ReferenceRun`。执行循环沿用旧控制器的准备、等待同意、PLAY/STOP、封存等待和退出顺序，加入模式、二进制、终止证据及清理检查：

| 模式 | 原子进程接口 | PLAY / STOP | 时钟 |
|---|---|---|---|
| REF | ADAPTED_REF原vp-c参数与 `AFTELLE_VPC_COMPARISON_FD` | observation+4 / +9秒 | R2 continuous锚点→absolute纳秒 |
| HOST | 原 `--apple-vp-acoustic-test --apple-vp-score-control-fd=` | score+0 / +11秒；4秒预热 | 原mach_absolute纳秒 |

不用旧 `--arm A/B`表示REF/HOST，不混传事件fd。原50ms迟到门槛保持；重复/外来run、缺事件、EOF、子进程失败、取消和时钟倒退均失败退出。活播放器最多收到一次STOP；已退出或断管道时记录无法投递并回收，不伪造STOP成功。

**DEVICE_DISABLED=true**：`run()`默认在启动任何进程前拒绝；离线测试仅显式注入带禁用标识的Fake子进程。模块原命令行也拒绝启动。R3完整连接指实际执行控制循环、Unix管道和身份检查，子进程为Fake；不是蓝牙/麦克风执行。

R4新增独立 `device_once.py` / `run_device_once()`，只供已明确批准的REF/HOST各一次实验。必须显式指定 `--authorize-device-once REF|HOST` 和 `--consent R4_REF_HOST_ONCE_LOCAL_RECORDING_AND_ANALYSIS`，并传入已核验的bundle、目标二进制及新的私有证据目录。该选项记录操作者已取得的授权，不产生或替代授权。缺少同意、目标/播放器SHA不符、证据目录不安全均零启动；私有父目录的 `R4_REF_consumed.json` / `R4_HOST_consumed.json` 排他创建，失败也不自动重试。默认入口不变；实机路径直接使用Popen，不伪造Fake标识。

该入口保留原系统权限、REF可见实验确认、HOST原UI配置/采集/显式导出。SIGTERM及异常进入原STOP/进程回收路径；HOST不能传REF参数。实际完成只记 `CONTROL_COMPLETED_DEVICE`，声学结论和用户听感另行审核。证据和录音须保存在Git外0700目录，禁止未经单独授权公开音频。

R4第一次实机准备发现旧控制器/Fake把播放器的 `duration_seconds` 误写为 `duration_s`，在启动REF前误拒绝正确素材。已修正控制器和Fake，并按已登记原生源码检查ready字段集合；错误旧字段继续拒绝。41项离线通过不能替代修复后的实机验证；原失败及单次尝试标记保留，未自动重试。

REF原产物是没有`.app`目录的CLI；当前CUA无法按名称、bundle ID或裸可执行路径选择它。`prepare_reference_app.py`仅复制登记SHA的可执行文件及原资源，生成含原Info字段的本地`.app`，只增加CFBundleExecutable/PackageType，不重编译、不签名改写Mach-O、不改VP/窗口/排程源码。其二进制SHA仍为原ADAPTED_REF值；工具本身不启动应用。新增两个离线用例验证原身份/资源、拒绝错误二进制及不覆盖已有包装，累计43项PASS。

该字节一致包装使CUA能识别应用，但原NSAlert仍不可控。用户明确允许AppleScript后，原async CLI入口在本机仍无可操作窗口。最终只在新的派生副本应用`ref-gui-entry.patch`：移除原`@main`、保留原main的`@MainActor`隔离、新增同步AppKit run-loop调用原main。音频驱动、Tap、VPCWindow、配置与排程不改。新产物名为`R4_GUI_ENTRY_ADAPTED_REF`，SHA为`65fadd2acbb09dc9cf19e8f8a93013ad795ff93cef543a3e65420d5d59a9a52b`；不能冒充旧R3/历史二进制。`prepare_reference_app.py`只接受这两个明确登记的REF身份，不开放任意SHA。

重建时，将R2的`ADAPTED_REF`复制到新的Git忽略目录（排除`.build/.swiftpm`），然后只在该副本执行：

```bash
git -C "$REF_GUI_COPY" apply --unidiff-zero \
  "$PWD/tools/reference_host_comparison/ref-gui-entry.patch"
xcrun swift build --package-path "$REF_GUI_COPY" -Xswiftc -warnings-as-errors
python3 -B tools/reference_host_comparison/prepare_reference_app.py \
  --reference "$REF_GUI_COPY/.build/debug/apple-vp-reference" \
  --info "$REF_GUI_COPY/Info.plist" --output "$NEW_REF_APP"
```

这不是自动升级二进制登记；工具链变化后SHA不符会停止，必须另行审核。构建、包装及Fake测试不会自动启动设备。R4最终经原REF可见同意、HOST原录音/导出确认，各取得一次真实录音及正常退出。用户报告两段都有时有时无、忽大忽小；居民来源仍不确定，声学对照INCONCLUSIVE。前序采集前准备失败均保留，未进行失败录音重录。详见[R4实际报告](../../docs/stage7_5/test3_apple_vp_clean/T3_2_A_reference_host_R4_device_comparison.md)。

同一个证据目录禁止复用，结果0600；命令与事件有界、失败不重试、清理失败不能写PASS。源码/产物身份和33项新增测试、原42/13/9回归见[R3报告](../../docs/stage7_5/test3_apple_vp_clean/T3_2_A_reference_host_comparison_R3_player_integration.md)。READY仅表示离线技术准备；真实时序、音量、物理覆盖和参考隔离仍未验证。

## 身份与范围

- REF 来源：`c64c7e2629ec775062fdc2ea1e4a934c73c1fa75:tools/apple_vp_reference_v1/`。
- `prepare.py` 在新的、Git 忽略的 `.build/` 子目录分别导出 `FROZEN_REF`、`ADAPTED_REF`，只给后者应用 `ref-events.patch`。
- 原 33 项 REF 用例、HOST 生产源码和旧蓝牙控制器不修改。HOST WAV 解析函数从当前源码提取，仅去掉 private 可见性供无设备测试使用。
- 仅接受 `materials.py` 登记的两份非私人语音 SHA。没有麦克风录音输入接口。
- 依赖现有 Swift/Xcode、Python 3、NumPy、SciPy；本次验证版本见 R2 报告。不自动安装依赖。

## 重现离线准备

先将以下三个环境变量设为已有文件：`RESIDENT_WAV`、`PROXY_WAV`、`R2_ORIGINAL_CONTROLLER`。第三项必须是已登记 SHA 的原 `sync_once.py`；不要提供任何私人录音。

```bash
python3 -B tools/reference_host_comparison/prepare.py \
  --output .build/reference_host_r2/new_attempt \
  --resident "$RESIDENT_WAV" --proxy "$PROXY_WAV"

export R2_ASSETS_DIR="$PWD/.build/reference_host_r2/new_attempt/assets"
xcrun swift test \
  --package-path .build/reference_host_r2/new_attempt/ADAPTED_REF \
  -Xswiftc -warnings-as-errors \
  --filter 'VPCWindowTests|VPCCommandTests|VPAMaterialSafetyTests|VPCComparisonEventsTests|ComparisonMaterialTests'

python3 -B tools/reference_host_comparison/test_control.py
python3 -B "$R2_ORIGINAL_CONTROLLER" --self-test
```

输出目录必须不存在；不覆盖先前尝试。42 项 Swift 用例、13 项 Python 用例及旧控制器 9 项自测全部只做离线检查。Python 异常退出/管道丢失用例拦截 Popen，未启动 App、播放器或设备。

## 素材与时间语义

- REF 居民：原 24k PCM16 → 16k Float32，增加 1 秒前导零值、补尾零值至 128000 帧。原素材自身的 1 秒静默仍保留。REF 原 t=2 播放，首个数字非零约 t=4。
- HOST 居民：原文件逐字节不变，原 t=3 播放，加原素材 1 秒静默，首个数字非零 t=4。
- REF 代理：原文件不变，原控制窗 [4,9)。HOST 代理：原文件前加 4 秒零值，原控制窗 [0,11)。[4,9) 使用相同的前 5 秒源样本。
- 两个代理文件均保留完整源内容，但原控制窗口分别在源第 5/7 秒停止。不能声称播完全文，也不能把共同数字内容当作真实物理重叠。
- HOST 原 0–3 秒 human_only 提示在此素材方案下没有代理语音；这个比较方案不能验证首 3 秒真人保留。

## REF 事件合同

派生工具可选读取 `AFTELLE_VPC_COMPARISON_FD`。必须是继承的可写、非阻塞 pipe fd（大于 2），不接受普通文件。它不替代原 vp-c 授权参数、系统权限、可见窗口确认或素材/设备注册。

真实 `observationStart` 产生一行 JSON schedule：`schema_version=1`、`source=ADAPTED_REF`、真实 `run_id`、`clock=mach_absolute_nanoseconds`、`observation_start_ns`、`near_start_ns`（+4 秒）、`near_stop_ns`（+9 秒），以及 absolute-before / continuous / absolute-after / numer / denom 原始锚点。terminal 输出 stop 或 cancel；没有音频样本或设备 UID。

每条不超过 512 bytes，原控制路径执行非阻塞原子写；不在 Tap 回调写入。原有观察循环检查管道和时钟；满管道/断开/时钟不连续导致原异常清理。断开的管道无法保证交付 cancel 字节，外部消费者仍必须在 EOF、子进程异常或超时时停止代理。

`controller.py` 只加载并校验原 `SingleRun` 类，精确翻译 REF 的 5 秒 near 窗口；HOST 的 11 秒合同不改。它没有设备启动 CLI，也没有声学 PASS 判定。

## R2历史阻塞（保留）

旧 `execute` 在启动辅助播放器前固定检查原代理 SHA；`HOST_proxy.wav` 会被拒绝。本轮负控验证了拒绝发生且 Popen 次数为 0。辅助播放器二进制也含 `Frozen speech SHA mismatch` 校验文字，但本轮没有执行它或恢复到可审核的原 Swift 源码。

R3的解决方式见本页上方：原控制器仍会拒绝派生素材，新的派生播放器/外部连接独立登记身份，不改写这条历史负控。设备执行未授权。
