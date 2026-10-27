---
name: sherl-vivado-resource-baseline
description: 从已完成的 Vivado 综合或实现结果导出完整模块层级资源、整机及 PHY 时序和可追溯基准，并对比同条件的前后版本。用于资源基线、优化收益和生 bit 后的时序分析；不启动综合实现，不修改 HDL 或约束。
---

# Vivado 资源与时序基准

将“这一版用了多少资源、违例集中在哪里、与基线相比改变了什么”落实到同一份网表及其输入证据。不要只给 PHY 顶层或摘要前十条路径；完整层级表是主要交付，关键计算／缓存／控制模块从表中选出解释。

## 1. 确认对象

- 使用用户指定的已完成 DCP，或以只读方式打开现有工程的已完成 run。明确 synthesized、placed、routed；不同阶段不能冒充同条件比较。
- 指定 PHY 的精确实例路径，例如 `u_fmc_thz_test_top/u_phy_top_rx`。实例更名或被扁平化时先核对，不能让空集合悄悄变成“PHY 无违例”。
- 确认输出目录、基线及当前结果。采集必须新建目录，不覆盖旧证据。工具及许可证沿当前环境配置，不在技能中写死安装位置。
- 记录工程、DCP、配套 bit/LTX、HDL、ROM/MEM、XCI/BD、XDC 及脚本哈希。**一同收集的源码和 bit 不等于构建来源已匹配**；有构建时输入清单才据其逐项核验，没有就明确缺口。

## 2. 采集

使用 [scripts/baseline.py](scripts/baseline.py)，Python 3 标准库即可。它调用同目录 `collect.tcl`，只打开现有结果并导出报告；不运行 `launch_runs`、`reset_run`、`save_project` 或写检查点。所有日志留在输出目录。

```bash
python3 scripts/baseline.py collect \
  --vivado /path/to/Vivado/2021.2/bin/vivado \
  --dcp /path/to/adaloop_top_routed.dcp --stage routed \
  --phy u_fmc_thz_test_top/u_phy_top_rx \
  --source-root /path/to/rx.srcs \
  --artifact project=/path/to/rx.xpr \
  --artifact bit=/path/to/adaloop_top.bit \
  --out /path/to/report/stage2_baseline --audits
```

也可将 `--dcp ...` 改为 `--project /path/to/rx.xpr --run impl_1`；综合结果用 `--run synth_1 --stage synthesized`。工程方式以 `open_project -read_only`、`open_run` 打开既有网表，可同时记录 run 策略和参数。DCP 方式若缺少构建配置证据，不能推定策略相同。

- `--source-root` 可多次指定，扫描 HDL、约束、IP/BD 和初始化文件；不要指向整个项目或包含大量历史工程的参考目录。
- `--artifact label=path` 可附带 LTX、XPR、配置记录；`--build-input-manifest` 保留构建时输入清单，但脚本不把未经审查的清单自动判为可信。
- `--audits` 追加 CDC、clock interaction、exception coverage/ignored、bus skew、methodology、DRC。分析跨域或交付时序时启用；仅看面积的局部比较可不启用。
- 负裕量查询上限默认 200000，层级深度默认 64。命中上限会提示不完整；按实际规模增加 `--cap`／`--depth` 后重新采集，不能声称已覆盖全部失败终点。

## 3. 解读与比较

先看 `summary.md`，核对 `summary.json` 和原始报告。结果包括：

- 整机 `utilization.rpt`、完整 `hierarchy.rpt` 和 `complete_resource_hierarchy.csv`。摘要与对照同时显示整机使用量、可用量、利用率及实际占用 CLB／Slice；原报告没有的保持 unknown，不虚构模块层级 CLB。
- 官方建立、保持、脉宽摘要及未约束检查。TNS/THS/TPWS 取官方摘要；**不能将舍入后的逐条 slack 相加当作官方总负裕量**。
- `whole`、`phy_internal`、`into_phy`、`out_of_phy` 的建立／保持代表路径；`negative_paths.tsv` 是按 `-nworst 1` 查询的代表负路径／失败终点视图，不枚举全部组合路径。命中查询上限时端点覆盖不全。PHY 分区以时序寄存器及顶层 I/O 为边界，不包含已排除或未约束的路径。
- `manifest.json` 绑定输入、工具、原始报告和采集命令，记录采集期间输入内容是否变化。

大型 PHY 的寄存器集合可能触发 Vivado `12-4439` 性能提示，应与设计时序告警分开解释。为避免无路径时 `12-975` 将整段巨大对象列表写进日志，独立采集进程只抑制这一条“无路径”提示；各 scope 的空查询计数和 EMPTY 报告仍明确保留，其他错误／Critical 不抑制。代表路径先查询成 timing-path 对象再报告，避免将数十万个对象展开到报告命令头。查询报错仍使采集失败，不能当成空集合。

比较时读取两套采集目录，不改写旧基准：

```bash
python3 scripts/baseline.py compare \
  --old /path/to/report/stage2_baseline \
  --new /path/to/report/optimized \
  --out /path/to/report/comparison
```

完整前后表保留精确路径、inclusive/self 范围与缺失项，差值统一为“新减旧”。器件、工具、网表阶段、时钟、约束、run 配置及调试 IP 参数分别标成 same／different／unknown；有缺项就说明，不把 unknown 当 same。对已经存在的原始报告，可先用 `summarize <目录>` 生成层级表和摘要；此方式缺少采集清单时仅是报告导入。

## 4. 报告要求

- `inclusive` 已包含子模块，父子不可相加；`self` 仅指模块直接拥有的逻辑。BRAM36 等效数为 RAMB36 加 RAMB18/2，URAM 单列。
- 模块更名、扁平化、优化后消失时保留 null，先追踪映射再解释，不能把缺失行计作零资源。脚本不自动猜别名。
- 从整机到 PHY，再到重要计算、缓存、控制模块说明变化；不要只摘优化模块，也不要用 OOC 核报告替代完整 routed 结果。
- 调试核增删、约束／策略变化、映射与层级归属变化单独说明。减去 ILA 子树只能算算术参考，不能称为旧版关闭 ILA 后重新实现的测量结果。
- 正 WNS 只覆盖当前 STA 范围；结合 no_clock、未约束 I/O、ignored exceptions、CDC Critical 判断。PHY 内通过不等于 PHY 跨边界或整机通过。
- 报告聚焦结构瓶颈和验收结论；不因单个端点报错就自行加 false path、放松时钟或修改 RTL。生成 bit、功能仿真、板测各有独立证据，不能由本技能的采集成功代替。

技能来源、输出字段与验证范围见 [references/provenance.md](references/provenance.md)。
