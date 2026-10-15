# Apple Voice Progress v1 · VP-A 历史VP_OFF Input内容核验

日期：2026-10-15（Asia/Shanghai）。节点：Stage 7.5 / VP-A_OFF_INPUT_CONTENT_CHECK。

**内容子项：VP_OFF_INTELLIGIBLE_ECHO_SUPPORTED。** 用户手动试听09原播放控制段条件性定位得到的原幅度Input副本，明确选择“A．能清楚辨认居民语句”。由此补足历史OFF中可听辨居民回声的定性内容负控；不修复09的窗口BLOCKED，不授予VP-A、Apple AEC或Test3 PASS。

## 1. Git基线与本次授权

开始时 `Apple-Voice-Progress-v1` 的HEAD、upstream及实时远端均为 `43c4461b2639822b283fd274a78a1c6cd94e11ce`，工作区干净。阅读09/10/11报告后，只新增本12报告；07–11及全部工具/生产代码不变。

本次任务提示词没有被当作09私人PCM访问授权。先明确申请“是否授权只读09号VP_OFF私人PCM，导出原播放窗口的本机私有试听副本，并由你手动试听”，用户回复“明确授权只读、导出及手动试听”后，才读取该容器和关联必要元数据。

只处理09对应运行；未读取08或其他历史PCM，未重新读取ON PCM、固定素材源、登记或原ACE3资产。没有Engine、麦克风采集、实验素材外放、权限请求、自动播放、ASR/LLM/Provider调用、新实验或重试。

## 2. 原始证据、验证器与格式

| 核验项 | 结果 |
| --- | --- |
| 准确运行 | 私有计划对应09的 `b25ce43fd6749bf6eadcb58de0ae981f1be2c414` 基线，manifest为VP_OFF、270条记录；没有误选首次08 |
| 原容器身份 | SHA-256与09运行结束时保存的独立verify记录一致，仅本地保存摘要 |
| manifest/prepared | run/build/config身份一致；build身份与09原固定记录一致；容器start_tick与armTick对应 |
| seal/receipt | 原有独立verify复核容器、footer及receipt的checksum、文件长度和计数通过，INVALID=0 |
| 原Input | 48kHz、mono、Float32、noninterleaved、formatFlags=41；135条，每条4800 frames，总648000 frames/13.5秒 |
| 时间/布局 | sampleTime从0连续至648000（exclusive），hostTime/sampleTime有效；host向前，单plane布局及payload长度合法 |
| 原诊断 | lost/overflow/pending均0，sealed及controlSealSucceeded为true、integrity VERIFIED；未改写原状态 |

09旧可执行文件路径已由后续已批准构建更新，当前文件不再具有09原二进制摘要，故**没有宣称运行09原二进制**。使用现有已固定Release，仅调用其非设备 `verify`；实际文件身份核验一致，并确认C Recorder/header及verify命令源码自09基线至当前没有变化。没有重新构建、重签或修改程序来读取历史数据。

原prepared、manifest、容器、receipt以及09既有分析文件/脚本在本次核验、导出和读回后字节身份均保持一致。结构完整性及文件身份不证明唯一USB物理来源或声学绝对时间。

## 3. 原播放窗定位及条件性限制

使用原始 `playRequestTick → plannedTailStartTick`，控制等待实际为 **8.017029917秒**。不强制截成8秒、不改为Render首末非零区间、不添加尾段或其他有利片段。

严格复现09原离线方法：取四个已保存配对的offset下/上界包络，以该包络映射每个控制事件，再用区间中点进行原native样本选择；逐buffer使用其raw hostTime、原ASBD名义48kHz和ceil边界，全部所选原生帧连续保留。重算的边界与09既有分析记录一致。

以首个Render raw hostTime为0，条件性play起点区间约为 `[2.002746875, 2.002746958]` 秒，终点约为 `[10.019776792, 10.019776875]` 秒。已观察offset包络宽2 ticks，名义83.333ns，**不是全程跨域、硬件或声学误差上界**；不能证明配对点之间偏移恒定。事件字段与pair.C也不能套用新版六阶段直接绑定语义。

因此它是**原播放控制段的条件性内容副本**，不是原2/8/3窗口无条件验收证明，也不是完整源buffer或全部回声。原Render最后非零结束约10.049873399秒，比本副本的条件性控制窗终点晚约30.097ms；本轮没有为包含该末段而扩窗。09原窗口BLOCKED保持。

所选Input实际384820 frames，按48kHz为 **8.017083333秒**，比控制等待多约53.417µs（2.564个名义帧）。这是逐块host步进、名义采样率及样本边界选择的描述性差异，不伪称纯粹1帧量化，也不补帧或重采样。条件性起止均落在已保存Input内；原record/样本范围只保存在私有导出记录中。

## 4. 私有副本与用户实际听辨

只导出一份原play Input：48kHz、mono、IEEE Float32 WAV，384820 frames，文件共1,539,336 bytes（其中native PCM 1,539,280 bytes）。保留原幅度，无归一化、放大、滤波、降噪、增强、淡入淡出或重采样；不导出Render或另选窗口。

