# Eterna Aftelle · T3.0-F · Fixture 恢复与基线验证

日期：2026-10-16（Asia/Shanghai）。入口：[README v2](README.md)。范围：只恢复原固定测试资产，补齐 [T3.0](T3_0_baseline_review.md) 因缺 Fixture 受阻的离线回归。

**T3.0-F = REVIEW_PENDING；Baseline Verification = PASS_PENDING_MAIN_REVIEW。** 七个指定入口各执行一次，全部 exit 0；未修改生产/测试源码、测试标准或忽略规则。结果只支持 Test2 离线安全基线，不替代历史在线验收、真实设备或正式 Test3。

## 1. Git、工具链与 Worktree 身份

| 项目 | 本轮实际核验 |
| --- | --- |
| Repository / origin | JerryYork3516/Eterna_Aftelle / https://github.com/JerryYork3516/Eterna_Aftelle.git |
| Branch / upstream | Test3-AppleVP-Clean / origin/Test3-AppleVP-Clean |
| 起始 HEAD、upstream、实时远端 | 均为 bcb70a830c48d7638263114c868cf134fe95e9f0；初始工作区干净 |
| 实际测试 HEAD | bcb70a830c48d7638263114c868cf134fe95e9f0；全部测试在文档修改及回滚提交前执行 |
| Test2 源码基线 | 728423813ebfc60e303372f3761fc631ac1c03d1；apps、tools、brain、shared-protocol 的跟踪文件与其零差异 |
| Clean Worktree | 独立 Eterna_Aftelle_Test3_AppleVP_Clean 目录；原 ACE3/VP 目录只读 |
| 原目录保护 | ACE3 保持 a7563f9a16aebeaa05398a155c6b38b604362f91 及原有未提交状态；VP 研究保持 c64c7e2629ec775062fdc2ea1e4a934c73c1fa75 及干净状态；前后 diff/status 摘要核验一致 |
| 工具链 | Xcode 27.0 / 27A266a，Swift 6.4，macOS SDK 27.0，arm64；未替换 SDK、项目配置或依赖 |
| 文档回滚点 | 8b5b7fdaf08acaee47d6e917259755d1a05db2e6；测试完成后建立同tree空提交，不改变已测源码 |

生产及测试输入身份按测试 HEAD 登记，覆盖66个已跟踪路径（Swift、fake、脚本、timeout runner、项目静态检查与资产登记等，不表示66项都为编译单元）。逐文件 Git blob 清单留在本机忽略目录；Fixture、日志和本机私人 SHA 不写入本报告或 Git。

## 2. Fixture 来源、独立授权与信任链

预定目标固定为 apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident。

1. 授权前仅对 git worktree list 已知目录的上述同一路径检查存在性、lstat 类型/权限/长度及符号链接目标；未全盘搜索、读取内容、计算 DR 摘要或复制。
2. 登记候选 F-01：原 ACE3 checkout 的固定相对路径，普通可读文件，9,058,396字节，0644。三个已知历史测试 Worktree 同名链接均指向F-01。另有同名普通副本，但未读取或用其替代。Clean与VP研究目录无此文件；路径/大小本身不作为原件证明。
3. 向用户报告来源、候选身份、恢复目标及尚未核验的限制；用户本轮明确回复：**“授权核验 F-01；通过后恢复并跑离线回归”**。此回复发生在读取内容、摘要和复制之前，不沿用其他轮次私人内容授权。
4. 原件证明使用已跟踪的 [冻结资产登记](../../../apps/macos/Aftelle/Fixtures/Stage7_5/stage7_5_test_assets.json) 的 resident 子记录；该登记原字节与Test2冻结提交相同。F-01同时匹配 required_sha256、sha256、文件名/长度、resident_id、revision及版本登记。摘要与身份的具体值仅私存，公开只报告匹配结果。
5. 必要格式核验通过：JSON对象、受支持版本、manifest/payload双身份与名称一致、语言/结构字段存在、non-executable及四个安全flag满足。浅核验不能替代Runtime完整解析；其后实际七入口均通过既有Runtime loader。
6. 用非链接源读取与前后stat检查防止读取期间变更；目标以exclusive create方式创建，拒绝覆盖，原字节复制，目标0600。复制后逐字节/摘要一致，测试后再次确认源与目标完整性；未修改其他Worktree原件。
7. .gitignore未改，原有 *.digital_resident 规则排除目标，git ls-files无此资产；恢复后跟踪工作区仍干净。无symlink替代或假DR生成，也未把其他居民冒充固定Fixture。

