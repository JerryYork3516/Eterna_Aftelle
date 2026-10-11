# RBT-1 隔离入口实现 · Stage7.5/Test3/03

状态：**REVIEW_PENDING**。`execution_admitted=false`、`one_item_authorized=false`；Test3 **BLOCKED**。

## 本轮范围

只新增本目录代码与控制/证据文件。未读取PCM、checkpoint或native二进制；未运行DSP、模型、optimizer、训练、CHECK科学试验、grid、性能或Host/Gate/Runtime。旧设计与所有已消费试验不修改、不重启、不返还预算；无commit/push。

## 关键实现

- `source_origin_triple.py`：沿用冻结线性LTV路径及一次噪声/增益/时钟；B独立一次ADC，E/N共用一个mic bytes对象，B/N共用一个render bytes对象。实际提交F32 render差产生独立preADC truth；不按臂重新归一化。
- `rbt_capture.py`：104三元组/312次独立Core、全前史与真实producer epoch。独立truth只在响应后附到source映射；104组共同target span必须同时有active/inactive，失败停止且不换样。保留rows/reset/invalid/col9/EOF；slots/rows/reset与160/J分别SHA绑定。
- `rbt_factory.py`：精确冻结teacher32449/anchor1057/norm160+40；原temporal-J函数，3617/5tensor fresh-zero deltas，不读旧557bed deltas或Adamstate。新RBT checkpoint严格family、shape、进度、norm、population及control绑定。
- `train_rbt.py`：冻结64FIT、8batch轮回、200updates/1600 triplevisits/4800 full-arm forwards；每次一个graph，不改成two-pass或旧400全TRAINpasses。冻结source-likelihood原损失、半active/半inactive、batch除8仅一次；原AdamW/LR1..200/clip1/seed20261006/CPUF32单线程。
- `check_rbt.py`：独立fresh model、只加载当前最终checkpoint，40CHECK/120原features真实epoch前向一次，无optimizer/norm fit。全场景B/E共同负峰与原legal triples严格概率比较；invalid/EOF留在全事件/活动分母。tau=null，不运行Gate或999grid。
- `run_rbt_once.py`：默认false在资产验证/科学依赖/进程前拒绝；固定1800s起钟先policy IO。Budget小seed/锁检查后durable fresh run claim，claim先于public输入完整hash/census。owner/driver共享计量锁；stdin/streams/aggregate RSS、实际wait、EOF、残组、partial及停机均不得被child0覆盖。失败保留文件，不删除/retry。最终真实tool receipt需未来执行时由root单独取得。

## 资源合同

冻结1800s whole / aggregate2GiB / retained64MiB，四类别56/4/2/2MiB。原子pending→final同一份文件，所有失败路径与临时文件计数。312臂rows/reset记录、104truth、最终checkpoint与≤1MiB transport partial的binary上界53,610,592B<56MiB。transport partial可含160/J，仅失败证据、不可用作cache。无PUBLIC新增文件或PCM/feature/J/P缓存。新预算独立，旧预算不重置。

实际双卷空间、完整static freeze后census、真实RSS/backing/复制/图与1800s能力均**NOT_RUN**；不足直接BLOCKED/技术STOP，不删旧资产或抬预算。

## 一次执行的通过/停止条件（当前不执行）

1. 必须先完成后续独立审查、全部身份/资源准入和新的单次授权；当前false合同不允许试验。
2. 拟议单次：208公共文件/manifest/worker/lib/FIR/Hann/Mel/teacher/anchor/norm/factory/所有源SHA及真实格式一致；104固定人口、共享字节、独立状态、标签隔离、source及epoch正确；首更新前初始teacher/candidate byte identity和104activity admission通过。
3. 严格200/1600/4800、capture312/prefix192/CHECK120，当前checkpoint进度/源/全部norm frozen，真实owner/driver/native退出、双EOF、无timeout/RSS/transport/monitor/residual、完整容量及封存都通过。
4. CHECK需要short≥19/20、weakshort10/10、long≥19/20，完整long活动100*above≥90*total。全部用N证据严格大于所有B/E全时负峰；并列/无Te计失败。通过仅`SOURCE_RELATION_PILOT_SUPPORTED_PRODUCT_GATES_NOT_RUN`，失败`REJECT_RBT1_MECHANISM_PILOT`；无阈值或正式产品Decision。
5. 身份、构造、标签流、source/reset/invalid、非有限、完成/退出或资源任一失败：`TECHNICAL_STOP_INCONCLUSIVE`，保留partial，机制未被检验，不重试/扩大预算。资源不足`NOT_RUN_RESOURCE`/BLOCKED。

## 未解决问题

- 真实PCM源、312臂构造/DSP与初始byte identity尚未执行。
- 真实function/gradient/update及独立CHECK尚未执行；静态/合成PASS不证明声源选择性或收敛。
- 所需实际空间/RSS/time未验证；任何一项不合格即停。
- 原pureecho零资格/确认、95%/90%、3/15/20、原AEC3clean/onset、actual-ready含queue及native/fullchain预算、DEVLOCK/PUBLICTEST/49/165与实体真人验收全部保留且NOT_RUN。

## 交付与审核

详见`key-diff.patch`、`identity-inventory.json`、`resource-inventory.json`与最终合成/静态回执。静态身份表列出的PCM、权重、native哈希来自已封存声明，本轮未重新打开或冒称独立实测。

**停止在REVIEW_PENDING，不自动开始试验或任何下一阶段。**

## 本轮实际核验

- 15份当前Python模块在内存compile通过，真实工具 `a0f00b/0`，不导入科学依赖。
- 一次stdlib入口fixture **11/11 PASS**，工具 `792123/0`，子进程41969实际wait退出0；测试体0.017866958s、supervisor whole0.089480166s，无timeout。历史protocol及pre-fixture false控制快照保留。
- 本次正常fixture执行后收到的launcher timeout分支问题已留原执行版，改为kill/reap后直接STOP，静态AST `a0f00b/0`和只读 `77eba8/0`闭合；未重复fixture。不把这项source闭合称为真实超时故障注入PASS。
- scientific trial/CHECK、实际空间/RSS/time、正式产品门均NOT_RUN。
