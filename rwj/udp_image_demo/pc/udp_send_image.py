#!/usr/bin/env python3
"""
udp_send_image.py —— 电脑端：把 RGB565 图片通过千兆以太网 UDP 发送到开发板

配套:
    PC : images  ->  img_to_rgb565.py  ->  xxx.bin (RGB565 raw) + xxx.bin.json
    板 : fpga 工程（板子 IP 192.168.0.2，UDP 端口 8080）

UDP 分包协议（每包 UDP payload，全部大端序）:
    offset  0 : magic        2B    固定 0xA55A
    offset  2 : frame_id     2B    帧号
    offset  4 : packet_idx   2B    包号（从 0 开始）
    offset  6 : total_pkts   2B    本帧总包数
    offset  8 : payload_len  2B    本包图片数据字节数
    offset 10 : reserved     2B    保留（置 0）
    offset 12 : byte_offset  4B    本包数据在整帧中的字节偏移
    offset 16 : data         N B   RGB565 像素数据
    ------------------------------------------------------------
    包头固定 16 字节

    默认每包 1280 字节数据（1280+16 = 1296 字节 UDP payload），
    对应 IP 包 1296+8+20 = 1324 < 1500 MTU，安全。

用法:
    python3 udp_send_image.py logo.bin                    # 发送
    python3 udp_send_image.py logo.bin --dry-run          # 只看分包结果
    python3 udp_send_image.py logo.bin --gap 0.0002       # 加包间隔
    python3 udp_send_image.py logo.bin --verify           # 发送后监听回环
"""

import argparse
import json
import os
import socket
import struct
import sys
import time

# ----------------------------------------------------------------
# 协议常量
# ----------------------------------------------------------------

MAGIC = 0xA55A

# magic / frame_id / packet_idx / total_pkts / payload_len / reserved / byte_offset
HEADER_FMT = ">HHHHHHI"
HEADER_SIZE = struct.calcsize(HEADER_FMT)      # = 16 字节

DEFAULT_IP = "192.168.0.2"       # 板子 IP
DEFAULT_PORT = 8080              # 板子 UDP 端口
SCREEN_WIDTH = 1280
SCREEN_HEIGHT = 720
FRAME_SIZE = SCREEN_WIDTH * SCREEN_HEIGHT * 2
# 每包图片数据字节数：
#   必须同时满足：① 16 字节对齐（DDR3 AXI 是 128-bit）；② 偶数（RGB565 2B/像素）
#   1280 = 640 像素 = 半行（1280 像素一行），1280/16 = 80 个 128-bit beat = 5 个 16-beat 突发
DEFAULT_CHUNK = 1280


