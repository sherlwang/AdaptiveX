# ILA/debug hub uses the PS fclk_100m reported in the imported block design.
# Explicit ILA probe widths/depths are owned by their local XCI configurations.
set_property C_CLK_INPUT_FREQ_HZ 99999001 [get_debug_cores -quiet dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores -quiet dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores -quiet dbg_hub]
connect_debug_port dbg_hub/clk [get_nets -quiet fclk_100m]
