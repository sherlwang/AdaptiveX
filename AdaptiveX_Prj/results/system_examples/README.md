# 作品测试图表

本目录保存源工程技术文档及演示使用的代表性图表与九体制实采波形统计。图表属于源工程作品测试，随包工程的独立验证见[工程验证记录](../README.md)。

| 文件 | 内容 |
|:---|:---|
| `figures/pilot_detection.png` | 已知 P 条件下，首块导频 M 识别的样本正确率 |
| `figures/frame_mer.png` | 数字链路仿真中，82 帧序列的 FDE/NLMS MER 与模式轨迹 |
| `figures/system_constellation.png` | 九体制基带直连实采波形经 HDL 接收后的 NLMS 星座 |
| `tables/mode_summary.csv` | 九体制的 FDE/NLMS 汇总质量指标 |
| `tables/frame_summary.csv` | 实采波形的逐帧处理统计 |
| `tables/capture_summary.csv` | 各次采集的汇总统计 |

三张图来自不同试验，测试条件按各图含义及技术文档说明。实采波形的 MER 按参考能量与误差能量汇总计算，本目录实采质量统计采用 MER 口径。