def load_meta(bin_path):
    """读取 img_to_rgb565.py 生成的同名 .json 元数据（宽高等）。"""
    meta_path = bin_path + ".json"

    if not os.path.isfile(meta_path):
        return None

    try:
        with open(meta_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def make_packet(frame_id, pkt_idx, total, byte_offset, chunk):
    """拼一个完整 UDP payload：16 字节包头 + 图片数据。"""
    header = struct.pack(
        HEADER_FMT,
        MAGIC,
        frame_id,
        pkt_idx,
        total,
        len(chunk),
        0,                      # reserved
        byte_offset
    )
    return header + chunk


def fit_to_screen(data, meta, mode):
    """按元数据把任意尺寸 RGB565 转成固定 1280x720 framebuffer。"""
    if not meta:
        if len(data) == FRAME_SIZE:
            return data, None
        raise ValueError(
            f"输入是 {len(data)} 字节，不是屏幕要求的 {FRAME_SIZE} 字节，"
            "且缺少同名 .json，无法判断源分辨率"
        )

    try:
        src_width = int(meta["width"])
        src_height = int(meta["height"])
    except (KeyError, TypeError, ValueError) as exc:
        raise ValueError("元数据缺少有效的 width/height") from exc

    expected_size = src_width * src_height * 2
    if len(data) != expected_size:
        raise ValueError(
            f"文件为 {len(data)} 字节，但元数据 {src_width}x{src_height} "
            f"RGB565 应为 {expected_size} 字节"
        )

    if (src_width, src_height) == (SCREEN_WIDTH, SCREEN_HEIGHT):
        return data, None

    endian = meta.get("endian", "little")
    if endian not in ("little", "big"):
        raise ValueError(f"不支持元数据中的字节序：{endian}")

    try:
        from PIL import Image
        from resize_bin import (
            resize_adaptive,
            rgb565_to_rgb888,
            rgb888_to_rgb565,
        )
    except ImportError as exc:
        raise ValueError(f"自动缩放需要 Pillow 和 NumPy：{exc}") from exc

    rgb888 = rgb565_to_rgb888(data, src_width, src_height, endian)
    source = Image.fromarray(rgb888, "RGB")
    result, _content_size = resize_adaptive(
        source, (SCREEN_WIDTH, SCREEN_HEIGHT), mode, 1.20
    )
    fitted = rgb888_to_rgb565(result, endian).tobytes(order="C")
    fitted_meta = dict(meta)
    fitted_meta.update({
        "source_width": src_width,
        "source_height": src_height,
        "width": SCREEN_WIDTH,
        "height": SCREEN_HEIGHT,
        "resize_mode": mode,
        "size_bytes": len(fitted),
    })
    return fitted, fitted_meta


def main():
    parser = argparse.ArgumentParser(
        description="把 RGB565 raw 图片通过 UDP 分包发送到开发板"
    )

    parser.add_argument("input", help="RGB565 raw 文件")
    parser.add_argument("--ip", default=DEFAULT_IP,
                        help=f"板子 IP，默认 {DEFAULT_IP}")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT,
                        help=f"板子 UDP 端口，默认 {DEFAULT_PORT}")
    parser.add_argument("--chunk", type=int, default=DEFAULT_CHUNK,
                        help=f"每包图片数据字节数，默认 {DEFAULT_CHUNK}（自动取偶）")
    parser.add_argument("--frame-id", type=int, default=0,
                        help="帧号，默认 0")
    parser.add_argument("--gap", type=float, default=0.0002,
                        help="每包发送间隔(秒)，默认 0.0002（板端 UDP RAM 会被下一包覆盖，先保守间隔）")
    parser.add_argument("--local-port", type=int, default=DEFAULT_PORT,
                        help=f"本地绑定端口（收回环用），默认 {DEFAULT_PORT}")
    parser.add_argument("--dry-run", action="store_true",
                        help="只显示分包结果，不实际发送")
    parser.add_argument("--verify", action="store_true",
                        help="发送后监听回环数据")
    parser.add_argument("--verify-timeout", type=float, default=5.0,
                        help="回环监听超时(秒)，默认 5")
    parser.add_argument(
        "--fit-mode",
        choices=("stretch", "smart", "contain", "cover"),
        default="stretch",
        help="非 1280x720 输入的自动适配方式，默认 stretch（铺满全屏）",
    )
    parser.add_argument(
        "--no-auto-fit",
        action="store_true",
        help="禁止发送前自动适配；尺寸不是 1280x720 时直接报错",
    )

    args = parser.parse_args()

    # ============================================================
    # 1. 读取图片文件
    # ============================================================

    if not os.path.isfile(args.input):
        print(f"[ERROR] 文件不存在：{args.input}")
        sys.exit(1)

    with open(args.input, "rb") as f:
        data = f.read()

    if len(data) == 0:
        print("[ERROR] 文件为空")
        sys.exit(1)

    meta = load_meta(args.input)

    try:
        if args.no_auto_fit:
            if len(data) != FRAME_SIZE:
                raise ValueError(
                    f"输入为 {len(data)} 字节，屏幕要求 {FRAME_SIZE} 字节"
                )
            fit_info = None
        else:
            original_size = len(data)
            data, fitted_meta = fit_to_screen(data, meta, args.fit_mode)
            fit_info = None
            if fitted_meta is not None:
                fit_info = (
                    int(fitted_meta["source_width"]),
                    int(fitted_meta["source_height"]),
                    args.fit_mode,
                    original_size,
                )
                meta = fitted_meta
    except ValueError as exc:
        print(f"[ERROR] {exc}")
        sys.exit(1)

    size = len(data)

    # chunk 取偶：RGB565 每像素 2 字节
    chunk_size = args.chunk

    if chunk_size <= 0:
        print("[ERROR] --chunk 必须为正数")
        sys.exit(1)

    if chunk_size % 2 != 0:
        chunk_size -= 1
        print(f"[WARN] chunk 自动调整为偶数：{chunk_size}")

    total_pkts = (size + chunk_size - 1) // chunk_size

    # ============================================================
    # 2. 打印分包信息
    # ============================================================

    print("=" * 60)
    print("RGB565 图片 UDP 发送")
    print(f"输入文件   : {args.input}")

    if fit_info:
        src_w, src_h, fit_mode, original_size = fit_info
        print(f"自动适配   : {src_w} x {src_h} -> {SCREEN_WIDTH} x {SCREEN_HEIGHT}")
        print(f"适配模式   : {fit_mode}")
        print(f"原始大小   : {original_size} Byte")

    if meta:
        print(f"分辨率     : {meta.get('width')} x {meta.get('height')}")
        print(f"像素格式   : {meta.get('pixel_format')}")

    print(f"数据大小   : {size} Byte ({size / 1024 / 1024:.3f} MiB)")
    print(f"每包数据   : {chunk_size} Byte")
    print(f"包头大小   : {HEADER_SIZE} Byte")
    print(f"总包数     : {total_pkts}")
    print(f"目标       : {args.ip}:{args.port}")
    print(f"帧号       : {args.frame_id}")
    print("=" * 60)

    if total_pkts > 0xFFFF:
        print(f"[ERROR] 包数 {total_pkts} 超过 uint16 上限，请增大 --chunk")
        sys.exit(1)

    # ============================================================
    # 3. dry-run：只预览分包
    # ============================================================

    if args.dry_run:
        print()
        print("[dry-run] 前 3 包预览：")

        for i in range(min(3, total_pkts)):
            off = i * chunk_size
            c = data[off:off + chunk_size]
            pkt = make_packet(args.frame_id, i, total_pkts, off, c)

            print(f"  包{i}: byte_offset={off}  数据={len(c)}B  整包={len(pkt)}B")
            print(f"        包头: {pkt[:HEADER_SIZE].hex(' ')}")

        print()
        print("[dry-run] 未实际发送")
        return

    # ============================================================
    # 4. 发送
    # ============================================================

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", args.local_port))

    target = (args.ip, args.port)

    print()
    print(f"开始发送 {total_pkts} 包 ...")

    t0 = time.time()
    sent_bytes = 0
    step = max(1, total_pkts // 20)

    for i in range(total_pkts):
        off = i * chunk_size
        c = data[off:off + chunk_size]
        pkt = make_packet(args.frame_id, i, total_pkts, off, c)

        sock.sendto(pkt, target)
        sent_bytes += len(pkt)

        if args.gap > 0:
            time.sleep(args.gap)

        if (i + 1) % step == 0 or (i + 1) == total_pkts:
            pct = (i + 1) * 100 // total_pkts
            print(f"  进度 {i + 1}/{total_pkts} ({pct}%)  "
                  f"已发 {sent_bytes / 1024:.0f} KiB")

    dt = time.time() - t0

    # ============================================================
    # 5. 统计
    # ============================================================

    print()
    print("=" * 60)
    print("发送完成")
    print(f"发送包数   : {total_pkts}")
    print(f"发送字节   : {sent_bytes} Byte ({sent_bytes / 1024 / 1024:.3f} MiB)")
    print(f"耗时       : {dt:.3f} s")

    if dt > 0:
        print(f"速率       : {sent_bytes * 8 / dt / 1e6:.1f} Mbps"
              f"  ({sent_bytes / 1024 / dt:.0f} KiB/s)")

    print("=" * 60)

    # ============================================================
    # 6. 可选：监听回环
    # ============================================================

    if args.verify:
        print()
        print(f"监听回环 {args.verify_timeout}s ...")

        sock.settimeout(0.5)

        t_end = time.time() + args.verify_timeout
        got_pkts = 0
        got_bytes = 0
        first = None

        while time.time() < t_end:
            try:
                rdata, raddr = sock.recvfrom(65535)
            except socket.timeout:
                continue

            got_pkts += 1
            got_bytes += len(rdata)

            if first is None:
                first = (len(rdata), raddr, rdata[:HEADER_SIZE])

        print(f"收到回环   : {got_pkts} 包, {got_bytes} Byte")

        if first:
            print(f"首包       : {first[0]} 字节  来自 {first[1][0]}:{first[1][1]}")
            print(f"              包头 = {first[2].hex(' ')}")
        else:
            print("[WARN] 没收到回环数据（板子未运行对应 bit）")

    sock.close()


if __name__ == "__main__":
    main()
