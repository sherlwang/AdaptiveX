# 使用与复现

## 1. 环境与文件检查

| 工具 | 用途 |
|---|---|
| Vivado 2021.2，支持 `xczu47dr-ffve1156-2-i` | 工程重建、综合、实现、XSim |
| Vitis 2021.2 | A53 standalone PS 初始化应用 |
| Python 3.10+，标准库 | 展开载荷、构建与仿真入口、清单检查 |
| MATLAB | 数值复核；重新产生 RRC 波形使用 Communications Toolbox |

工具和器件/IP 使用条件由接收者自己的安装提供。在工程根目录执行：

```bash
python3 tools/verify_package.py
```

脚本检查工程 `MANIFEST.json`、九核压缩载荷及展开后哈希。总目录原生 Vitis 工作区的复制一致性单独核对。`.gitattributes` 的 `* -text` 保持跨平台文件字节。Windows 可将 `python3` 换成 `python`，工具路径可使用正斜线。

## 2. Vivado 成品工程与可选重建

### 2.1 打开已完成工程

本节路径对应完整工程包；仅使用代码 RAR 时，按第 2.2 节从源输入另建工程。

使用 Vivado 2021.2，在 GUI 中打开以下工程：

| 端 | XPR | bit | LTX | 含 bit 的 XSA |
|---|---|---|---|---|
| Tx | `Tx/project/tx.xpr` | `Tx/project/tx.runs/impl_1/adaloop_top.bit` | `Tx/project/tx.ltx` | `Tx/project/tx_with_bit.xsa` |
| Rx | `Rx/project/rx.xpr` | `Rx/project/rx.runs/impl_1/adaloop_top.bit` | `Rx/project/rx.ltx` | `Rx/project/rx_with_bit.xsa` |

保留完整的 `Tx/`、`Rx/` 目录与各自的 `cores/`、`project/` 相对关系。打开工程后可查看已有的 `synth_1`、`impl_1` 结果；本版实现统计与原始报告见[工程验证记录](../results/README.md)。

### 2.2 从源输入另行构建

```bash
python3 build/build.py tx --stage bit --output validation/tx_bit --vivado-root /path/to/Vivado/2021.2
python3 build/build.py rx --stage bit --output validation/rx_bit --vivado-root /path/to/Vivado/2021.2
```

阶段可选 `create`、`synth`、`bit`，分别对应建工程、综合、完整实现与导出。每次选择新目录，脚本拒绝覆盖既有输出。综合使用 `Flow_PerfOptimized_high`，实现使用 `Performance_ExtraTimingOpt`；构建按非增量设置执行，并使用随包 Rx 实现 hook。

| 输出 | 内容 |
|---|---|
| `cores/` | 哈希检查后展开的 EDIF、stub 和功能模型 |
| `project/` | XPR、本地源文件、IP 与运行目录 |
| `console.log`、`vivado.log` | 工具日志 |
| `build_result.json` | 请求阶段执行结果；时序数值见对应报告 |

`project/` 中的 XPR 可在 Vivado GUI 打开；保留其旁边的 `cores/`。构建保留 BD 自动源管理，以综合后置 hook 严格链接 EDIF；实现继续使用完整综合检查点。

## 3. 仿真与 MATLAB

### 3.1 运行功能网表

```bash
python3 sim/run.py codec --output validation/codec --vivado-root /path/to/Vivado/2021.2
python3 sim/run.py rrc --output validation/rrc --vivado-root /path/to/Vivado/2021.2
python3 sim/run.py rx_link --output validation/rx_link --vivado-root /path/to/Vivado/2021.2
```

| 测试 | 输入与判定 |
|---|---|
| `codec` | 九模式随机信息位，每模式六块；编码逐字匹配 MATLAB，译码恢复原始信息位并核对标签/计数。软输入为理想 LLR ±63 |
| `rrc` | 三档插值整数卷积；核对 252 个 12 路输出及零尾部。`din_v=0` 表示继续滤波零输入 |
| `rx_link` | 16 个连续 P2/BPSK 帧；核对帧/块/起点、P 标签、位宽、LDPC 前后真实比特、控制错误及 AI 事件 |

入口会展开功能模型并调用 `xvhdl/xvlog/xelab/xsim`，记录 `execution.json` 与工具日志。有效数据含 X、长度不符或比特不符均报错。功能仿真不含布线延迟。

随包接收数据集为 RRC span16、4.9152 GSPS、1.2 GHz 实中频、25 dB ADC 输入 SNR、20 kHz 频偏和 7 个 ADC 样点输入延迟。`data/adc_input.mem` 每行包含十二个 16-bit 实样点，最低位样点最早到达；`coded_expected.mem` 和 `decoded_expected.mem` 保存低位先到的编码位和业务真值，`reference.mat` 保存数值帧和条件。