结论：**RESTORED_BYTE_IDENTICAL / REGISTERED_TEST2_ASSET_MATCH**。runner本身没有固定摘要pin；本轮在执行前通过冻结registry完成外置pin，不能仅以“能够loadDR”证明原资产身份。原件/目标摘要、必要登记身份、授权与复制记录保存在Git外，不打印DR内容、私人字段或密钥。

## 3. 离线边界、依赖与执行环境

逐项只读审核check.sh、必要测试注册/fake及调用依赖，确认：

- Qwen使用注入的内存Fake WebSocket；Evidence/resident使用fake权限、credential、capture、device、AEC、player；InputBridge使用fake frame source/provider。链接AVFoundation/CoreAudio/Security或存在endpoint字符串不代表调用真实设备、Keychain或Provider。
- 既有DEBUG Controller初始化仍执行ProviderKeychainStore.exists的系统Keychain存在性/属性查询（AppController 803–831、6280–6287、6318–6331；ProviderKeychainStore 54–60），未请求secret data，未调用secret读取/写入/删除路径。Provider执行仍使用注入Fake。CFFIXED_USER_HOME仅隔离测试Session/Memory/UserDefaults，不是系统Keychain隔离证明；不声称Keychain API调用为零，也未新增此调用路径。
- confirmed仅包装r832-confirmed-only，latency仅包装r833-latency-stale-only；各通过指定包装入口执行一次，不再单跑相同模式。
- r823-full执行独立负控/正控和持久化；r853-qwen-suite只编译一次并执行handoff、repeated reassociation、queued-start三个子模式，不再单跑这些子模式。未运行total_regression、r851-key-repeat或额外重复矩阵。
- 控制器在子进程环境中移除 AFTELLE_R853_NEAR_END_PCM16LE，确保仅用代码合成PCM，不读取外部私人音频；同时移除 AFTELLE_PENDING_REVIEW_CASE、AFTELLE_UNSENT_RACE_ONLY、AFTELLE_PENDING_ANSWER_ONLY、AFTELLE_CANCEL_HANDOFF_ONLY，保证Qwen默认完整覆盖。未打印这些变量原值。
- 每入口设置独立TMPDIR及CFFIXED_USER_HOME；InputBridge脚本未自行设置home，因此外层隔离尤为必要。其余脚本继续使用自身独立runtime-home；r853进一步按子模式隔离。未重定向或覆盖系统HOME。
- 测试可能在隔离临时目录写原Fixture副本及测试Session/Memory；不修改原DR字节，不访问用户业务持久化。关闭core dump，原始stdout/stderr、退出码/时间及私人完整性证据仅保存于忽略目录。

以下为实际传给子进程的命令；环境移除/隔离通过执行控制器的环境字典完成，未修改check.sh或Swift。全部首次执行完成，无失败重试。

## 4. 七个入口实际结果

共同源码/测试身份为§1的测试HEAD，测试资产均为§2已验证F-01；每项完整输入、退出码、原始日志与时间记录均私存。第一失败原因栏不以缺失日志代替成功标记：各入口均取得exit 0和其既有完成/guard要求。

