#!/usr/bin/env bash

# jzy/riscv_game 唯一自动回归入口。
#
#   ./scripts/regress.sh quick
#   ./scripts/regress.sh contract
#   ./scripts/regress.sh full

set -u
set -o pipefail

usage()
{
    cat <<'EOF'
Usage: scripts/regress.sh {quick|contract|full}

Modes:
  quick     host tests + mutation tests + make check + two RISC-V builds
  contract  quick + authoritative BitBlt/framebuffer compile-time contract
  full      contract + registered M1/M2 FPGA board regressions

Important environment overrides:
  RISCV_GAME_ROOT       Project root (default: parent of this script)
  BITBLT_INC_DIR        Authoritative bitblt_regs.h/bitblt_api.h/layout directory
  CROSS_CC              RISC-V gcc used by Makefile checks
  HOST_CC               Host C compiler (default: gcc)
  LOG_ROOT              Log parent (default: <project>/logs/regression)

  EFINITY_ROOT          Efinity root containing pgm/ and debugger/ (2026.1)
  RISCV_IDE_ROOT        Efinity RISC-V IDE root containing toolchain/
  BITSTREAM             FPGA .bit file
  M1_BOARD_PROJECT      rendererM1Demo project directory
  M1_ELF                M1 board-test ELF
  M2_BOARD_PROJECT      rendererM2Demo project directory
  M2_ELF                M2 board-test ELF
  SOC_ROOT              Generated Sapphire SoC directory containing cpu0.yaml
  OPENOCD_CFG_DIR       Directory containing ftdi_ti.cfg and debug_ti.cfg
  UART_DEVICE           Board UART device
  PROGRAMMER            ftdi_pgm.sh path
  OPENOCD               OpenOCD executable
  GDB                   riscv-none-elf-gdb executable
  FTDI_URL              Optional ftdi:// URL passed to ftdi_pgm.sh -u
  GDB_PORT              OpenOCD GDB port (default: 3333)
  BOARD_TIMEOUT_SECONDS UART marker timeout (default: 30)
EOF
}

MODE=${1:-quick}
case "$MODE" in
    quick|contract|full) ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RISCV_GAME_ROOT=${RISCV_GAME_ROOT:-$(cd -- "$SCRIPT_DIR/.." && pwd)}
BITBLT_INC_DIR=${BITBLT_INC_DIR:-$RISCV_GAME_ROOT/../../04_project/bitblt_accel/sw/driver}
HOST_CC=${HOST_CC:-gcc}

EFINITY_ROOT=${EFINITY_ROOT:-$HOME/efinity/2026.1}
RISCV_IDE_ROOT=${RISCV_IDE_ROOT:-$HOME/efinity/efinity-riscv-ide-2026.1}
CROSS_CC=${CROSS_CC:-$RISCV_IDE_ROOT/toolchain/bin/riscv-none-elf-gcc}

SOC_ROOT=${SOC_ROOT:-$RISCV_GAME_ROOT/../co_debug_2026/par/ddr_demo_ti60_2026/embedded_sw/soc}
# M2 must never use the original DDR-demo bitstream: it leaves SYSTEM_AXI_A
# without the BitBlt responder, so the CPU stalls on the first STATUS read and
# no CLINT-based software timeout can run.  Point at B's overlay output by
# default; BITSTREAM remains available for relocated/generated artifacts.
BITSTREAM=${BITSTREAM:-$RISCV_GAME_ROOT/../../04_project/bitblt_accel/hw/efinity/overlay/par/ddr_demo_ti60/outflow/ddr_demo_ti60.bit}
M1_BOARD_PROJECT=${M1_BOARD_PROJECT:-$SOC_ROOT/software/standalone/renderer/rendererM1Demo}
M1_ELF=${M1_ELF:-$M1_BOARD_PROJECT/build/rendererM1Demo.elf}
M2_BOARD_PROJECT=${M2_BOARD_PROJECT:-$SOC_ROOT/software/standalone/renderer/rendererM2Demo}
M2_ELF=${M2_ELF:-$M2_BOARD_PROJECT/build/rendererM2Demo.elf}
UART_DEVICE=${UART_DEVICE:-/dev/serial/by-id/usb-FTDI_Quad_RS232-HS-if02-port0}
OPENOCD_CFG_DIR=${OPENOCD_CFG_DIR:-$SOC_ROOT/bsp/efinix/EfxSapphireSoc/openocd}
PROGRAMMER=${PROGRAMMER:-$EFINITY_ROOT/pgm/bin/ftdi_pgm.sh}
OPENOCD=${OPENOCD:-$EFINITY_ROOT/debugger/openocd/bin/openocd}
GDB=${GDB:-$RISCV_IDE_ROOT/toolchain/bin/riscv-none-elf-gdb}
FTDI_URL=${FTDI_URL:-}
GDB_PORT=${GDB_PORT:-3333}
BOARD_TIMEOUT_SECONDS=${BOARD_TIMEOUT_SECONDS:-30}
OPENOCD_START_TIMEOUT_SECONDS=${OPENOCD_START_TIMEOUT_SECONDS:-15}
BSP=${BSP:-efinix/EfxSapphireSoc}

