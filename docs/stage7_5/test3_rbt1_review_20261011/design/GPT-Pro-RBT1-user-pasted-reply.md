## 实际读取边界

本轮重新读取了旧附件中的：

- `feature_worker.cc`第1–129、145–224行：真实mic/render进入FIR、SPX、四路特征及source/epoch/available记录的路径。
- `v4/train_head.py`第243–284行：原编码器、因果残差块及输出层。
- 旧`dev-evaluation-contract.json`第65–199行：资格比较、三连确认、完整分母、col9及独立验收门。

**没有取得最新temporal-J完整源码、checkpoint、SOR输出或两次off结果。** 新数字按你的本机执行摘要使用，没有独立复算。本轮不执行任何模型、DSP、训练或求解。

# 唯一决定：`GO_DESIGN_ONLY — RBT-1，三元来源对照监督`

**不再修改J、不直接关闭J、不增加网络容量。保留当前模型函数，重新建立一个独立的、小规模“来源归属监督”候选。**

这不是续训`557bed…`。旧候选及SOR拒绝全部保留。新候选从**同一冻结V4、同一anchor、全零headdelta和VJ**开始，只检验一个新增机制：

> **用“同麦克风却不同来源”与“同参考却不同来源”两种约束共同监督模型，迫使低训练损失依赖mic与实际render的关系，而不是某一路的语音存在或能量。**

这是新监督合同，不是旧代码Bug修复；成功也不能单独归因于换了一项loss。

## 1．现有反例支持什么决定

按你给出的结果，该pair中：

\[
p_{E,\mathrm{off}}>a_{N,\mathrm{off}}
\]

所以在原`p≥tau`及原合法三连定义下，关闭J仍不能同时满足这个负例的安全要求和近端及时条件。**继续做J开关、校准或重复峰值检查没有必要。**

但SOR原来只有：

```text
同一个mic + 包含短语音的render → 应无近端
同一个mic + 不包含短语音的render → 应有近端
```

它能排除“只看mic就足够”，却没有单独排除一种捷径：**模型只根据render中是否出现额外语音作判断，而没有核对它与mic的对应关系。**

因此，下一项补的不是另一个谱量，而是**同时约束两个单路捷径的监督关系**。

## 2．一个三元组，只有短语音的来源不同

使用独立公共语音 \(r,s\)、冻结的线性声学路径 \(\mathcal A\)及共同噪声 \(n\)：

\[
m_0=\mathcal A(r)+n
\]

\[
m_1=\mathcal A(r)+\mathcal A(s)+n
\]

构造三个臂：

| 臂 | 提交的render | mic | 近端标签 |
|---|---|---|---|
| **B：短语音不存在** | \(r\) | \(m_0\) | 0 |
| **E：短语音来自播放** | \(r+s\) | \(m_1\) | 0 |
| **N：短语音来自近端** | \(r\) | \(m_1\) | 来自独立源 \(\mathcal A(s)\) 的活动标签 |

必须做到：

- **E/N共用同一份canonical mic字节**，包括共同ADC处理。
- **B/N共用同一份render字节**。
- 噪声、增益、时钟、路径参数不按臂重新计算。
- 每臂独立初始化，完整前史顺序执行，不借另一臂状态。
- 标签来自公共clean源及冻结源映射，不来自J、模型分数或Gate。
- 线性路径、叠加顺序及ADC规则明确冻结；不能将非线性路径的可加性当作既定事实。

这是新控制输入族。近端路径故意与播放路径相同，用于验证来源关系，**不是现实嘴到麦克风路径的模型，也不是实体400ms验收**。

### 它新增了什么可识别约束

在完整活动区间：

- 只依赖mic的函数会给E/N相同结果，无法同时正确。
- 只依赖render的函数会给B/N相同结果，也无法同时正确。

因此，模型要同时解释三臂，必须利用两路之间的关系，或者与该关系共同变化的处理状态。

**这仍不能排除所有双路能量捷径、声场记忆或模拟器偏差。** 但它比再证明“J改变了分数”多了一项可学习、可反驳的任务约束。

## 3．只改变监督机制，模型与输入路径不变

继续使用你封存的真实函数：

```text
P0 = frozen_projection_and_first4blocks(old160)
P  = P0 + linear(normalizedJ, VJ)
H  = frozen_dilation16_lastblock(P)
z  = frozen_out(H) + anchored_head_correction(H)
```

