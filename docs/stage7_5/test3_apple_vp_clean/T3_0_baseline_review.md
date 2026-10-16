# Eterna Aftelle · T3.0 · Test2 基线审核

日期：2026-10-16（Asia/Shanghai）。关联入口：[正式节点计划](README.md)。

**T3.0 = REVIEW_PENDING；基线验证 = PARTIAL / FIXTURE_BLOCKED。** Debug/Release 构建、Release 静态检查及 Host/Playback 基础回归通过；身份与中断回归缺少未跟踪 fixture，不能报告全部 PASS。Test3 继续 `BLOCKED`，`execution_authorized=false`。未移植生产代码，未开放 Apple VP 或正式自动中断。

## 1. Git 身份与隔离

| 项目 | 实际核验 |
| --- | --- |
| Repository / origin | `JerryYork3516/Eterna_Aftelle` / `https://github.com/JerryYork3516/Eterna_Aftelle.git` |
| 远端预建分支 | `Test3-AppleVP-Clean`，建立前实时 `ls-remote` 为下述完整初始 SHA |
| 初始 HEAD | `728423813ebfc60e303372f3761fc631ac1c03d1` |
| 初始 tree | `f526846e8d0239703d8d89bdfb5d3eeb49c3b85a` |
| 本地分支 / upstream | `Test3-AppleVP-Clean` / `origin/Test3-AppleVP-Clean`；初始 ahead/behind=`0/0` |
| Worktree | 新建独立目录 `Eterna_Aftelle_Test3_AppleVP_Clean`；此前目录不存在，无覆盖 |
| 初始工作区 | `git status --porcelain` 为空；无旧未跟踪 PCM、DR 或源码补丁 |
| 原目录 | ACE3 保持 `a7563f9a16aebeaa05398a155c6b38b604362f91` 及原未提交状态；VP 研究保持 `c64c7e2629ec775062fdc2ea1e4a934c73c1fa75` |
| 文档修改前回滚提交 | `0d3fb87ff64c2800718db6011fdf65e4b26843bc`，空提交，tree 与初始基线相同 |

先执行 `git worktree list --porcelain`、`git status`、`git branch -avv`，确认没有同名目录/本地分支占用；仅 fetch 已有远端分支，再 `git worktree add --track -b` 建立本地追踪。未重复创建远端分支，未改变其初始起点。各 checkout 路径分离，Git 对象和 refs 按正常 Worktree 机制共享；不把共享 Git 元数据误称为完全独立仓库。

构建和离线执行均在任何文档改动及回滚提交之前进行，实际测试 HEAD 就是初始 SHA。源码/构建输入没有移植历史补丁。原目录仅作 Git 元数据和 diff 摘要核验，不读取私人音频或 DR。

## 2. 执行范围与工具链

只读取 AGENTS、Test2 验收、Stage7 checklist、统一 Gate 的有关条款、冻结 VP 架构/24 号结论、指定修复差异、必要脚本和关键源码；开发手册仅取执行/回滚规则。未全库扫描；未运行完整 A7、WebRTC build/sync、研究 CLI 或在线探针。

工具链为 Xcode `27.0 / 27A266a`、macOS SDK `27.0`、Apple Swift `6.4`、arm64。项目保留 `MACOSX_DEPLOYMENT_TARGET=26.5` 和 `SDKROOT=macosx`，没有覆盖目标版本或替换依赖。

先核实共享 scheme 文件并执行 `xcodebuild -list -project apps/macos/Aftelle/Aftelle.xcodeproj -disableAutomaticPackageResolution -skipPackageUpdates`，实际 target/scheme 均为 `Aftelle`，配置包含 Debug/Release。

构建命令（`<configuration>` 分别为 Debug、Release）：

```sh
xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj \
  -scheme Aftelle -configuration <configuration> \
  -destination platform=macOS \
  -derivedDataPath .build/t3_0_baseline_review/DerivedData \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO build
```

这是未签名编译/链接检查，未 launch、install 或执行 App，不等于签名、Release Human Gate 或设备验收。没有执行 clean，也没有更改生产配置。

