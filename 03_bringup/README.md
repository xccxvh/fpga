# Board Bring-up Status

## 01_led/LED_8bit_Test

- 来源：厂家 `01_Ti60F225_Key_led_osc_demo`
- Efinity 2026.1 完整编译：通过
- JTAG SRAM 下载：通过
- 板上 LED/按键现象：通过

## 06_hdmi_test/hdmi_rx2tx_loop_v19

- 来源：厂家 `02_Ti60F225_hdmi_demo`
- Efinity 2026.1 完整编译：通过
- JTAG SRAM 下载：通过
- 功能状态：排查中，尚未标记为硬件验证通过
- 兼容修改：关闭旧 Debugger 自动实例化；移除未使用的旧 BSCAN 调试接口
- 注意：工程实际输出 `b_led[0:1]` 位于 GPIOR_21/GPIOR_22，厂家手册的 D3/D4 描述与 V4 原理图/工程存在不一致。
