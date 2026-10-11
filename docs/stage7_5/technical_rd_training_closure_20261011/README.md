# Stage7.5 / Test3/03 · 技术研发训练收口

日期：2026-10-11。当前固定RBT-1组合正式收口：**REJECT_RBT1_MECHANISM_PILOT / NO_PATCH**。Test3/03继续BLOCKED，全部实验及DEV/grid/Runtime权限false。后续研究需要新的机制依据和单独决策；本次未启动下一阶段。

## 本轮实际结果

| 指标 | 保存结果及外部只读复算 | 冻结要求 |
| --- | --- | --- |
| short | 5/20 | ≥19/20 |
| weak-short | 0/10 | 10/10 |
| long | 6/20 | ≥19/20 |
| 完整long活动 | 1069/4478＝23.8723% | ≥90% |

共同B/E负峰n_BE＝0.9964888095855713。这是离线机制排序筛查失败，不是正式资格、确认或实体真人失败计数；tau=null。

唯一已授权试验完成200步、1600三元组访问、4800臂前向；64 FIT每个访问25次，40 CHECK独立加载最终checkpoint，120臂最终预测。工具最终d483a4/session51526 exit0；driver和native真实wait均0，native312请求、双EOF。全程93.28557225秒，聚合RSS采样峰1,032,634,368B，连续峰未获证明。exit0说明技术执行完成，不代表机制通过。

checkpoint仅发布身份：24,329B，SHA-256 `aaa40bd8d33df0024ea23dbdd0c838d6935ca70b66eb590534ee7d71ec83736b`。本目录及ZIP不含其权重。

## 证据与复审边界

- [结果包](RBT1-result-review.zip)：已审247 payload及manifest，共248成员；冻结设计、实际ARMED/CLOSED协议、实际源码文本副本、全部200步日志、40 CHECK事件、120臂119,760概率/119,880 source rows、40 truth区间及构造元数据。二进制记录只保存概率/source/reset及truth区间，没有PCM、features160、J40、H或权重。
- [200步日志](updates.jsonl)、[完整40 CHECK结果](check-completion.json)、[真实退出回执](runner-final-actual-tool-receipt.json)另以可读文本发布。
- [外部Pro正式收口](RBT1-Pro-review-closure.json)：用户粘贴的独立只读复审结论，保存概率共同负峰、合法三连、事件和活动分母均与原结果一致，未发现足以改变REJECT的具体执行或评价错误。外部没有模型/DSP/训练执行，未取得222项未附科学资产或权重payload，不能扩大为独立模型/音频复现。
- [当前状态](current-state.json)：RBT1_CLOSED_REJECTED_NO_PATCH，全部执行权限false。ZIP内CLOSED/current-state是外部结果复审之前的“等待复审”历史快照；本目录current-state及Pro收口记录为最新。
- ARMED合同`aa91dd68…`与授权`c166d22d…`是唯一试验当时的实际字节。完成后关闭权限导致的CLOSED哈希变化不是执行中修改合同。ZIP的历史ARMED true不能作为现行执行授权。
- [收口完整性](closure-integrity.json)与[本次发布清单](publication-manifest.json)绑定来源和字节身份。原文件中的no_commit_push指当时实施/收口没有Git发布；本次仅依据用户随后授权发布此文档快照。

## FIT证据缺口

最终完整FIT概率和机制评价没有保存，**FIT没建立能力／FIT有效但CHECK失效无法区分，保持UNVERIFIED**。训练risk是更新前八三元组batch值；step200及最后八批不能拼成最终checkpoint的完整FIT评价。训练前零delta teacher身份也不证明训练后能力。没有为补齐此缺口再运行预测、训练或实验。

## 发布与产品边界

用户授权提交推送，命名“技术研发训练收口”。本次只新增本目录；原待审快照、封存代码、数据、预算及失败记录保持原样。原1800秒／聚合2GiB／retained64MiB预算未放宽，唯一授权已消耗。

Stage7隔离发布checklist **PASS**。未修改生产代码、Host/Gate/Runtime、Runtime API、DR schema或平台target；未进入Stage8。原纯回声零资格/确认、95%/90%、3/15/20、真实400ms、original AEC3 clean/onset、actual-ready含队列、native及独立DEV/实体门仍未获替代或放宽。

本次仅复制、封存、Git diff与身份检查；编译、App测试、DSP、模型、训练、grid、性能及设备录音/外放均NOT_RUN。未新增研究、调参或下一轮。
