#!/usr/bin/env python3
"""
send_image.py —— 一步到位：任意 JPG/PNG -> 自适应 1280x720 -> RGB565 -> UDP 发给板子

这是日常最常用的入口。不需要先手动转 .bin，也不需要关心 RGB565 的细节。

    python3 send_image.py a.jpg --mode fit
    python3 send_image.py a.jpg --mode fill --slot 1
    python3 send_image.py bg1.png --slot 0 --no-swap     # 预载，之后用板载按键切
    python3 send_image.py bg2.png --slot 1 --no-swap
    python3 send_image.py anim.png --dbuf                # 双缓冲，发送中不撕裂

模式（--mode）:
    fit      保持宽高比完整显示，多余部分补黑边 —— 默认，最安全
    fill     保持宽高比铺满屏幕，超出部分居中裁掉 —— 适合背景图
    stretch  强行拉成 1280x720 —— 只用于测试，会变形

板载按键（bit 烧进去之后）:
    KEY1 (GPIOL_07)  上一张
    KEY3 (GPIOL_03)  下一张

要发送已经转好的 .bin，用 udp_send_image.py。
"""

import argparse
import os
import socket
import sys
import time

import numpy as np
from PIL import Image

# 同目录模块
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from resize_bin import resize_adaptive, rgb888_to_rgb565          # noqa: E402
from udp_send_image import (                                       # noqa: E402
    DEFAULT_CHUNK,
    DEFAULT_IP,
    DEFAULT_PORT,
    SCREEN_HEIGHT,
    SCREEN_WIDTH,
    SLOT_COUNT,
    SLOT_SIZE,
    build_packets,
    check_slot,
    frame_checksum,
    report_ack,
    send_packets,
    wait_for_ack,
)

MODE_CHOICES = ("fit", "fill", "stretch", "smart", "contain", "cover")


def load_image_rgb(path):
    """读图，透明区域铺黑，统一转成 RGB。"""
    try:
        img = Image.open(path)
        img.load()
    except Exception as e:
        raise ValueError(f"无法打开图片：{e}") from e

    rgba = img.convert("RGBA")
    background = Image.new("RGBA", rgba.size, (0, 0, 0, 255))
    background.alpha_composite(rgba)
    return background.convert("RGB")