实际生成的 `Aftelle.app/Contents/MacOS/Aftelle` SHA-256：

| 配置 | 本轮 binary SHA-256 |
| --- | --- |
| Debug | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Release | `8b05d84140198a1fb0043ef6f0db5940a401fc691f6916036b4f22db808ea629` |

## 3. 实际 Build / 离线结果

每条离线脚本使用独立 `TMPDIR` 和 `CFFIXED_USER_HOME`；调用 fake transport、fake credential/device/capture/player 或代码合成 PCM。没有真实 Provider、Keychain 读取、麦克风、扬声器或私人音频调用。Output 套件虽构造 engine wrapper，但只调用注入的 stop，不 configure/start AVAudioEngine。

| 检查 / 实际入口 | 结果 | exit / 已取得证据 |
| --- | --- | --- |
| Debug build | PASS | 0；18.297 秒，`BUILD SUCCEEDED` |
| Release build | PASS | 0；37.032 秒，`BUILD SUCCEEDED` |
| `bash tools/realtime_release_route_guard/check.sh` | PASS | 0；Release 声明、调用边、权限先于 Provider、UI 入口、termination fence |
| `bash tools/qwen_realtime_resident_brain_tests/check.sh` | FAIL / PREREQUISITE_BLOCKED | 1；编译完成后输出 `qwen_realtime_resident_brain_fixture=BLOCKED`，运行断言未开始 |
| `bash tools/realtime_interruption_evidence_tests/check.sh` | FAIL / PREREQUISITE_BLOCKED | 133；测试二进制加载 fixture 时顶层缺文件错误，不能声称权限/Runtime 断言通过 |
| `bash tools/realtime_confirmed_interruption_tests/check.sh` | FAIL / PREREQUISITE_BLOCKED | 133；同一缺文件，confirmed 断言未完成 |
| `bash tools/mac_speech_realtime_brain_input_tests/check.sh` | FAIL / PREREQUISITE_BLOCKED | 133；`missing fixed R7 resident fixture` |
| `bash tools/speech_audio_host_tests/check.sh` | PASS | 0；131 checks，含 packetization、route/lifecycle、权限及共享图边界 |
| `bash tools/speech_audio_output_tests/check.sh` | PASS | 0；172 checks，含 queue/clear/stale、pressure、continuous playback、bit-exact |
| `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r823-full` | FAIL / PREREQUISITE_BLOCKED | 133；模式分派前加载同一 fixture 失败，负控断言未完成 |
| 同脚本 `r853-qwen-suite` | NOT_COMPLETED / PREREQUISITE_STOPPED | runner 已进入编译；确认公共前置缺失后停止本轮验证进程树，未取得 handoff 断言结果 |
| `bash tools/realtime_barge_in_latency_stale_audio_tests/check.sh` | NOT_RUN / PREREQUISITE_BLOCKED | 未启动；依赖同一 fixture |
| Stage7 人工越界检查 | PASS | 仅本轮文档/离线范围，见第 9 节 |
| 设备、真人、在线 Qwen/Provider、私人音频、完整 A7 | NOT_RUN | 不在本轮授权范围 |

缺失文件为 `apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident`。`git ls-files` 对该文件无输出，`git check-ignore -v` 指向 `.gitignore` 的 `*.digital_resident`。因此新 Worktree 不会获得它；这不是当前源码功能断言失败或 App 真机 crash 的证明。

本轮入口审核确认了脚本存在和 fake 依赖，但漏查 fixture 的实际存在性，导致若干测试重复在前置阶段终止。确认共享缺口后停止后续依赖执行。没有从旧目录复制居民文件，没有生成替代 fixture，没有修改源码/测试，也没有把旧报告计数当作本轮 PASS。

原始日志、退出码/用时 JSON、本地日志 SHA 清单只保存在忽略目录 `.build/t3_0_baseline_review/`，不提交 Git；公开报告只记录上述摘要。缺口需另行明确安全 fixture 的来源、权限与可复现配置，再对受影响入口复验，不能默认为已补齐。

## 4. 已有安全机制与静态证据

