#!/usr/bin/env bash
#
# convert.sh —— 调用 img_to_rgb565.py，把 JPG / PNG 转成 RGB565 raw 二进制
#
# 用法:
#   ./convert.sh <输入图片|输入目录> [输出] [选项]
#
# 单张图片:
#   ./convert.sh ./img/logo.png
#   ./convert.sh ./img/logo.png ./out/logo.bin --endian big
#
# 整个文件夹:
#   ./convert.sh ./img ./out
#   ./convert.sh ./img ./out -r --ext jpg,png
#
# 说明:
#   输入为文件时，输出默认为同目录下扩展名换成 .bin 的文件；
#   输入为目录时，输出默认为同级的 <输入目录>_rgb565_out 目录。
#   字节序默认为 little。
#

set -euo pipefail

# 脚本所在目录（无论从哪里调用，都能找到同目录的 py 文件）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_SCRIPT="${SCRIPT_DIR}/img_to_rgb565.py"

# ------------------------------------------------------------------
# Python 解释器
#   默认使用 conda 环境 cross_modal 中的 python；
#   可用环境变量 PYTHON_BIN 覆盖为其他解释器，
#   可用环境变量 CONDA_ENV 指定其他 conda 环境。
# ------------------------------------------------------------------
CONDA_ENV="${CONDA_ENV:-cross_modal}"

PYTHON_BIN="${PYTHON_BIN:-}"

# 未显式指定 PYTHON_BIN 时，优先使用 conda 环境
if [[ -z "$PYTHON_BIN" ]] && command -v conda >/dev/null 2>&1; then
    PYTHON_BIN="$(conda run -n "$CONDA_ENV" which python 2>/dev/null || true)"
fi

# 回退到系统 python3
if [[ -z "$PYTHON_BIN" ]]; then
    PYTHON_BIN="python3"
fi

usage() {
    cat <<EOF
用法: $0 <输入图片|输入目录> [输出] [选项]

参数:
  输入          图片文件，或包含图片的文件夹（必填）
  输出          文件输入时表示输出 .bin 文件；目录输入时表示输出目录（可选）
                文件输入默认: 同目录、同主名，扩展名 .bin
                目录输入默认: <输入目录>_rgb565_out（与输入目录同级）
  --endian      字节序，little（默认）或 big
  -r, --recursive  批量转换时递归处理子目录
  --ext EXT     批量转换的图片扩展名，逗号分隔，默认 jpg,jpeg,png,bmp,webp
  -h, --help    显示本帮助

环境变量:
  RESIZE        目标尺寸，默认 1280x720
  FIT_MODE      适配方式，默认 fit
                fit=保持比例完整显示补黑边 / fill=铺满裁边 / stretch=强行拉伸
  PYTHON_BIN    指定 python 解释器
  CONDA_ENV     指定 conda 环境，默认 cross_modal

示例:
  $0 ./img/logo.png
  $0 ./img/logo.png ./out/logo.bin --endian big
  $0 ./img ./out
  $0 ./img ./out -r --ext jpg,png
  FIT_MODE=fill $0 ./img/background.jpg

提示: 日常直接发图用 send_image.py 更省事，不用先转 .bin。
EOF
}

main() {
    local input=""
    local output=""
    local endian="little"
    local recursive=0
    local ext=""

    # ---------- 解析参数 ----------
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --endian)
                if [[ -z "${2:-}" ]]; then
                    echo "[ERROR] --endian 需要参数: little 或 big" >&2
                    exit 1
                fi
                endian="$2"
                shift 2
                ;;
            -r|--recursive)
                recursive=1
                shift
                ;;
            --ext)
                if [[ -z "${2:-}" ]]; then
                    echo "[ERROR] --ext 需要参数" >&2
                    exit 1
                fi
                ext="$2"
                shift 2
                ;;
            -*)
                echo "[ERROR] 未知选项: $1" >&2
                usage
                exit 1
                ;;
            *)
                if [[ -z "$input" ]]; then
                    input="$1"
                elif [[ -z "$output" ]]; then
                    output="$1"
                else
                    echo "[ERROR] 多余的参数: $1" >&2
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # ---------- 校验输入 ----------
    if [[ -z "$input" ]]; then
        echo "[ERROR] 缺少输入图片" >&2
        usage
        exit 1
    fi

    if [[ ! -e "$input" ]]; then
        echo "[ERROR] 输入不存在: $input" >&2
        exit 1
    fi

    # ---------- 生成默认输出 ----------
    if [[ -z "$output" ]]; then
        if [[ -d "$input" ]]; then
            output="${input%/}_rgb565_out"
        else
            local dir base
            dir="$(dirname "$input")"
            base="$(basename "$input")"
            base="${base%.*}"
            output="${dir}/${base}.bin"
        fi
    fi

    # ---------- 校验字节序 ----------
    if [[ "$endian" != "little" && "$endian" != "big" ]]; then
        echo "[ERROR] 不支持的字节序: $endian（可选 little / big）" >&2
        exit 1
    fi

    # ---------- 检查运行环境 ----------
    if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
        echo "[ERROR] 找不到 $PYTHON_BIN，请先安装 Python 3" >&2
        exit 1
    fi

    if ! "$PYTHON_BIN" -c "import PIL, numpy" >/dev/null 2>&1; then
        echo "[ERROR] 缺少 Python 依赖，请先安装: pip install Pillow numpy" >&2
        exit 1
    fi

    # ---------- 打印信息并执行 ----------
    echo "python  : $("$PYTHON_BIN" --version 2>&1)"
    echo "输入    : $input"
    echo "输出    : $output"
    echo "字节序  : $endian"
    echo

    # 默认自适应到 1280x720（FPGA HDMI 固定按此分辨率显示）
    # 注意：这里走的是 resize_bin 的自适应缩放，不是硬拉伸，
    #       非 16:9 的图会按 FIT_MODE 补黑边 / 裁边，不会变形。
    local resize="${RESIZE:-1280x720}"
    local fit_mode="${FIT_MODE:-fit}"

    local -a py_args=("$PY_SCRIPT" "$input" "$output" "--endian" "$endian"
                      "--resize" "$resize" "--fit-mode" "$fit_mode")

    if [[ "$recursive" -eq 1 ]]; then
        py_args+=("--recursive")
    fi

    if [[ -n "$ext" ]]; then
        py_args+=("--ext" "$ext")
    fi

    "$PYTHON_BIN" "${py_args[@]}"
}

main "$@"
