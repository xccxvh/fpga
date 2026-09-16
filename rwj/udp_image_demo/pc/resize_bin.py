#!/usr/bin/env python3
"""把 RGB565 raw 图片自适应到 HDMI 帧大小（默认 1280x720）。

默认 smart 模式允许有限拉伸，尽量铺满屏幕，同时避免宽高比差异很大时
产生严重变形。输入旁边存在“文件名.bin.json”时会自动读取源分辨率。
"""

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image


DEFAULT_WIDTH = 1280
DEFAULT_HEIGHT = 720
DEFAULT_MAX_STRETCH = 1.20
LANCZOS = getattr(Image, "Resampling", Image).LANCZOS


def load_source_size(input_path, src_width, src_height):
    """优先使用命令行尺寸，否则读取 img_to_rgb565.py 生成的 JSON。"""
    if (src_width is None) != (src_height is None):
        raise ValueError("--src-width 和 --src-height 必须同时提供")

    if src_width is not None:
        return src_width, src_height

    meta_path = input_path + ".json"
    if os.path.isfile(meta_path):
        try:
            with open(meta_path, "r", encoding="utf-8") as f:
                meta = json.load(f)
            return int(meta["width"]), int(meta["height"])
        except (OSError, KeyError, TypeError, ValueError) as exc:
            raise ValueError(f"无法从 {meta_path} 读取源分辨率：{exc}") from exc

    raise ValueError(
        "没有找到源分辨率：请提供 --src-width/--src-height，"
        f"或在输入文件旁放置 {os.path.basename(meta_path)}"
    )


