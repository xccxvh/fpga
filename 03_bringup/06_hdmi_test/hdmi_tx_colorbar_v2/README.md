# HDMI TX color-bar demo (1080p60 fix)

This is a working copy of the vendor `03_hdmi_tx_demo/hdmi_tx_demo_v2`
project. Keep the package under `local/vendor_original` unchanged.

## Change

The vendor RTL configured a 1920x1536 active image while using an approximately
148.5 MHz HDMI pixel clock. Many displays reject that non-standard combination.
`rtl/top.v` now uses CTA-861 1920x1080p60 timings:

- active: 1920 x 1080
- horizontal front porch / sync / back porch: 88 / 44 / 148
- vertical front porch / sync / back porch: 4 / 5 / 36
- total: 2200 x 1125

## Build

```bash
source /home/user/efinity/2026.1/bin/setup.sh
efx_run.py led_demo.xml --flow compile
```

For volatile JTAG programming, select `outflow/hdmi_tx.bit`.
