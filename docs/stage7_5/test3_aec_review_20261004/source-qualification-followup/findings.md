> 发布说明：以下是原离线实验阶段报告的脱敏快照。文中“本轮未commit/push”描述该实验阶段，不描述本次资料发布；旧资产名称由README映射到本目录材料，未提供PCM或二进制。

# Stage 7.5 / Test3 / 03 — 确认标签后的离线定位

## 裁定

用户回复“确认”已保存为独立纯回声标签。实体原运行 FAIL：播放期间 42 个错误人声资格帧，4 个确认链，48 个 Gate 开启帧，56 个按源身份去重的非零转发帧。正式 interrupt / cancel / clear / 新建 generation 均为 0。Test3/03 继续 BLOCKED，NO_PATCH。

本轮没有再次录音、播放或调用 Provider。没有改正式 Host、AEC、Capture、Bridge、Runtime、阈值。既有 Runner 保存修复和旧 PCM 保留，未 reset / clean / commit / push。

## 1. 资格见证双实现复算

见 `qualification-witness-audit-01/protocol.json`、`scalar-witnesses.json`、`result.json`。

17 个冻结帧含全部 12 个确认帧及第一链前置上下文。独立完整整数合法延迟域复算与真实路径统计最大绝对差为 2.701172618913006e-13，低于固定容差 1e-6。未发现能解释误确认的数组、归一化或窗口索引差异。所有确认帧现有 alternative 检查均不命中；以原门槛做 raw-fit 诊断也为 0/12，不成为修法。

第一链 372–374：旧 lock 在连续 miss 2/3/4 时仍存在。low_correlation_near_end 分支在当前参考相关低、clean/linear 输出相关高及 RMS 达标时授予资格；五次 miss 才解除 lock，三次资格按规则开 Gate。此处是现有证据语义，不是计数器漏加或匹配穷举漏搜。

其他三链为 adaptive / immediate double-talk。五个基线来源为 98、99、333、370、700；704 的 candidate 冻结基线。当前 expected / locked 匹配弱相关仍可进入 adaptive，historical-origin 才有该相关门槛。不能把基线个数足够等同于当前声源参考可靠。

## 2. 旧 lock 权威诊断消融：REJECTED

见 `lock-authority-ablation-01/protocol.json`、`diagnostic-only.diff`、`comparison.json`。仅在 ignored Host 副本禁用 locked 低相关资格臂；没有形成新声源证据。

|对照|原始|消融|
|---|---:|---:|
|实体错误资格帧|42|34|
|实体错误确认链|4|3|
|实体 Gate 帧|48|28|
|实体播放源非零转发帧|56|34|
|固定软件源区间资格帧|49|48|
|固定软件源区间转发块|165|165|

尚有三个错误确认且固定软件资格损失，按预登记停止。软件背景源区间转发 84→17；该软件背景不是实体纯回声。没有产品补丁，不能把软件源区间或全部转发数当真人保真结论。

## 3. AEC3 真正参考身份

见 `aec3-reference-identity-01/` 及 `ring-identity-01/`。固定上游 HEAD 为 9f30e83c018647b05804571699cf22b1f0f3409e。原音频调用、FIFO、已有 delay 控制事件离线重放，537600 个 clean 和 179200 个 linear float32 样本与原运行逐位一致。日志插桩后仍逐位一致。

共享事件序号按对象＋槽号＋最新先行写事件识别 GetBlock(0)，避免用重复波形峰值挑位置。2772 次写 payload 全部逐位对应真实 band0 连续输入；2800 次 y 对应捕获连续输入，2800 次 x 均等于实际槽内最新先行写。无未写槽、缺日志、未来到达调用。末尾 10 个 render 帧在最后 capture 后到达，留在队列，另有 32 个 framer 样本；差额明确，不是补零或丢流。

|错误确认源帧|AEC 块数|实际 render 源帧范围|记录内容时间差 ms|
|---|---:|---|---:|
|372–374|8|359–362|99.843|
|972–974|8|959–962|99.843|
|1014–1016|8|1010–1013|3.843|
|1063–1065|7|1059–1062|3.843|

四链共 31 块身份及到达顺序已核实。该表是 GetBlock(0) 锚点，不是完整自适应 FIR 的声学延迟。全 run 另有 83 个锚点内容时间差为负、73 个跨内部 Reset 的读；没有未来到达调用，不把“已到达”扩大为“全部内容时间满足声学因果”。正式 Host 合法匹配与 AEC 锚点是不同对象。

