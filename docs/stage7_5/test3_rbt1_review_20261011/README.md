# Stage7.5 / Test3/03 · RBT-1 待审入口快照

**REVIEW_PENDING；execution=false；Test3 BLOCKED。** 本次只发布审核材料，未开始科学试验或下一阶段。

## 审核范围与读取顺序

1. [入口交付报告](entry/outcome-report.md)、[设计v2](design/design-contract-v2.json)、[固定人口](design/population-descriptors.json)。
2. [三臂构造](entry/source_origin_triple.py.txt)、[损失](entry/routing_math.py.txt)、[训练](entry/train_rbt.py.txt)、[独立CHECK](entry/check_rbt.py.txt)。
3. 当前 `entry/` 的另外11个 `.py.txt`：完整身份、真实epoch、进度、退出、deadline、共享预算与失败封存边界。
4. [身份](entry/identity-inventory.json)、[资源](entry/resource-inventory.json)、[false合同](entry/entry-contract.json)、[false授权](entry/execution-authorization.json)、[真实fixture回执](entry/fixture-actual-tool-receipt.json)。
5. `dependencies/` 的8份直接Python源码供核对原模型、归一化、原source/三连/col9评价函数。历史 `pre-review/`、`pre-fixture/` 仅用于追溯，不是当前版本。

所有 `.py.txt` 均为原源码逐字节副本，仅追加 `.txt` 后缀。原 `.build` 封存目录未修改；绝对路径仍指向原本机来源，快照不能直接运行。[publication-manifest.json](publication-manifest.json) 绑定发布路径、原路径、字节及SHA256。

## 冻结内容

- 64 FIT / 40 CHECK 三元组；同一E/N mic、同一B/N render；一次噪声/增益/时钟，三臂独立Core状态。
- 原temporal-J函数及3617 fresh-zero deltas，固定source-likelihood损失、seed20261006、AdamW/LR1..200/clip1。
- 200updates /1600 triple visits /4800完整arm forwards；独立CHECK40/120完整原features trueepoch前向。
- 1800s whole、聚合2GiB、全部retained64MiB；临时与失败文件计入，不删旧资产或返还旧预算。
- 标签仅目标/评价使用；完整source/epoch/invalid/col9/EOF分母。

## 已有核验与未验证事项

一次stdlib合成fixture11/11通过，工具792123 exit0；当前15Python模块仅在内存compile。正常fixture后的timeout helper修复仅静态闭合，未重跑、未声称真实超时注入通过。原执行版见 `entry/pre-review/run_entry_fixture_once-executed.py.txt`。

未读取PCM、checkpoint、H或native二进制，未运行DSP、模型、训练、CHECK科学试验、grid、性能或Host/Gate/Runtime。真实空间/RSS/time与声源归属效果均NOT_RUN。

原资产SHA只是已封存声明。本包不含波形、权重、FIR/Hann/Mel二进制、native可执行/dylib、venv或真实H/J/P/feature缓存；也不包含旧1.65MiB temporal完整合同。不能据文本审核冒称独立实测这些缺件。

## 希望审核者给出的唯一决定

请先声明实际读取范围。核对构造的共享字节与标签隔离、梯度/200步/完整分母、checkpoint与实际退出绑定、预算及失败封存。只报有证据的问题及文件/行号，给GO_REVIEW / REWORK / STOP和唯一最小下一步；未取得材料须明确，不根据摘要补齐PASS。

CHECK拟议机制通过要求short≥19/20、weakshort10/10、long≥19/20、完整longactivity≥90%，N及时证据严格超过全B/E共同负峰。即使将来通过也仅SOURCE_RELATION_PILOT_SUPPORTED_PRODUCT_GATES_NOT_RUN；不替代pureecho零资格/确认、95/90、3/15/20、AEC3clean/onset、实际ready/native/独立DEV或实体真人门。

## 发布边界

本次提交推送由用户另行授权，仅新增本目录快照。原报告中的“无commit/push”为实施时历史事实；本次Git发布不改变原结果、预算或执行权限。基线为7.5.11 / d40fbb26b52453954312a12484b4d4f161baa12e，publication commit以所在提交URL为准。

Stage7隔离checklist：**PASS**。无生产代码、Runtime API、DR schema、平台target或Stage8变更。试验权限仍false。

发布检查：原 `key-diff.patch` 的7个空上下文行保留统一diff要求的空格标记，Git whitespace检查会报告这7行；其余发布文件单独通过diff检查。未为消除告警修改原封存patch。
