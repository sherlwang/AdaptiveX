# RF_SOM_core_board_REV13.pdf: PDF pages 5, 7, 8.
# RFSOM_EVM_REV12.pdf: PDF pages 4, 11, 13, 18, 25.
# See reports/schematic_pin_map.tsv for the package-to-connector trace.
# Bank88 is powered from VCC_1V8 (core PDF page 5).
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS18} [get_ports lmk_sync]
set_property -dict {PACKAGE_PIN H9 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN B11 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN B10 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN C11 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN E9 IOSTANDARD LVCMOS33} [get_ports {user_io[0]}]
set_property -dict {PACKAGE_PIN E11 IOSTANDARD LVCMOS33} [get_ports {user_io[1]}]
set_property -dict {PACKAGE_PIN D11 IOSTANDARD LVCMOS33} [get_ports {user_io[2]}]
set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS33} [get_ports {user_io[3]}]
set_property -dict {PACKAGE_PIN C9 IOSTANDARD LVCMOS33} [get_ports user_io4]
set_property -dict {PACKAGE_PIN A10 IOSTANDARD LVCMOS33} [get_ports user_io5]
set_property -dict {PACKAGE_PIN A9 IOSTANDARD LVCMOS33} [get_ports user_io6]
set_property -dict {PACKAGE_PIN C10 IOSTANDARD LVCMOS33} [get_ports user_io7]
set_property -dict {PACKAGE_PIN J12 IOSTANDARD LVCMOS33} [get_ports trig_in]
set_property -dict {PACKAGE_PIN K12 IOSTANDARD LVCMOS33} [get_ports trig_out]
set_property -dict {PACKAGE_PIN K11 IOSTANDARD LVCMOS33} [get_ports gps_1pps]
set_property -dict {PACKAGE_PIN H10 IOSTANDARD LVCMOS33} [get_ports txd_gps]
set_property -dict {PACKAGE_PIN E12 IOSTANDARD LVDS_25} [get_ports pl_clk_p]
set_property -dict {PACKAGE_PIN D12 IOSTANDARD LVDS_25} [get_ports pl_clk_n]
set_property -dict {PACKAGE_PIN E14 IOSTANDARD LVDS_25} [get_ports pl_sysref_p]
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVDS_25} [get_ports pl_sysref_n]
# HDIO LVDS_25 has no programmable differential termination. Leave DIFF_TERM
# and DIFF_TERM_ADV unset; the board provides the 100-ohm external resistors.

# Dedicated converter clocks and RF SYSREF. The RFDC primitive LOCs also fix
# these pads; PACKAGE_PIN makes the board mapping explicit. These dedicated
# RF pins do not use a fabric LVCMOS/LVDS IOSTANDARD constraint.
set_property PACKAGE_PIN AB5 [get_ports adc1_clk_p]
set_property PACKAGE_PIN AB4 [get_ports adc1_clk_n]
set_property PACKAGE_PIN J5  [get_ports dac2_clk_p]
set_property PACKAGE_PIN J4  [get_ports dac2_clk_n]
set_property PACKAGE_PIN N5  [get_ports sysref_in_p]
set_property PACKAGE_PIN N4  [get_ports sysref_in_n]

# ADC Tile224: communication receive channels Rx0/JA9 and Rx1/JA10.
set_property PACKAGE_PIN AK2 [get_ports vin0_01_p]
set_property PACKAGE_PIN AK1 [get_ports vin0_01_n]
set_property PACKAGE_PIN AH2 [get_ports vin0_23_p]
set_property PACKAGE_PIN AH1 [get_ports vin0_23_n]
# ADC Tile225: feedback Rx2/JA11, with Rx3/JA12 reserved.
set_property PACKAGE_PIN AF2 [get_ports vin1_01_p]
set_property PACKAGE_PIN AF1 [get_ports vin1_01_n]
set_property PACKAGE_PIN AD2 [get_ports vin1_23_p]
set_property PACKAGE_PIN AD1 [get_ports vin1_23_n]

# DAC Tile230: communication transmit channels Tx4/JA5 and Tx5/JA6.
set_property PACKAGE_PIN E2 [get_ports vout20_p]
set_property PACKAGE_PIN E1 [get_ports vout20_n]
set_property PACKAGE_PIN C2 [get_ports vout22_p]
set_property PACKAGE_PIN C1 [get_ports vout22_n]
# DAC Tile231: feedback uses DAC0/DUC0 Tx6/JA7; Tx7/JA8 sends zero.
set_property PACKAGE_PIN B4 [get_ports vout30_p]
set_property PACKAGE_PIN A4 [get_ports vout30_n]
set_property PACKAGE_PIN B6 [get_ports vout32_p]
set_property PACKAGE_PIN A6 [get_ports vout32_n]

# PL_CLK and PL_SYSREF have on-board 100-ohm terminations (RS1/RS3). HDIO
# LVDS_25 input-only receivers allow non-nominal VCCO without internal
# termination: AMD DS926, LVDS DC Specifications (LVDS_25), footnote 1.
# The external pl_clk/SYSREF frequency and timing have not been established;
# this file deliberately does not invent create_clock or input-delay values.

# Existing main-link 10GE GT pins retained from Tx.
set_property PACKAGE_PIN P33 [get_ports gt_rxp_in_0]
set_property PACKAGE_PIN K28 [get_ports gt_refclk_p]
set_property PACKAGE_PIN M33 [get_ports gt_rxp_in_1]
