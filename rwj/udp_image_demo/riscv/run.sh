#!/bin/bash
# ===========================================================================
#  RISC-V 程序 一键 编译 + 上板运行
#
#  用法：
#      ./run.sh p1test                 编译 projects/p1test 并上板运行
#      ./run.sh p1test --build-only    只编译，不上板
#      ./run.sh p1test --no-uart       上板运行但不监听串口
#      UART=/dev/ttyUSB0 ./run.sh ...  指定串口（默认 ttyUSB2）
#
#  目录约定：
#      projects/<名字>/    源码，唯一真本，可版本控制
#      tools/              openocd 配置 + cpu0.yaml
#
#  为什么要有这个脚本：
#   厂商 BSP 的 makefile 依赖完整目录树（software/standalone/common/*.mk、
#   bsp/efinix/EfxSapphireSoc/...），所以编译必须在那个树里做。
#   脚本负责把 projects/ 里的源码同步进去，/tmp 被清掉也能自动重建。
# ===========================================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS="$ROOT/tools"
BUILD="/tmp/riscv_sw/soc"

# 厂商参考工程（BSP / 链接脚本 / 公共 makefile 的来源）
VENDOR="${VENDOR:-/media/rwj/ZX1 2TB/FPGA2026/demo/08_ti60f225_soc_demo/09_Ti60F225_co_debug_demo/par/ddr_demo_ti60/embedded_sw/soc}"

# 工具链环境
RISCV_ENV="${RISCV_ENV:-/mnt/data300/envs/riscv-gcc/activate}"
OCD="${OCD:-/home/rwj/Efinity/efinity/2026.1/debugger/openocd/bin/openocd}"

UART="${UART:-/dev/ttyUSB2}"
BAUD=115200

PROJ_NAME="${1:-}"
BUILD_ONLY=0
NO_UART=0
for a in "$@"; do
    case "$a" in
        --build-only) BUILD_ONLY=1 ;;
        --no-uart)    NO_UART=1 ;;
    esac
done

say()  { echo; echo "########## $* ##########"; }
die()  { echo "!! $*" >&2; exit 1; }

[ -n "$PROJ_NAME" ] || die "用法: $0 <工程名> [--build-only] [--no-uart]
可用工程：$(ls "$ROOT/projects" 2>/dev/null | tr '\n' ' ')"

PROJ_SRC="$ROOT/projects/$PROJ_NAME"
[ -d "$PROJ_SRC" ] || die "找不到工程：$PROJ_SRC"

# ---------------------------------------------------------------------------
say "1. 激活 RISC-V 工具链"
# ---------------------------------------------------------------------------
[ -f "$RISCV_ENV" ] || die "找不到环境脚本：$RISCV_ENV"
# shellcheck disable=SC1090
source "$RISCV_ENV" || die "激活失败"

# ---------------------------------------------------------------------------
say "2. 准备编译树"
# ---------------------------------------------------------------------------
if [ ! -d "$BUILD/software/standalone/common" ] || [ ! -d "$BUILD/bsp" ]; then
    echo "  /tmp 里没有编译树（或被清掉了），从厂商工程重建..."
    [ -d "$VENDOR" ] || die "找不到厂商工程：$VENDOR"
    mkdir -p "$BUILD" || die "建目录失败"
    cp -r "$VENDOR/software" "$BUILD/" || die "拷 software 失败"
    cp -r "$VENDOR/bsp"      "$BUILD/" || die "拷 bsp 失败"
    echo "  ✓ 重建完成：$BUILD"
else
    echo "  ✓ 编译树已存在：$BUILD"
fi

# 用户工程统一放 software/standalone/user/<名字>
# （makefile 里 STANDALONE=../.. 正好指到 software/standalone）
PROJ_BUILD="$BUILD/software/standalone/user/$PROJ_NAME"
mkdir -p "$(dirname "$PROJ_BUILD")"
rm -rf "$PROJ_BUILD"
cp -r "$PROJ_SRC" "$PROJ_BUILD" || die "同步源码失败"
rm -rf "$PROJ_BUILD/build"
echo "  ✓ 源码已同步：$PROJ_SRC  ->  $PROJ_BUILD"

# ---------------------------------------------------------------------------
say "3. 编译"
# ---------------------------------------------------------------------------
cd "$PROJ_BUILD" || die "进不去编译目录"
make BSP=efinix/EfxSapphireSoc 2>&1 | tail -12
ELF="$PROJ_BUILD/build/$PROJ_NAME.elf"
[ -f "$ELF" ] || die "编译失败，没生成 $ELF"
echo
echo "  ✓ ELF：$ELF  ($(stat -c%s "$ELF") 字节)"

if [ "$BUILD_ONLY" = "1" ]; then
    say "只编译，结束"
    exit 0
fi

# ---------------------------------------------------------------------------
say "4. 上板运行"
# ---------------------------------------------------------------------------
CAT_PID=""
cleanup() {
    [ -n "$CAT_PID" ] && kill "$CAT_PID" 2>/dev/null
    rm -f /tmp/run_uart.log
}
trap cleanup EXIT

if [ "$NO_UART" = "0" ]; then
    [ -e "$UART" ] || die "串口不存在：$UART（用 UART=/dev/ttyUSBx 指定）"
    stty -F "$UART" $BAUD raw -echo 2>/dev/null
    cat "$UART" > /tmp/run_uart.log 2>/dev/null &
    CAT_PID=$!
    sleep 1
    echo "  串口 $UART 已在监听 @ $BAUD"
fi

# 关键流程，顺序不能变：
#   reset halt  —— CPU 复位向量是 0xf9000000 的 bootloader，必须抢在它执行前接管，
#                  否则它会用空 SPI flash 的 0xFF 覆盖 0x1000，把我们的程序冲掉
#   load_image  —— 应用固定加载到 0x1000（链接脚本 ORIGIN=0x1000）
#   reg pc      —— 设好入口
#   resume      —— 放行
cd "$TOOLS" || die "进不去 tools 目录"
"$OCD" -f "$TOOLS/openocd_ti60.cfg" \
    -c "init" \
    -c "reset halt" \
    -c "load_image $ELF" \
    -c "reg pc 0x1000" \
    -c "resume" > /tmp/run_ocd.log 2>&1 &
OCD_PID=$!
sleep 3

if ! grep -q "Target successfully examined" /tmp/run_ocd.log 2>/dev/null; then
    echo "  !! openocd 没连上 CPU，日志："
    grep -E "Error|error" /tmp/run_ocd.log | head -5
    kill $OCD_PID 2>/dev/null
    exit 1
fi
echo "  ✓ CPU 已接管，程序在跑"

if [ "$NO_UART" = "0" ]; then
    sleep 3
    echo
    echo "---------- $UART 输出 ----------"
    if [ -s /tmp/run_uart.log ]; then
        # 去掉 \r 但保留 UTF-8（用 cat -v 会把中文转义成 M-xx 乱码）
        sed 's/\r//g' /tmp/run_uart.log
    else
        echo "（无输出）"
    fi
    echo "-------------------------------"
fi

kill $OCD_PID 2>/dev/null