def main():
    parser = argparse.ArgumentParser(
        description="任意图片 -> 自适应 1280x720 -> RGB565 -> UDP 发送到开发板"
    )

    parser.add_argument("input", help="输入图片（JPG / PNG / BMP / WebP ...）")
    parser.add_argument("--ip", default=DEFAULT_IP,
                        help=f"板子 IP，默认 {DEFAULT_IP}")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT,
                        help=f"板子 UDP 端口，默认 {DEFAULT_PORT}")
    parser.add_argument("--chunk", type=int, default=DEFAULT_CHUNK,
                        help=f"每包图片数据字节数，默认 {DEFAULT_CHUNK}")
    parser.add_argument("--gap", type=float, default=0.0002,
                        help="每包发送间隔(秒)，默认 0.0002")
    parser.add_argument("--frame-id", type=int, default=None,
                        help="帧号，默认用当前时间的低 16 位")
    parser.add_argument("--local-port", type=int, default=DEFAULT_PORT,
                        help=f"本地绑定端口（收回执用），默认 {DEFAULT_PORT}")

    parser.add_argument(
        "--mode",
        choices=MODE_CHOICES,
        default="fit",
        help="适配方式：fit=保持比例完整显示补黑边（默认），"
             "fill=保持比例铺满居中裁边，stretch=强行拉伸",
    )

    parser.add_argument(
        "--slot", type=int, default=None,
        help=f"目标图片槽位 0..{SLOT_COUNT - 1}（每槽 {SLOT_SIZE // 1024 // 1024} MiB），默认 0",
    )
    parser.add_argument(
        "--dbuf", action="store_true",
        help="双缓冲：让板端挑'当前没在显示'的那一块写，写完自动切过去",
    )
    parser.add_argument(
        "--no-swap", dest="auto_swap", action="store_false", default=True,
        help="只写槽位，不把显示切过去（预载多张图，之后用板载按键切换）",
    )

    parser.add_argument(
        "--ack", action="store_true",
        help="要求板端整帧完成后回执，并报告帧完整性",
    )
    parser.add_argument("--ack-timeout", type=float, default=3.0,
                        help="等回执的超时时间(秒)，默认 3")
    parser.add_argument(
        "--retry", type=int, default=2,
        help="板端报帧不完整时整帧重传的次数，默认 2（只在 --ack 时生效）",
    )

    parser.add_argument(
        "--save", metavar="OUT.bin", default=None,
        help="顺便把转好的 RGB565 存成文件（默认不存）",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="只做转换和分包，不实际发送",
    )

    args = parser.parse_args()

    # ============================================================
    # 0. 槽位
    # ============================================================

    try:
        if args.dbuf and args.slot is not None:
            raise ValueError("--dbuf 和 --slot 不能同时用")
        # dbuf 时槽位由 FPGA 决定（它挑当前没在显示的那一块），
        # PC 不需要知道板子现在显示哪个槽位，按过键也不会错乱。
        slot = 0 if args.dbuf else check_slot(0 if args.slot is None else args.slot)
    except ValueError as exc:
        print(f"[ERROR] {exc}")
        sys.exit(1)

    # ============================================================
    # 1. 读图 + 自适应
    # ============================================================

    if not os.path.isfile(args.input):
        print(f"[ERROR] 文件不存在：{args.input}")
        sys.exit(1)

    if args.chunk <= 0:
        print("[ERROR] --chunk 必须为正数")
        sys.exit(1)

    chunk_size = args.chunk
    if chunk_size % 16 != 0:
        chunk_size -= chunk_size % 16
        if chunk_size == 0:
            print("[ERROR] --chunk 太小，取 16 的倍数后为 0")
            sys.exit(1)
        print(f"[WARN] chunk 自动调整为 16 的倍数：{chunk_size}")

    try:
        source = load_image_rgb(args.input)
    except ValueError as exc:
        print(f"[ERROR] {exc}")
        sys.exit(1)

    print("=" * 60)
    print("图片 -> RGB565 -> UDP")
    print(f"输入文件   : {args.input}")
    print(f"原始尺寸   : {source.width} x {source.height}")

    try:
        fitted, content_size = resize_adaptive(
            source, (SCREEN_WIDTH, SCREEN_HEIGHT), args.mode, 1.20
        )
    except ValueError as exc:
        print(f"[ERROR] {exc}")
        sys.exit(1)

    data = rgb888_to_rgb565(fitted, "little").tobytes(order="C")

    if args.mode in ("fit", "contain") and content_size != (SCREEN_WIDTH, SCREEN_HEIGHT):
        note = "（补黑边）"
    elif args.mode in ("fill", "cover"):
        note = "（居中裁边）"
    elif args.mode == "stretch":
        note = "（强行拉伸，宽高比失真）"
    else:
        note = ""

    print(f"屏幕       : {SCREEN_WIDTH} x {SCREEN_HEIGHT}")
    print(f"适配模式   : {args.mode}   有效内容 {content_size[0]} x {content_size[1]}{note}")
    print(f"数据大小   : {len(data)} Byte ({len(data) / 1024 / 1024:.3f} MiB)")

    if args.save:
        save_abs = os.path.abspath(args.save)
        os.makedirs(os.path.dirname(save_abs), exist_ok=True)
        with open(save_abs, "wb") as f:
            f.write(data)
        fitted.save(save_abs + "_preview.png")
        print(f"已保存     : {save_abs}")

    # ============================================================
    # 2. 分包
    # ============================================================

    frame_id = args.frame_id
    if frame_id is None:
        frame_id = int(time.time()) & 0xFFFF

    packets, total_pkts, total_bytes = build_packets(
        data, slot, frame_id, args.auto_swap, args.ack, chunk_size, args.dbuf
    )

    print(f"目标       : {args.ip}:{args.port}")
    print(f"帧号       : {frame_id}")
    if args.dbuf:
        print("目标槽位   : 由板端决定（挑当前没在显示的那一块）")
    else:
        print(f"目标槽位   : {slot}  (DDR 偏移 0x{slot * SLOT_SIZE:08X})")
    print(f"整帧切屏   : {'是（等 VSYNC 切过去）' if (args.auto_swap or args.dbuf) else '否（只写槽位）'}")
    print(f"板端回执   : {'要' if args.ack else '不要'}")
    print(f"总包数     : {total_pkts} 个 DATA 包 + START/END，共 {len(packets)} 包")

    # 校验和提前算，--dry-run 时也能看到
    local_ck = None
    if args.ack:
        try:
            local_ck = frame_checksum(data)
        except ValueError as exc:
            print(f"[ERROR] {exc}")
            sys.exit(1)
        print(f"帧校验和   : sum {local_ck[0]:08X}  xor {local_ck[1]:08X}")

    print("=" * 60)

    if args.dry_run:
        print()
        print("[dry-run] 未实际发送")
        return

    # ============================================================
    # 3. 发送（--ack 时按需整帧重传）
    # ============================================================

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", args.local_port))

    target = (args.ip, args.port)

    attempts = max(1, args.retry) if args.ack else 1

    for attempt in range(1, attempts + 1):
        if attempt > 1:
            print()
            print("=" * 60)
            print(f"重传 第 {attempt}/{attempts} 次（上一帧板端没有确认完整）")
            print("=" * 60)
            frame_id = (frame_id + 1) & 0xFFFF
            packets, _, _ = build_packets(
                data, slot, frame_id, args.auto_swap, args.ack,
                chunk_size, args.dbuf
            )

        print()
        print(f"开始发送 {len(packets)} 包 ... (frame {frame_id})")

        sent_bytes, dt = send_packets(sock, packets, target, args.gap)

        print()
        print("=" * 60)
        print("发送完成（PC 侧 sendto 返回；不代表 FPGA 已收全）")
        print(f"发送字节   : {sent_bytes} Byte ({sent_bytes / 1024 / 1024:.3f} MiB)")
        print(f"耗时       : {dt:.3f} s")
        if dt > 0:
            print(f"速率       : {sent_bytes * 8 / dt / 1e6:.1f} Mbps")
        print("=" * 60)

        if not args.ack:
            break

        # ============================================================
        # 4. 等回执并判定
        # ============================================================

        print()
        print(f"等 FPGA 回执（最多 {args.ack_timeout}s）...")
        ack = wait_for_ack(sock, frame_id, args.ack_timeout)
        verdict = report_ack(ack, chunk_size, dt, local_ck)

        if verdict is None:
            print()
            print("[NOTE] 没收到回执，无法判断 —— 不再重传（重传结果一样）。")
            break

        if verdict:
            break

        if attempt == attempts:
            print()
            print(f"[FAIL] 重传 {attempts} 次仍未收全。加大包间隔再试：")
            print(f"       --gap {max(args.gap * 5, 0.001):.4f}")

    sock.close()

    # 给一句下一步提示，省得每次翻文档
    if not args.ack:
        print()
        if args.dbuf:
            print("提示：本次写到板端当前没在显示的那一块，写完会自动切过去。"
                  "想确认板子是否收全，加 --ack。")
        elif args.auto_swap:
            print(f"提示：整帧写完后屏幕会切到槽位 {slot}。"
                  "想确认板子是否收全，加 --ack。")
        else:
            print(f"提示：已预载到槽位 {slot}，屏幕没变。"
                  "按板载 KEY1/KEY3 逐张切换。")


if __name__ == "__main__":
    main()