LOG_ROOT=${LOG_ROOT:-$RISCV_GAME_ROOT/logs/regression}
timestamp=$(date '+%Y%m%d_%H%M%S')
LOG_DIR=$LOG_ROOT/$timestamp
if [[ -e "$LOG_DIR" ]]; then
    LOG_DIR=${LOG_DIR}_$$
fi
mkdir -p -- "$LOG_DIR" || exit 1
SUMMARY_LOG=$LOG_DIR/summary.log

if [[ -n ${NO_COLOR:-} ]]; then
    RED='' GREEN='' YELLOW='' RESET=''
else
    RED=$'\033[31m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    RESET=$'\033[0m'
fi

declare -a STEP_NAMES=()
declare -a STEP_RESULTS=()
declare -a STEP_LOGS=()
FAILURES=0
OPENOCD_PID=''
GDB_PID=''
UART_PID=''

stop_process()
{
    local pid=${1:-}
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
}

cleanup()
{
    stop_process "$GDB_PID"
    stop_process "$UART_PID"
    stop_process "$OPENOCD_PID"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

record_result()
{
    local name=$1
    local result=$2
    local logfile=$3

    STEP_NAMES+=("$name")
    STEP_RESULTS+=("$result")
    STEP_LOGS+=("$logfile")

    case "$result" in
        PASS) printf '%s[PASS]%s %s\n' "$GREEN" "$RESET" "$name" ;;
        FAIL)
            printf '%s[FAIL]%s %s (log: %s)\n' "$RED" "$RESET" "$name" "$logfile" >&2
            FAILURES=$((FAILURES + 1))
            ;;
        SKIP) printf '%s[SKIP]%s %s\n' "$YELLOW" "$RESET" "$name" ;;
    esac
}

run_step()
{
    local name=$1
    local filename=$2
    shift 2
    local logfile=$LOG_DIR/$filename
    local rc

    printf '\n== %s ==\n' "$name"
    "$@" 2>&1 | tee "$logfile"
    rc=${PIPESTATUS[0]}
    if (( rc == 0 )); then
        record_result "$name" PASS "$logfile"
        return 0
    fi

    printf 'exit_code=%d\n' "$rc" >>"$logfile"
    record_result "$name" FAIL "$logfile"
    return "$rc"
}

run_quick()
{
    run_step "host tests" 01_host_tests.log \
        env "ASAN_OPTIONS=${ASAN_OPTIONS:+$ASAN_OPTIONS:}detect_leaks=0" \
        make -C "$RISCV_GAME_ROOT" test CC="$HOST_CC" BITBLT_INC_DIR="$BITBLT_INC_DIR" || true
    run_step "mutation tests" 02_mutation_tests.log \
        make -C "$RISCV_GAME_ROOT" mutation-test CC="$HOST_CC" || true
    run_step "static checks" 03_make_check.log \
        make -C "$RISCV_GAME_ROOT" check BITBLT_INC_DIR="$BITBLT_INC_DIR" || true
    run_step "RISC-V cross build" 04_riscv_build.log \
        make -C "$RISCV_GAME_ROOT" riscv-build CROSS_CC="$CROSS_CC" \
            BITBLT_INC_DIR="$BITBLT_INC_DIR" || true
    run_step "RISC-V hardware-path build" 05_riscv_build_hw.log \
        make -C "$RISCV_GAME_ROOT" riscv-build-hw CROSS_CC="$CROSS_CC" \
            BITBLT_INC_DIR="$BITBLT_INC_DIR" || true
}

