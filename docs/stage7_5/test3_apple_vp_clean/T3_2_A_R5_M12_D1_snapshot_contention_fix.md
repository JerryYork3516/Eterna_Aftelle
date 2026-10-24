# T3.2-A / M12-D1 · 诊断快照竞争与精确App退出修复

> 2026-10-24。OFFLINE_FIX=PASS；新的单次A组授权已取得，须提交后重新预检，尚未启动本轮设备。

## 1. 身份与范围

起始HEAD/upstream/实时远端均为`a6ef72a0a10c72d38f5e095330a528b46c4950f4`；跨文件修改前回滚提交`a6e33a8`。继续使用干净隔离Worktree，原7个冲突、索引及未跟踪证据按登记摘要/stat保护。

仅修改`MacSpeechAudioCapture.swift`的DEBUG诊断快照读取及对应原Fake；新增可复现的精确PID原UI导出/退出脚本和最小离线选择测试。本轮未改`AppController.swift`任何门禁、音频Callback的更新逻辑、PCM、Converter、格式、拓扑、AGC/AEC/NS、RuntimeCore、Provider、正式Gate或时钟容差。

## 2. RED及最小修复

CONFIRMED_CODE_DEFECT：`MacSpeechNativeVoiceTiming.snapshot()`与回调update共用busy原子标记。原单次CAS在写入占用时返回nil；现有安全消费者将nil转为`runtime_diagnostics_unavailable`并停止。确定性Fixture由后台任务持有真实update标记，只有读者实际观察到竞争后的等待回调才释放写者，不依赖人工计时或循环碰运气。原获取逻辑下RED exit133，失败断言为`temporary snapshot contention must not fabricate unavailable evidence`。历史失败Run是否恰好由此触发仍HYPOTHESIS，不能反向填补未记录的失败瞬间。

修复只改变非实时snapshot获取：最多20次CAS尝试、5ms单调时间预算，尝试间隔250μs；正常无竞争仍一次成功。只在取得同一标记后复制当时完整状态，不使用旧快照缓存，不把nil或UNKNOWN判为合格。超过时间/次数预算、读时钟倒退、缺少诊断仍返回nil，由原门禁fail-closed。OS调度可能使实际调用墙钟耗时超过请求的睡眠间隔，故5ms是检查预算，不宣称硬实时期限。

实时更新仍一次CAS、失败有界计数、无等待；通知丢失仍UNKNOWN，配置变化、RunID/generation/configurationID、设备资格、VP/AGC和Stop检查均未放宽。等待发生在原控制快照路径释放lifecycleLock后，没有在音频/通知回调增加等待、HAL查询、文件I/O、动态扩容或逐帧日志。测试专用hold方法只被Fake调用，位于原DEBUG类型内。

## 3. 精确PID退出修复

新增`tools/reference_host_comparison/finish_host_original_ui.applescript`，保留原封存状态检查及JSON/WAV导出确认。它始终按unix PID查找进程；退出前核对进程名Aftelle，必须唯一匹配名为Aftelle的菜单，再唯一匹配`Quit Aftelle`、`退出Aftelle`或`退出 Aftelle`。缺失、重复或disabled均报错，不回退到Apple系统菜单、菜单位置1、前缀匹配、全局Cmd-Q或另一个App。回执记录实际选中的完整Quit标题。

离线直接加载编译后的生产AppleScript，仅调用纯exactIndex处理程序，未执行UI run handler。7项Fake验证Apple菜单在前/换序、App菜单缺失/重复、三种精确Quit标题、退出登录/其他App/Force Quit、部分名称和大小写、重复Quit及PID/原导出门禁结构。原不安全私有脚本及历史证据原样保留，禁止后续复用。

## 4. 实际验证

| 检查 | 结果 |
|---|---|
| RED现有`check.sh m03-only` | 1轮，exit133，编译成功后命中预期失败断言 |
| GREEN同入口 | 29 cases / 514 checks，exit0；原M12门禁4/112、诊断8/72保留 |
| 最终样式收口后的定点复核 | 29/514，exit0；没有降低或删除断言 |
| 新负控 | 持续占用、5ms预算、固定时钟的20次上限、读时钟倒退均拒绝；配置通知/关闭观察仍可见；回调更新维持单次非阻塞行为 |
| PCM及内容时钟 | 复用原M12非零合成转换正负控，样本/顺序/时间及拒收结果不变 |
| AppleScript离线选择Fake | 7/7，exit0；原UI处理程序未执行，真实音频/设备0 |
| Debug构建 | 精确隔离project/DerivedData一次，exit0，16.977秒；未借用原冲突工作区或运行App |
| Release隔离 | Capture Release投影与基线逐字节相同；未重复Release全构建 |
| Release Route / Architecture / Secret Guard | 均exit0；最终交付再次核验新报告隐私 |
| 增量规范 | 变更行SwiftFormat/SwiftLint问题0，新增B类0；两受影响Swift文件既有233项format（exit1）、22项lint（exit2）与基线相同 |
| FULL_CURRENT / REF / 蓝牙 / 实机 | 离线阶段全部0次 |

完整命令、exit、RED断言及编译警告留本机。初次联合Python测试因缺少既有R3_BUNDLE环境在加载阶段exit1，未运行用例；改用本任务独立UI选择测试后7项通过。未改integration.py或R3身份逻辑。规范初检发现7项新增format问题，均局部更正后复核，没有格式化无关代码。

主程序SHA：`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`。

新Debug dylib SHA：`efaca216eaa35ceb150cc74273119d0781651cc064699af04c4c6e33f5d83466`。

## 5. 单次实机边界与审核

用户本次指令已明确授权：离线验证、Commit+Push、重新预检通过后直接执行一次M12-D1 A组，无需重复询问。本次另建独立同意及单次消耗记录，不复用旧R4或上次失败授权。预检必须再次核实默认TinyUSB60%、内置扬声器55%、权限/路由、素材及新构建身份；不自行改变音量、路由或Mic Mode，不操作新系统权限弹窗。

计划仅一次Capture及一次固定居民播放：4秒持续预热+15秒评分，score+3播放原居民；总预算19秒，评分PCM上限720000bytes，预热PCM不保存。复用原App确认、同RunID原JSON/WAV导出及安全清理；不启动BT、REF、B/C，不自动重试。产生有效本轮WAV才提供本机试听，不上传音频或私人Manifest。

五维SELF_REVIEW（离线）：身份PASS；确定性复现及修复PASS；实时/Release边界PASS；隐私和Git保护PASS；声学效果NOT_RUN。CRITICAL=0、MAJOR=0（本轮两个工程缺陷已有离线修复）、MINOR=1（历史规范债务）；实机兼容和AEC效果仍未验证。Stage7 Forbidden Checklist=PASS：无六红线触碰，无Runtime API、DR schema、平台target或Stage8变更。

```ini
SNAPSHOT_CONTENTION_OFFLINE_FIX=PASS
EXACT_PID_APP_QUIT_OFFLINE=PASS
DEVICE_RUNS_THIS_TASK=0
DEVICE_AUTHORIZATION=CURRENT_USER_EXPLICIT_SINGLE_A
PRECHECK=NOT_YET_RUN_AFTER_COMMIT
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
