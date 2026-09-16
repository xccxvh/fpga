from PIL import Image
import numpy as np
import argparse
import json
import os
import sys


class ConversionError(Exception):
    """图片转换过程中出现的错误。"""
    pass


DEFAULT_IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp", ".tif", ".tiff"}


def convert_to_rgb565(input_path, output_path, endian="little", target_size=None):
    """
    将 JPG / PNG 转换为 RGB565 raw 二进制数据。

    像素扫描顺序：
        从左到右、从上到下（row-major / C-order）

    RGB565:
        R: 5 bit
        G: 6 bit
        B: 5 bit

    同时生成：
        1. RGB565 raw 文件
        2. JSON 元数据
        3. RGB565 恢复预览图
    """

    # ============================================================
    # 1. 检查输入文件
    # ============================================================

    if not os.path.isfile(input_path):
        raise ConversionError(f"输入文件不存在：{input_path}")

    # 获取输出目录
    output_abs = os.path.abspath(output_path)
    output_dir = os.path.dirname(output_abs)

    # 如果输出目录不存在，则自动创建
    os.makedirs(output_dir, exist_ok=True)

    # ============================================================
    # 2. 读取图片
    # ============================================================

    try:
        img = Image.open(input_path)
    except Exception as e:
        raise ConversionError(f"无法打开图片：{e}")

    print("========== 输入图片 ==========")
    print(f"文件       : {input_path}")
    print(f"原始模式   : {img.mode}")
    print(f"原始尺寸   : {img.width} x {img.height}")

    # ============================================================
    # 3. 统一处理透明图片
    # ============================================================
    #
    # 无论 JPG、RGB PNG、RGBA PNG、P 模式 PNG
    # 都先转成 RGBA。
    #
    # 透明区域铺成黑色。
    #

    rgba = img.convert("RGBA")

    background = Image.new(
        "RGBA",
        rgba.size,
        (0, 0, 0, 255)
    )

    background.alpha_composite(rgba)

    img_rgb = background.convert("RGB")

    # 可选：缩放到目标尺寸（如 1280x720）
    if target_size is not None:
        img_rgb = img_rgb.resize(target_size, Image.LANCZOS)
        print(f"缩放后尺寸 : {img_rgb.width} x {img_rgb.height}")

    width, height = img_rgb.size

    # ============================================================
    # 4. Pillow → NumPy
    # ============================================================

    rgb = np.asarray(
        img_rgb,
        dtype=np.uint16
    )

    # rgb.shape:
    # (height, width, 3)

    r = rgb[:, :, 0]
    g = rgb[:, :, 1]
    b = rgb[:, :, 2]

    # ============================================================
    # 5. RGB888 → RGB565
    # ============================================================
    #
    # RGB888：
    #
    # RRRRRRRR GGGGGGGG BBBBBBBB
    #
    # RGB565：
    #
    # RRRRR GGGGGG BBBBB
    #
    # bit:
    # [15:11] R
    # [10:5]  G
    # [4:0]   B
    #

    rgb565 = (
        ((r & 0xF8) << 8) |
        ((g & 0xFC) << 3) |
        (b >> 3)
    ).astype(np.uint16)

    # ============================================================
    # 6. 写 RGB565 raw 文件
    # ============================================================
    #
    # NumPy 数组本身排列：
    #
    # pixel(0,0)
    # pixel(1,0)
    # pixel(2,0)
    # ...
    # 换下一行
    #
    # 即：
    # 左 → 右
    # 上 → 下
    #

    if endian == "little":
        raw_data = rgb565.astype("<u2")

    elif endian == "big":
        raw_data = rgb565.astype(">u2")

    else:
        raise ConversionError(f"不支持的字节序：{endian}")

    raw_data.tofile(output_path)

    size_bytes = width * height * 2

    # ============================================================
    # 7. 生成 JSON 元数据
    # ============================================================

    metadata = {
        "source_filename": os.path.basename(input_path),

        "width": width,
        "height": height,

        "pixel_format": "RGB565",

        "bits_per_pixel": 16,
        "bytes_per_pixel": 2,

        "scan_order": "left-to-right, top-to-bottom",

        "memory_layout": "row-major",

        "endian": endian,

        "size_bytes": size_bytes
    }

    json_path = output_path + ".json"

    try:
        with open(
            json_path,
            "w",
            encoding="utf-8"
        ) as f:

            json.dump(
                metadata,
                f,
                indent=4,
                ensure_ascii=False
            )

    except Exception as e:
        raise ConversionError(f"JSON 写入失败：{e}")

    # ============================================================
    # 8. RGB565 → RGB888
    #
    # 用于生成验证图片
    # ============================================================

    r5 = (
        (rgb565 >> 11) & 0x1F
    ).astype(np.uint8)

    g6 = (
        (rgb565 >> 5) & 0x3F
    ).astype(np.uint8)

    b5 = (
        rgb565 & 0x1F
    ).astype(np.uint8)

    # ============================================================
    # 使用硬件常见的位扩展方法
    #
    # 5bit → 8bit
    #
    # abcde
    #
    # abcdeabc
    #
    # 等价：
    # (value << 3) | (value >> 2)
    #
    #
    # 6bit → 8bit：
    #
    # abcdef
    #
    # abcdefab
    #
    # 等价：
    # (value << 2) | (value >> 4)
    #
    # ============================================================

    r8 = (
        (r5 << 3) |
        (r5 >> 2)
    ).astype(np.uint8)

    g8 = (
        (g6 << 2) |
        (g6 >> 4)
    ).astype(np.uint8)

    b8 = (
        (b5 << 3) |
        (b5 >> 2)
    ).astype(np.uint8)

    restored_rgb = np.stack(
        (
            r8,
            g8,
            b8
        ),
        axis=-1
    )

    # ============================================================
    # 9. 保存恢复预览图
    # ============================================================

    preview_path = output_path + "_preview.png"

    preview_image = Image.fromarray(restored_rgb)

    try:
        preview_image.save(preview_path)

    except Exception as e:
        raise ConversionError(f"预览图保存失败：{e}")

    # ============================================================
    # 10. 输出转换信息
    # ============================================================

    print()
    print("========== 转换完成 ==========")

    print(f"输入文件     : {input_path}")
    print(f"输出 RAW     : {output_path}")

    print(
        f"分辨率       : "
        f"{width} x {height}"
    )

    print(
        "扫描顺序     : "
        "左 → 右，上 → 下"
    )

    print(
        "内存排列     : "
        "row-major"
    )

    print(
        "像素格式     : "
        "RGB565"
    )

    print(
        "每像素       : "
        "16 bit / 2 Byte"
    )

    print(
        f"字节序       : "
        f"{endian}"
    )

    print(
        f"RAW 数据大小 : "
        f"{size_bytes} Byte"
    )

    print(
        f"约           : "
        f"{size_bytes / 1024 / 1024:.3f} MiB"
    )

    print(
        f"JSON         : "
        f"{json_path}"
    )

    print(
        f"预览图       : "
        f"{preview_path}"
    )

    print("==============================")


