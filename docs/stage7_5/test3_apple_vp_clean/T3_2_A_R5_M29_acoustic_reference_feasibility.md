# T3.2-A / R5-M29：独立声场参照可行性与准入审查

日期：2026-10-31（Asia/Shanghai）。READ_ONLY_FEASIBILITY_AUDIT；仅新增本报告。

**最终裁定：INSUFFICIENT_EVIDENCE。** 已登记设备为Mac mini M4、TinyUSB USB输入、Mac内置扬声器，尚无可核实的独立录音机、手机及采集App身份与处理合同。不能证明现有条件已满足独立声场参照，也不能把“未登记第二设备”写成“用户没有第二设备”或技术上永远不可行。`M29_REFERENCE_QUALIFICATION=UNVERIFIED`，不是设备执行READY。

## 1. Git、范围与证据来源

开始时隔离Worktree干净；HEAD / upstream / 实时远端均为`bb7d884975abe7acf40c3ecec21aa4914bfd50cc`，本地分支`codex/reference-host-comparison-preparation`，推送目标`Test3-AppleVP-Clean`。沿用用户免除后续读取范围重复确认的指令，先报告限定范围再读取；没有将读取豁免当作私人录音或设备授权。

只读AGENTS、Stage7 Forbidden Checklist及以下已提交报告的相关章节；没有访问历史私人WAV/JSON、Manifest、UID或日志，没有枚举新设备或运行HAL探测。报告的设备事实为**既有登记**，不是本轮在线、占用、音量或权限快照。

| 依据 | 本轮用途与证据边界 |
|---|---|
| [M28 §3–8](T3_2_A_R5_M28_targeted_residual_differential.md) | R2持续约3.28秒居民模板对应、约99.665% PCM能量处于Render期间，强差异已在VP后Native；独立声场未被记录，不能恢复过去声场 |
| [M27最终报告](T3_2_A_R5_M27_original_aec_stability.md) | 已登记TinyUSB/内置输出、60%/55%、三轮技术资格与运行态；听闻不能可靠分配到轮次或地点，不是独立声压测量 |
| [M26-D3最终报告](T3_2_A_R5_M26_D3_timing_witness_fix_and_batch_review.md) | 两臂既有播放见证和技术资格；没有新增外部采集设备证据 |
| [M25 §2–4](T3_2_A_R5_M25_reference_host_differential_audit.md)、[旧独立REF准备报告 §3–4](T3_2_A_R5_independent_human_reference_review.md) | 历史成功/派生REF均使用VP输入；独立程序不等于未经VP的声场参照。历史成功条件不完整，不重开原始录音 |
| [M06 §1及可行性结论](T3_2_A_R5_M06_pre_vp_raw_capture_feasibility.md) | 复用其Apple官方API/SDK审查：独立HAL/AUHAL仅为PARTIAL候选，并行无扰动及ADC Raw来源未验证。本轮不重新实现、运行或扩展这些接口 |

没有进行新的产品能力或API可用性断言：没有具体外部设备型号与App，不能代其填写PCM、增益或处理能力。已向用户请求一次现有候选型号/系统/App文字信息；截至本报告未取得可核实登记。未要求购买、安装、打开App或录音。

## 2. 已核实设备与实际可用性的边界

| 对象 | CONFIRMED：已有登记 | 未验证能力 / 本轮限制 |
|---|---|---|
| Mac mini M4 | 本地Aftelle宿主、内置扬声器；既有目标输出55%、未静音 | 本轮未查询当前设置；扬声器不是独立采集通道，没有登记第二个合格内置输入 |
| TinyUSB USB输入 | 既有实验输入，目标系统60%；旧设备报告登记USB输入，VP运行后Native为16kHz/3ch Float32 | 设备别名和系统音量不证明ADC、硬件DSP或增益曲线。当前Aftelle Native已经过VP，不是独立参考或ADC Raw |
| Mac内置扬声器 | 既有居民播放端；M26-D3有用户听闻 | 软件Render、默认设备、播放完成及听闻均不能单独提供麦克风附近的定量声场记录 |
| 独立硬件录音机 | 没有型号、可用性或采集路径登记 | UNVERIFIED；不能假定现有设备支持手动固定增益或关闭处理 |
| 独立手机录音系统 | 没有手机、系统及现有App身份登记 | UNVERIFIED；普通录音或无损文件不能自动取得RAW资格 |
| 其他独立采集设备 | 没有第二个采集设备及接口登记 | UNVERIFIED；不假设存在，不下载工具寻找替代通道 |

