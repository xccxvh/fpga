#!/usr/bin/env bash

set -u
set -o pipefail
ulimit -c 0

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$TEST_DIR/.." && pwd)
MUTATION_TMP=$(mktemp -d "${TMPDIR:-/tmp}/riscv-game-mutation.XXXXXX") || exit 1
trap 'rm -rf -- "$MUTATION_TMP"' EXIT

CC=${CC:-gcc}
WERROR=${WERROR:--Werror}
COMMON_FLAGS=(-std=c99 -O0 -g -Wall -Wextra -Wpedantic "$WERROR"
              -I"$PROJECT_ROOT/render")

build_and_expect_rejection()
{
    local name=$1
    local mutant=$2
    local binary="$MUTATION_TMP/$name"
    local output="$MUTATION_TMP/$name.output"

    if ! "$CC" "${COMMON_FLAGS[@]}" \
        "$TEST_DIR/test_renderer.c" "$mutant" -o "$binary"; then
        echo "[FAIL] mutation $name: 变异体未能编译，无法证明测试杀死了它" >&2
        return 1
    fi

    # Run through a child shell so an expected SIGABRT from assert is captured
    # in the mutation log instead of being printed as shell noise by this runner.
    if sh -c '"$1"' mutation-runner "$binary" >"$output" 2>&1; then
        echo "[FAIL] mutation $name: 错误实现未被 host tests 发现" >&2
        sed -n '1,80p' "$output" >&2
        return 1
    fi

    echo "[PASS] mutation $name 被 host tests 杀死"
}

# Mutant 1: fill 忽略调用方颜色。
sed 's/row\[px\] = color;/row[px] = (pixel_t)(color ^ color);/' \
    "$PROJECT_ROOT/render/renderer_sw.c" >"$MUTATION_TMP/fill_ignores_color.c"
if cmp -s "$PROJECT_ROOT/render/renderer_sw.c" "$MUTATION_TMP/fill_ignores_color.c"; then
    echo "[FAIL] mutation fill_ignores_color: 未找到预期变异点" >&2
    exit 1
fi

# Mutant 2: blit 每行都复制源行的第一个像素。
sed 's/sy \* src_stride + sx/sy * src_stride + 0/' \
    "$PROJECT_ROOT/render/renderer_sw.c" >"$MUTATION_TMP/blit_repeats_first_pixel.c"
if cmp -s "$PROJECT_ROOT/render/renderer_sw.c" "$MUTATION_TMP/blit_repeats_first_pixel.c"; then
    echo "[FAIL] mutation blit_repeats_first_pixel: 未找到预期变异点" >&2
    exit 1
fi

failures=0
build_and_expect_rejection fill_ignores_color "$MUTATION_TMP/fill_ignores_color.c" || failures=$((failures + 1))
build_and_expect_rejection blit_repeats_first_pixel "$MUTATION_TMP/blit_repeats_first_pixel.c" || failures=$((failures + 1))

if (( failures != 0 )); then
    echo "Mutation tests FAILED ($failures)" >&2
    exit 1
fi

echo "Mutation tests PASSED (2/2)"