不增加层、宽度、lag、历史或新输入；不解冻teacher／anchor。原3617个可训练参数重新置零，不加载失败候选的delta或Adam状态。

旧代码已经确认：四路Feature包含实际render，M/L/E又通过reference-conditioned producer产生。新监督有真实输入通道可用，不需要把标签接入前向。feature_worker feature_worker

**唯一新的机制变量是三元来源监督。** 为实现它，需要成套改变训练样本组织及其联合损失；这不是一个“只换loss、其他数据完全相同”的归因实验。

### 固定来源似然

每个共同source target得到三个实际logit：

\[
z_B,\ z_E,\ z_N
\]

训练时加入固定的“无近端”零logit，定义：

\[
\pi=\operatorname{softmax}(0,z_B,z_E,z_N)
\]

令 \(y\in[0,1]\) 为N臂原始活动占比，目标质量只分配给“无近端”和N：

\[
\boxed{
\ell=\log\!\left(1+e^{z_B}+e^{z_E}+e^{z_N}\right)-y z_N
}
\]

梯度为：

\[
\frac{\partial\ell}{\partial z_B}=\pi_B,\quad
\frac{\partial\ell}{\partial z_E}=\pi_E,\quad
\frac{\partial\ell}{\partial z_N}=\pi_N-y
\]

这样，E与B都受到明确的负侧压力，N只在独立近端活动时获得正侧监督。**不是用两个臂的分数差作在线输入。** 部署前向仍只接收当前一组mic/render；三元组只用于训练。

为避免10秒场景的大量无活动帧淹没短句，本次固定每个三元组：

\[
L_{\rm triple}
=\tfrac12\,\operatorname{mean}_{y>0}\ell
+\tfrac12\,\operatorname{mean}_{y=0}\ell
\]

再对三元组等权平均。不搜索权重；fractional标签保持原值。这个平衡方式是**本次明确新增的机制试验条件**，不是产品概率先验或资格阈值。

若某三元组缺少预定的活动／非活动集合，整项数据准入失败，不在评分后换样补齐。

### 最小函数边界

```python
# 新隔离文件；不改旧CQM及失败模型。
def routing_loss(z_b, z_e, z_n, y):
    stacked = stack([zeros_like(z_n), z_b, z_e, z_n])
    per_row = logsumexp(stacked, axis=0) - y * z_n
    return (
        mean(per_row[y > 0]) + mean(per_row[y == 0])
    ) / 2

# 三臂各自按完整真实producer epoch计算。
# 标签和arm角色不得传入head.forward、reset或特征生成。
z_b = head(features_b)
z_e = head(features_e)
z_n = head(features_n)
loss = routing_loss(
    map_to_common_source(z_b, z_e, z_n),
    frozen_near_activity,
)
```

三臂不能按dense score下标强行对齐。若reset或invalid不同，必须按原raw48 target和epoch映射；没有三臂真实输出的训练行标记不可用，**仍留在最终事件和活动分母中**。

## 4．唯一有限实验：新公共三元组上的机制学习与独立检查

不重跑原160对SOR，不用TRAIN:0079及已分析反例训练，也不把它们重新包装成“未见测试”。

建议预登记一个小型、明确的新范围：

| 项目 | 固定设计 |
|---|---|
| 机制拟合集 | 64个三元组：32个400ms短事件、32个长事件；各一半weak |
| 机制检查集 | 40个三元组：20短、20长；各一半weak |
| 来源 | 仅既有已准入public TRAIN源池；按源文件／说话人及路径组固定划分，不依据模型分数选样 |
| 隔离 | 拟合与检查的说话人和路径组分开；旧SOR材料只保留，不参与此次拟合和选择 |
| 长事件 | 沿用预先指定公共源的1–4秒范围；不以结果选择长度 |
| 模型初始化 | 同teacher／anchor／norm，3617个delta全零，原seed和构造顺序 |
| 训练 | batch含8个完整三元组；固定200次更新、原AdamW/LR1…200/clip1；最终步唯一产物 |
| 运行次数 | 各三元组的前端只生成一次；最终检查集仅一次前向，不跑grid或旧模型对照 |

这200次是**新来源监督机制的有限拟合预算**，不是给失败CQM续加200步；它不保证优化充分。