run_contract()
{
    run_step "BitBlt/display API contract" 00_contract.log \
        make -C "$RISCV_GAME_ROOT" contract-test CROSS_CC="$CROSS_CC" \
            BITBLT_INC_DIR="$BITBLT_INC_DIR" || true
}

port_ready()
{
    (exec 9<>"/dev/tcp/127.0.0.1/$GDB_PORT") >/dev/null 2>&1
}

board_preflight()
{
    local failed=0
    local file

    echo "bitstream: $BITSTREAM"
    echo "M1 ELF: $M1_ELF"
    echo "M2 ELF: $M2_ELF"
    echo "UART: $UART_DEVICE"
    echo "programmer: $PROGRAMMER"
    echo "OpenOCD: $OPENOCD"
    echo "GDB: $GDB"
    echo "OpenOCD configs: $OPENOCD_CFG_DIR"

    for file in "$BITSTREAM" "$M1_ELF" "$M2_ELF" \
                "$OPENOCD_CFG_DIR/ftdi_ti.cfg" "$OPENOCD_CFG_DIR/debug_ti.cfg" \
                "$SOC_ROOT/cpu0.yaml"; do
        if [[ ! -f "$file" ]]; then
            echo "missing required file: $file" >&2
            failed=1
        fi
    done

    for file in "$PROGRAMMER" "$OPENOCD" "$GDB"; do
        if [[ ! -x "$file" ]]; then
            echo "missing executable: $file" >&2
            failed=1
        fi
    done

    if [[ ! -c "$UART_DEVICE" ]]; then
        echo "UART is not a character device: $UART_DEVICE" >&2
        failed=1
    fi

    if port_ready; then
        echo "GDB port $GDB_PORT is already in use; refusing to attach to an unknown server" >&2
        failed=1
    fi

    if (( failed != 0 )); then
        if [[ ! -f "$BITSTREAM" ]]; then
            echo "M2 requires the BitBlt overlay bitstream; the base DDR-demo bitstream is not compatible." >&2
            echo "Generate B's overlay output or set BITSTREAM=/path/to/bitblt-overlay.bit." >&2
        fi
        echo "Set the documented environment overrides for this workstation." >&2
        return 1
    fi
}

program_fpga()
{
    local -a args=(-m jtag)
    if [[ -n "$FTDI_URL" ]]; then
        args+=(-u "$FTDI_URL")
    fi
    args+=("$BITSTREAM")

    # ftdi_pgm.sh relies on variables normally installed by Efinity setup.sh.
    EFINITY_HOME="$EFINITY_ROOT" \
    EFXDBG_HOME="$EFINITY_ROOT/debugger" \
    EFINITY_USER_DIR_INI="${EFINITY_USER_DIR_INI:-$HOME/.local/share/efinity/user_dir.ini}" \
    PYTHONHOME="$EFINITY_ROOT" \
    PYTHONPATH="$EFINITY_ROOT/lib${PYTHONPATH:+:$PYTHONPATH}" \
        "$PROGRAMMER" "${args[@]}"
}