既有报告证明前述Mac路线曾工作，不证明本轮实时可用。没有合格独立设备的登记，故本轮不建立待运行计划或已消耗授权记录。

## 3. 候选参照比较

下表是**候选必须提供的证据**，不是产品功能承诺。三类外部候选目前均为UNVERIFIED。

| 检查项 | A：硬件录音机 | B：手机＋现有录音App | C：其他独立采集设备 |
|---|---|---|---|
| 实际可用 | 型号、持有/可使用确认 | 手机型号、系统、App版本及可使用确认 | 设备、宿主及采集接口身份 |
| 独立性 | 自身麦克风/ADC/记录路径，不经Mac VP | 本机采集路径不经Mac/Aftelle，也不共享当前AEC状态 | 逐段证明不经Aftelle图及当前VP状态 |
| PCM来源 | 编码、位深、采样率、声道和处理流程资料 | App实际输入、保存格式和处理路径资料；扩展名不够 | 接口合同及实际输出格式 |
| AGC固定/禁用 | 模式及开关证据 | App与系统处理状态证据 | 硬件与宿主处理状态证据 |
| NS/AEC关闭 | 各处理开关与实际模式 | 不能仅凭“原声/无损”名称推定关闭 | 所有中间处理点可说明 |
| 增益锁定 | 手动值及跨轮不变证据 | 实际可锁定、读回或等价可信证据 | 硬件/软件各级固定值 |
| 格式固定 | 实际文件与设备配置一致 | 实际文件与采集配置一致 | 接口格式与实际文件一致 |
| 采集时间 | 样本计数、实际时间信息及不连续标记 | App能提供的实际采样时间信息，不用文件创建时间冒充 | 原采样时钟及时间戳语义 |
| 动态范围 | 本次信号无饱和、压限主导或不可用底噪 | 同左；位深标称不替代实际检查 | 同左，需明确有效范围 |
| 自动响度/限幅 | 开关或确定性处理合同 | App/系统/硬件各级行为清楚 | 中间处理行为清楚 |

**现有信号不构成替代方案：** HOST Native和旧REF Input均位于VP之后；Player Render是数字源观察，不是外部声场；同Mac“另一录音流”也不能因流独立就获得来源及并行无扰动资格。M06的HAL/AUHAL尚未交付合格参考通道，本轮禁止新增采集器，故不以其理论可设计性填补设备缺口。

`RAW_PROVENANCE=UNVERIFIED`。独立于Mac VP、PCM编码、未经全部硬件/系统处理的ADC Raw是三个不同命题。允许评估处理行为明确且固定的参照，但未知动态AGC/降噪/响度处理不得准入；已知固定处理也必须说明其对可比性的限制。

## 4. 最低参照资格合同

| 资格 | 必须取得的真实证据 | 当前结论 |
|---|---|---|
| REFERENCE_INDEPENDENCE | 设备及采集路径身份；不经过Aftelle AudioGraph/VoiceProcessingIO，不共享本次AEC状态 | 现有VP信号不满足；外部候选UNVERIFIED |
| REFERENCE_SIGNAL_INTEGRITY | 已知PCM格式；增益固定；无未知动态AGC/NS/AEC/自动响度；限幅与完整性可检查 | UNVERIFIED |
| REFERENCE_PHYSICAL_PLACEMENT | TinyUSB附近固定位置、距离、方向、遮挡及支撑方式的登记；两轮不移动，不改变原设备摆位 | UNVERIFIED |
| REFERENCE_TIME_ALIGNMENT | 独立样本时钟、偏移/漂移与误差界证据；只比较共同且可信的内容覆盖 | UNVERIFIED |
| REFERENCE_EVIDENCE | 设备/系统/App身份，实际格式/增益/处理状态，原件SHA、RunID、完整性与封存记录 | UNVERIFIED |

