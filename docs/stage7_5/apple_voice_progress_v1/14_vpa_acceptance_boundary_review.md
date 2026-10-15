# Apple Voice Progress v1 · VP-A研究收口与正式验收边界复核

日期：2026-10-15（Asia/Shanghai）。节点：Stage 7.5 / VP-A_ACCEPTANCE_BOUNDARY_REVIEW。

**复核结论：VP-A Research = POSITIVE_WITH_LIMITATIONS；建议当前研究活动CLOSED_FOR_NOW，交主控确认收口。VP-A Formal = BLOCKED。** 现有OFF可辨、ON未听辨出居民语句的内容对照，足以支持有保留的积极研究判断；不支持净AEC增益、零回声或正式Test3 PASS。不再继续USB排他取证循环，也不以无限补齐未知项作为主控单独审核VP-B研究准备的前置。本文件不授权B准备、实现或实机执行。

## 1. 基线与已确认事实

开始时 `Apple-Voice-Progress-v1` 的HEAD、upstream及实时远端均为 `aa603f731de7308a9a45dace17708d1ecfbb82b9`，工作区干净。本轮只新增14报告，按需核对01/02/06及07–13、正式Human Gate相关条款和Test2获批边界。无源码、音频图、正式合同或历史报告变更；无私人PCM/登记/设备身份读取、实时设备查询、Engine、录音或播放。

本节 **CONFIRMED** 指既有公开证据记录中的具体观察已获支持（`BY_REPORTED_EVIDENCE / USER_REVIEWED`），不是本轮重测或对声学因果的普遍确认。