start_openocd()
{
    local logfile=$LOG_DIR/openocd.log
    local deadline
    : >"$logfile"

    (
        # Efinity's debug_ti.cfg starts its cpu0.yaml search at ".." and
        # walks up at most four levels.  Launch from the application project
        # so that the fourth candidate is SOC_ROOT; launching in SOC_ROOT
        # itself skips the cpu0.yaml that is in the current directory.
        cd -- "$M1_BOARD_PROJECT" || exit 1
        exec "$OPENOCD" \
            -c "set bsp_loc {$SOC_ROOT}" \
            -f "$OPENOCD_CFG_DIR/ftdi_ti.cfg" \
            -f "$OPENOCD_CFG_DIR/debug_ti.cfg"
    ) >>"$logfile" 2>&1 &
    OPENOCD_PID=$!

    deadline=$((SECONDS + OPENOCD_START_TIMEOUT_SECONDS))
    while (( SECONDS < deadline )); do
        if port_ready; then
            record_result "OpenOCD startup on port $GDB_PORT" PASS "$logfile"
            return 0
        fi
        if ! kill -0 "$OPENOCD_PID" 2>/dev/null; then
            wait "$OPENOCD_PID" 2>/dev/null || true
            OPENOCD_PID=''
            tail -n 40 "$logfile" >&2
            record_result "OpenOCD startup on port $GDB_PORT" FAIL "$logfile"
            return 1
        fi
        sleep 0.2
    done

    echo "timeout waiting for OpenOCD port $GDB_PORT" >>"$logfile"
    stop_process "$OPENOCD_PID"
    OPENOCD_PID=''
    record_result "OpenOCD startup on port $GDB_PORT" FAIL "$logfile"
    return 1
}

