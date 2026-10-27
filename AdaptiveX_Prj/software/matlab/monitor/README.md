# 1. RX264 monitor

Run `jiemian` from this directory in MATLAB. Keep the `.m` classes and helpers together when copying the monitor.

The receiver expects the current 264-byte UDP layout. Default board address: `192.168.2.77`; UDP port: `8001`. Set the host network adapter to the matching subnet. The UI exposes the connection settings.

MATLAB requires `udpport` support and Communications Toolbox for the MER display. This program is a passive receiver. It does not configure the FPGA, change RFDC clocks, or prove hardware BER by itself.
