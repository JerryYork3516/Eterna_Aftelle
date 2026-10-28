# R5-M20-D2 · Mac-only AEC自动批次执行审核

2026-10-28，Stage 7.5 / T3.2-A。**BLOCKED_STARTUP_IDENTITY：首轮App启动身份门禁失败，批次按原规则停止。App启动尝试1次，控制链未触发Capture或居民Playback；完成评分0轮，后两轮NOT_RUN，没有新评分JSON/WAV。不得将本次技术阻塞表述为AEC声学FAIL。**

## 1. 身份与执行授权

执行前HEAD、upstream、实时远端均为`d52b4193da53132ff6cfd6e39e1052912d09644b`，已登记隔离Worktree干净。本轮只提交本报告，代码、设备配置、冻结计划及检测阈值均未修改。

批次UUID：`D43CA586-8AE1-48D3-9C1C-2F02AE918C0A`。用户本轮明确授权最多3轮A组，沿用D1计划和既有唯一设备入口，没有复用M19或旧设备授权。计划中的准备字段`execution_authorized=false`原样保留；按正式入口合同，新的执行同意由CLI参数传入并记录到本批排他授权消耗文件。

| 冻结对象 | 本轮重新核验SHA-256 |
|---|---|
| `plan.json`，执行前后相同 | `8b36066cf777842e857bedbdd7f799ccb012fc925ae448623698768727bb4a0e` |
| Debug dylib | `9992d3b86a02920669aa471d03a72610b6c0260d7ff444c03f3547afdc80e635` |
| App启动器 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| 固定居民WAV | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` |

全部计划登记的源码、原UI脚本、只读探测器、原控制器身份检查通过。默认TinyUSB USB输入、系统输入60%；默认Mac mini内置扬声器、系统输出55%、未静音；设备在线、空闲，无其他Aftelle/REF/代理实验实例；Cache权限0700/0600。原7个冲突、索引与14项未跟踪证据与保护基线一致。

## 2. 实际命令、轮次与失败传播

唯一设备调用为下列命令，完整私有绝对路径和执行日志只留本机：

```text
python3 -B tools/reference_host_comparison/m20_batch.py
  --plan <D1冻结计划>
  --evidence <计划绑定的同一批次目录>
  --authorize-batch '授权开始M20单批3轮AEC测试'