| 能力 | 核验结论与源码身份 |
| --- | --- |
| Test2 范围 | `docs/r8_5_3_test2_acceptance.md:3–27`：缩小范围 PASS；严格 Provider overlap 独立保留 0/3 |
| Release 正式入口 | `cbd4736bf29ff25c368dcdc13f655b34c44f0cf7` 是基线祖先；基线 Controller `758–767` 接 production composition；本轮构建及静态 guard PASS |
| 麦克风权限 | `b005109d7c8634afd43464cfec54cbd9bf0423e8` 是基线祖先；Controller `3103–3136` 在 await 后重验 attempt/shutdown，拒绝 denied/restricted；动态离线断言受 fixture 阻断 |
| Qwen 身份 | 基线 Adapter `1127–1168、1559–1583、2052–2056` 保留隔离恢复与 connection token fence；到 `c64c7e2` 的 Adapter、composition、Realtime Output Bridge 均 ZERO_DIFF，无后续同类修复可声称必须搬回 |
| Runtime 授权 | 基线 RuntimeCore `5601–5679、5731–5887` 校验声学与语义证据、身份和时间并产生单一 Decision；Host/Provider 不取得 generation authority |
| 共享依赖 | 基线 Controller `729–741、778–790` capture/player 共享 engine；Realtime/Native bridge 共用 speechAudioHost；Capture `686、714–735` 固定模式；Cascaded `4549–4555` 仍标 `.aec3Processed` |

上述源码行号均对应 `728423813ebfc60e303372f3761fc631ac1c03d1`，不是当前文档行号。静态存在不等于本轮缺失的动态回归已经通过。

Apple 后端只是可复用骨架：Capture `850–862` 播放时 mute；`943–977` 在 VP enable 前取 mixer 格式并连接 player；Acoustic Host `977–980、1055–1075、1184–1203` 使用 disabled stats 和 uncertain 分类。Capture `41–60` 活动标签与 Runtime provider `448–500、593–649` 又依赖旧 AEC 事实。因此不能只切枚举，也不能伪造 linear PCM/ERLE/confidence 接通旧判断。

## 5. 选择性移植清单（仅分析，全部未实施）

来源完整 SHA：

- A：`a3458ef6c7bac13a480fd84d9afac2d998abccd5`
- B：`01728b34c539c71cceeb63cd0721269580b2fad9`
- C：`904613c1903c90d66432fa367818e3b68806711d`
- D：`fbe7b77ec663832954d428bac90694447cecfba7`
- E：`1d3cfcb59b5cd4626d06c3ea04ba1a08d9e639f7`

下表源文件均取对应历史提交，目标为干净分支中**相同仓库相对路径**；“基线无”指修复尚不在 Test2，不等于本轮观察到实体故障。

