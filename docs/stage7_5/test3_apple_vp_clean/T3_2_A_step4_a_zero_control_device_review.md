# T3.2-A · Step 4-A 全零对照设备审核

## 1. 结果

**BLOCKED_UI_PREPARATION。** 冻结 App 启动一次，加载映像与进程身份核验通过。准备综合 C 时，辅助功能读取该进程的 `AXWindows` 失败（`AX_COLLECTION_UNAVAILABLE_AXWindows`），综合 C 就绪状态未建立。故障出现在打开素材选择器和录音确认面板之前，界面读取失败的具体原因仍未知。

控制器停止准备并终止本次所属 App 进程（SIGTERM，退出状态 −15）。复查确认 PID 已消失，默认输入输出设备可用且空闲，路线、音量及静音状态与预检一致。未发出 Windows 播放提示，未申请或消耗本轮单次采集授权，未启动采集或 Mac 播放，未生成 RunID 或导出文件。没有重试。

## 2. 已核验项目

| 项目 | 结果 |
| --- | --- |
| Git | 本地 HEAD、upstream、实时远端均为 `84525fdac60b353cdb9ce3e63800a2ccc065571d`。隔离 Worktree 启动前干净。`apps` 树与冻结运行源码 `574fc735ca239c9b334029debbdee546cda18d49` 一致。原 7 项冲突、索引和 14 项证据与受保护基线一致。 |
| 构建 | 冻结 Debug launcher SHA-256 `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`，Debug dylib SHA-256 `e419552e1b539db52c6a971e6b703aaa695cb503fdfbf479fe20c25c5586a132`。磁盘身份、App 签名登记及实际加载映像通过。 |
| 设备及权限 | TinyUSB 默认输入 60%，Mac mini 内置扬声器默认输出 55%、未静音。预检和退出后 HAL 均确认可用且空闲，无冲突实验进程。系统设置显示 Aftelle 已获麦克风权限，AX 授权只读核验通过。 |
| 全零素材 | 24 kHz、Mono、PCM16LE、114032 帧、228064 PCM 字节。完整数据段为零，与居民素材格式和帧数一致。SHA-256 `a7169f4bb25dc688e739888880d85640c9f5a0170df46bcc43ccd9c1823f96eb`。 |
| Windows 素材 | 上轮登记男声的 Mac 本机参考副本 SHA-256 `4c3c96b1c4b704a1ef1ab7c2f8e90ef21fafce2f21fdbe117afe5282741dd173` 匹配。Windows 端本轮实际选材、音量和发声待运行时确认。 |
| 导出 | 本机导出目录为当前用户所有、权限 0700、无 Git 祖先。前后导出清单无变化。 |

原综合 C 的源码以 PCM 字节长度判断普通场景素材资格，登记全零文件满足 144000–288000 字节范围，并保留原排程入口。该项为静态资格。本次未到达素材选择和运行，实际调度、Render 全零、VP 双端及 AGC 读回、Native 短窗、CLOCK、丢包、欠载及 Stop/Seal 均为 `NOT_RUN`。

## 3. 对照时间映射与后续

未来有效 A 轮应记录同一 Run 的原 `playbackStarted` 软件事件和 PCM 内容零点。以该事件作为锚点，沿用上一居民轮居民非零窗口相对这一事件的偏移，检查预定窗是否被连续 PCM 覆盖。A 轮实际素材播放仍须由排程、Player Render 全零统计及正常完成证据独立核验。投影窗只定义软件比较范围。本次 A 轮不存在可投影的运行事件，也没有男声压制结果。

在重新获准准备时，先以有界只读观测确认所持 PID 的主窗口已就绪，再执行一次原 Prepare C。实际采集仍需在完整预检后取得用户本次 Windows 播放确认和单次采集许可。

## 4. 交付边界

Stage 7 Forbidden Checklist 自审 PASS。仅新增本脱敏报告。启动准备与失败证据留在本机，未修改生产代码、AEC、AGC、阈值、设备路由、Runtime API、DR Schema 或平台 target，无 Stage 8 改动。未进入 B 组。

```ini
STEP4_A_READ_ONLY_PREFLIGHT=PASS
STEP4_A_UI_PREFLIGHT=BLOCKED
STEP4_A_EXECUTION=NOT_RUN
STEP4_A_CAPTURE_AUTHORIZATION=NOT_REQUESTED
STEP4_A_RENDER_ZERO=NOT_RUN
STEP4_A_NEAR_END_SUPPRESSION=UNKNOWN
DEVICE_CAPTURES=0
MAC_PLAYBACKS=0
LOCAL_AUDIO_EXPORTS=0
P4_FORMAL_53_C_RUNS=0
T3_2_A=BLOCKED
Formal_Test3=BLOCKED
```
