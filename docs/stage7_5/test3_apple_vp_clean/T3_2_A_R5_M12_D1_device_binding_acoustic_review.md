# T3.2-A / R5-M12-D1 · 单次执行记录

**BLOCKED_PRE_CAPTURE_UI_TIMEOUT。** 本次启动1次，未执行原Start确认，实际Capture、居民播放、应用JSON/WAV导出均0次。原控制器在文件选择阶段触发240秒UI看门狗并回收App；没有生成可试听WAV，也没有新的设备绑定、配置事件、AEC或时钟结论。该结果是执行准备失败，不能记为声学FAIL或PASS。

## 1. 版本、设备与授权

- 启动前HEAD、upstream、实时远端均为`e28f9578541f907ed3b025caf98620bd42c47554`，沿用干净隔离Worktree。
- 本次新用户指令明确授权M12-D1一次采集、本地JSON/WAV及试听；新建本轮同意和排他消耗记录，未复用旧R4/M03/M09同意。
- 主程序SHA：`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`。
- 实际加载的Debug dylib SHA：`2058a19003de698e95275728c16171c003e6b118a0fa5a5a564e3dba45a21e5a`。启动后按确切PID核验可执行路径、映射文件和摘要，PASS。
- 固定居民素材SHA：`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`，未替换或播放。
- 只读设备核验：默认TinyUSB，系统显示输入60%；默认Mac mini内置扬声器55%、未静音；物理设备身份与预检相同，启动前及退出后均alive=1、running=0。未改音量、路由或Mic Mode。
- 麦克风权限外部查询及Mic Mode继续UNKNOWN；没有操作新系统权限弹窗。本轮没有到达原App采集授权调用，因此不能宣称已验证当前采集权限。

## 2. 实际过程及失败证据

| 事项 | 结果 |
|---|---|
| App启动 | 1次，原DEBUG A组入口；没有BT、REF或普通实例 |
| 原Prepare与文件选择 | 已进入，原NSOpenPanel及“前往文件夹”界面可见 |
| 原Start确认 / Capture | 未执行 / 0次 |
| ScoreControl schedule / resident PLAY | 无 / 0次 |
| 新RunID / 运行态快照 | 未生成 / 不可用 |
| 原JSON/WAV导出 | 0 / 0；本地控制失败JSON不是应用Manifest |
| 控制器退出 | exit1，240.023696秒，`TimeoutError: UI/control watchdog` |
| App清理 | 原控制器reap回收；确切PID已不存在，两目标设备running=0 |
| 自动重启 / 重试 | 0 / 0 |

UI自动化最初使用的`rows`变量触发System Events错误-10000；局部改名后可读窗口。SwiftUI按钮不提供可用AXTitle，读取该属性产生-1728。随后根据已核验源码和实际AX结构进入原文件面板；尚未完成选择时，看门狗结束了进程，下一次控件调用返回进程不存在-1719。全部为本轮UI准备错误，不是Native、PCM、VP或时间戳拒收证据。

命令与exit保留本机：`python3 -B launch_m12_d1.py`→1；按PID的`ps`/`lsof`身份核验→0；相关`osascript`分别保留上述失败与成功回执；既有无参数只读设备探针在启动前/结束后各1次→0。没有修改、延长或绕过原240秒看门狗。

为后续明确授权的准备重走，已将核验过的控件层级和原文件面板操作收束为一个本地短脚本，原Start确认仍保留；仅`osacompile`离线语法检查exit0，**没有执行该脚本或再次启动App**。脚本SHA：`91f14050ebb25aa79a32b7c55068c0185cb96d7e6ee843b8e563c82fbd7cc763`。此处不把语法检查冒充真实UI流程通过。

## 3. 结论与边界

- CONFIRMED：构建与实际进程映射身份、设备静态前后读回、UI看门狗失败、App已回收、本轮无采集/播放/录音导出。
- UNKNOWN / NOT_RUN：进程方向设备、Engine配置事件、VP/AGC运行态读回、HAL耗时、Native/PCM连续性、M09时钟问题及AEC效果。未运行不能记为NOT_REPRODUCED。
- 没有WAV可供本次试听，不使用历史录音代替本轮结果。USER_LISTENING=NOT_AVAILABLE_NO_WAV。
- 下一项仅建议主控明确允许保留本次失败记录后重走采集前准备；仍限制实际采集和居民播放各1次，不自动追加。不修改音频算法、门禁或看门狗以规避失败。

本次只新增脱敏报告。完整命令、控制失败回执、设备标识和本地辅助脚本留在0700/0600受控本机目录；没有私人音频上传，也未读取历史私人录音。70项既有Cache条目大小、mtime、权限与所有者未改变，新增仅本轮控制证据目录；交付后复核原7个冲突、索引及未跟踪stat。

五维SELF_REVIEW：身份PASS；执行BLOCKED（采集前UI超时）；隐私及清理PASS；音频架构NO_CHANGE；声学/时钟证据NOT_RUN。CRITICAL=0、MAJOR=1（执行准备阻塞）、MINOR=0，不登记为生产AEC缺陷。

文档白名单、隐私、`git diff --check`及Secret Guard检查用于本报告；不重复Fake、Debug或FULL_CURRENT。Stage7 Forbidden Checklist=PASS：无红线触碰，无生产代码、Runtime API、DR schema、平台target或Stage8变更。

```ini
R5_M12_D1=BLOCKED_PRE_CAPTURE_UI_TIMEOUT
APP_LAUNCHES=1
CAPTURE=0
RESIDENT_PLAYBACK=0
WAV_EXPORT=0
AUTOMATIC_RETRIES=0
USER_LISTENING=NOT_AVAILABLE_NO_WAV
DEVICE_RETRY=NOT_AUTHORIZED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
