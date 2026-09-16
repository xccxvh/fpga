#!/usr/bin/env bash
#
# build.sh —— 编译 fpga 工程（UDP 收图 -> DDR3 -> HDMI）
#
# 重要：
#   不要自己设置 EFINITY_HOME！efx_run 只有在 EFINITY_HOME 为空时
#   才会 source setup.sh（里面才有 PYTHONHOME/PYTHONPATH 等必需环境）。
#   也清掉 ROS 污染的 PYTHONPATH。
#
set -e

cd "$(dirname "$0")"

unset PYTHONPATH
unset PYTHONHOME
unset EFINITY_HOME

EFX_BIN=/home/rwj/Efinity/efinity/2026.1/bin

echo "=============================================="
echo "工程     : $(pwd)/ddr3_hdmi_test.xml"
echo "Efinity  : $EFX_BIN"
echo "开始编译（综合 + 布局布线 + bitstream）..."
echo "=============================================="
echo

"$EFX_BIN/efx_run" --prj -f compile ddr3_hdmi_test.xml

echo
echo "=============================================="
echo "编译流程结束。检查 bit 文件："
if [ -f outflow/ddr3_hdmi_test.bit ]; then
    ls -la outflow/ddr3_hdmi_test.bit
    echo "OK：可以烧录了"
else
    echo "未找到 outflow/ddr3_hdmi_test.bit，请检查上面的日志"
    exit 1
fi
echo "=============================================="