| # | 实际执行命令 | exit / 结果 | cases / checks | 第一失败原因 |
| --- | --- | --- | --- | --- |
| 1 | bash tools/qwen_realtime_resident_brain_tests/check.sh | 0 / PASS | 148 / 1972 | 无 |
| 2 | bash tools/realtime_interruption_evidence_tests/check.sh | 0 / PASS | 24 / 205 | 无 |
| 3 | bash tools/realtime_confirmed_interruption_tests/check.sh | 0 / PASS | 1 / 62 | 无 |
| 4 | bash tools/mac_speech_realtime_brain_input_tests/check.sh | 0 / PASS | 32 / 210 | 无 |
| 5 | bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r823-full | 0 / PASS | 12 / 126 | 无 |
| 6 | bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r853-qwen-suite | 0 / PASS | 3子模式，合计15 / 208 | 无 |
| 7 | bash tools/realtime_barge_in_latency_stale_audio_tests/check.sh | 0 / PASS | 1 / 68 | 无 |

Qwen默认pending-answer matrix为37 cases / 774 checks，包含在148/1972总数内，不重复相加；默认覆盖、wire scope、Runtime seam、credential scope guards通过，real websocket明确NOT_RUN_HUMAN_GATE。

r853三个子模式分别为：handoff 10/110、同Session repeated reassociation 1/58、queued-start 4/40。每模式仅一次；重复场景内部预定的10次interruption是原测试合同，不是外层重跑到PASS。该模式证明Fake transport下的既有Adapter/Controller链，不是10次新在线Qwen实验。

本轮无FAIL/BLOCKED/未完成的指定入口。T3.0原记录的缺文件exit 1/133、停止的r853和未启动latency保持历史事实；本报告补充新运行，不覆盖旧结果。

| 已有检查或范围 | 本轮状态 / 原因 |
| --- | --- |
| Debug/Release未签名构建 | NOT_RUN；T3.0已PASS且源码/配置未变，不重复 |
| Release route guard、Host131、Playback172 | NOT_RUN；T3.0已PASS且未受影响，不重复；本轮包装内自身guard不等于重跑这些套件 |
| 真实Qwen/其他Provider、麦克风/扬声器、Apple VP、私人PCM/WAV、完整A7/正式Test3 | NOT_RUN；未授权且本轮无执行 |
| Fixture恢复前的依赖测试 | NOT_RUN；先授权、验证、恢复，再一次执行，未重复触发缺文件错误 |

## 5. Test2安全结论与实际证据

| 安全边界 | 本轮证据 / 有效范围 |
| --- | --- |
| Qwen身份碰撞、canonical user | 默认148/1972含跨角色/assistant ownership、canonical用户、旧连接、generation与cancel等待防护；默认完整矩阵通过，不以碰撞消失或模型普遍正确作为结论 |
| RuntimeCore唯一中断owner、exactly-once | Evidence24/205和静态authority guards通过；confirmed1/62中eligible/observed/acoustic/semantic/confirmed/provider interrupt/clear各1，Runtime/Playback generation各+1，Session/lease/routeEpoch变化0 |
| Provider取消与Playback clear | confirmed Fake provider报告interrupt=1、cancels=0，是该fake契约，不伪称wire cancel=1；真实Adapter注入Fake WebSocket的Qwen默认及r853覆盖原cancel链。r853同Session interruptions/cancel-wait reassociations/clear-before-ack各10，无新增取消owner |
| generation/stale与N+1 | InputBridge32/210及latency1/68；110旧事件注入/返回供校验，fence后接纳旧输出、旧代播放、旧播放重启、旧文字/字幕复活均0；N+1 Input/Output/Playback/Listening各1 |
| Session/Memory/History/Relationship | confirmed及resident-only错误轮次/错误持久化为0；原load/append/导入路径在隔离home回归，不写用户业务目录 |
| resident-only负控与正控 | r823负控6场景、740 observations、3840 audio frames；eligible/confirmed/interrupt/cancel/clear/generation/lease/false-turn/错误持久化为0。长负控另报告120 observations/3840 frames；正控eligible/Runtime observed/acoustic各1，只有声学证据时confirmed/clear仍0 |
| 首次麦克风权限/Stop fence | Evidence中的六组权限用例通过，fail-closed Provider sessions=0，迟到授权后Provider sessions/prepare calls=0；重复Start permission requests/provider sessions各1。是fake权限控制流，非实际系统权限弹窗实验 |
| 本地Fake延迟/stale | first-valid-near-end→eligibility=7.710750ms，confirmed→clear=0.271750ms，first-valid-near-end→clear=31.108625ms；仅该Fake run，不能当Real Qwen语义/网络或物理设备延迟 |