## 4. 重置与回调排程

独立占用模型复现全部 5572 个内部 buffer 事件，差异 0。非启动 Reset 在 capture 200、600、800、1000，分别为 AEC block 500、1500、2000、2500：250-block 观察域最小占用 26 > 原有 8 门槛，触发 DetectExcessRenderBlocks。不是 render Insert 碰撞，也不是 BridgeReset；全部 render_insert 事件为 0。内部另有 145 次 underrun，不等于原报告 Host I/O underrun 指标。

以末次 Reset 为例，capture 851–860 前没有新 render 插入，产生 24 次内部 underrun；capture 861 补入 50 blocks，之后余量持续 25 blocks。block 2500 的 read 从 129→154，额外前移 24 blocks=96 ms，对应后两链锚点变化。该行为符合已有上游规则，未证明 API/配置契约错误。

两 tap 在正式 Capture 源码都请求约 10 ms，但本路由实际交付 capture 4800/48k 与 render 4410/44.1k，均 100 ms。112 对回调均与调用记录身份对应，13 对 render 入口晚于同序 capture 完成。缺线程身份与反事实，不认定 CPU 阻塞已被证明；100 ms 分批本身也不自动构成 Bug。

## 5. 一次因果 FIFO 调度对照：未获得充分修法

见 `causal-pair-scheduling-01/protocol.json`、`assessment-final.json`。预登记后只试一次：每路保序，完整真实帧已到达时，一帧 render 后接一帧 capture；无注入，保留原 delay 控制事件序列及 120 样本边界丢弃。延期使某源帧消费的 hint 可能改变，不能称逐帧 hint 相同。原输入逐位保留。GetStats 观察重复与第一次对照 clean/linear 逐位相同。

非启动 Reset 从 4→0，原四个误确认三帧区间 clean RMS 都降低。但保持原 Host 时序的事后诊断仍有 41 个错误资格帧、104 个 Gate 帧、110 个唯一未清零播放源 span、3 个开闸点（232、500、630）。这不是实时因果验收；真实新决策时间没有重建。126.380375 ms 只是记录回调入口计算的等待分量，不是已证实的新增决策延迟。

按纯回声非零资格停止条件拒绝其作为充分修法，不再调排程参数，也未扩大到软件正控。消除 Reset 不足以直接修好当前资格规则；此结果不否定所有可能的排程修法。

## 路由验收账

|路由/项目|状态|证据边界|
|---|---|---|
|Timesintelli USB＋Mac 内置扬声器，实际身份/样本链|已验证|本次真实路由、无注入、保存及逐位重放完整|
|同路由 WebRTC AEC3，纯回声声源资格|失败|4 次错误确认，正式权限 0 不掩盖资格失败|
|同路由 WebRTC AEC3，当前约 400 ms 真人及长句完整验收|未验证|本轮没有新增真人录音；旧软件对照不能替代|
|Apple AEC 当前代码/硬件复测|未验证|本轮未切路由，也未拿历史局部覆盖当本轮通过|

## 唯一下一步

在现有 WebRTC 路线内，针对 Host 的三类资格臂（低相关 near-end、自适应 double-talk、即时 double-talk）做有代码见证的修法设计复审：明确“参考/基线在当前帧可靠”的证据，以及如何保护独立人声。使用本次已冻结实体负控和既有固定软件源区间作为反例；给出一份具体可证伪的隔离方案，或明确 NO_PATCH 的缺口。停止继续找已复算一致的索引/相关小 Bug，也不再把只消除 Reset 当充分修复。

当前不需要用户重录。本次远端复审任务与发布材料见 [README.md](README.md)。候选通过冻结负控、源身份、固定软件保护以及因果可用时间后，才安排一次关键真人验收；本报告没有提前承诺该候选一定能成立。

## Stage 7 检查

- 结论：PASS（阶段边界，独立于 Test3 BLOCKED）。
- 触碰红线：无。
- 修改文件：本 run 下 ignored 报告、Python 离线脚本、诊断 C++/Swift 副本及输出；正式产品文件未新增修改。
- 是否改代码：仅隔离诊断代码；正式 Host / AEC / Capture / Bridge / Runtime 否。
- Runtime API / DR schema / 平台 target / Stage 8：均否。
- 新录音、播放、外部发送、提交推送：均否。
- 需要停止请求用户确认：否；本轮隔离方向按预登记负控条件停止，正式中断权限继续关闭。