阶段文件 `window.txt`、`fde.txt`、`nlms.txt` 中的 P 标签随数据对齐。`events.txt` 的 `FRAME` 行记录同步时刻与当时的监视寄存器 P；该寄存器未与同步事件对齐，因此逐帧处理参数按阶段文件核对。

### 3.2 数值复核

在 MATLAB 工程根目录执行：

```matlab
addpath('matlab');
report = verify_link(fullfile(pwd,'validation','rx_link'));
```

入口计算逐帧 FDE/NLMS MER，并从实际 FFT 输入独立计算浮点 Mov_ZF。F13/F14 与固定增益口径见[工程说明](engineering.md)。

随包已记录输出可只读重算：

```matlab
addpath('matlab');
report = verify_link(fullfile(pwd,'results','rx_link'),true,false);
```

最后一个 `false` 关闭结果写回。命令行形式为：

```bash
matlab -singleCompThread -batch "addpath('matlab'); verify_link(fullfile(pwd,'results','rx_link'),false,false);"
```

对自己已有的仿真输出可执行 `python3 sim/run.py rx_link --output validation/rx_link --check-only`。历史记录中完整接收网表回归约 2 小时、九模式编解码约 20 分钟，耗时随机器与工具环境变化。

### 3.3 改变信道条件

```matlab
make_adc_input('new_adc.mem',25,20000,7,7312);
```

参数依次为输出名、SNR、频偏、ADC 样点延迟与随机种子。随后运行：

```bash
python3 sim/run.py rx_link --adc-file new_adc.mem --output validation/rx_link_new --vivado-root /path/to/Vivado/2021.2
```

该入口保留原有 16 帧业务真值，仅改变信道波形，不能直接换任意业务内容后沿用旧真值。改变延迟或抽样相位后的结果需实际检查，新结果存入独立目录。

## 4. Vitis 工作区与 PS 软件

### 4.1 原生工作区

总目录 `../vitis_workspace/` 为 `SubmissionProjects/vitis_new` 的原样副本。使用 Vitis 2021.2 选择该目录作为工作区，按其中的平台与应用配置查看工程。

本轮核对范围为与来源的逐文件复制一致性；跨目录构建、平台重生成和板卡执行状态按实际验证记录确认。工作区中的平台、硬件引用与启动配置以其自身内容为准。需要重新建立与本版 Tx/Rx 匹配的应用时，使用下一节的源码与 XSA 入口。

### 4.2 从源码建立新工作区

随包提供匹配两端工程的 XSA，可直接建立新 Vitis 工作区：

```bash
xsct -nodisp software/board/build_app.tcl tx software/board/hardware/tx_hardware.xsa validation/vitis_tx
xsct -nodisp software/board/build_app.tcl rx software/board/hardware/rx_hardware.xsa validation/vitis_rx
```

这些 XSA 为对应实现的原生导出，内含匹配的 bit。自行重新生成硬件后，改用本次构建导出的 XSA：

```bash
xsct -nodisp software/board/build_app.tcl tx validation/tx_bit/project/tx_with_bit.xsa validation/vitis_tx
xsct -nodisp software/board/build_app.tcl rx validation/rx_bit/project/rx_with_bit.xsa validation/vitis_rx
```

脚本使用 A53 standalone 64-bit、libmetal 与角色对应的 `RFDC_PROFILE`，ELF 输出到各工作空间 `artifacts/`。保留 `main.c` 旁的 `devices/`、`rfsoc/` 和链接脚本。随后使用 Vitis GUI 打开生成的工作空间；手动建平台、导入源码及编译设置见 [PS 软件说明](../software/board/README.md)。这个入口构建应用，不连接或下载板卡。

## 5. 板卡接入与启动

### 5.1 板卡与 RF 路径

本工程对应搭载 ZU47DR 的 RFSOM 核心板与 REFEVM 开发平台。具体 PCB 版本和原理图未随包提供，实际接入按板卡资料核对；以下是包内软件/RTL 的原板约定。

| 路径 | 发送端 | 接收端 |
|---|---|---|
| 主业务，Tx → Rx | Tx4/JA5，DAC tile 2 block 0 | Rx0/JA9，ADC tile 0 block 0 |
| 反馈，Rx → Tx | Tx6/JA7，DAC tile 3 block 0 | Rx2/JA11，ADC tile 1 block 0 |

模拟输入功率、线缆损耗、衰减器和板上标号以实际硬件资料为准；包内未提供对应原理图与允许值。