| ID / 来源 / 源文件＝目标文件 | 实际问题；基线是否已有 | 移植判断、依赖、最早节点 | 必须回归；不得同带 |
| --- | --- | --- | --- |
| P1 / A / `apps/macos/Aftelle/MacSpeechAudioCapture.swift` | Apple startOutput 主动 mute，配置依赖 muted-speech listener；基线无修复 | 必须保留持续 unmuted 和移除 listener 启动门槛的语义；T3.2，依赖 VP 配置/失败关闭 | 播放期间采集连续、start/finish/clear/stop/close；不带 HAL start 硬依赖、RMS/相关性 Gate、软件注入资格 |
| P2 / A / 同上 | stopCapture 持状态锁 removeTap，回调也取该锁，存在锁等待环风险；基线无 | 应移植先撤 active、释放锁后 removeTap 的最小顺序；T3.2，不能外推所有 tap 路径已安全 | Stop/close 幂等、在途 callback、start/stop 竞态；不带 VAD/runner/诊断，不声称已测出设备死锁 |
| P3 / B / 同上 | render tap 固定配置时 localFormat，重建后可能过期；基线无 | 应移植 `format:nil`；T3.2，与 VP enable 后重新协商格式共同验证 | 初始图、路由 rebuild、输出/converter 格式；不带旧设备 Gate |
| P4 / C＋D（含 A 的纳秒容差取整）/ 同上转换器及 capture/render 调用点 | Test2 返回数组并沿用输入 callback 时间，未维护输出内容区间；基线无 | 复用现有 converter 时必须保留 output cursor、完整输入覆盖、sample/host 连续性、reset；T3.2，C/D 和调用点成组适配 | 44.1/48k、跨 callback、缺时间、前跳/倒退、亚采样 jitter、generation reset；不带 raw PCM trace、HAL ledger、WebRTC 声学补偿 |
| P5 / E / `apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift`、`apps/macos/RuntimeCore/RuntimeCore.swift`、`apps/macos/Aftelle/MacSpeechRealtimeBrainInputBridge.swift` | 无独立 sourceAttributionConfirmed 最终硬条件；基线无 | 必须保留资格与非零 epoch 硬约束；T3.1 只定规则，T3.3 建 facts/Shadow，T3.4 正式执行前接通；依赖获批规则和可靠证据 | false/zero/unknown、设备/route/stale/duplicate、声学语义两种到达顺序、纯回声；不带 causal qualification、explicit UI，不直接赋 true |
| P6 / E / `apps/macos/Aftelle/MacSpeechRealtimeBrainInputBridge.swift`、`apps/macos/Aftelle/AppController.swift` | confirmed resume 会 discard/drain 未提交 capture，短插话可能被丢；基线无保留路径 | T3.4 原子组：有界 capture 保留＋等退休 pump＋脱离 pump callback 执行 transition；仅匹配 confirmed Decision，普通切代仍丢旧数据 | 字节/顺序、短句 onset、旧 pump completion、发送归属不明、Stop/route change、N+1；不带 episode、pause/resume、功率比阈值 |
| P7 / E / `apps/macos/RuntimeCore/RuntimeCore.swift` | complete 等待后不清 pending；基线 close 已有匹配清理，自动路径也可覆盖 pending | 建议 T3.4 保留只清同 Decision 的生命周期收敛；不是“基线自动中断必停摆”，不依赖 explicit API | 连续 confirmed、close/complete 竞态、旧 complete 不清新 Decision、失败恢复；不带 explicit interruption API/UI |
| P8 / E / `apps/macos/Aftelle/MacSpeechAudioOutputHost.swift` | watchdog 只有 generation 检查，同 generation 旧回调仍可能迟到；基线无 token | 应独立保留 consumerWatchdogID；最早 T3.2、最迟 T3.4，不依赖 provisional pause | 同 generation 重启拒绝旧 timeout、真实 timeout、stop/close/route 清 token；不带 pause 状态和 player pause/resume |

来源审查位置：A Capture `886–897、941–967、1040–1064`；B Capture `1380–1394`；C Capture `683–761`；D Capture `762–857`；E Runtime provider `772–783`、RuntimeCore `5759–5773、5950–5967`、Input Bridge `419–542、667–692、809–834`、Controller `3829–3866、4251–4254`、OutputHost `583–621`。这些位置对应各来源 SHA，不能混用为 Test2 行号。

P6 不应被描述为 Test2 已存在自等待：旧 suspend 不等待退休 pump；自等待是移植新增等待后必须同时防止的依赖风险。P7 也不作为已证实的自动中断停摆根因。

后续可选择性复用的历史回归素材包括 E 的 capture-preservation 测试和 attribution=false 反例、D 的 `ConverterTimelineTests.swift` 时钟边界用例。它们未在本轮移植或运行；watchdog 同 generation 迟到回调须针对性验证，不能用已有跨 generation 测试替代。

## 6. 明确排除与共同依赖边界

不整体 cherry-pick A～E。排除旧 HAL/RMS/相关性组合 Gate、HAL 必须启动才允许 VP 的条件、causal provisional pause/resume、explicit 插话 UI、ACE3 整套观测/ledger、WebRTC 专属延迟/相关性补偿和 VP 研究 CLI/实验会话。HAL 生命周期修复仅在后续明确仍保留 HAL 时评估，不能为保留修复而重引入 HAL。

