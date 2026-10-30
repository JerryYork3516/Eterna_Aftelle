# T3.2-A / R5-M26-D1：输出声道A/B批次启动失败审核

日期：2026-10-30（Asia/Shanghai）。结论：**STOPPED_PRE_CAPTURE；A/B声学对照未执行。**

用户在本批准备结果后明确回复“授权”。仅执行已登记的同一批次，未沿用其他批次同意。正式Test3授权没有改变。

## 1. Git、冻结身份与授权

执行前隔离工作区HEAD、upstream及实时远端均为`cbb4da9503d3e9535b7ab6e342db3f02677427ee`，工作区干净。本轮不修改源码、构建产物、设备设置、计划或评分器；只新增本报告。报告交付Commit见Git提交记录，避免自引用SHA。

| 身份 | SHA-256 |
|---|---|
| Debug launcher | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug dylib | `b4cc575b386443344a4eb3d09a6b6e0d990cf07d36e4b24af466714714377095` |
| 原居民WAV | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` |
| M26控制器 | `ebd9bf1abda5994bf0ff0ae61e088aaadb2176fc2e4dd1794f2a497200221055` |
| 冻结M20评分器 | `f9363dd62100563fe80c5693b4889dea65e60f7c99c2a36715feb8f4c46b49ae` |
| READY计划原件 | `53318270707d3924128e0712cfe23b984fbd000a0c578af7b051320e3377427c` |

批次UUID：`916C1941-2986-477A-8BB8-6FEF4F16F885`。冻结顺序A=`TRIPLE_EQUAL`、B=`FIRST_CHANNEL_ONLY`；每臂4秒预热+15秒评分，score+3秒请求居民一次，最多两臂、38秒，不重试。计划原件及原草案未覆盖。

正式入口创建了`M26_AUTHORIZATION_CONSUMED.json`；此批授权已消耗。静态计划中的起跑前`authorization_consumed=false`不表示仍可使用，消费标记优先；没有删除标记或复用批次。

## 2. 实际执行与安全清理

| 项目 | A | B |
|---|---|---|
| 已保留的尝试 | 1 | 0 |
| App启动 | 1 | 0 |
| RunID | NOT_CREATED | NOT_CREATED |
| Capture / 居民播放 / 评分 | 0 / 0 / 0 | 0 / 0 / 0 |
| JSON/WAV录音导出 | 0 / 0 | 0 / 0 |
| 声学结果 | INCONCLUSIVE（未采集，评分器未运行） | INCONCLUSIVE（未启动） |

A的确切PID及实际dylib映射核验为`VERIFIED`：前5次只读检查为`DYLIB_NOT_READY`，第6次通过，合计约0.731秒，未超过原3秒界限。随后在原素材选择UI调用前抛出`KeyError: 'resident'`。没有`prepare_ui.json`、`start_ui.json`，控制事件及命令列表均为空；失败发生在`capture_requested=true`之前。

控制器记录`failure_ui=PRE_CAPTURE_OWNED_CHILD_REAP`，只回收所持App子进程，退出码`-15`（SIGTERM），不是正常Quit成功。随后独立确认所持PID已不存在，无冲突Aftelle/REF/代理实验进程，默认输入输出均在线且`running=0`。B目录未创建。整个入口exit1，`BATCH_STOPPED.json`记录completed=0、KeyError、retries=0；没有自动重试。

启动前与停止后的只读设备检查通过：TinyUSB为USB输入，系统输入60%；Mac mini内置扬声器系统输出55%、未静音，HAL scalar=`0.5500001311302185`，满足既有容差。没有调整设备、音量、路由或Mic Mode，没有操作系统权限弹窗。

VP/AGC、active Mic Mode、Engine/Render、Native/PCM、时钟、丢包、物理发声均为**NOT_RUN**。本批没有录音可供试听或声学分析，不能沿用上批数据补齐。

## 3. 已确认的计划合同缺口

**CONFIRMED：计划预检未覆盖执行器实际读取的素材字段；不是AEC或声道分配失败。**

- READY计划有`files.resident.path`及正确SHA，但缺少顶层`resident`。
- `tools/reference_host_comparison/m26_channel_allocation.py:21–31`校验M26合同及`files.resident.sha256`，继而调用既有`batch.check_plan`；后者核验登记文件、设备及进程，却未校验顶层`resident`。
- `tools/reference_host_comparison/m20_batch.py:401–405`在身份核验后求值`plan["resident"]`，再调用原prepare UI。实际traceback停在405行；因此该UI尚未执行。
- 同文件444行在采集后分析源素材时也读取顶层`resident`，故仅绕开第一次报错不构成完整修复。

上一节点的READY结论漏检了此合同，本报告撤回本批“具备可执行资格”的结论。已通过的SHA、只读设备和精确PID身份检查仍有效，但不能替代完整执行参数资格。未将这一启动错误归因于Apple VP、AGC、3ch格式或TCC。

**最小后续修复建议（本轮未实施）：** 在准备计划时明确登记顶层素材路径，并在启动任何App之前严格要求它与已登记`files.resident.path`一致，继续核验固定SHA及原素材准入。对缺失、路径冲突、SHA错误及正确计划增加定点Fake，覆盖实际prepare参数边界；错误计划必须在App启动和授权消耗前拒绝。不得通过任意路径、删除SHA校验或现场改已消耗计划恢复执行。

## 4. 验证、隐私与SELF_REVIEW

实际检查：一次正式M26入口（exit1，采集前失败）；一次执行前`m26.check_plan`（exit0，暴露其覆盖不足）；停止后`m26.check_plan`及原`probe`（exit0）；一次确切PID存在性/权限/无新音频/原计划SHA检查（exit0）。READY计划SHA保持不变，受控目录0700、文件0600；无新WAV/PCM。

没有重建或重跑Swift/Python大型回归。`bash tools/secret_guard/check.sh`一轮exit0；文档交付做单文件白名单、diff及报告独立隐私检查。原始traceback、PID/映射、设备标识、计划及完整日志仅留本机受控目录，不提交原件。

| 维度 | 结论 |
|---|---|
| 合同正确性 | BLOCKED：发现真实计划/执行器字段缺口，未降低门槛 |
| 安全与生命周期 | PASS：采集前失败回收所持子进程，设备释放；未正常Quit如实记录 |
| 科学有效性 | NOT_RUN：没有A/B音频，不能判断声道策略或AEC |
| 隐私与Git | 仅提交本报告；原7个冲突、索引、14项未跟踪证据在交付前后核对 |
| 变更范围 | 不改代码/算法/音频图/Converter/时钟/正式Gate；不追加实验 |

新增CRITICAL=0、MAJOR=1（`M26-D1-M01`：计划预检与执行参数合同不完整）、MINOR=0。该MAJOR属于实验启动准备，未证明生产音频故障。`M18_E01`继续DEFERRED。

Stage7 Forbidden Checklist：**PASS**。六红线未触碰；修改文件仅本报告；代码、Runtime API、DR schema、Provider、平台target和Stage8均未修改。

**唯一下一步：** 先离线修复并验证计划字段合同，再以新UUID/新计划重新预检、另行授权；不复用本批，不追加设备采集。

```ini
M26_BATCH_PLAN=CONSUMED_BLOCKED
M26_DEVICE_EXECUTION=STOPPED_PRE_CAPTURE
APP_LAUNCHES=1
DEVICE_CAPTURES=0
RESIDENT_PLAYBACKS=0
M26_AB_COMPARISON=NOT_RUN
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=DEFERRED
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
