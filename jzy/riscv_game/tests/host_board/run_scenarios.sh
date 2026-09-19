#!/usr/bin/env bash
#
# 板端 smoke 的 host 场景回归。
#
# 先跑一遍正常路径，再逐个注入故障，确认 T0~T3 真的会拦住它们 ——
# 一个从不出现在失败栏里的测试等于没有测试。
#
#   run_scenarios.sh /path/to/m2_board_logic
#
# 退出码 0 = 所有场景都符合预期。
#
# 【边界】这里通过只说明"板端测试的判定逻辑是对的"，
# 不说明它在真板上会通过。真板结论只能由 scripts/regress.sh full 给出。

set -u
set -o pipefail

BIN=${1:-}

if [[ -z "$BIN" || ! -x "$BIN" ]]; then
    echo "用法：$(basename "$0") /path/to/m2_board_logic" >&2
    exit 2
fi

PASS_MARK='M2 BITBLT BOARD TEST PASSED'
FAIL_MARK='M2 BITBLT BOARD TEST FAILED'

CASES=0
BAD=0

show()
{
    printf '%s\n' "$1" | sed 's/^/       | /'
}

run_case()
{
    local fault=$1
    local want_pass=$2
    local want_text=$3
    local label=${fault:-clean}
    local out

    CASES=$((CASES + 1))

    out=$(M2_STUB_FAULT="$fault" "$BIN" 2>&1)

    if [[ "$out" != *"$want_text"* ]]; then
        echo "[FAIL] $label：输出里没有 '$want_text'"
        show "$out"
        BAD=$((BAD + 1))
        return
    fi

    if (( want_pass == 1 )); then
        if [[ "$out" != *"$PASS_MARK"* ]]; then
            echo "[FAIL] $label：期望 PASSED"
            show "$out"
            BAD=$((BAD + 1))
            return
        fi
    else
        if [[ "$out" == *"$PASS_MARK"* ]]; then
            echo "[FAIL] $label：期望 FAILED，却打出了 PASSED"
            show "$out"
            BAD=$((BAD + 1))
            return
        fi
        if [[ "$out" != *"$FAIL_MARK"* ]]; then
            echo "[FAIL] $label：期望 FAILED，但连结论都没打出来"
            show "$out"
            BAD=$((BAD + 1))
            return
        fi
    fi

    echo "[ok]   $label"
}


# 正常路径：T0~T3 四个用例全过
run_case "" 1 "[PASS] T3_guard_sentinel"

# T0 的 fail-fast：三条分支都必须立刻出结论，并且明确说明没碰 MMIO
run_case nohook    0 "tick source not injected"
run_case nohook    0 "BitBlt MMIO was NOT touched"
run_case freeze    0 "tick did not advance"
run_case slowclock 0 "10ms delta="

# T1 门：版本不对就不下发 FILL
run_case version   0 "expected=0x00010003 actual=0x00010002"
run_case version   0 "fill tests were NOT run"

# T2 / T3 的拦截能力
run_case short     0 "[FAIL] T2_bitblt_fill_readback"
run_case pad       0 "[FAIL] T3_guard_sentinel"
run_case overrun   0 "[FAIL] T3_guard_sentinel"


echo
if (( BAD == 0 )); then
    echo "board logic scenarios: $CASES/$CASES 符合预期"
    exit 0
fi

echo "board logic scenarios: $BAD/$CASES 不符预期" >&2
exit 1