def resize_adaptive(img, target_size, mode, max_stretch):
    """返回固定目标尺寸的图像，以及实际缩放内容尺寸。"""
    target_w, target_h = target_size
    src_w, src_h = img.size
    target_aspect = target_w / target_h
    src_aspect = src_w / src_h

    if mode == "stretch":
        return img.resize(target_size, LANCZOS), target_size

    if mode == "cover":
        scale = max(target_w / src_w, target_h / src_h)
        content_size = (
            max(1, round(src_w * scale)),
            max(1, round(src_h * scale)),
        )
        resized = img.resize(content_size, LANCZOS)
        left = (content_size[0] - target_w) // 2
        top = (content_size[1] - target_h) // 2
        return resized.crop((left, top, left + target_w, top + target_h)), content_size

    if mode == "contain":
        content_aspect = src_aspect
    else:  # smart：把宽高比朝屏幕方向最多修正 max_stretch 倍
        aspect_ratio = target_aspect / src_aspect
        bounded_ratio = min(max(aspect_ratio, 1.0 / max_stretch), max_stretch)
        content_aspect = src_aspect * bounded_ratio

    if content_aspect <= target_aspect:
        content_h = target_h
        content_w = max(1, min(target_w, round(content_h * content_aspect)))
    else:
        content_w = target_w
        content_h = max(1, min(target_h, round(content_w / content_aspect)))

    content_size = (content_w, content_h)
    resized = img.resize(content_size, LANCZOS)
    canvas = Image.new("RGB", target_size, (0, 0, 0))
    canvas.paste(resized, ((target_w - content_w) // 2, (target_h - content_h) // 2))
    return canvas, content_size


def rgb565_to_rgb888(raw, width, height, endian):
    dtype = "<u2" if endian == "little" else ">u2"
    pixels = np.frombuffer(raw, dtype=dtype)
    expected_pixels = width * height
    if pixels.size != expected_pixels:
        raise ValueError(
            f"输入大小不匹配：{len(raw)} 字节，{width}x{height} RGB565 "
            f"应为 {expected_pixels * 2} 字节"
        )

    rgb565 = pixels.reshape(height, width).astype(np.uint16)
    r5 = ((rgb565 >> 11) & 0x1F).astype(np.uint8)
    g6 = ((rgb565 >> 5) & 0x3F).astype(np.uint8)
    b5 = (rgb565 & 0x1F).astype(np.uint8)
    return np.stack(
        (
            (r5 << 3) | (r5 >> 2),
            (g6 << 2) | (g6 >> 4),
            (b5 << 3) | (b5 >> 2),
        ),
        axis=-1,
    )


def rgb888_to_rgb565(img, endian):
    arr = np.asarray(img, dtype=np.uint16)
    rgb565 = (
        ((arr[:, :, 0] >> 3) << 11)
        | ((arr[:, :, 1] >> 2) << 5)
        | (arr[:, :, 2] >> 3)
    )
    return rgb565.astype("<u2" if endian == "little" else ">u2")


def main():
    parser = argparse.ArgumentParser(description="RGB565 图片自适应 HDMI 屏幕")
    parser.add_argument("input", help="输入 RGB565 raw 文件")
    parser.add_argument("output", help="输出 RGB565 raw 文件")
    parser.add_argument("--src-width", type=int, help="源图宽度；默认从 .bin.json 读取")
    parser.add_argument("--src-height", type=int, help="源图高度；默认从 .bin.json 读取")
    parser.add_argument("--width", type=int, default=DEFAULT_WIDTH, help="屏幕宽度，默认 1280")
    parser.add_argument("--height", type=int, default=DEFAULT_HEIGHT, help="屏幕高度，默认 720")
    parser.add_argument(
        "--mode",
        choices=("smart", "stretch", "contain", "cover"),
        default="smart",
        help="smart=有限拉伸（默认），stretch=完全铺满，contain=完整显示，cover=铺满裁边",
    )
    parser.add_argument(
        "--max-stretch",
        type=float,
        default=DEFAULT_MAX_STRETCH,
        help="smart 模式允许的最大宽高拉伸倍数，默认 1.20",
    )
    parser.add_argument("--endian", choices=("little", "big"), default="little")
    args = parser.parse_args()

    try:
        if args.width <= 0 or args.height <= 0:
            raise ValueError("目标宽高必须为正数")
        if args.max_stretch < 1.0:
            raise ValueError("--max-stretch 不能小于 1.0")
        if not os.path.isfile(args.input):
            raise ValueError(f"输入文件不存在：{args.input}")

        src_w, src_h = load_source_size(args.input, args.src_width, args.src_height)
        if src_w <= 0 or src_h <= 0:
            raise ValueError("源图宽高必须为正数")

        with open(args.input, "rb") as f:
            raw = f.read()

        rgb888 = rgb565_to_rgb888(raw, src_w, src_h, args.endian)
        source = Image.fromarray(rgb888, "RGB")
        result, content_size = resize_adaptive(
            source, (args.width, args.height), args.mode, args.max_stretch
        )
        output = rgb888_to_rgb565(result, args.endian)

        output_abs = os.path.abspath(args.output)
        os.makedirs(os.path.dirname(output_abs), exist_ok=True)
        output.tofile(output_abs)

        metadata = {
            "source_filename": os.path.basename(args.input),
            "source_width": src_w,
            "source_height": src_h,
            "width": args.width,
            "height": args.height,
            "content_width": content_size[0],
            "content_height": content_size[1],
            "resize_mode": args.mode,
            "max_stretch": args.max_stretch if args.mode == "smart" else None,
            "pixel_format": "RGB565",
            "bits_per_pixel": 16,
            "bytes_per_pixel": 2,
            "scan_order": "left-to-right, top-to-bottom",
            "memory_layout": "row-major",
            "endian": args.endian,
            "size_bytes": int(output.size * 2),
        }
        with open(output_abs + ".json", "w", encoding="utf-8") as f:
            json.dump(metadata, f, indent=4, ensure_ascii=False)
        result.save(output_abs + "_preview.png")

    except (OSError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    print("=" * 56)
    print("RGB565 图片自适应完成")
    print(f"源图       : {src_w} x {src_h}")
    print(f"屏幕       : {args.width} x {args.height}")
    print(f"模式       : {args.mode}")
    print(f"有效内容   : {content_size[0]} x {content_size[1]}")
    print(f"输出文件   : {output_abs}")
    print(f"数据大小   : {output.size * 2} Byte")
    print(f"预览图     : {output_abs}_preview.png")
    print("=" * 56)
    return 0


if __name__ == "__main__":
    sys.exit(main())