def list_image_files(input_dir, recursive=False, extensions=None):
    """
    列出目录下所有图片文件（按扩展名过滤）。

    参数:
        input_dir  : 输入目录
        recursive  : 是否递归子目录
        extensions : 允许的扩展名列表（如 ["jpg", "png"]），
                     默认使用 DEFAULT_IMAGE_EXTS

    返回:
        排序后的图片文件路径列表
    """
    if extensions:
        exts = set()
        for e in extensions:
            e = e.strip().lower()
            if e:
                exts.add(e if e.startswith(".") else "." + e)
    else:
        exts = DEFAULT_IMAGE_EXTS

    files = []

    if recursive:
        for root, _dirs, filenames in os.walk(input_dir):
            for name in filenames:
                if os.path.splitext(name)[1].lower() in exts:
                    files.append(os.path.join(root, name))
    else:
        for name in os.listdir(input_dir):
            full = os.path.join(input_dir, name)
            if os.path.isfile(full) and os.path.splitext(name)[1].lower() in exts:
                files.append(full)

    files.sort()
    return files


def convert_directory(input_dir, output_dir, endian="little",
                      recursive=False, extensions=None):
    """
    批量转换目录下所有图片。

    每张图片分别输出:
        <output_dir>/<相对路径主名>.bin
        <output_dir>/<相对路径主名>.bin.json
        <output_dir>/<相对路径主名>.bin_preview.png

    返回:
        失败图片数量（0 表示全部成功）
    """
    if not os.path.isdir(input_dir):
        raise ConversionError(f"输入目录不存在：{input_dir}")

    image_files = list_image_files(input_dir, recursive, extensions)

    # 若输出目录位于输入目录内部（如默认的 <输入>/rgb565_out），
    # 递归时需要排除输出目录，避免把上次生成的预览图等产物再次当成输入
    output_abs = os.path.abspath(output_dir)
    input_abs = os.path.abspath(input_dir)

    if output_abs != input_abs and output_abs.startswith(input_abs + os.sep):
        image_files = [
            p for p in image_files
            if not os.path.abspath(p).startswith(output_abs + os.sep)
        ]

    if not image_files:
        print(f"[WARN] 目录下没有找到可转换的图片：{input_dir}")
        return 0

    os.makedirs(output_dir, exist_ok=True)

    print("=" * 60)
    print("批量转换")
    print(f"输入目录   : {input_dir}")
    print(f"输出目录   : {output_dir}")
    print(f"图片数量   : {len(image_files)}")
    print(f"字节序     : {endian}")
    print(f"递归子目录 : {'是' if recursive else '否'}")
    print("=" * 60)

    success = 0
    failed = 0

    for i, img_path in enumerate(image_files, start=1):
        rel = os.path.relpath(img_path, input_dir)
        stem = os.path.splitext(rel)[0]
        out_path = os.path.join(output_dir, stem + ".bin")

        print()
        print(f"[{i}/{len(image_files)}] {img_path}")

        try:
            convert_to_rgb565(img_path, out_path, endian)
            success += 1
        except ConversionError as e:
            failed += 1
            print(f"[ERROR] 转换失败：{e}")
        except Exception as e:
            failed += 1
            print(f"[ERROR] 未知错误：{e}")

    print()
    print("=" * 60)
    print(f"批量转换结束：成功 {success} 张，失败 {failed} 张")
    print("=" * 60)

    return failed


