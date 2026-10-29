# T3.2-A / R5-M20-D4 — AEC自动回归与物理发声见证

## 1. 结论与身份

本批完成3轮，无重试。用户在批次结束后一次性确认：**“三轮都听到了”**，已分别绑定以下实际RunID。冻结检测器结果为第1轮INCONCLUSIVE、第2/3轮ECHO_DETECTED；没有ECHO_NOT_DETECTED轮次，因此没有取得“低回声且已见证发声”的成功案例。不能据此宣布AEC长期稳定、确认根因或追认上批第3轮成功。

- 实际源码：`02e02255326fa9770f141d75729e34643bf2b884`；预检及启动前三方HEAD一致。使用原干净隔离工作区；本任务仅新增此报告。
- 新批次：`1E86B79D-65B1-4883-A51B-D1BF71CECF8C`。本批在PRECHECK_READY后取得新明确授权“授权开始M20单批3轮AEC测试”；历史计划、目录及授权消耗记录未复用。
- Launcher SHA256：`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`。
- Debug dylib SHA256：`4de26c8850e670dd6be73b03ce60b29c8404b2791d154276087d34295d32433e`，复用上批已验收候选；文件及对应源码指纹一致，未重建。
- 居民WAV SHA256：`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`；24kHz/Mono/PCM16LE，114032帧，前导和内容未改。
- 检测器SHA256：`f9363dd62100563fe80c5693b4889dea65e60f7c99c2a36715feb8f4c46b49ae`；保持M20_v0.1全部参数。NCC检出限0.25、未检出限0.12、负控余量0.10、包络限0.35、能量集中度限0.70、低能量限−50dBFS均未调节。

## 2. 执行、授权与用户见证

设备只读预检及逐轮前后检查通过：TinyUSB USB输入60%，Mac mini内置扬声器55%、未静音、设备空闲；未改音量、路由或Mic Mode。复用现有 `m20_batch.py` 正式设备入口、原UI可见确认/Stop、显式JSON/WAV导出及确切PID的App退出菜单。界面保留round/limit和运行阶段，无新增提示音或播放器。

每轮独立App/PID/RunID，计划4秒持续预热+15秒评分，score+3秒请求固定居民一次。Capture=3、居民Playback=3、JSON Export=3、WAV Export=3；执行器exit 0，BATCH_COMPLETE=3。每轮3次实际PID/映射dylib身份回执通过，App正常退出并验证设备释放。没有新的系统权限授予、真人讲话任务、蓝牙、REF或第4轮。

| 轮次 / 实际RunID | 自动结果 | 用户物理发声见证 |
| --- | --- | --- |
| 1 / `D6256B84-187F-4E30-8B47-6ECA273C2F51` | INCONCLUSIVE | 听到；USER_WITNESSED_EMISSION |
| 2 / `82DB2A5D-96BA-4284-8EE7-6D354DC2101D` | ECHO_DETECTED | 听到；USER_WITNESSED_EMISSION |
| 3 / `7FD5B8BA-71ED-409F-815C-254A857800CE` | ECHO_DETECTED | 听到；USER_WITNESSED_EMISSION |

原始自动analysis中的physical_emission/aec_acceptance=UNVERIFIED保持原样；人工见证另存本批私有记录并按RunID关联，未改写软件测量。该见证证明用户现场听到发声，不证明校准声压、完整逐字播放覆盖或Apple内部参考。用户未被要求试听WAV，不能把此反馈写成“录音中回声不可闻”。本批见证也不能追溯替代上批9EDBABEA第3轮缺失的现场事实。

## 3. 固定评分结果

表中NCC取绝对值；第2/3轮实际匹配NCC为负，按原检测器处理。RMS为冻结检测器以实际非零Render界定的窗口，不能当作ERLE。

| 轮次 | 模板NCC / 全局NCC | 反向 / 安静负控NCC | 包络相关 | Render窗PCM RMS dBFS / Peak | 非零Render，WAV相对秒 |
| --- | --- | --- | --- | --- | --- |
| 1 | 0.107454 / 0.124596 | 0.101926 / 0.040661 | 0.060334 | -34.043 / 0.528351 | 4.214063–7.961722 |
| 2 | 0.397474 / 0.397474 | 0.080352 / 0.026503 | 0.467961 | -18.402 / 1.000000 | 4.182060–7.929719 |
| 3 | 0.388142 / 0.388142 | 0.075344 / 0.026868 | 0.680197 | -17.710 / 1.000000 | 4.182063–7.929723 |

第1轮原因是AMBIGUOUS_TEMPLATE_OR_ENERGY：模板与反向负控接近，包络相关低；全局NCC约0.1246且Render窗RMS约−34.04dBFS，不满足冻结的未检出条件。不能因为局部NCC约0.1075就改判成功。其声音可能包含残余居民、非线性处理产物或环境声，来源UNKNOWN。第2/3轮源模板相对负控有明确余量，按原规则检出固定居民特征；这仍是自动数值证据，不冒充用户WAV听感。

与上一批相比：上一批分类为检出/检出/未检出（NCC约0.406/0.358/0.041）；本批为不确定/检出/检出。上一批第3轮Render窗约−65.15dBFS，本批未再出现该类低能量轮次。当前取得3/3物理见证，但“低回声时扬声器是否确实发声”仍未在同一轮得到再现性证据，不能无限重跑以取得PASS。

