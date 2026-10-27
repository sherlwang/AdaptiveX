# 第三方文件索引

本索引对应随包文件中的原始版权与许可头。下表中 `{tx,rx}` 表示两端对应目录。

| 随包文件 | 原文与引用位置 |
|---|---|
| `src/{tx,rx}/sources_1/board/up_axi.v` | ADI 2014–2017；头部给出 GPL version 2 或 ADI-specific BSD 两条路径，并引用 [LICENSE_GPL2](LICENSES/LICENSE_GPL2) 与 [LICENSE_ADIBSD](LICENSES/LICENSE_ADIBSD) |
| `src/{tx,rx}/sources_1/board/ad_iobuf.v` | ADI 2011；完整条件直接保留在文件头，包括 source/binary notice、名称、专利和 ADI 连接条件 |
| `software/board/{tx,rx}/devices/parameters.h`、`platform_drivers.c`、`platform_drivers.h` | ADI 2017；完整原始条件保留在各文件头 |
| `software/board/{tx,rx}/main.c`、`devices/platform.c`、`devices/platform.h` | Xilinx 许可全文保留在各文件头；`platform.c` 另含 Xilinx 设备/互连使用条件 |
| `software/board/{tx,rx}/lscript.ld` | Xilinx 2010–2019 自动生成文件，保留原版权头 |
| `sim/vendor_models/*.vhd` | Xilinx 生成模型，保留其原始 notice 与 disclaimer |
| `software/board/hardware/*.xsa` | 对应工程的 AMD/Xilinx 原生硬件导出，含 PS 配置与本版 bit；工具与生成文件说明沿原档保留 |
| `src/{tx,rx}/sources_1/ip/**/*.xci`、`sources_1/bd/**`、`ip/{tx,rx}/*/core_*` | AMD/Xilinx 配置和生成表示，保留文件中的原始 notice；使用对应工具/IP 条款 |

两份 ADI 许可正文的获取 commit、URL 与 SHA-256 见 [LICENSES/upstream.json](LICENSES/upstream.json)。`ad_iobuf.v` 与 ADI C 文件的原始头部不因 `up_axi.v` 的二选一表述而改变。本索引不选择其中一条许可路径，也不替换原始条款。