# Generic board-test runner. Adding M2 only needs another call such as:
#   run_board_test "M2" "$M2_ELF" "M2 BITBLT BOARD TEST PASSED"
run_board_test()
{
    local name=$1
    local elf=$2
    local pass_marker=$3
    local safe_name=${name// /_}
    local gdb_log=$LOG_DIR/gdb_${safe_name}.log
    local uart_log=$LOG_DIR/uart_${safe_name}.raw.log
    local deadline
    local reason=''

    : >"$gdb_log"
    : >"$uart_log"

    if [[ ! -f "$elf" ]]; then
        echo "missing ELF: $elf" >>"$gdb_log"
        record_result "$name board test" FAIL "$gdb_log"
        return 1
    fi

    if ! stty -F "$UART_DEVICE" 115200 cs8 -cstopb -parenb \
            -ixon -ixoff raw -echo 2>>"$uart_log"; then
        echo "failed to configure UART: $UART_DEVICE" >>"$uart_log"
        record_result "$name board test" FAIL "$uart_log"
        return 1
    fi

    # cat writes bytes exactly as received; no CR/LF conversion is performed.
    cat "$UART_DEVICE" >"$uart_log" &
    UART_PID=$!
    sleep 0.2
    if ! kill -0 "$UART_PID" 2>/dev/null; then
        wait "$UART_PID" 2>/dev/null || true
        UART_PID=''
        echo "UART capture terminated before GDB started" >>"$uart_log"
        record_result "$name board test" FAIL "$uart_log"
        return 1
    fi

    timeout --signal=TERM "${BOARD_TIMEOUT_SECONDS}s" \
        "$GDB" -batch "$elf" \
        -ex "target extended-remote :$GDB_PORT" \
        -ex "monitor reset halt" \
        -ex "load" \
        -ex 'set $pc = _start' \
        -ex "continue" >"$gdb_log" 2>&1 &
    GDB_PID=$!

    deadline=$((SECONDS + BOARD_TIMEOUT_SECONDS))
    while (( SECONDS < deadline )); do
        if grep -aFq -- "$pass_marker" "$uart_log"; then
            stop_process "$GDB_PID"
            GDB_PID=''
            stop_process "$UART_PID"
            UART_PID=''
            record_result "$name board test" PASS "$uart_log"
            return 0
        fi

        if ! kill -0 "$GDB_PID" 2>/dev/null; then
            wait "$GDB_PID" 2>/dev/null || true
            GDB_PID=''
            reason="GDB exited before UART marker: $pass_marker"
            break
        fi
        if ! kill -0 "$UART_PID" 2>/dev/null; then
            wait "$UART_PID" 2>/dev/null || true
            UART_PID=''
            reason='UART capture exited unexpectedly'
            break
        fi
        sleep 0.2
    done

    if [[ -z "$reason" ]]; then
        reason="timeout waiting for UART marker: $pass_marker"
    fi
    echo "$reason" >>"$gdb_log"
    echo "$reason" >&2
    stop_process "$GDB_PID"
    GDB_PID=''
    stop_process "$UART_PID"
    UART_PID=''
    record_result "$name board test" FAIL "$gdb_log"
    return 1
}

run_full()
{
    # Create the required evidence files even when a prerequisite fails and the
    # hardware phase is deliberately skipped.
    : >"$LOG_DIR/fpga_programmer.log"
    : >"$LOG_DIR/openocd.log"
    : >"$LOG_DIR/gdb_M1.log"
    : >"$LOG_DIR/uart_M1.raw.log"
    : >"$LOG_DIR/gdb_M2.log"
    : >"$LOG_DIR/uart_M2.raw.log"

    if (( FAILURES != 0 )); then
        record_result "FPGA board regression" SKIP "$LOG_DIR/openocd.log"
        return
    fi

    run_step "M1 board ELF build" 07_m1_board_build.log \
        env "PATH=$RISCV_IDE_ROOT/toolchain/bin:$PATH" \
        make -C "$M1_BOARD_PROJECT" BSP="$BSP" \
            RENDER_ROOT="$RISCV_GAME_ROOT" BITBLT_INC_DIR="$BITBLT_INC_DIR" || true
    if (( FAILURES != 0 )); then
        record_result "FPGA board regression" SKIP "$LOG_DIR/openocd.log"
        return
    fi

    run_step "M2 board ELF build" 08_m2_board_build.log \
        env "PATH=$RISCV_IDE_ROOT/toolchain/bin:$PATH" \
        make -C "$M2_BOARD_PROJECT" BSP="$BSP" \
            RENDER_ROOT="$RISCV_GAME_ROOT" BITBLT_INC_DIR="$BITBLT_INC_DIR" || true
    if (( FAILURES != 0 )); then
        record_result "FPGA board regression" SKIP "$LOG_DIR/openocd.log"
        return
    fi

    run_step "board preflight" 09_board_preflight.log board_preflight || true
    if (( FAILURES != 0 )); then
        record_result "FPGA board regression" SKIP "$LOG_DIR/openocd.log"
        return
    fi

    run_step "FPGA programming" fpga_programmer.log program_fpga || true
    if (( FAILURES != 0 )); then
        record_result "OpenOCD and board tests" SKIP "$LOG_DIR/openocd.log"
        return
    fi

    if ! start_openocd; then
        record_result "registered board tests" SKIP "$LOG_DIR/openocd.log"
        return
    fi

    run_board_test "M1" "$M1_ELF" "M1 BOARD TEST PASSED" || true
    run_board_test "M2" "$M2_ELF" "M2 BITBLT BOARD TEST PASSED" || true

    stop_process "$OPENOCD_PID"
    OPENOCD_PID=''
}

write_summary()
{
    local overall=PASS
    local i
    if (( FAILURES != 0 )); then
        overall=FAIL
    fi

    {
        echo "riscv_game regression summary"
        echo "timestamp: $timestamp"
        echo "mode: $MODE"
        echo "project: $RISCV_GAME_ROOT"
        echo "logs: $LOG_DIR"
        echo
        for ((i = 0; i < ${#STEP_NAMES[@]}; i++)); do
            printf '%-5s  %-34s  %s\n' \
                "${STEP_RESULTS[$i]}" "${STEP_NAMES[$i]}" "${STEP_LOGS[$i]}"
        done
        echo
        echo "OVERALL: $overall"
    } >"$SUMMARY_LOG"

    echo
    cat "$SUMMARY_LOG"
    if [[ "$overall" == PASS ]]; then
        printf '%sOVERALL PASS%s\n' "$GREEN" "$RESET"
    else
        printf '%sOVERALL FAIL (%d failed step(s))%s\n' "$RED" "$FAILURES" "$RESET" >&2
    fi
}

echo "Regression mode: $MODE"
echo "Log directory: $LOG_DIR"
if [[ "$MODE" == contract || "$MODE" == full ]]; then
    run_contract
fi
run_quick
if [[ "$MODE" == full ]]; then
    run_full
fi
write_summary

if (( FAILURES != 0 )); then
    exit 1
fi
exit 0