理论支持不能填PASS；未知开关不能以默认值代填。参照放在TinyUSB附近仍不是同一ADC或同一空间点，位置、指向性及频响差异必须保留。不得遮挡原麦克风/扬声器或引入接触振动；摆位改变后的数据不得与前轮冒充固定声场。

## 5. 时间同步与有效覆盖（仅设计）

保留独立设备原采样率与样本计数，以秒和实际覆盖区间比较，不能直接对应16kHz Native、24kHz PCM与参照的样本索引。文件创建时间、按下录音按钮和软件播放请求都不是物理起音。

未来须在运行前冻结以下准入合同：

1. 建立参照时钟与HOST内容时间的偏移/漂移模型，登记模型来源与误差，不用名义采样率宣称两个时钟锁定。
2. 优先使用设备可信采样时间信息及原居民素材中分散的可辨特征作交叉核验，不新增提示音、不换素材。若用声学特征拟合映射，须分开拟合锚点与留出核验点，检查匹配歧义和随时间变化；低相关或多个可比峰不得配对成功。
3. **拟议准入上限：参与20ms比较的共同区间，合并对齐不确定度须有证据界定为不超过10ms。** 这是待主控审定的参照设计要求，不是已测精度、现有门禁修改或AEC性能标准。拟合残差小本身不足以证明误差界；无法验证时保持UNKNOWN。
4. 单次约3.75秒有效居民语音若只能提供局部锚点，最多证明锚点覆盖内的局部对齐；不得外推整个19秒或据此保证静默前后段。无足够跨度不能宣称测得整轮时钟漂移。
5. NCC最佳lag只是匹配估计，包含输出/采集处理与传播等因素，不能直接解释为物理延迟。保存映射与不确定度，不为使两轮相似而事后单独挑lag；边界不可信、缺样、时钟不连续或无重合时返回REFERENCE_INCONCLUSIVE，不补零造覆盖。

目前没有独立设备的时间接口或实际文件，无法证明上述精度可实现；这本身是停止准入的缺项，不用新同步框架补齐。

## 6. 最小配对实验设计（未实现、未授权）

前提：五项资格均有真实证据，主控另行审定设备、对齐合同及本地采集/转存权限；否则不启动。不是READY计划，没有新批次或执行授权。

| 项目 | 未来固定合同 |
|---|---|
| 次数 | 最多2轮，各独立App/Engine生命周期；不是声场参照有/无的AEC单变量实验 |
| HOST | 原TRIPLE_EQUAL、原Converter/Fade/图/评分器；TinyUSB系统60%、内置输出55%、未静音，VP/AGC ON；其余资格沿用原安全合同 |
| 居民 | 原固定WAV，SHA `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`；每轮4秒预热＋15秒评分，score+3秒请求播放一次 |
| 独立参照 | 已验证固定增益/处理及格式，固定在TinyUSB附近；先覆盖采集开始、居民有声段及尾部，范围与总时限在另行授权前冻结，不延长HOST19秒计划 |
| 配对证据 | 同轮独立参照录音、既有VP后Native证据、Player Render及时间、运行态设备/格式、独立时间映射/不确定度、SHA和RunID。Native统计不是ADC Raw，也不冒称完整Native WAV已保存 |
| 有效性 | 格式/处理状态可信、增益与位置不变、无未解释缺样/削波/限幅主导、共同覆盖及对齐达标，原技术门禁通过；不合格返回REFERENCE_INCONCLUSIVE |
| 比较 | 比较同一参照设备两轮的相对波形/能量稳定性，再分别观察VP后残留；不以未校准跨设备绝对RMS求衰减或ERLE |
| 停止 | 身份、权限、设备/配置、覆盖/对齐、时钟、导出、Stop或资源释放异常立即停余下轮；保留原UI确认与随时Stop。不改增益/摆位/阈值/素材，不重试、不追加第三轮 |

