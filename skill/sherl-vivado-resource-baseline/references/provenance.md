# 1. 提炼来源

本技能来自单载波多速率项目实际使用的报告流程，移除了工程绝对路径、Tx/Rx 硬编码表以及历史版本专属判断，不依赖原工程或历史压缩包运行。

| 来源 | 沉淀内容 |
| :--- | :--- |
| `AI_Outputs/resource_optimization/verification.zip` 中 `reports/export_reports.tcl` | routed 资源、完整层级、PHY 内建立／保持及 CDC 报告 |
| 同包 `reports/parse_hierarchy.py` | Vivado 层级缩进、inclusive/self 和 BRAM36 等效解析 |
| 同包 `reports/compare_resources.py` | 完整前后层级对照、缺失行保留、ILA 算术减法与真实测量分开 |
| `AI_Outputs/resource_optimization/postcleanup_timing_reports.zip` 中 `export.tcl` | 全部负裕量端点、约束覆盖、ignored exception 与构建版本分开 |
| `work/latest_timing_1019/inspect_routed.tcl` | 建立／保持负路径 TSV，起终点、时钟、逻辑级数与数据延迟 |
| `work/frontend_architecture_review_1019/resources/collect.py` | DCP／bit／源码／报告哈希绑定，缺少历史结果时不借用其他版本 |

本技能没有复制原工程 HDL、ROM、IP、板卡配置、实采数据或 DCP。源脚本仅用于提炼方法；这些工程专属材料不属于技能运行依赖。

# 2. 输出与比较边界

`manifest.json` 记录输入路径和 SHA256、工具启动文件与采集脚本 SHA256、实际命令、返回码、输入在采集期间是否改变、原始输出哈希。Vivado 实际版本、器件、run 策略／选项和时钟另见 `metadata.tsv`、`clocks.tsv`。

`source_files` 是用户给定源码根目录下的当前文件；它不是从 DCP 反推出的构建输入。附带的 bit/LTX 和构建清单也只是证据，采集脚本不能证明它们由这份 DCP 产生。需要结合原构建记录、文件哈希、时间顺序和实际运行日志核验。同理，对不带工程的 DCP，不能假定约束、run 策略和调试配置已完整保留。

`complete_resource_hierarchy.csv` 的字段为 Path、Depth、Scope、Module、LUT、LogicLUT、LUTRAM、SRL、FF、RAMB36、RAMB18、URAM、DSP、BRAM36eq；未出现在当前器件报告中的可选项不凭空补零。Path 使用 Vivado 实例路径：顶行为顶层模块名，子实例路径不加顶层名；self 行指向其所属实例。

`whole_utilization` 从官方整机 Site Type 表读取 Used、Available、Util%，包含占用 CLB（或 Slice）。原报告缺项时保持 unknown；不把 CLB 估算或分摊到层级表。常见资源同时与层级顶行交叉核对，不一致会警示报告可能来自不同网表。重新离线解析时，`summary.json` 另记实际解析器 SHA256；原采集清单不改写成新版解析器已经执行过采集。

`summary.json` 中 `official_timing` 来自官方 Design Timing Summary，覆盖建立、保持、脉宽；`path_scopes` 是区域性时序查询，只有最差裕量及查询到的代表负路径／唯一端点数，不自造区域性 TNS。负裕量查询采用 `-nworst 1`，用于覆盖各失败终点的代表路径，不枚举全部组合路径；命中 `--cap` 时连端点覆盖也不完整。

`hierarchy_comparison.csv` 保留每个路径的旧值、新值、差值和匹配状态。只比较精确路径与 scope；若模块改名，需要人工核实后另列功能映射，不修改原始层级表。`comparison.json` 同时保存两套报告及清单的哈希。

CDC、DRC、methodology 的命令支持与可用检查随 Vivado、器件、网表阶段变化。命令失败会记录在 `report_status.tsv`，不得将“生成部分报告”写成“全部检查通过”。综合／布局阶段的时序只能作为估计，routed 结果也只代表当前约束下的 STA。

代表路径使用 `get_timing_paths` 返回的对象传给 `report_timing -of_objects`，不重复传 `-delay_type` 或巨大 from/to 列表。无路径时写入明确的 EMPTY 文本；空查询不是 API 错误，也不是未约束路径安全的证明。采集进程仅抑制 `Vivado 12-975` 的无路径长命令回显，并在 metadata 记载；其他性能、约束和设计告警均保留。

# 3. 依赖与验证

- Python 3.9 以上，全部使用标准库。
- Vivado 命令行和可用许可证；原流程使用 Vivado 2021.2。先使用与工程构建相同版本，不自动升级 IP 或迁移工程。
- Tcl 由 Vivado 内置解释器执行；普通 `tclsh` 只能进行语法／分支检查，不能验证 EDA API。
- 新输出目录可写，生产工程和参考材料可读。工程方式使用只读打开，不保存工程、不生成 IP、不启动 run。

提交前应执行：

1. 用真实历史 `utilization.rpt`、`hierarchy.rpt`、`timing_summary.rpt` 离线解析，核对占用 CLB／利用率、顶层资源、self／子模块路径、三类时序摘要。
2. 对同一套报告比较，全部匹配行资源差值应为零；确认旧基准的哈希不变。
3. 用已有 routed DCP 做一次只读试跑，核对 PHY 精确实例、边界时序查询、代表负路径／失败终点计数和可选检查状态；不启动综合实现。该试跑仅验证采集工具，不构成通信功能或板测结论。