| 项目 | 包内配置与核对项 |
|---|---|
| RFDC | 4.9152 GSPS；主 ADC/DAC 为 12 实样点/409.6 MHz |
| LMK | `main.c` 的 `sample_rate=409600000` 选择 409.6 MHz 参考输出表；`spi_ctrl.c` 将此表注释为 19.2 MHz 参考输入，实际参考源位置按板卡确认 |
| 反馈 RFDC | 40.96 MHz 接口，Tx 插值 20、Rx 抽取 10；默认 DAC NCO +1200 MHz、ADC NCO −1200 MHz |
| SYSREF/PL 时钟 | 顶层保留差分 `pl_clk`、`pl_sysref` 与采样连接；初始化保留 LMK 同步/SYSREF 设置 |
| 锁定检查 | 始终检查 PLL2；默认 `require_pll1_lock=0`，实际参考链仍须核对 |

配置依据为两端 `main.c`、`rfsoc/rfsoc_cfg.h`、`system.bd` 与 XDC。迁移板卡需同时核对这些配置。

### 5.2 下载与初始化

两端 BD 配置 UART0 为 MIO 42～43、115200 baud，同时启用 UART1/EMIO。`platform_config.h` 选择 PSU UART 设备 0；在本次 BSP 中确认 `stdin/stdout` 绑定后，打开实际主机串口。串口硬件位置与帧格式以 BSP/板卡配置为准。

1. 选择成套的 Tx/Rx bit、LTX、XSA 与 PS 应用，核对对应实现报告；自行重新构建时使用同次输出。
2. 在 Hardware Manager 选择 `Tx/project/tx.runs/impl_1/adaloop_top.bit`、`Tx/project/tx.ltx`，或 Rx 对应路径，连接实际目标并下载。
3. 两端 `vio_rst_n=0`，Tx 自动反馈为 0，设置合法手动 P/M。
4. 在 Vitis 的 `psu_cortexa53_0` standalone 硬件运行/调试配置中执行匹配 XSA 的 PS 初始化，再运行对应 ELF。应用源码不主动调用 `psu_init()`，PS DDR/UART 等初始化由该平台流程完成。
5. 查看串口：程序依次停止 PL、配置 GPIO/SPI/LMK、校准 AUX DAC、检查锁定、启动/回读 RFDC、检查 PL 时钟，成功后写 `mode=1`、`config_done=1`、`start=1`。末尾应出现角色对应的 `Running: main Tx4...` 或 `Running: main Rx0...`，以及 `All enabled ADC0/ADC1/DAC2/DAC3 channels configured and checked.`。`ERROR: startup failed at ...; PL stays stopped.` 指明失败阶段。
6. PS 初始化成功后先释放 Rx、再释放 Tx。应用返回后 PL 按启动寄存器与 VIO 继续运行；重新下载 bit 或复位 PS 后重新执行匹配初始化。

以上步骤依据随包源码、硬件配置与构建流程整理；本次交付验证覆盖离线构建和仿真，板卡执行状态见对应测试记录。

### 5.3 常用 VIO

| 端 | VIO/probe | 用途 |
|---|---|---|
| Tx | `u_vio_tx_control.out0` | `vio_rst_n`，0 清状态、1 持续运行 |
| Tx | `u_vio_tx_control.out1/out2` | P=2/4/8；M=0/1/2 |
| Tx | `u_vio_tx_auto.out0` | 0 人工目标、1 反馈控制 |
| Tx | `vio_gain.out0/out1/out2` | 增益、上变频步进、Q 反向控制 |
| Rx | `u_vio_rx_control.out0` | `vio_rst_n` |
| Rx | `u_vio_rx_control.out1` | BER 统计使能；0 清零/关闭 |
| Rx | `u_vio_rx_control.out2` | Mov_ZF 窗长 1/3/5/11/21，默认 5 |
| Rx | `u_vio_rx_control.in0/in1` | 当前识别 P/M |
| Rx | `u_vio_rx_control.in2/in3/in4` | 统计比特数、错误计数、计数窗口状态 |

先人工选择 P/M，释放 Rx 后释放 Tx，再检查识别模式与星座。无以太网业务、Tx 填零时可打开现有 BER 统计；它以全零业务为参考，真实视频等业务不采用该参考逐位计算 BER。其他调试核名称以本次 LTX 为准。

## 6. MATLAB 上位机

进入 `software/matlab/monitor` 运行 `jiemian`，保留同目录 `.m` 类、辅助函数与 `.fig`。接收协议为 264 字节 UDP，默认板端 `192.168.2.77:8001`，主机网卡置于匹配子网，界面可设置连接参数。MATLAB 需要 `udpport` 支持与用于 MER 显示的 Communications Toolbox。

上位机是被动接收程序；独立显示类 API 见该目录的 `README_GUI.md`。离线比特核对采用仿真中的真实 Tx 真值。