上述离线回归未发现Test2已冻结安全机制退化。继承 [Test2验收](../../r8_5_3_test2_acceptance.md) 的批准范围，不把当前离线结果替代历史在线10轮、真实声源归属或正式53-A～E。

**Qwen Strict Overlap = 0/3** 原样保留。本轮没有同旧response/连接的真实持续overlap样本，也不把合成双讲、cancel成功或物理双讲视为该资格。

## 6. 未解决事项与 T3.2-A 准入建议

- Fixture缺口已恢复并完成全部受阻入口；T3.0 Baseline从历史PARTIAL/FIXTURE_BLOCKED更新为 **PASS_PENDING_MAIN_REVIEW**，本轮不自行宣布主控APPROVED。
- 主控本轮明确 **T3.1-R2 Plan = APPROVED**；只在README记录当前批准，不追溯修改R2与T3.0历史报告。正式Apple合同等价剖面及后续节点执行授权仍按独立边界处理。
- SQ-M1保持MAJOR OPEN：它是Apple处理结果与Test2既有接口的兼容/安全问题，不阻PCM机械设计，不能因本次Test2离线PASS关闭；安全不足时正式中断fail-closed。
- Apple状态/活动/时间等价证据、53-C自然合格样本、R8.5.4完整设备/网络、R8.5.5长会话/Release及T3.P仍未验证；本轮不对这些判PASS。
- 建议主控审核本报告后确认基线验证结果，再单独批准T3.2-A执行范围和预算；**T3.2-A/B仍NOT_AUTHORIZED**。本轮不接入Apple生产代码，不把恢复Fixture当下一节点授权。

## 7. 五维审核与问题登记

实际来源为本任务内三个独立AI Reviewer，均阅读落盘报告后审查，不以运行前方案审核代替最终结论。作者/root负责恢复、执行、编辑和交付SELF_REVIEW；独立Reviewer未运行测试、改文件或读取私人DR。五维通过是Codex审核建议，不是主控批准。

| 维度 | 实际来源、范围与证据 | 最终结果 |
| --- | --- | --- |
| TECHNICAL_REVIEW | /root/t30f_safety_review：实际报告、脱敏结果、冻结registry和必要源码/断言；核对Fixture信任链、Runtime唯一授权、Fake契约、权限/Stop、cancel/clear/N+1/持久化和负控；未重复读取私人DR/摘要 | PASS；文档及离线基线范围 |
| ENGINEERING_REVIEW | /root/t30f_script_audit：七入口与包装依赖、隔离/环境、真实Git diff与输入身份、无重复/源码修改/新owner | PASS |
| EVIDENCE_REVIEW | /root/t30f_script_audit：报告/脱敏记录与七份实际日志的164项计数/guard逐项一致，另核对pending37/774；/root/t30f_safety_review复核技术证据边界 | PASS；原始日志未公开，最终exit/完整完成标记均有记录 |
| CONSISTENCY_REVIEW | /root/t30f_consistency_review：实际报告、README/DEVLOG diff、脱敏结果、保护文件Git核验；对照主控授权与T3.0/R2/Test2/0/3/OPEN边界 | PASS；未读取私人字节，不冒称独立重算Fixture摘要 |
| Stage7 Forbidden Checklist | /root/t30f_consistency_review独立检查；作者对实际交付复核；Keychain既有metadata查询限制如实披露 | PASS（本轮范围）；六红线未触碰 |