def main():

    parser = argparse.ArgumentParser(
        description=(
            "Convert JPG / PNG to RGB565 raw binary data.\n"
            "支持单张图片或整个文件夹批量转换。"
        )
    )

    parser.add_argument(
        "input",
        help="输入图片文件，或包含图片的文件夹"
    )

    parser.add_argument(
        "output",
        help=(
            "输出路径：input 为文件时表示输出 .bin 文件；"
            "input 为文件夹时表示输出目录"
        )
    )

    parser.add_argument(
        "--endian",
        choices=[
            "little",
            "big"
        ],
        default="little",
        help=(
            "RGB565 字节序，"
            "默认 little"
        )
    )

    parser.add_argument(
        "-r",
        "--recursive",
        action="store_true",
        help="批量转换时递归处理子目录"
    )

    parser.add_argument(
        "--ext",
        default="jpg,jpeg,png,bmp,webp",
        help=(
            "批量转换时处理的图片扩展名，"
            "逗号分隔，默认 jpg,jpeg,png,bmp,webp"
        )
    )

    parser.add_argument(
        "--resize",
        default=None,
        help="缩放图片到 WxH（如 1280x720），默认不缩放"
    )

    args = parser.parse_args()

    # 解析 --resize 为 (W, H)
    target_size = None
    if args.resize:
        try:
            w_str, h_str = args.resize.lower().split("x")
            target_size = (int(w_str), int(h_str))
        except Exception:
            print(f"[ERROR] --resize 格式应为 WxH（如 1280x720），实际是：{args.resize}")
            sys.exit(1)

    extensions = [e for e in args.ext.split(",") if e.strip()]

    if os.path.isdir(args.input):
        # 批量模式：input 是目录，output 是输出目录
        try:
            failed = convert_directory(
                input_dir=args.input,
                output_dir=args.output,
                endian=args.endian,
                recursive=args.recursive,
                extensions=extensions,
            )
        except ConversionError as e:
            print(f"[ERROR] {e}")
            sys.exit(1)

        sys.exit(1 if failed else 0)

    # 单文件模式：input 是文件，output 是输出文件
    try:
        convert_to_rgb565(
            input_path=args.input,
            output_path=args.output,
            endian=args.endian,
            target_size=target_size,
        )
    except ConversionError as e:
        print(f"[ERROR] {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()