参照声场改变且Native相应改变：支持外部声学变化参与，不证明唯一因果。参照稳定而Native仍大幅不同：降低外部声场解释优先级，仍不能区分TinyUSB自身处理、VP内部状态和尚未观测的HOST状态，更不是Apple BUG证明。参照状态未知或两轮无强残留差异时分别记REFERENCE_INCONCLUSIVE或NOT_REPRODUCED，不扩展实验。

独立参照无法恢复M27过去未记录的声场，也不能用一处参照测量证明整个房间声场相同。

## 7. 隐私、权限与风险

本轮真实采集/播放/私人文件读取/下载/权限请求均0。没有打开Aftelle、录音App、麦克风或扬声器，没有改变音量、路由或Mic Mode。

未来新授权必须覆盖独立设备采集与本地转存，确认采集App处理及自动上传行为；不能沿用M27设备授权。Mac上的私有证据目录0700、文件0600，设备上的保存保护需按其真实系统另审，不能虚报相同POSIX权限。音频、私人JSON、UID和完整日志不进入Git或外部识别服务。

## 8. 缺失条件、裁定及唯一下一步

缺少：**一台已确认可用的独立采集设备及现有采集App/接口身份**；可验证的固定增益与AGC/NS/AEC/响度/限幅合同；实际PCM格式与动态范围；可信采样时间及对齐误差界；固定摆位和完整性证据。没有其中任何一项的实际PASS可供本轮填写。

因此选择**INSUFFICIENT_EVIDENCE**，不选择“已有充分设备证据”的FEASIBLE_WITH_VERIFIED_REQUIREMENTS，也不因抽象候选存在便写CONDITIONALLY_FEASIBLE。当前登记未提供可用参照，但没有核实外部设备确实不存在或明确不支持，不能断言NOT_FEASIBLE_WITH_CURRENT_EQUIPMENT。

**唯一下一步：补齐一台现有候选的型号、系统、现有采集App/接口及固定增益/处理路径资料，先由主控做文档准入。** 若没有候选或资料不足，就在缺项处停止；不要求购买，不下载替代App，不重跑AEC，不用Fake声场代替实测。无确认工程缺陷或生产修复依据，H1/H2/H3仍不能裁定。

## 9. 本轮检查与Stage状态

- Git三方起点核验、明确单报告白名单、`git diff --check`与staged diff检查、报告隐私/密钥扫描、`bash tools/secret_guard/check.sh`：PASS（各自一次正式交付检查）。
- 原工作区：7个冲突、原索引字节/未合并记录/status及14项未跟踪证据size/mtime前后不变；未读取其内容，未stash/pop、reset/clean、强推或处理冲突。
- 仅一个新报告，无跨文件修改；不需要创建跨文件回滚提交。生产源码、原评分器、AGENTS治理和正式阶段状态无修改。
- 编译、App/Fake/音频测试及硬件在线/权限读回：NOT_RUN，文档任务不重复这些操作。独立参照资格未实测，不把文档检查PASS当作声学可行性PASS。

Stage7 Forbidden Checklist（前/后）：**PASS**；触碰红线：无；修改文件：仅本报告；改代码/Runtime API/DR schema/新增平台target/进入Stage8：均否；无需额外读取确认，本轮在设备资格缺口处停止，不申请设备执行。

```ini
M29_FEASIBILITY=INSUFFICIENT_EVIDENCE
M29_REFERENCE_QUALIFICATION=UNVERIFIED
M29_DEVICE_EXECUTION=NOT_AUTHORIZED
M29_DEVICE_RUNS=0
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=DEFERRED
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