新副本及有界来源/校验记录位于Git之外，私有父目录0700、文件0600、当前用户所有、非symlink，未覆盖原证据。独立读回WAV的fmt/fact/data，再按原文件offset/record/frame范围重读Input，导出payload与原样本**逐样本bitwise一致**。副本峰值0.775923729、RMS 0.187280433，非有限、越1及满幅计数均0；这些数值只描述副本，不代替听辨。

向用户提供本机私有文件位置及手动播放入口，未自动播放或上传。用户在A/B/C/D选择中实际回复：

> A．能清楚辨认居民语句

按本任务约定裁定 **VP_OFF_INTELLIGIBLE_ECHO_SUPPORTED**。未要求公开逐字内容，未由AI替代用户识别，也没有凭RMS或文件名判断居民身份。确认限本次所选片段及用户听辨，不表示完整源语句、所有时段或唯一物理来源都已验证。没有追加试听文件或因结果换段。

## 5. 与10/11的有限对照及剩余阻塞

**1．是否形成有意义的回声对照？是，形成有限的定性历史对照。** 09原Input中居民语句由用户清楚辨认；10真实外放已由用户确认，11对其处理后Input的原音量试听没有听辨出居民语句，只报告不明杂音。本轮补足此前缺少的OFF内容负控子项，不再仅依赖“大RMS/小RMS”的并列。

**2．是否支持有限回声抑制结论？为Apple VP整体路径降低可听辨居民回声的研究假设提供有限支持。** OFF可辨、ON未辨出语句这一主观差异有实际内容依据；ON不是全零或记录失败。但未进行盲测或独立声学标定，不能推出零残留、净AEC增益、稳定性能或近端语音无损，也不能排除噪声遮盖等解释。

**3．正式VP-A仍为何BLOCKED？**

- 09原2/8/3数字窗口仍缺完整无条件证据；本轮内容副本不能追溯修复，亦未改变原协议。
- ON quiet中先于本工具播放的输入信号，以及后段以高频为主的杂音，其来源/原因仍UNVERIFIED，限制声学归因。
- 两臂的Input 48kHz/mono与16kHz/3ch重复、AGC false/true、Render声道/格式/幅度和工具时序版本不同；同素材和音量设置不保证同声压或完全同条件。没有计算跨轮RMS比、ERLE或净AEC效果。

USB唯一物理来源及声压真值等既有未知项保留，不为本内容子项新增验收阈值；也不把纯回声观察当作近端保留或线上零错误授权证明。本轮不提出、准备或执行VP-B/C及新的设备实验；主控仅获得补足内容负控后的有限证据，仍须独立裁决。

## 6. 三维审核与Stage7 Forbidden Checklist

**TECHNICAL_REVIEW：HISTORICAL_OFF_CONTENT_CONTROL_SUPPORTED。** 精确运行身份、原生格式、seal及原选择方法可复核；原跨时钟条件性、未纳入的数字末段和声学未知项如实保留。

**ENGINEERING_REVIEW：NO_CODE_CHANGE / NATIVE_EXPORT_VERIFIED。** 单份导出读回与原样本一致，原始文件及既有分析未变。仅运行离线verify及副本校验；源码不变，构建、262项测试、Lint/Format/C11本轮NOT_RUN，不以重复非设备检查代替内容负控。

**EVIDENCE_REVIEW：VP_OFF_INTELLIGIBLE_ECHO_SUPPORTED；QUALITATIVE_COMPARISON_SUPPORTED_WITH_LIMITATIONS。** A级用户听辨仅授予内容子项；VP-A正式状态保持BLOCKED，Apple AEC PASS未成立。

| Stage7检查 | 结果 |
| --- | --- |
| Stage/平台/六红线 | PASS；仅Stage7.5 macOS研究报告，无新target/Stage8，无红线触碰 |
| Runtime、Qwen、Test2、Provider、正式音频图 | PASS；无代码/API/授权/generation改动或正式动作 |
| DR、Studio、Memory、Session、ACE3 | PASS；无schema/资产写入，未操作原ACE3工作区 |
| 设备及后续阶段 | PASS；无录音、Engine、测试素材外放、权限或自动重试；仅用户手动试听既有授权副本，未进入B/C |
| 冻结历史与隐私 | PASS；07–11及全部源码不变；只提交12，无PCM、私人路径、设备身份/摘要、素材摘要、登记、原始日志或密钥 |

独立方法/报告复审仅使用脱敏事实，不冒充第二人读取或听辨私人PCM。

```text
VP_OFF content = VP_OFF_INTELLIGIBLE_ECHO_SUPPORTED
OFF/ON historical qualitative contrast = SUPPORTED_WITH_LIMITATIONS
VP-A = BLOCKED
USB unique physical source = UNVERIFIED
VP-B/C = NOT_AUTHORIZED
Apple AEC PASS = NOT_ESTABLISHED
Test3 = BLOCKED
Test3.execution_authorized = false
```

提交推送后立即停止，等待主控审核，不自动推进实验或实现。