划分必须在任何新分数产生前冻结。若现存公共资产不能满足这个身份与隔离要求，直接`STOP_PUBLIC_PAIR_ADMISSION`，不下载另一批数据或挑替代样本。

还要如实说明：冻结V4可能见过这些公共TRAIN来源。因此检查集仅对**本次delta拟合**未使用，不能称作完整模型从未见过的泛化测试。

## 5．只用一次任务检查决定是否继续，不以loss下降晋级

最终模型在40个机制检查三元组上计算一次原Float32概率。先定义共同负峰：

\[
n_-=\max_{\text{全部B/E臂、全部有效source rows}}p
\]

对每个N事件，沿用原合法三连：

\[
a_e=\max_{T\in\mathcal T_e}\min_{i\in T}p_i
\]

\(\mathcal T_e\)仍要求三有效连续同epoch、活动相交及col9 frontier在起点后0…9600 raw48内。不能根据分数改变集合。原合同对这些区别已有明确规定。dev-evaluation-contract dev-evaluation-contract

机制继续条件固定为：

- short至少19/20满足 \(a_e>n_-\)；
- weak-short至少10/10满足；
- long至少19/20满足；
- long完整活动分母至少90%的有效分数严格大于 \(n_-\)；
- 所有invalid、不可达事件、起音前缀和尾部均保留，概率相等不算分开。

**这是共同安全排序的必要条件，不是已执行资格／确认。** 不选择 \(n_-\) 为tau，不取`nextafter`，不跑999 grid，也不把最佳三连当作真实CLOSED→CONFIRMED或原PCM已经保留。

结果只允许：

| 结果 | 决定 |
|---|---|
| 训练loss下降，但完整机制条件失败 | `REJECT_RBT1_MECHANISM_PILOT`；不加步数、换seed或改权重 |
| 两类单路捷径被约束，检查集任务排序条件全部成立 | 支持当前函数族**在这一控制输入族上可以通过来源监督学到参考归属选择性**；才值得提出后续训练域适配 |
| 输入／状态／源码／数值身份失败 | 机制未被检验，停止，不将其写成模型不行 |

即使通过，也不能证明网络真正恢复了物理回声路径。它可能学到控制声场中有效、但实体中脆弱的双路关系。这是后续独立数据和实际设备必须继续否证的风险。

## 6．资源、冷状态及固定停止边界

本项拟议总上限为：

```text
一次完整item：1800秒，包含公共构造、前端、训练、终检与封存
聚合RAM：2GiB
最坏新增保留／临时提交／失败封存：64MiB
无新增权重下载、无旧资产删除
```

这些是**待root核验的新资源合同，不是已取得额度，也不是耗时预测**。不能挪用或重置已耗尽的J-CIP额度；实际余量不足即`NOT_RUN_RESOURCE`。若完整新前端产物无法在既定RAM与封存合同中留存必要身份，不以“先capture、后面再说”启动。

实现错误、hash变化、越epoch、未来支持、输出缺失、非有限值、超时或超内存均停止。不能重试另一个配置。

实际输出时刻仍须晚于所需输入、producer、Feature、模型及发布完成；本轮离线前向不提供线上ready证明。新权重后的完整native预算必须另行验证，不能继承旧随机头或早期SPX调用耗时。

# 最终唯一下一项

**封存RBT-1三元来源数据构造、联合来源似然及一次64拟合／40检查的隔离合同，先静态与必要fixture复审。当前仅`GO_DESIGN_ONLY`，训练／capture授权继续为false。**

它不再问“J有没有改变数字”，而是检验：

> **当前函数族能否在同时不能依赖mic单路、也不能依赖render单路的监督下，学会有任务效用的来源绑定。**

这是有因果动机的新监督试验，不是保证可行的新补丁。当前J映射及SOR失败不翻案，也不因此否定所有reference-aware方案。

**Stage7隔离设计边界PASS；Test3/03保持BLOCKED。** 正式WebRTC、Host/Gate、Runtime权限不动；原纯回声零资格／确认、95%／90%、3／15／20、originalAEC3clean及432样本／9ms、PCM起音、actual-ready含queue、0.5／1／10ms预算、DEV-LOCK／PUBLIC-TEST／49与165及最终实体门全部保留。当前不需要用户讲话或录音。