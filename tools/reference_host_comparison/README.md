# REF/HOST R2 离线适配

这是冻结 VP-C 的派生素材、事件补丁和离线验证，**不是设备执行器**。
当前状态为 `PARTIAL`：已有蓝牙播放器/控制器固定原代理素材摘要，不能直接使用本轮 HOST 派生代理素材。禁止跳过该校验运行设备。

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

## 尚未完成的实际执行连接

旧 `execute` 在启动辅助播放器前固定检查原代理 SHA；`HOST_proxy.wav` 会被拒绝。本轮负控验证了拒绝发生且 Popen 次数为 0。辅助播放器二进制也含 `Frozen speech SHA mismatch` 校验文字，但本轮没有执行它或恢复到可审核的原 Swift 源码。

下一步应先定位既有播放器源码，有限增加明确的派生素材 SHA/时长登记，并把本翻译器接入原单次执行/清理循环。不得用替换文件、删断言、二进制补丁或重写播放器绕过阻塞。本轮设备执行未授权。