| 问题 / 严重度 | 发现、修订与复验 | 状态 / 限制 |
| --- | --- | --- |
| T30F-E1 / MINOR（技术与证据Reviewer同一发现，合并登记） | 初稿§8“无任何Keychain调用”过强；既有DEBUG Controller init执行exists属性查询。§3/§8明确真实边界及home隔离限制；两Reviewer定点复验通过，不改代码或重跑 | CLOSED（文档修正） |
| SQ-M1 / MAJOR（历史继承，非本轮回归失败） | Apple处理结果/既有声学接口兼容安全仍未验证；本轮只恢复Test2资产与回归 | OPEN；不阻PCM机械设计，不开放正式中断或Test3 |

新增问题计数：CRITICAL=0、MAJOR=0、MINOR=1（CLOSED）；新增未关闭项=0。继承MAJOR OPEN=1（SQ-M1）。七入口无未关闭回归失败；T3.0-F维持REVIEW_PENDING、Baseline维持PASS_PENDING_MAIN_REVIEW。

## 8. Stage7 Forbidden Checklist

| 检查域 | 本轮事实 / 结论 |
| --- | --- |
| A 阶段；G 调度 | Stage7.5 macOS离线回归与文档，无新target/Stage8/多居民/后台监听或调度：PASS |
| B RuntimeCore；C Host | Runtime仍唯一Decision/Provider/Session/Memory授权owner；无源码/接口修改、新状态owner或旁路：PASS |
| D DR/API | 只恢复冻结登记的原测试资产，原件与内容零改动、忽略且未跟踪；不改fixture标准/schema/API：PASS |
| E Provider/secret | 明确Fake依赖、清除外部PCM开关，无真实Provider/音频设备调用或secret读取/写删/入Git；既有DEBUG初始化的Keychain存在性/属性查询已披露，未新增路径/依赖：PASS |
| F 持久化/Trace | 测试home/TMP隔离，未改业务持久化或DR，私人原始证据Git外保存：PASS |
| H UI/渲染/路线 | 未改UI/渲染/音频后端/阈值，保留Realtime与Cascaded边界，不启动音频Engine：PASS |
| I 输出/证据 | 新运行、旧PASS、前置阻塞及NOT_RUN分开，保留0/3/OPEN/BLOCKED，不篡改历史结果：PASS |

六条红线逐项：①大脑不碰平台PASS；②Store带版本PASS（无schema改动）；③三层不黏连PASS；④DR只读/revision PASS（只按字节恢复，不改原件）；⑤逻辑/画法分层PASS；⑥Intent交互PASS。

Stage7结论：**PASS（本轮范围）**。触碰红线：无。获批文档范围为本报告、README必要状态和DEVLOG简记；不改生产/测试源码、Runtime API、DR schema、.gitignore、target或历史合同。无需追加权限继续本轮已授权文档交付；提交后停止，后续节点另行授权。

## 9. 证据保管、交付与最终状态

私人Fixture/原始日志/私人SHA/本机绝对源路径均留在Git外。对外文档不包含DR实际身份、名字、revision值、完整资产摘要、原始日志或私人音频。提交前再次核验显式三文档白名单、链接、旧报告零差异、原Worktree与Fixture完整性；正常push，不强推。

~~~text
T3.0 Documentation = APPROVED
T3.0-F = REVIEW_PENDING
Baseline Verification = PASS_PENDING_MAIN_REVIEW
T3.1-R2 Plan = APPROVED
T3.2-A/B = NOT_AUTHORIZED
T3.3–T3.6 = NOT_STARTED
SQ-M1 = OPEN
T3.P = NOT_AUTHORIZED
Qwen Strict Overlap = 0/3
Production Apple VP = NOT_STARTED
Formal Test3 = BLOCKED
Test3.execution_authorized = false
~~~

报告和实际Git交付身份以最终commit/远端核验为准，不在文档内自引用本提交SHA。完成本轮后停止。
