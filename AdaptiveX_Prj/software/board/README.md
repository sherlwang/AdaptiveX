# Board initialization software

This directory contains the board-initialization C sources and matching hardware handoffs for the delivered Tx and Rx builds. Use **Vitis 2021.2**. The source files are shared by both roles; the build selects the appropriate RFDC profile.

The submission root also contains `vitis_workspace/`, copied byte for byte from `SubmissionProjects/vitis_new`. Open that directory as a workspace to inspect its original platform and application projects. This delivery check establishes copy consistency; it does not establish a new cross-directory build. The source-and-XSA recipe below is a separate entry point that was built successfully in new workspaces.

| Role | Hardware handoff | Application | Compile-time profile |
|---|---|---|---|
| Tx | `hardware/tx_hardware.xsa` | `rf_tx_init` | `RFDC_PROFILE=0` |
| Rx | `hardware/rx_hardware.xsa` | `rf_rx_init` | `RFDC_PROFILE=1` |

The XSA files are unchanged exports of the corresponding public hardware builds and include their matching bitstreams. Use the corresponding XSA when recreating a platform or configuring a launch.

## 1. Create and build a clean workspace

Open a terminal with the Vitis 2021.2 tools available. Run the following commands from this directory, replacing the final argument with a **new, empty workspace path**:

```text
xsct -nodisp build_app.tcl tx hardware/tx_hardware.xsa /your/new/tx_workspace
xsct -nodisp build_app.tcl rx hardware/rx_hardware.xsa /your/new/rx_workspace
```

On Windows, use your Vitis 2021.2 command prompt and Windows workspace paths. The script copies the supplied sources, creates an A53 standalone platform and application, generates the BSP, and builds the application. It does not connect to a board or program a device.

A successful build produces:

```text
<workspace>/artifacts/tx_init.elf          # Tx
<workspace>/artifacts/rx_init.elf          # Rx
<workspace>/artifacts/build_result.txt
```

Open Vitis 2021.2 using the generated workspace. The platform, application and system projects are then available in the GUI. Build the initialization application; this package does not define an SD-card boot flow. Create any board-specific JTAG launch configuration locally, using the corresponding generated platform and ELF.

This `software/board` directory is the source-and-hardware entry point. The original saved workspace is available separately at the submission root as `vitis_workspace/`.

## 2. Create the same projects in the GUI

If creating projects manually, use these settings:

1. Create a platform project from the role's XSA: processor `psu_cortexa53_0`, operating system `standalone`, architecture `64-bit`. Boot components are not needed for this initialization application.
2. In the standalone BSP, enable `libmetal`, then regenerate the BSP and build the platform.
3. Create an `Empty Application(C)` on that platform. Import the contents of `tx/` or `rx/` into the application's `src/` directory, including `lscript.ld` and the `devices/` and `rfsoc/` subdirectories.
4. Add the following application build settings. Build the application and confirm that its ELF is produced.

| Setting | Value |
|---|---|
| Include paths | Application `src`, `src/devices`, `src/rfsoc` |
| Compiler definitions | `__BAREMETAL__`, plus `RFDC_PROFILE=0` for Tx or `RFDC_PROFILE=1` for Rx |
| Optimization | `None (-O0)` |
| Linker libraries | `m`, `metal` |
| Linker script | Application `src/lscript.ld` |

The automated recipe above records the same settings and was verified by creating and building the applications in new workspaces.

## 3. Validation boundary

Both roles were recreated and compiled in new directories with Vitis 2021.2 using the supplied sources and the supplied XSA. The application ELF was checked after the build. This verifies software compilation and hardware-handoff compatibility; no board was connected or programmed during this packaging check.