| CONFIRMED具体事实 | 来源与保留边界 |
| --- | --- |
| VP_OFF Input可听辨居民语句 | [12§4](12_vpa_off_content_check.md#4-私有副本与用户实际听辨)：用户原音量手动试听选择A。保留原标签 `VP_OFF_INTELLIGIBLE_ECHO_SUPPORTED`；不是整段源语音、全部回声或正式协议PASS |
| VP_ON Input未被听辨出居民语句 | [11§5](11_vpa_on_evidence_triage.md#5-用户选择的私有内容听辨)：用户报告未辨出语句、有不明杂音。确认的是这次主观听辨结果，**不是确认没有残留** |
| 模式实际配置与有限生命周期记录 | [09§3](09_vpa_vp_off_timing_rerun.md#3-唯一执行及apple配置生命周期)、[10§3](10_vpa_vp_on_screening.md#3-实际执行apple状态及生命周期)：OFF双端disabled/AGC=false，ON双端enabled、bypass=false、AGC=true；实际播放、启动/停止与已观察路由稳定。非所有瞬时异步状态保证 |
| 已通过的连续PCM与封存子项 | 09每流13.5秒、10每流13.6秒连续PCM，记录器无已报lost/overflow/INVALID，seal与独立verify通过。完整性不自动等于窗口或声学完整 |
| ON原2/8/3数字评分跨度已获证 | [10§4](10_vpa_vp_on_screening.md#4-预热控制窗口与六阶段局部时钟)：六阶段局部配对及两流真实host/sample锚点支持原窗数字跨度；可选post-roll缺完整末端锚点仍单列，不补入评分 |
| P4已有指定近端语句响应 | [06§14](06_vp0_source_probe_device.md#14-用户追加授权提示修复及第二次采集)：成功轮7.8秒连续PCM、三声道均听到两句；保留APPROVED_SOURCE_SUPPORTED。不是正常语音保真或持续双讲验收，不重复P4 |
| quiet信号、声道重复等现象确有记录 | 11确认ON播放前有无法辨认的信号，后段频谱以高频为主；Input三声道重复，不能分配其内部角色。原因未确认 |

08首次VP_OFF、09复验的历史BLOCKED以及10/11的声学UNVERIFIED均保持原样。12只补内容负控子项；13只厘清来源机制和能力缺口。本14给出研究推进层级的综合判断，**不追溯把任何历史运行改为PASS**。

## 2. 有限研究结论与未知项

**SUPPORTED_WITH_LIMITATIONS：Apple VP整体路径具有降低可听辨居民回声的迹象。** 在已登记设备设置、同一固定历史素材及已报告真实外放背景下，OFF Input可辨居民语句，ON Input未听辨出居民语句，构成有意义的定性历史对照。已不限于“大RMS/小RMS”的推测，但尚非严格匹配、盲测或净AEC因果测量。[12§5](12_vpa_off_content_check.md#5-与1011的有限对照及剩余阻塞)

OFF与ON的Input rate/channels、AGC、Render格式/幅度及工具时序版本不同；同音量设置不保证同声压。正常Apple VP整体变化不能全归于AEC，也不能因ON低RMS或低相关就宣布成功。没有计算ERLE、跨轮净增益或设立新dB阈值。P4近端响应及登记USB默认路由共同支持 `SOURCE_SUPPORTED_ONLY`，不升级唯一来源。[13](13_vpa_on_source_verification.md)

| UNVERIFIED | 对本轮结论的实际限制 |
| --- | --- |
| 净AEC增益、零残留与一般化稳定效果 | 不能从整体VP/听辨差异剥离AGC、降噪、输出处理或噪声遮盖 |
| ON quiet杂音及后段高频成分来源 | 原因未知，不能改写为真人、环境噪声、AGC伪影或AEC故障；现场主观无异常不覆盖数字记录 |
| USB唯一物理输入来源、内部三声道角色 | 仍未排除替代/混合来源；也没有证据确诊实际用了错误输入。保留SOURCE_SUPPORTED_ONLY |
| 真实声压、全部声学时序与起尾音 | Render不是声压真值，数字host/sample覆盖不是全部物理到达/尾响证明 |
| 正常真人语音保真与持续双讲 | P4两句可辨不等于各类近端语音无损；A纯回声也不能排除近端损伤或验证双讲 |

这些未知必须进入后续证据说明；**本轮不将它们逐个升级为新增验收标准或无限取证任务**。尤其不要求购买声压仪、取得净ERLE、证明内部声道角色或通过当前不可得接口确认唯一USB后，才允许主控讨论独立研究准备。

## 3. 研究收口与正式协议通过分开

| 层级 | 本轮判断 | 不产生的授权/结论 |
| --- | --- | --- |
| A．VP-A声学研究能否收口 | **可以，POSITIVE_WITH_LIMITATIONS / CLOSED_FOR_NOW建议成立。** 已回答值得继续研究的有限问题；目前不需要继续A或USB排他循环来决定是否提交B准备审核 | 不表示所有声学未知已解决、Apple AEC PASS或永久免验证 |
| B．VP-A完整独立实验协议是否通过 | **BLOCKED。** 07要求的完整协议证据未全满足，09原2/8/3双流窗口仍仅条件性定位；本轮不修补或改判旧窗。ON数字跨度通过不能复制给OFF。quiet归因及两臂对照局限也仍在 | 不降低07的“对照可判读GO”，不以内容负控子项替代整项协议 |
| C．正式Test3产品安全是否通过 | **BLOCKED / NOT_EVIDENCED。** 独立工具不接Runtime，未验证正式负控/插话/双讲/取消全链 | 工具不具资格或中断能力，不等于已通过线上零误授予 |
| D．能否接正式工程链 | **NOT_AUTHORIZED。** 尚缺目标路线的近端/双讲能力、正式声源证据与既有Runtime配对/安全验证，以及Apple适用合同的主控裁决 | 不自动迁移后端，不解除 `sourceAttributionConfirmed` 或其他资格锁，不改已冻结接口 |

**CLOSED_FOR_NOW是停止当前A研究活动与重复补证的治理结论，不是PASS的别名。** 13的 `DESIGN_CAPABILITY_BLOCKED` 继续解释该排他取证路线，不再作为本阶段必须解锁的循环任务。保留物理来源未知是诚实限界，不是将其改判CONFIRMED。

格式/AGC不同、缺少净增益或SPL测量是比较解释的限制，不自动新增“两个模式必须相同格式/AGC”“残留必须数字全零”等要求。09原窗缺口则是已有协议事实，不能靠本轮研究收口取消。即使未来完整VP-A协议通过，也不等于正式Test3通过。

## 4. 正式Test3与研究安全边界

权威仍为[正式Human Gate](../../r8_5_unified_human_gate_checklist.md)；[01合同修订建议](01_test3_acceptance_revision_draft.md)只是待批准草案。本文不发布Apple新合同版本、不修改Test2或Test3。

| 正式条款 | 完整保留的义务及当前状态 |
| --- | --- |
| 53-A，正式L187–191 | 用户静音的5完整周期及既定音量/tail覆盖；false double-talk、source-gate false open、eligibility、confirmed、Provider interrupt/cancel、Playback clear、generation/lease变化、false user turn全部0。纯回声零错误资格/中断/虚假轮次不放宽 |
| 53-B，L193–197 | 10次真人实质性插话、既定发声位置/自然音量覆盖；资格、formal forward、语义融合、confirmed、interrupt、clear、generation等各严格+1，身份约束保持 |
| 53-C，L199–201 | 其中至少3次正常可识别语音持续重叠>1秒，原doubleTalk见证及同Session连续条件保留；不能用HIL代理或P4两句代替 |
| 53-D，L203–205 | confirmed后N立即stale，旧输出/回调拒绝，取消、清空、推进exactly-once，N+1恢复；Runtime身份、Session/lease/route epoch和持久化安全不绕过 |
| 53-E，L207–217 | 三段monotonic时间证据与本地 `confirmed→clear≤50ms` 保留；本A研究没有confirmed事件，此项 **NOT_EXERCISED**，不是0ms/PASS。200ms不自动成为Real Qwen全链硬门槛 |
| 后端适用性与证据来源 | 正式53-E仍绑定`.webRTCAEC3`；54-C/55-A另有相应恢复/保持要求。01的Apple版本化/见证映射待批准，不能直接替枚举、删计数或以缺字段当0；缺证记NOT_EVIDENCED |

错误History/Memory/Relationship/Tool副作用及身份/取消安全仍遵守正式共同记录与零副作用约束。普通活动候选、HAL读数、残余能量或语义转写不能自动变成权威声源资格；也不能将原合同的false double-talk等权威计数改名后删除。自然语音、极短附和与澄清策略仍按已批准语义处理，01的拟议变化不在本轮生效。400ms是语音持续时间维度，不是400ms完成全链中断的期限。

独立工具的 `sourceQualificationGranted=false`、未接Provider/Runtime及无正式cancel/clear，证明的是**隔离边界**。本次没有让正式检测/资格/语义链面对纯回声，所以不得把未执行的权威计数填成已验证的0。07–13听感、配置或容器子项也不能充当53-A的5周期与完整全链证据。

### 设备来源、声源资格与身份认证

1. **物理端点归属**：回答使用哪个麦克风/输入链。即使只接USB，它仍会同时拾取居民扬声器回声、环境声音及近端语音。
2. **运行时声学资格**：回答当前、同一目标路线的音频是否具有足以进入既有正式链的近端/非居民证据，并与时效和身份匹配。必须受纯回声负控、近端/双讲正控及既有安全规则约束，不能由设备UID或某条语义直接置true。
3. **真人声源真实性与语义意图**：真实性仍须有证据，但不等于识别某个具体人的生物身份。本轮不新增生物识别、声纹或专用“人类认证器”要求；是否有实质性插话意图由既有语义/Runtime链处理，也不能用明确语义反推声源真实。最终中断仍只能由现有Runtime依既有合同授权。

因此，**不再追唯一USB不等于放弃Runtime声源安全；确认唯一USB也不等于取得真人/中断资格。**

Test2已获批的本地身份保护、中断恢复、播放及持久化安全继续冻结；其独立Provider overlap仍0/3，不能改成持续双讲已通过。新Apple路线不能复制旧Test2 PASS替代本路线声学/身份配对证据，也不能为本研究重构Qwen Realtime原生全双工主链。[Test2获批范围](../../r8_5_3_test2_acceptance.md)

## 5. VP-B研究准备的准入建议

**建议主控后续单独审核“是否授权仅VP-B独立研究准备”，不要求先把VP-A Formal或USB排他证明改成PASS。** 正常近端保留尚未回答，具有与重复A/USB取证不同的决策价值；本句只说明可审核，不提供B实验方案或设备权限。

| 尚存限制 | 可否仅因它阻止主控审B准备 | 对正式接入的约束 |
| --- | --- | --- |
| 唯一USB未证、Builtin呈现/重复三声道 | 不作为自动否决；继承SOURCE_SUPPORTED_ONLY及未知，不重新启动13取证路线 | 不得冒充Runtime声源真实性，目标route/证据仍须可信可审计；如以后有具体错路由证据则停止接入 |
| quiet/高频原因、跨轮AGC/格式及声压局限 | 不阻止仅文档/非设备准备审核，也不认为已解决 | 未解释异常若使目标信号质量或证据不可判读，不能宣布相关能力通过或继续授权链 |
| 正常近端、双讲、正式资格和取消链未验证 | 不必先完成这些才能审核研究准备 | 实质阻止生产迁移、正式资格/中断接入或Test3 PASS；仍须分层获证，不能用当前积极结论抵扣 |
| Apple合同映射尚未批准 | 不把独立研究观察冒称正式验收即可提交准备审核 | 正式Apple适用合同、backend身份及权威见证必须由主控另行处理；01/本14不能自行生效 |

本轮 **VP-B/C = NOT_AUTHORIZED**。主控同意“可审准备”也不等于Codex已获准备、实现或录音授权；若另发新任务，需明确其范围、隔离、有限成本、可改变决策的问题与停止边界。设备录制/播放仍需另行现场许可；HIL代理不能取代真人最终正式验收。本文不设计、实现或执行B/C/D/E。

Runtime工程接入前真正不能跳过的是：目标路线有效近端保留/双讲能力、纯回声不获得错误正式资格的证据、已批准的适用见证与身份/新鲜度配对，以及既有exactly-once/旧代闭合/N+1/≤50ms义务。它们不因研究收口而获豁免；唯一物理端点证明不是这些要求的替代品或新增统一前置。

## 6. 主控最小裁决事项

1. **是否接受本次有限研究结论并收口当前A研究活动**：`POSITIVE_WITH_LIMITATIONS / CLOSED_FOR_NOW`，同时明确完整协议及正式Test3仍BLOCKED，保留全部历史记录和未知项。
2. **是否在后续另行发起“仅VP-B独立研究准备”的审核任务**：本轮不授权、不执行；没有该新决定就停在当前节点。该决定不连带批准B实机、C/D/E、Runtime接入或正式合同变更。

不要求主控现在批准01整体合同、解除source锁、迁移正式后端或先取得当前公开接口无法证明的USB排他性；这些不能捆绑进A研究收口。仅就已发布材料，未发现必须追加A证据才可作上述准备层决策的新关键反证，故**不提出新录音、旧PCM重分析、补窗口、调参、重复Mock或进一步USB取证任务**。正式验收缺口仍记账，不用“暂时收口”消除它们。

## 7. 三维审核及Stage7 Forbidden Checklist

**TECHNICAL_REVIEW：POSITIVE_WITH_LIMITATIONS。** 具体听辨/配置/PCM子项确认，有限研究支持与净AEC/物理来源/近端双讲未知分列；不以低RMS或未听到语句判零回声。

**ENGINEERING_REVIEW：DOCUMENTATION_ONLY / NO_CODE_CHANGE。** 仅做文档证据映射、条款/状态/链接、隐私与Git范围一致性检查。不运行独立音频工具或设备；Debug/Release、262项测试、Lint/Format/C11全部NOT_RUN，未重复冻结验证。

**EVIDENCE_REVIEW：RESEARCH_CLOSEOUT_RECOMMENDED；FORMAL_BLOCKED。** 可供主控接受当前研究积极结论与CLOSED_FOR_NOW；07原GO条件、08/09 BLOCKED、10/11声学未知、12内容负控、13来源限界均未追溯改变。没有授予任何新的阶段或Runtime权限。

| Stage7检查 | 结果 |
| --- | --- |
| Stage/macOS/六红线 | PASS；无新平台/Stage8，无六红线触碰 |
| Qwen原生全双工、Provider、Runtime、Test2 | PASS；实现、协议、API、授权、generation及取消机制均未改变 |
| DR/Studio/Memory/Session/ACE3 | PASS；无schema/资产写入，未操作原ACE3工作区、SSD/quarantine |
| 设备/私人数据 | PASS；无录音、播放、Engine、实时查询、权限操作、私人PCM或登记读取 |
| 历史/正式合同 | PASS；01–13和Test2/Test3合同原样保留，只新增14 |
| Git/后续阶段 | PASS；仅脱敏报告，无私人路径、音频、设备身份/摘要或密钥；不准备/执行B/C/D/E或Runtime集成 |

独立复核只读公开报告和正式条款，不冒充重新测量或试听私人证据。

```text
VP-A Research = POSITIVE_WITH_LIMITATIONS
VP-A Research closeout recommendation = CLOSED_FOR_NOW
VP-A Formal = BLOCKED
USB Source = SOURCE_SUPPORTED_ONLY
USB unique physical source = UNVERIFIED
VP-B/C = NOT_AUTHORIZED
VP-D/E = NOT_AUTHORIZED / BLOCKED
Runtime Integration = NOT_AUTHORIZED
Apple AEC PASS = NOT_ESTABLISHED
ACE3 Step 2A/2B = FROZEN
ACE3 Step 2C = PAUSED
Test3 = BLOCKED
Test3.execution_authorized = false
```

提交推送后停止，等待主控复审；不自动执行任何后续研究准备或实验。
