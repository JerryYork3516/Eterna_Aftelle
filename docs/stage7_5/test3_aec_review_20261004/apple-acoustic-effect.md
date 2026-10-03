> Published historical report. Source: `.build/test3-apple-acoustic-effect-20261002/report.md`.
> Local home/device identifiers are redacted; relative artifact links are rendered as text.
> Read [README](README.md) for chronology and corrections. Referenced PCM, traces and binaries remain local and are not part of this publication.
> Statements such as "no commit/push" describe the original experiment, not this later publication.

# Test3/03 · 同构实体 Apple VP 与旁录回声差异审计

**裁定：观察到显著但不稳定的 Apple 路径波形变化；没有查到可复现的“整轮 AEC 未启用”或声道路由错误。Test3/03 仍 `BLOCKED`。** 这只是现有录音的事后声学审计，不是近端声源判据、Gate 候选或正式 Runtime 决策。

## 输入与方法

- 2026-10-01 同一 Debug launcher `09c754fd…`、dylib `aac219fe…` 的 Timesintelli USB 麦克风 → Mac 内置扬声器实体静默负控和真人轮。两轮 UID、居民源 SHA-256 `72434d68…`、Host render PCM SHA-256 `dea8ff9f…`、resident digital gain `0.5` 均相同；render 第一帧相对 capture 第一帧的内容时间分别为 `391.603666`／`391.603667 ms`。这个 render PCM 是**送往播放器的数字参考**，不是独立麦克风测到的扬声器实际声压。两轮记录均为 Apple VP 模式，启动代码调用 `setVoiceProcessingEnabled(true)` 并检查输入／输出 node 的 `isVoiceProcessingEnabled`；0 注入、0 AEC fallback、0 输出欠载、0 供音逾期。实际系统 SPL、硬件增益、麦克风／扬声器几何和 Apple VP 内部状态未独立记录。
- SHA 检查原生 Apple VP 16 kHz 输入、pre-Apple Timesintelli 16 kHz **混合输入**旁录、Host render、回调／时序／决策 JSON。两轮每轮原生输入 3 个通道的**整份 PCM SHA 完全相同**（负控 `d59fc9e3…`，真人 `36fe182a…`）；当前 converter `channelMap=[0]` 没有遗漏一条不同的原生声道。`pre-Apple` 旁录不能称纯近端人声。
- 沿用先前仅用负控居民波形标定的 `sidecar host − Apple native content host = −41.343417 ms`；按 sidecar 连续 chunk epoch 映射，不重新拟合正控 lag。Apple native 与 Host 48 kHz processed 的波形／内容身份此前在两轮 18/18 固定窗通过，本次用 native 直接避免 converter 重采样混淆。合法 render lag 的时间原点使用**旁录映射后的内容时间**；新脚本复算已与既有 `source-evidence-margin/audit.py` 在负控五个分散帧的峰值相关和 lag 完全一致（数值差 < `1.5×10⁻¹⁵`、lag 差 0）。
- 预先固定负控 `75,100,…,1050` 帧尾的 40 个互不重叠 250 ms 播放窗；两段播放前 80 ms 窗只作基线。180–3500 Hz 因果带通后，**仅用旁录**在完整、已到达、保留的 Host render 0–500 ms 参考范围内选最大相关 lag；Apple 输入只在同一参考算相关，不替它另找有利峰。正控只取原报告预标的三段纯回声 `71–120`、`726–775`、`886–935` 中各两个 250 ms 窗，共六窗；再把完全相同六个帧尾用于负控配对诊断。无阈值、分类器或 Gate 改动。输入哈希、精确窗与计算式见同目录 `protocol.json`、`positive-holdout-protocol.json`、`matched-endpoints-protocol.json`、`cross-run-protocol.json`；完整逐窗数值在 `result.json`、`positive-holdout-result.json`、`matched-endpoints-result.json`、`cross-run-result.json`，版本／设备与回调对照在 `environment-check.json`。

## 量化结果

| 纯回声观察 | Apple/旁录 RMS dB，中位数 | 旁录→render 同 lag \|r\| 中位数 | Apple→render 同 lag \|r\| 中位数 | Apple↔旁录同内容 Pearson 中位数 |
| --- | ---: | ---: | ---: | ---: |
| 静默负控 40×250 ms | **−6.60 dB**（35/40 窗 Apple 更低） | 0.740 | 0.632 | 0.915 |
| 真人轮中已标纯回声 6×250 ms | **−47.93 dB** | 0.844 | 0.0206 | 0.0586 |

