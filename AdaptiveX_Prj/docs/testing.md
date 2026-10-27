# 验证结果

## 1. 本包验证

| 项目 | 数据与结果 |
|---|---|
| 九模式编解码 | 149,940 个编码 bit、112,896 个信息 bit 匹配 |
| 三档 Tx RRC | 252 个并行输出拍及零尾部与 MATLAB 整数卷积一致 |
| P2/BPSK 接收 | 16 帧、96 个 LDPC 块；译码前 0/48,960、译码后 0/36,864 |
| 接收数值 | 平均 FDE MER 29.588613 dB、NLMS MER 30.886128 dB |
| 工程实现 | Tx/Rx 已完成综合、实现及 bit/LTX/XSA 导出，约束统计与资源见原始报告 |
| PS 软件 | 两端 A53 standalone64-bit 应用的新工作区构建与 XSA/ELF 对应关系已核对 |

本包接收回归条件为 25 dB ADC 输入 SNR、20 kHz 频偏、7 个 ADC 样点输入延迟与 offset=0。编解码、RRC 与完整接收的验证对象分别列于上表。逐帧图如下：

![本包P2 BPSK接收仿真的逐帧MER与浮点对照](../results/rx_link/mer_per_frame.png)

详细数值、STA 约束范围、运行记录与报告链接见[工程验证记录](../results/README.md)。数值入口与数据格式见[使用与复现](usage.md)。

## 2. 源工程作品测试

出于核心技术保护考虑，本次提供部分功能代码；技术文档及演示中的性能结果来自源工程。

源工程的模式识别、数字链路与九体制实采图表保存在[作品测试资料](../results/system_examples/README.md)，按各自试验条件引用。本页第一节是本包输入与数据对应的验证记录，两类资料分别归属。

## 3. 原生 Vitis 工作区

总目录 `vitis_workspace/` 为原工作区的原样副本。本轮核对其复制一致性；`software/board` 的源码、匹配 XSA 与 `build_app.tcl` 是独立的新工作区构建入口，其两端 ELF 构建记录见[PS 交付复核](../results/software/handoff.json)。