共享 engine、converter、packetizer、队列、权限和既有 Runtime/Bridge 可复用；Apple 图配置、活动 facts 和资格映射仍需后续节点。后端不能运行中切换，不能把一条路线的 provenance 借给另一条。Cascaded 的 AEC3 资产和语音消息合同保留，T3.0 不改任何消费者。

## 7. 未解决风险与 T3.1 准入

当前风险：缺失 fixture 导致身份/取消/权限动态回归证据不足；Apple 后端骨架尚未达到正式 PCM/资格链；共享模式切换尚无 API；源资格规则未冻结且没有有效性证明；Qwen 严格 overlap 仍 0/3；53-C 物理 >1 秒不能靠延迟 clear 取得。

进入 T3.1 必须同时满足：

1. 主控审阅并接受本轮报告及计划，明确是否允许带显式 fixture 缺口开展 T3.1 纯合同工作；未作此决定则不进入。相关安全回归通过前不能把验证状态改为完整 PASS。
2. 登记必要 fixture 的安全来源、使用授权、隔离和复验安排；在另行授权范围补齐受影响安全回归，源码接入 T3.2 前必须通过。若主控要求先复验再开展合同工作，则 T3.1 也不得提前。不从旧目录盲拷私人 DR，不修改忽略规则绕过 Git 安全。
3. 明确仅授权 T3.1 合同/作用域/规则工作及最小文件范围，继续禁止 Apple 生产接入、设备和 Provider 执行。
4. 保留正式 Test3 BLOCKED/false、旧合同原样、T3.P 0/3；不把“规则已冻结”解释为“算法已有效”。

因此当前为 `T3.1 admission = PENDING / NOT_AUTHORIZED`。可以提交审核材料，不能自动进入下一节点。即便主控允许先讨论 T3.1，fixture 复验缺口仍须显式保留。

## 8. 交付与历史保护

本轮仅新增本目录两份文档，AGENTS 新增一个阶段指针，DEVLOG 新增必要事实。01–24、ACE3、Test2 验收、统一 Human Gate、Runtime 架构/边界及生产/测试源码均不改。

提交前检查完整 diff、显式文件白名单、无 PCM/WAV/DR/密钥/私人绝对路径/原始日志，确认新分支源码与起点零差异；提交使用 `[7.5][T3.0]`，仅推送既有 `Test3-AppleVP-Clean`。交付后核验本地/upstream/实时远端一致，保留原 Worktree diff/状态摘要。实际最终提交 SHA 以 Git 记录和交付回复为准，避免在提交内自引用。

## 9. Stage7 Forbidden Checklist

| 检查域 | 前置 / 收口判断 |
| --- | --- |
| A Stage 范围 | PASS；Stage7.5/macOS，无新平台或 Stage8 |
| B RuntimeCore | PASS；未改源码，单一 Runtime/ExecutionEngine authority 保留 |
| C Host | PASS；无新 Provider、Scheduler、Memory owner 或旁路 |
| D DR/API | PASS；无 DR/fixture/schema/API 修改，缺失 fixture 不补造 |
| E Provider/Secret | PASS；只用离线 fake，未读 Keychain、未真实调用、无 secret 入 Git |
| F Store/Memory/Trace | PASS；仅隔离测试目录，无业务持久化政策修改 |
| G 调度 | PASS；无后台监听、timer/scheduler 产品功能或自主循环 |
| H UI/音频/路线 | PASS；无实现/后端/阈值/Runtime 授权变化；旧合同和 Cascaded 保留；人工检查按本轮文档范围，不冒称历史 checklist 已迁移 |
| I 输出与证据 | PASS；Build/离线 PASS、前置 FAIL、停止/未运行项分别保留，不伪造声学或 Human Gate 结论 |

结论：**PASS（本轮范围越界检查）**。触碰红线：无。修改文件：本目录 README、本报告、AGENTS 最小指针、DEVLOG 简记。是否改代码/Runtime API/DR schema/新增平台 target/进入 Stage8：均否。是否需要停止并请求新的执行授权：本轮已获授权的文档交付继续完成；交付后停止，下一节点另行授权。该 PASS 不等于 T3.0 主控批准或 Test3 PASS。