## 4. Native/PCM、时钟及系统状态

M19同内容时间对照仅汇总WAV相对4.00–7.74秒完整20ms行：187行、Native59840样本与PCM89760样本，无插值/补零。Native是Apple VP后ch0，不能称ADC Raw。

| 轮次 | Native / PCM RMS dBFS | PCM−Native dB | generated=drained；queued | Native秒 / WAV秒 | WAV实际PCM bytes；配对行 | Native满幅/声道；PCM端点 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | -33.1005 / -33.1007 | -0.0003 | 944=944；0 | 18.9 / 14.86 | 713280；743 | 0；0 |
| 2 | -17.6503 / -17.6549 | -0.0046 | 944=944；0 | 18.9 / 14.86 | 713280；743 | 44；46 |
| 3 | -16.8438 / -16.8443 | -0.0005 | 949=949；0 | 19.0 / 14.96 | 718080；748 | 2；7 |

三轮保留PCM均≤720000 bytes，不保留4秒预热PCM；尾部仍为PARTIAL，不制造15秒完整覆盖。全部保存包连续、M19行均MATCHED_CONTENT_COVERAGE，并由原审核器核对实际WAV样本统计。末次drain回执为0→0→0、0→0→0、5→5→0（排空前队列→真实消费→Seal队列），没有通过清空队列伪造零值。Native与最终PCM的大窗幅度差约0.005dB以内，本批幅度差异在VP后Native已存在，不支持后级Converter产生大幅整体增益损伤。

三轮Native各项拒收、capture dropped/stale、playback underrun/rejected、Input/Render missing/duplicate/backwards/sample-gap/host-gap均为0；观察skipped/invalid/stale均为0，raw_timestamp_diagnostic为空。Engine配置事件/skippedNotifications均0，监听关闭。历史时钟异常本批NOT_REPRODUCED，不等于根因已修复。Native non-finite/over-scale均0；第2/3轮有稀疏满幅与PCM端点，未达原持续满幅停止限，不能写“零满幅”，也不能仅据此宣布AGC BUG或可闻失真。

| 轮次 | EngineStarted / PlaybackStarted HAL读回，ms | VP Input/Output；AGC；bypass；mute | Mic Mode active/preferred |
| --- | --- | --- | --- |
| 1 | 4.051 / 3.202 | true/true；true；false；false | 0/0，两点一致 |
| 2 | 3.368 / 2.756 | true/true；true；false；false | 0/0，两点一致 |
| 3 | 3.709 / 2.882 | true/true；true；false；false | 0/0，两点一致 |

两点及跨三轮client/hardware格式和进程方向设备集合一致；输入资格均PROCESS_SHARED_IO_DEVICE_SET_METADATA_QUALIFIED，输出PROCESS_DEVICE_METADATA_MATCHES_DEFAULT，engineRunning=true。Mic Mode为AVCaptureDevice公开应用路由API的实际active和preferred读回（0=Standard），不是物理端点/硬件DSP/AEC状态证明。正常属性不证明内部AEC参考相同或有效。

## 5. 证据等级、检查与唯一建议

- **CONFIRMED**：本批3次真实运行技术合格；用户现场逐轮听到扬声器；第2/3轮固定模板被检出，第1轮无法可靠归属。可观察配置相同，但输出能量/特征有差异。
- **HYPOTHESIS**：VP或更早阶段的状态/声学条件差异与结果相容。没有VP前原音和内部参考，不能确认为Apple算法或Aftelle集成缺陷。
- **UNKNOWN**：第1轮非零声音的具体来源、各轮实际声压/声学条件是否完全相同、Apple内部参考/适应状态，以及上批第3轮物理发声。没有本批AEC成功或长期稳定性证据。
- **唯一建议**：先对本批第1轮现有私有WAV做一次人工听音归属复核，解决INCONCLUSIVE的声音来源；不加诊断代码、不改参数、不自动追加设备测试。音频继续私有，如需交给外部主控须另获具体授权，本次不要求用户试听。

复用冻结候选的既有Fake/Debug/Release/Guard证据，本任务构建=0、大型回归=0、代码修改=0。当前执行：文件/素材SHA与WAV头核验、正式M20评分器三次、三份新导出SHA核验、目录权限、文档/隐私/白名单、`git diff --check`及Secret Guard。旧批次元数据、原7个冲突、索引和14项未跟踪证据保持不变；WAV/PCM、私人JSON/Manifest、设备UID和原始日志仅本机0700/0600保存，未上传、转录或自动播放。

Stage7 Forbidden Checklist：PASS；红线触碰=无；改动=仅本报告；代码/Runtime API/DR schema/新增平台target/Stage8均否。五维SELF_REVIEW：范围PASS、控制/安全PASS、统计可追溯PASS、隐私/Git PASS、声学结论保留INCONCLUSIVE/UNKNOWN。新增代码CRITICAL/MAJOR/MINOR=0（无代码修改）；既有AEC及Formal门禁未关闭。

```ini
M20_D4_DEVICE_RUNS=3
M20_D4_PHYSICAL_WITNESS=3_OF_3_USER_CONFIRMED
LOW_ECHO_WITH_PHYSICAL_WITNESS=NOT_OBSERVED_IN_THIS_BATCH
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
