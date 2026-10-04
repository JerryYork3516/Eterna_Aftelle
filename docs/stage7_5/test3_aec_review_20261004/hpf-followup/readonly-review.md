# 只读复审汇总

## 关联与校准审查

`hpf_calibration_readonly`独立确认：frame85同一实际classification窗口，HPF输出相关不满足两项≥0.55的关联支持，候选1→0。frame87曾复位，224–226才是首次基线建立的直接连续链。frame346同窗口，immediate因raw相关<实际0.35返回，自适应因0<5返回。现有证据支持规则按设计执行，未证明实现Bug；不给产品patch。

## pinned信号语义审查

`hpf_signal_contract_readonly`独立确认：capture HPF顺序与pinned APM fullband路径一致；render路径无对应HPF不是调用错误；有状态IIR相位不能直接折成整数lag。linear来自低频block独立framer，processed还经过抑制/全频合成，72/144模型与源码一致。

Host box抽取与真正band0不同，但不同不能直接推出当前启发式统计量实现错误。替换splitter会改变统计量、历史和额外延迟，不能为了frame85达到0.55选择变换。固定HPF参照诊断linear仍0.457918，因此本协议STOP，无可批准产品patch。

源码定位：

- Host：1356–1361、2635–2713、3432–3550、3998–4068。
- Bridge：`tools/webrtc_aec3/bridge/AftelleAECBridge.mm`；隔离副本`capture_hpf.mm:134–139`。
- pinned `audio_processing_impl.cc:1232–1236、1292、1311–1313、1350–1351、1588–1613`。
- pinned `echo_canceller3.cc:167–205、809–815`。
- pinned `three_band_filter_bank.cc:178–224`、`.h:25–38、65–69`。
- pinned `block_framer.cc:24–30`、`suppression_filter.cc:132–143`。

两项均NO_CHANGE，无设备操作。root以实际文件和独立数值复算核验结论；当前Test3为BLOCKED。
