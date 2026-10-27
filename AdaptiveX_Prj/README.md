# AdaptiveX：智能自适应多速率宽带通信系统

基于 AMD RFSoC ZU47DR 的九体制单载波通信工程，采样率为 4.9152 GSPS，支持 P=2/4/8 与 BPSK、QPSK、16QAM 的九种组合，对应符号率 409.6/819.2/1638.4 Msymbol/s。系统包含模式识别、AI 推荐、反馈切换、以太网业务和星座监测接口。

出于核心技术保护考虑，本次提供部分功能代码；技术文档及演示中的性能结果来自源工程。

## 1. 直接打开工程

使用 Vivado 2021.2，在 GUI 中分别打开：

| 端 | 已完成工程 | bit |
|---|---|---|
| Tx | `Tx/project/tx.xpr` | `Tx/project/tx.runs/impl_1/adaloop_top.bit` |
| Rx | `Rx/project/rx.xpr` | `Rx/project/rx.runs/impl_1/adaloop_top.bit` |

两端目录包含综合、实现与导出结果；保留各自完整目录及 `cores/`、`project/` 的相对关系。配套 LTX、XSA、Vitis 入口与板卡启动步骤见[使用与复现](docs/usage.md)。

总目录同层的 `../vitis_workspace/` 为原生 Vitis 工作区的原样副本；`software/board` 提供另一条已验证的 PS 源码、XSA 和新工作区构建入口。

## 2. 目录

| 路径 | 内容 |
|---|---|
| `Tx`、`Rx` | 已完成综合、实现及 bit 导出的 Vivado 工程和配套依赖 |
| `src/tx`、`src/rx` | 集成 RTL、IP/BD、约束、初始化数据及必要实现 hook |
| `ip/tx`、`ip/rx` | 预编译核、功能模型、接口声明及哈希 |
| `build` | 可选新建工程、展开网表、综合与实现入口 |
| `software/board` | Tx/Rx 的 PS 初始化源码、匹配 XSA 和 Vitis 构建入口 |
| `software/matlab/monitor` | 264 字节 UDP 星座与质量监测上位机 |
| `sim`、`data`、`matlab` | 测试台、固定输入与真值、数值检查 |
| `results` | 本次随包输入的仿真、实现和软件构建记录，以及源工程作品测试资料 |
| `docs` | 工程说明、使用与复现、验证结果及作品展示图 |
| `LICENSES` | 随第三方文件保留的许可正文；对应关系见[第三方索引](THIRD_PARTY_NOTICES.md) |
| `tools`、`MANIFEST.json` | 交付文件清单与完整性检查 |

源重建输入与成品工程分别保留。完整工程包使用本页第一节的 XPR 入口；代码 RAR 使用第三节的源重建入口。代码 RAR 从源输入及必要依赖提取，具体范围见[交付与上传说明](../skill/sherl-github-project-publish/references/adaptivex_upload.md)。

## 3. 文件检查与可选重建

使用 Vivado/Vitis 2021.2、Python 3.10+；MATLAB 用于数值复核。在本目录检查文件与网表载荷：

```bash
python3 tools/verify_package.py
```

需要从源输入另建工程时，选择新的输出目录：

```bash
python3 build/build.py tx --stage create --output validation/tx --vivado-root /path/to/Vivado/2021.2
python3 build/build.py rx --stage create --output validation/rx --vivado-root /path/to/Vivado/2021.2
```

使用 `--stage synth` 或 `--stage bit` 可分别执行综合或完整构建。接口和配置见[工程说明](docs/engineering.md)，仿真与 PS 软件入口见[使用与复现](docs/usage.md)。

只读重算随包接收记录，在 MATLAB 工程根目录执行：

```matlab
addpath('matlab');
report = verify_link(fullfile(pwd,'results','rx_link'),true,false);
```

## 4. 作品与验证资料

下图来自源工程的九体制基带直连实验，展示实采波形经 HDL 接收后的 NLMS 星座。

![源工程九体制基带直连实采波形经HDL接收后的NLMS星座](docs/figures/system_constellation.png)

源工程图表与统计见 [system_examples](results/system_examples/README.md)。本包仿真使用独立的 P2/BPSK 数据集；其测试条件、逐帧数值与实现记录见[验证结果](docs/testing.md)。

[独立 Skill](../skill/README.md) 与 [MIT 许可证](../LICENSE)位于总目录；第三方适用条款见[第三方索引](THIRD_PARTY_NOTICES.md)。
