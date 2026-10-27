---
name: sherl-vivado-netlist-delivery
description: 将自有 Verilog 运算模块交付为可链接的 EDIF、接口声明和结构功能模型，并核验 Vivado 工程接入。用于保留原始 RTL 的模块级交付；不是 RTL 加密、授权破解或完整 IP Catalog 自动封装。
---
# 1. 边界

先确定哪些模块以可读 RTL 提供，哪些提供网表，哪些功能不公开。封装本身不授权删减算法或改变协议；项目已确认的功能裁剪不能变成其他项目的默认步骤。

EDIF 和结构功能模型仍可被分析，不承诺不可逆向。网表固化内部点数、位宽、流水、模型权重及 HDL 参数；通过端口提供的 P/M 等运行时控制可以保留。第三方加密 IP 和对应工具许可仍按原要求使用。

本方法在 Vivado 2021.2 的自有 Verilog/推断 RAM/DSP/XPM 模块上提炼。含厂商加密 IP、跨器件迁移、不同工具版本或未公开的外部初始化文件时，先检查适用性。不要通过去掉 LUT/RAM INIT 来“保护”可运行交付。

# 2. 导出

在私有工作目录建临时工程，显式读取模块的有效 RTL、头文件和初始化文件。原工程只读。仅导出该模块，不把源码快照、原 TB、日志或原始 MATLAB 实现复制进公开目录。

```tcl
create_project -in_memory -part <device>
read_verilog <approved_module_and_dependency_files>
# Set include_dirs and stage each required $readmemh file in this working directory.
synth_design -top <module> -mode out_of_context -flatten_hierarchy full
# Add -generic {PARAMETER=value} only for the actual intended configuration.
set bb [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]
if {[llength $bb]} {error "Unresolved module dependencies: $bb"}
write_edif -force core.edf
write_verilog -force -mode synth_stub core_stub.v
write_verilog -force -mode funcsim core_sim.v
report_utilization -file utilization.rpt
```

不要用父级板卡约束代替模块的时钟分析。独立综合资源不能直接当作整机资源，导出成功也不证明时序收敛。

使用 [finalize.py](scripts/finalize.py) 整理交付目录：

```bash
python3 scripts/finalize.py --source /private/export --output /new/payload \
  --top my_core --part xczu47dr-ffve1156-2-i --parameters '{"DYNAMIC_MODE":1}'
```

它只读取四个已导出文件，生成压缩 EDIF、压缩结构模型、stub、资源报告和哈希配置，不收集其他源码。输出目录必须为空。

脚本会为结构模型的本地子模块加唯一前缀。实际遇到过 `xpm_fifo_sync` 等专用网表模块与安装库同名，XSim 错绑定到默认位宽的情况；仅看到模块编译通过不足以发现它。前缀只作用于这些本地模块名，不修改门级计算、INIT、端口或流水；`glbl` 是仿真全局单元，保留其名称。

# 3. 接入工程

只有空 stub 会形成黑盒，只有功能模型不能生成 bit。禁止让自动层级分析把真正 EDIF 静默停用。

原 BD 有 `module_ref` 时保留自动源管理；不要用全局手动编译模式绕过问题。可采用已验证的后置绑定方式：

- stub 加入设计文件集，只用于 synthesis。
- 功能模型加入 simulation 文件集，不用于 synthesis/implementation。
- EDIF 由 [bind_cores.tcl](scripts/bind_cores.tcl) 的 `update_design -strict` 填入对应黑盒；目录名须等于实际模块名。
- 在设置策略和生成 IP 后，最后注册 `STEPS.SYNTH_DESIGN.TCL.POST` 调用该脚本；策略赋值会重置 step hook，注册后核对属性。Vivado 2021.2 在默认 checkpoint/report 写出后才执行此 hook，因此脚本必须再次保存完整 DCP 和资源报告。

该脚本约定：复制到构建目录 `project/bind_cores.tcl`，网表放在同级父目录的 `cores/<side>/<module>/core.edf`。这是交付目录约定；用于其他构建框架时明确调整路径。保留原有其他必要 hook，不覆盖其功能。

只有实际 `open_run` 和实现链接后确认目标模块不再是黑盒，才能报告工程接入完成。换网表后重新构建，不依赖旧增量结果。

# 4. 验证与交付

用同一批输入核对原 RTL、交付结构模型和独立 MATLAB/整数参考。明确有效周期、位序、符号位、Q 格式和模式/帧归属。包含复位和连续输入；修改反馈或跨域接口时补充相应测试。

XSim 例化位宽不一致是模型绑定错误，不能当作普通警告忽略。比特检查还要核对数量与丢帧；涉及均衡等运算时逐帧比较数值和 MER，不能靠重新拟合增益、相位或平移掩盖差异。

在只含公开目录的新位置重建工程，核验 ROM、IP/BD、约束、PS 软件和构建脚本依赖。分别说明导出、功能仿真、综合、实现、时序与板测结果，未执行项留为未执行。

最终公开工程明确哪些是可读源码、哪些是预编译网表及其固定配置。发布范围、许可证和 GitHub 推送由项目负责人决定；创建本 Skill 不安装技能或发布文件。

来源：AdaptiveX 公开工程的实际网表交付与复现验证。依据 [UG835 update_design](https://docs.amd.com/r/2021.2-English/ug835-vivado-tcl-commands/update_design)、[UG900 网表仿真](https://docs.amd.com/r/2021.2-English/ug900-vivado-logic-simulation/Running-Post-Synthesis-and-Post-Implementation-Simulations)。项目实例的具体通过项以随项目保留的验证记录为准。