负控有一窗对应 render 参考零方差，render 相关只对 **39/40** 窗可评分；其 Apple/旁录能量和直接相关仍可评分。负控在同一参考下，Apple render 相关低于旁录的为 **27/39** 窗，并非每窗都抑制。播放前两窗 Apple/旁录 RMS 分别为 **+3.57/+3.74 dB**；进入播放后的典型比值变小，说明两路输出不能用一个固定全程增益解释，但也不能将差值全部归因于 AEC。

负控内部按时间顺序固定分成四组各十窗，`Apple/旁录 RMS` 中位依次为 **−0.94、−5.90、−6.10、−7.53 dB**；Apple 对同一 render 的 \|r\| 中位依次为 **0.227、0.555、0.648、0.834**，旁录的对应中位为 **0.874、0.583、0.704、0.854**。因此较晚的 Apple 输出尽管绝对能量降低，却越来越像居民回声；不能把整轮解释为一个稳定的回声衰减率。真人轮三个预标纯回声区间各两窗的 Apple→render \|r\| 中位约 **0.0169、0.0206、0.0188**，没有显示同样的晚期上升；样本各只有两窗，不作趋势估计。

同源、同相对播放时刻的配对窗进一步显示变化具有**时间和轮次依赖**：第 750 帧，负控与真人轮旁录 RMS 分别 `0.1963/0.1986`，Apple RMS 却为 `0.09331/0.00008199`；第 910 帧旁录 `0.1560/0.1600`，Apple 为 `0.06095/0.00008663`。六对窗的旁录 RMS 差为 **+0.06 至 +0.95 dB**，旁录→render 最佳相关也相近；但是其中五对最佳 lag 在两轮相差约 **3.125 ms**，说明声学路径时序并未被证明完全相同。反例是第 120 帧：负控 Apple RMS `0.00002607`，比真人轮的 `0.0002977` 更低。故不能简单说负控整轮“关了 AEC”、真人轮整轮“开了 AEC”。负控第 900 帧的 250 ms 窗，Apple↔旁录 Pearson `0.99785`，两者对同一个 render 窗的 \|r\| 分别 `0.94942/0.95017`，仍有明显居民波形残留；另一早期窗第 100 帧，旁录→render `0.91585`，Apple→同参考只有 `0.00114`。这些值也不支持“Apple 路径完全没作用”。

## 判读与下一条件

两轮供音 PCM、软件镜像、设备 UID 和回调内容关系一致，使“拿错数字素材／声道 0 选错不同的 AEC 输出／已记录路由切换”缺少证据。已完成的无声环境反证还检查了两轮全部 108 个 Apple native input 回调：均为 16 kHz、3 通道、每回调 1600 样本、连续 sampleTime；全部 108 个 render 回调均为 44.1 kHz、4410 样本、转换状态 `ok`；Host 时间线无缺口，HAL 状态读取 0 错误。这排除了已记录的格式突变／样本重置，却无法检测未记录的 VP 内部参数或实际扬声器声压。Apple 路径对纯回声有时大幅改变波形，有时仅降低能量而保留几乎同形的回声。**现有资产不能把变化唯一分配给 AEC、AGC、噪声抑制、设备自身处理或内部自适应状态；也没有 Apple VP 内部状态、物理扬声器声压或麦克风增益轨来指认一个配置 bug。** 这些观察不修复短句 HAL=false 与相关否决，更不能据能量比调阈值接 Gate。

本轮已执行可证伪的无声环境核查：**同一六个居民窗口**的旁录 RMS 与旁录→render 相关若也剧烈变化，跨轮 Apple 差异可由输入声学耦合解释；实测旁录 RMS 相近、render 相关相近，但最佳 lag 相差约 3.125 ms，因而只排除“数字素材／输入音量完全不同”，不能排除房间／设备延迟差异。两轮已封存的 `run-events.json`／`app.stdout.json` 只保存了设备 UID、数字 `resident_gain=0.5` 和“system volume unchanged; SPL not calibrated”，没有实时硬件输入增益、物理声压或 Apple VP 自适应状态。**下一个可证伪的无声环境核查条件**是：若项目中另有这两次实体轮的同步系统音频属性／配置变更记录，按同一六窗时间戳核对增益、输出设备和 VP 状态；若没有，则旧录音无法回答这些原因，停止把能量差命名为 AEC 配置 bug，转回离线声源判据研究，不因这些描述数值让用户重录。正式声源归属 Decision、Provider cancel／playback clear 仍禁止；Test3/03 保持 `BLOCKED`。

Stage 7 越界检查：**PASS**。触碰红线：无；仅在 ignored `.build/test3-apple-acoustic-effect-20261002/` 新增协议、只读数据分析脚本与报告；未改产品代码、Runtime API、DR schema、平台 target，未进入 Stage 8；未外放、录音、切路由、reset、clean、commit 或 push。