```

| 轮次 | App启动 | 声学RunID | Capture / 居民Playback / JSON与WAV导出 | 结果 |
|---|---:|---|---|---|
| 1 | 1次 | NOT_CREATED：未进入原Start路径 | 控制链均未触发 | INCONCLUSIVE，启动身份门禁失败 |
| 2 | 0 | NOT_RUN | 0 | NOT_RUN：批次已停止 |
| 3 | 0 | NOT_RUN | 0 | NOT_RUN：批次已停止 |

正式入口exit **1**，外部控制进程从启动到退出约**0.816秒**，这是进程耗时，不是录音时长。`BATCH_STOPPED.json`记录`completed=0`、`error_type=ValueError`、`error="actual PID or loaded dylib mismatch"`。首轮控制回执`status=FAIL`，`events=[]`、`commands=[]`；没有schedule、Stop或其他评分事件。没有`prepare_ui.json`、`start_ui.json`、运行Manifest或评分WAV。

明确的源码与调用位置：

1. [首次身份核验位于UI准备之前](https://github.com/JerryYork3516/Eterna_Aftelle/blob/d52b4193da53132ff6cfd6e39e1052912d09644b/tools/reference_host_comparison/m20_batch.py#L266-L273)：`prepare(pid)`第268行调用`verify_loaded()`，第269行才会调用原Prepare界面，第273行才会操作原Start确认。本次在第268行抛出。
2. [实际拒绝条件](https://github.com/JerryYork3516/Eterna_Aftelle/blob/d52b4193da53132ff6cfd6e39e1052912d09644b/tools/reference_host_comparison/m20_batch.py#L138-L148)：`ps -p <pid> -o comm=`结果必须精确等于解析后的启动器绝对路径，且`lsof -a -p <pid> -d txt -Fn`必须包含预期dylib映射。两项任一不符就在第144行抛出同一错误；后续运行中二进制SHA核验尚未到达，不能写成“已加载SHA匹配”。
3. [失败保全及资源回收](https://github.com/JerryYork3516/Eterna_Aftelle/blob/d52b4193da53132ff6cfd6e39e1052912d09644b/tools/reference_host_comparison/integration.py#L407-L445)：异常进入原失败回调；该回调再次核验同一PID时也报相同错误，故没有点击Stop、导出或Quit菜单。原`finally`进入所持子进程回收路径并写出控制失败回执；不存在`cleanup_error`。失败回执未记录App退出码，不能确认自然退出、信号退出或正常Quit；只读复核确认PID已不存在。

没有绕过身份检查，没有重启App，没有运行第二、三轮，没有现场修补后重录。本批授权消耗标记已存在，保留失败目录，不能继续使用该批次目录重跑。

## 3. 声学、系统状态与一致性

| 要求的观察 | 本次证据 |
|---|---|
| NCC、反向/静默负控、回声残留RMS | NOT_AVAILABLE：冻结检测器未进入分析，没有评分音频 |
| Native/PCM 20ms、满幅、零样本 | NOT_RUN |
| 实际VP/AGC/Mic Mode与完整格式 | NOT_RUN；不能以配置请求值或M19历史读回代替 |
| Input/Render内容时钟、丢包、拒收 | NOT_RUN；没有音频回调或评分证据可用于本次判断 |
| 物理发声资格 | UNVERIFIED；没有触发居民播放，不虚构物理见证 |
| 三轮声学一致性、AEC时好时坏 | 无法比较；本次未产生有效声学轮次 |
| App与控制器退出 | 只读`ps`确认所持App和控制进程均已不存在 |
| 设备释放 | 再用原只读`probe(plan)`核验，目标身份/60%/55%/未静音保持匹配，两个设备均空闲，无冲突实验实例 |
| 文件边界 | 原计划SHA未变，批次目录及新回执为0700/0600，原始执行日志及设备信息仅本机保存 |

## 4. 证据等级与唯一下一步

**CONFIRMED：** 预检身份和外部设备条件通过；第一处运行中身份门禁拒绝；该拒绝在原UI Prepare/Start之前；原回收路径执行后确认所持进程均已退出，后两轮未运行，批次没有重试。离线Fake通过不等于真实启动器就绪和身份读取已经兼容。

**HYPOTHESIS：** 子进程启动后立即读取身份/动态库可能遭遇装载尚未就绪，或`ps`路径表示与预期路径不同。当前不能把任一机制确认为实现缺陷。

**UNKNOWN：** 冻结实现未保存本次`actual`值和`mappings`内容，因此无法区分哪个OR分支触发，也不能宣布实际加载了错误二进制。没有AEC、AGC、设备声学或内容时钟根因的新证据。

**唯一推荐动作：** 单独批准离线核验`verify_loaded()`的两项比较与启动就绪合同，保留每项失败的有界只读结果及所持子进程退出码，构造未就绪、路径不符、错误库与正确身份的确定性负控。仅证明就绪问题后才考虑有界等待；不删除或放宽PID、路径及SHA断言。本轮不实施该修改，也不追加设备运行；修复审核后必须重新准备新批次并取得新授权。

## 5. 安全、Git与正式状态

只新增本脱敏报告。私人计划、回执、设备UID与原始日志均不提交；没有新WAV/PCM或私人Manifest可提交。没有读取历史私人录音，没有ASR、DTW、重建、回归重跑或AEC/AGC/NS、Converter、AudioGraph、时钟、RuntimeCore、Provider、正式Gate改动。

提交前`git diff --check`、暂存差异检查、报告唯一文件白名单、隐私扫描及原冲突保护检查均通过。只读保护检查器首轮因将基线数组误作对象而exit 1；按原结构读取后exit 0，保护基线未修改。构建、Fake、Guard和大型回归本轮均NOT_RUN，复用未变的M20离线证据。

Stage7 Forbidden Checklist：PASS；红线/API/DR schema/新平台/Stage8变更均无。工程问题等级：CRITICAL=0；MAJOR=1（真实启动身份门禁阻塞）；MINOR=1（两项拒绝原因缺少分支读回证据）。没有确认生产音频算法BUG。报告完成后正常Commit/Push并核验三方HEAD，原冲突现场继续保留。

```ini
M20_D2=BLOCKED_STARTUP_IDENTITY
APP_LAUNCH_ATTEMPTS=1
COMPLETED_ACOUSTIC_ROUNDS=0
CONTROL_TRIGGERED_CAPTURE=0
CONTROL_TRIGGERED_RESIDENT_PLAYBACK=0
AUTOMATIC_RETRIES=0
AUTHORIZATION=CONSUMED_STOPPED
ACOUSTIC_RESULT=INCONCLUSIVE
PHYSICAL_EMISSION=UNVERIFIED
AEC_ROOT_CAUSE=UNKNOWN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
