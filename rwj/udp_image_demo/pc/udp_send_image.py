#!/usr/bin/env python3
"""
udp_send_image.py —— 电脑端：把 RGB565 图片通过千兆以太网 UDP 发送到开发板

配套:
    PC : images  ->  img_to_rgb565.py  ->  xxx.bin (RGB565 raw) + xxx.bin.json
    板 : fpga 工程（板子 IP 192.168.0.2，UDP 端口 8080）

一帧的构成（START / DATA... / END 三段）:

    START   无数据，声明本帧总字节数、目标槽位、AUTO_SWAP / ACK_REQ 标志
    DATA    真正的图片数据，每包 chunk 字节
    END     无数据，声明本帧实际发了多少包，触发板端“整帧完成”

板端只有在收到 END 且累计字节数等于 START 声明的总字节数时，才认为
这一帧完整；此时才会按 AUTO_SWAP 切屏、按 ACK_REQ 回执。

UDP 分包协议（每包 UDP payload，全部大端序，包头固定 16 字节）:

    offset  0 : magic        2B    固定 0xA55A
    offset  2 : frame_id     2B    帧号
    offset  4 : packet_idx   2B    包号（DATA 包从 0 开始）
    offset  6 : total_pkts   2B    本帧 DATA 包总数
    offset  8 : payload_len  2B    本包数据字节数（START/END 时为 0）
    offset 10 : slot         1B    目标图片槽位 0..7（每个槽位 2 MiB）
    offset 11 : flags        1B    见下面 FLAG_*
    offset 12 : byte_offset  4B    DATA=帧内字节偏移 / START=本帧总字节数 / END=实发包数
    offset 16 : data         N B   RGB565 像素数据（仅 DATA 包有）

    flags:
        0x01 START      本包是帧起始
        0x02 END        本包是帧结束
        0x04 AUTO_SWAP  整帧写完后，等 VSYNC 把显示切到本槽位（双缓冲）
        0x08 ACK_REQ    整帧写完后，板子回一个 16 字节 ACK

默认每包 1280 字节数据（1280+16 = 1296 字节 UDP payload），
对应 IP 包 1296+8+20 = 1324 < 1500 MTU，安全。

用法:
    python3 udp_send_image.py logo.bin                      # 发到槽位 0 并立即显示
    python3 udp_send_image.py logo.bin --slot 2             # 存进槽位 2 并显示
    python3 udp_send_image.py logo.bin --slot 2 --no-swap   # 只存不显示（预载素材）
    python3 udp_send_image.py logo.bin --dbuf               # 双缓冲：板端挑不显示的槽位写
    python3 udp_send_image.py logo.bin --ack                # 等板子回执，报告丢包+校验和
    python3 udp_send_image.py logo.bin --ack --retry 3      # 不完整就整帧重传
    python3 udp_send_image.py logo.bin --dry-run            # 只看分包结果

要一步到位（JPG/PNG -> 自适应 -> 发送），用同目录的 send_image.py。
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

FLAG_START = 0x01
FLAG_END = 0x02
FLAG_SWAP = 0x04
FLAG_ACK = 0x08
FLAG_DBUF = 0x10            # 双缓冲：由 FPGA 挑"当前没在显示"的那块

# magic / frame_id / packet_idx / total_pkts / payload_len / slot / flags / byte_offset
HEADER_FMT = ">HHHHHBBI"
HEADER_SIZE = struct.calcsize(HEADER_FMT)      # = 16 字节

# 板端回执，24 字节
ACK_MAGIC = 0xA55B
# magic frame_id rx_bytes expect_bytes slot status disp_slot rsv ck_sum ck_xor
ACK_FMT = ">HHIIBBBBII"
ACK_SIZE = struct.calcsize(ACK_FMT)            # = 24 字节

ACK_ST_FRAME_OK = 0x01      # 字节数对上了
ACK_ST_CAL_DONE = 0x02      # DDR3 校准完成
ACK_ST_NO_ARP = 0x04        # 板端 ARP 表未命中，回执本身可能没发出来
ACK_ST_SEQ_ERR = 0x08       # packet_idx 断号/重复，或 frame_id 不一致
ACK_ST_FIFO_OVF = 0x10      # 板端 FIFO 溢出，丢过拍

DEFAULT_IP = "192.168.0.2"       # 板子 IP
DEFAULT_PORT = 8080              # 板子 UDP 端口
SCREEN_WIDTH = 1280
SCREEN_HEIGHT = 720
FRAME_SIZE = SCREEN_WIDTH * SCREEN_HEIGHT * 2

SLOT_SIZE = 2 * 1024 * 1024      # 每个图片槽位 2 MiB
SLOT_COUNT = 8                   # 与 FPGA 端 SLOT_COUNT 对应

# 每包图片数据字节数：
#   必须同时满足：① 16 字节对齐（DDR3 AXI 是 128-bit）；② 偶数（RGB565 2B/像素）
#   1280 = 640 像素 = 半行（1280 像素一行），1280/16 = 80 个 128-bit beat = 5 个 16-beat 突发
DEFAULT_CHUNK = 1280

def frame_checksum(data):
    """和 FPGA 端同口径的帧校验和，返回 (ck_sum, ck_xor)，都是 32 位。

    FPGA 侧对每个真正写进 DDR 的 128-bit 字做两件事：
        ck_sum += wdata[63:0] + wdata[127:64]     （64 位自然回绕）
        ck_xor ^= wdata                           （128 位）
    wdata 是按包内字节序组装的小端字：前 8 字节在低位，后 8 字节在高位。

    这里用 numpy 一次算完：加法和异或都满足交换律结合律，所以不必按顺序
    逐字累加，结果和 FPGA 的逐拍累加完全一样。
    """
    try:
        import numpy as np
    except ImportError as exc:
        raise ValueError(f"帧校验和需要 NumPy：{exc}") from exc

    if len(data) % 16:
        data = data + bytes(16 - (len(data) % 16))

    w = np.frombuffer(data, dtype="<u8")
    lo = w[0::2]                       # 每个 16 字节字的前 8 字节
    hi = w[1::2]                       # 后 8 字节

    mask64 = 0xFFFFFFFFFFFFFFFF
    s = (int(np.sum(lo, dtype=np.uint64)) + int(np.sum(hi, dtype=np.uint64))) & mask64
    x = int(np.bitwise_xor.reduce(lo)) | (int(np.bitwise_xor.reduce(hi)) << 64)

    ck_sum = ((s & 0xFFFFFFFF) ^ (s >> 32)) & 0xFFFFFFFF
    ck_xor = ((x & 0xFFFFFFFF) ^ ((x >> 32) & 0xFFFFFFFF)
              ^ ((x >> 64) & 0xFFFFFFFF) ^ ((x >> 96) & 0xFFFFFFFF)) & 0xFFFFFFFF
    return ck_sum, ck_xor


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


def check_slot(slot):
    if not (0 <= slot < SLOT_COUNT):
        raise ValueError(f"槽位必须在 0..{SLOT_COUNT - 1} 之间，实际是 {slot}")
    return slot


def make_header(frame_id, pkt_idx, total, payload_len, slot, flags, byte_offset):
    """拼一个 16 字节包头。"""
    return struct.pack(
        HEADER_FMT,
        MAGIC,
        frame_id & 0xFFFF,
        pkt_idx & 0xFFFF,
        total & 0xFFFF,
        payload_len & 0xFFFF,
        slot & 0xFF,
        flags & 0xFF,
        byte_offset & 0xFFFFFFFF,
    )


def build_packets(data, slot, frame_id, auto_swap, want_ack, chunk, dbuf=False):
    """把整帧数据切成 [(header, payload_bytes), ...]，含 START / END。

    长度会补齐到 16 字节的倍数：板端 DDR3 AXI 是 128-bit，
    每拍固定 16 字节，非对齐的尾巴会被直接丢掉。

    dbuf=True 时 slot 字段没有意义 —— 板端会忽略它，自己挑"当前没在显示"
    的那一块写。这样 PC 不需要知道板子现在显示哪个槽位。
    """
    if len(data) % 16 != 0:
        data = data + bytes(16 - (len(data) % 16))

    total_bytes = len(data)
    total_pkts = (total_bytes + chunk - 1) // chunk

    frame_flags = ((FLAG_SWAP if auto_swap else 0)
                   | (FLAG_ACK if want_ack else 0)
                   | (FLAG_DBUF if dbuf else 0))

    packets = [
        # START：byte_offset 借用来放“本帧总字节数”
        (make_header(frame_id, 0, total_pkts, 0, slot,
                     FLAG_START | frame_flags, total_bytes), b"")
    ]

    for i in range(total_pkts):
        off = i * chunk
        payload = data[off:off + chunk]
        packets.append(
            (make_header(frame_id, i, total_pkts, len(payload), slot, 0, off),
             payload)
        )

    # END：byte_offset 借用来放“实际发了多少包”
    packets.append(
        (make_header(frame_id, 0, total_pkts, 0, slot,
                     FLAG_END | frame_flags, total_pkts), b"")
    )

    return packets, total_pkts, total_bytes


def send_packets(sock, packets, target, gap=0.0, progress=True):
    """把 build_packets() 的结果依次发出去。返回 (发送字节数, 耗时秒)。"""
    t0 = time.time()
    sent_bytes = 0
    total = len(packets)
    step = max(1, total // 20)

    for i, (hdr, payload) in enumerate(packets):
        sock.sendto(hdr + payload, target)
        sent_bytes += len(hdr) + len(payload)

        if gap > 0:
            time.sleep(gap)

        if progress and ((i + 1) % step == 0 or (i + 1) == total):
            pct = (i + 1) * 100 // total
            print(f"  进度 {i + 1}/{total} ({pct}%)  "
                  f"已发 {sent_bytes / 1024:.0f} KiB")

    return sent_bytes, time.time() - t0


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
    result, content_size = resize_adaptive(
        source, (SCREEN_WIDTH, SCREEN_HEIGHT), mode, 1.20
    )
    fitted = rgb888_to_rgb565(result, endian).tobytes(order="C")
    fitted_meta = dict(meta)
    fitted_meta.update({
        "source_width": src_width,
        "source_height": src_height,
        "width": SCREEN_WIDTH,
        "height": SCREEN_HEIGHT,
        "content_width": content_size[0],
        "content_height": content_size[1],
        "resize_mode": mode,
        "size_bytes": len(fitted),
    })
    return fitted, fitted_meta


def wait_for_ack(sock, frame_id, timeout):
    """等板端回执。返回 dict 或 None。

    没等到回执不算失败：图片很可能已经正常显示了，回执只是额外确认。
    """
    deadline = time.time() + timeout
    sock.settimeout(0.3)

    seen = 0
    while time.time() < deadline:
        try:
            rdata, raddr = sock.recvfrom(65535)
        except socket.timeout:
            continue
        except OSError:
            break

        if len(rdata) < ACK_SIZE:
            seen += 1
            continue

        try:
            (magic, ack_frame, rx_bytes, expect, slot, status,
             disp_slot, _rsv, ck_sum, ck_xor) = \
                struct.unpack(ACK_FMT, rdata[:ACK_SIZE])
        except struct.error:
            seen += 1
            continue

        if magic != ACK_MAGIC:
            seen += 1
            continue

        return {
            "frame_id": ack_frame,
            "rx_bytes": rx_bytes,
            "expect_bytes": expect,
            "slot": slot,
            "status": status,
            "disp_slot": disp_slot,
            "ck_sum": ck_sum,
            "ck_xor": ck_xor,
            "addr": raddr,
            "other_pkts": seen,
        }

    return None


def report_ack(ack, chunk, dt, local_ck=None):
    """把回执翻译成人话。返回 True 表示这一帧可以认为是好的。"""
    print()
    print("-" * 60)

    if ack is None:
        print("[WARN] 没等到 FPGA 回执。可能原因：")
        print("       1. bit 不是这一版（旧版没有回执功能）")
        print("       2. 电脑 IP 不是 192.168.0.3，板子的 ARP 请求没人应答")
        print("       3. 板子 ARP 表没能解析到电脑 MAC（防火墙拦了 ARP？）")
        print("       —— 图片本身很可能已经正常显示了，回执只是额外确认。")
        print("-" * 60)
        return None

    rx = ack["rx_bytes"]
    expect = ack["expect_bytes"]
    status = ack["status"]

    print(f"FPGA 确认  : Frame {ack['frame_id']}  写入槽位 {ack['slot']}"
          f"  当前显示槽位 {ack['disp_slot']}")
    print(f"板端收到   : {rx} Byte ({rx / 1024 / 1024:.3f} MiB)")
    print(f"声明总长   : {expect} Byte ({expect / 1024 / 1024:.3f} MiB)")

    problems = []

    # ---- 1. 字节数 ----
    if status & ACK_ST_FRAME_OK and rx == expect:
        print("字节数     : OK")
    else:
        lost = expect - rx
        approx = (lost + chunk - 1) // chunk if chunk else 0
        problems.append(f"字节数少了 {lost} Byte（约 {approx} 个包）")
        print(f"字节数     : 不完整，少了 {lost} Byte（约 {approx} 个包）")

    # ---- 2. 包序号连续性 ----
    if status & ACK_ST_SEQ_ERR:
        problems.append("packet_idx 断号/重复，或 frame_id 与 START 不一致")
        print("包序号     : 断号/重复，或混进了别的 frame_id 的包")
    else:
        print("包序号     : OK（0..N-1 连续，无重复）")

    # ---- 3. FIFO 溢出 ----
    if status & ACK_ST_FIFO_OVF:
        problems.append("板端 FIFO 溢出，丢过拍")
        print("板端 FIFO  : 溢出过 —— 发得太快，用更大的 --gap 重发")
    else:
        print("板端 FIFO  : OK")

    # ---- 4. 帧校验和 ----
    if local_ck is not None:
        lsum, lxor = local_ck
        if (lsum, lxor) == (ack["ck_sum"], ack["ck_xor"]):
            print(f"帧校验和   : OK  (sum={lsum:08X} xor={lxor:08X})")
        else:
            problems.append("帧校验和不一致，DDR 里的数据和发出的不一致")
            print("帧校验和   : 不一致！")
            print(f"             PC  发送 = sum {lsum:08X}  xor {lxor:08X}")
            print(f"             板端写入 = sum {ack['ck_sum']:08X}  "
                  f"xor {ack['ck_xor']:08X}")
            print("             —— 这不是丢包，是板端写 DDR 的路径算错了")

    if ack["other_pkts"]:
        print(f"（另有 {ack['other_pkts']} 个非回执包被忽略）")

    if status & ACK_ST_NO_ARP:
        print("[WARN] 板端 ARP 表未命中：这条回执本身可能发不出去，")
        print("       或者回执里报的槽位/状态是上一帧的。")

    if not (status & ACK_ST_CAL_DONE):
        print("[WARN] 板端 DDR3 还没校准完，这一帧的写入结果不可信。")

    print()
    if problems:
        print("结论       : 这一帧不可用，板端**没有**切屏。")
        for p in problems:
            print(f"             - {p}")
    else:
        print("结论       : 帧完整，板端会在下一个 VSYNC 切过去。")

    print(f"耗时       : {dt:.3f} s")
    print("-" * 60)
    return not problems


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
    parser.add_argument("--frame-id", type=int, default=None,
                        help="帧号，默认用当前时间的低 16 位")
    parser.add_argument("--gap", type=float, default=0.0002,
                        help="每包发送间隔(秒)，默认 0.0002（板端 UDP RAM 会被下一包覆盖，先保守间隔）")
    parser.add_argument("--local-port", type=int, default=DEFAULT_PORT,
                        help=f"本地绑定端口（收回执用），默认 {DEFAULT_PORT}")
    parser.add_argument("--dry-run", action="store_true",
                        help="只显示分包结果，不实际发送")
    parser.add_argument("--verify", action="store_true",
                        help="发送后监听回环数据")
    parser.add_argument("--verify-timeout", type=float, default=5.0,
                        help="回环监听超时(秒)，默认 5")

    # ---- 适配 ----
    parser.add_argument(
        "--mode",
        choices=("fit", "fill", "stretch", "smart", "contain", "cover"),
        default="fit",
        help="非 1280x720 输入的适配方式："
             "fit=保持比例完整显示补黑边（默认），"
             "fill=保持比例铺满居中裁边，"
             "stretch=强行拉伸",
    )
    parser.add_argument(
        "--fit-mode",
        dest="mode",
        choices=("fit", "fill", "stretch", "smart", "contain", "cover"),
        help="--mode 的旧名字，等价",
    )
    parser.add_argument(
        "--no-auto-fit",
        action="store_true",
        help="禁止发送前自动适配；尺寸不是 1280x720 时直接报错",
    )

    # ---- 槽位 / 双缓冲 ----
    parser.add_argument(
        "--slot", type=int, default=None,
        help=f"目标图片槽位 0..{SLOT_COUNT - 1}（每槽 {SLOT_SIZE // 1024 // 1024} MiB），"
             "默认 0；配合 --no-swap 就是“预载素材”",
    )
    parser.add_argument(
        "--dbuf", action="store_true",
        help="双缓冲：让板端挑'当前没在显示'的那一块写，写完自动切过去。"
             "PC 不需要知道板子现在显示哪个槽位，按过键也不会错乱",
    )
    parser.add_argument(
        "--no-swap", dest="auto_swap", action="store_false", default=True,
        help="只写槽位，不把显示切过去（预载多张图，之后用板载按键切换）",
    )

    # ---- 回执 ----
    parser.add_argument(
        "--ack", action="store_true",
        help="要求板端整帧完成后回执，并报告帧完整性（默认不发回执）",
    )
    parser.add_argument("--ack-timeout", type=float, default=3.0,
                        help="等回执的超时时间(秒)，默认 3")
    parser.add_argument(
        "--retry", type=int, default=2,
        help="板端报帧不完整时整帧重传的次数，默认 2（只在 --ack 时生效）。"
             "每次重传用新的 frame_id",
    )

    args = parser.parse_args()

    # ============================================================
    # 0. 解析槽位
    # ============================================================

    try:
        if args.dbuf and args.slot is not None:
            raise ValueError("--dbuf 和 --slot 不能同时用")
        # dbuf 时槽位由 FPGA 决定（它会挑当前没在显示的那一块），
        # 包头里的 slot 字段随便填，板端不看。
        slot = 0 if args.dbuf else check_slot(0 if args.slot is None else args.slot)
    except ValueError as exc:
        print(f"[ERROR] {exc}")
        sys.exit(1)

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
            data, fitted_meta = fit_to_screen(data, meta, args.mode)
            fit_info = None
            if fitted_meta is not None:
                fit_info = (
                    int(fitted_meta["source_width"]),
                    int(fitted_meta["source_height"]),
                    args.mode,
                    original_size,
                    int(fitted_meta.get("content_width", SCREEN_WIDTH)),
                    int(fitted_meta.get("content_height", SCREEN_HEIGHT)),
                )
                meta = fitted_meta
    except ValueError as exc:
        print(f"[ERROR] {exc}")
        sys.exit(1)

    size = len(data)

    # chunk 取偶 + 取 16 的倍数：DDR3 AXI 是 128-bit，包头必须 16 字节对齐
    chunk_size = args.chunk

    if chunk_size <= 0:
        print("[ERROR] --chunk 必须为正数")
        sys.exit(1)

    if chunk_size % 16 != 0:
        chunk_size -= chunk_size % 16
        if chunk_size == 0:
            print("[ERROR] --chunk 太小，取 16 的倍数后为 0")
            sys.exit(1)
        print(f"[WARN] chunk 自动调整为 16 的倍数：{chunk_size}")

    frame_id = args.frame_id
    if frame_id is None:
        frame_id = int(time.time()) & 0xFFFF

    # ============================================================
    # 2. 打印分包信息
    # ============================================================

    print("=" * 60)
    print("RGB565 图片 UDP 发送")
    print(f"输入文件   : {args.input}")

    if fit_info:
        src_w, src_h, fit_mode, original_size, cw, ch = fit_info
        print(f"自动适配   : {src_w} x {src_h} -> {SCREEN_WIDTH} x {SCREEN_HEIGHT}")
        print(f"适配模式   : {fit_mode}   有效内容 {cw} x {ch}")
        print(f"原始大小   : {original_size} Byte")

    if meta:
        print(f"分辨率     : {meta.get('width')} x {meta.get('height')}")
        print(f"像素格式   : {meta.get('pixel_format')}")

    print(f"数据大小   : {size} Byte ({size / 1024 / 1024:.3f} MiB)")
    print(f"每包数据   : {chunk_size} Byte")
    print(f"包头大小   : {HEADER_SIZE} Byte")
    print(f"目标       : {args.ip}:{args.port}")
    print(f"帧号       : {frame_id}")
    if args.dbuf:
        print("目标槽位   : 由板端决定（挑当前没在显示的那一块）")
    else:
        print(f"目标槽位   : {slot}  (DDR 偏移 0x{slot * SLOT_SIZE:08X})")
    print(f"整帧切屏   : {'是（等 VSYNC 切过去）' if (args.auto_swap or args.dbuf) else '否（只写槽位）'}")
    print(f"板端回执   : {'要' if args.ack else '不要'}")

    packets, total_pkts, total_bytes = build_packets(
        data, slot, frame_id, args.auto_swap, args.ack, chunk_size, args.dbuf
    )

    print(f"总包数     : {total_pkts} 个 DATA 包 + START/END，共 {len(packets)} 包")
    if args.ack:
        lsum, lxor = frame_checksum(data)
        print(f"帧校验和   : sum {lsum:08X}  xor {lxor:08X}")
    print("=" * 60)

    if total_pkts > 0xFFFF:
        print(f"[ERROR] 包数 {total_pkts} 超过 uint16 上限，请增大 --chunk")
        sys.exit(1)

    # ============================================================
    # 3. dry-run：只预览分包
    # ============================================================

    if args.dry_run:
        print()
        print("[dry-run] 前 3 包 + 最后 1 包预览：")

        preview = list(range(min(3, len(packets)))) + [len(packets) - 1]
        for i in sorted(set(preview)):
            hdr, payload = packets[i]
            print(f"  包{i}: 整包={len(hdr) + len(payload)}B  数据={len(payload)}B")
            print(f"        包头: {hdr.hex(' ')}")

        print()
        print("[dry-run] 未实际发送")
        return

    # ============================================================
    # 4. 发送（带重传）
    # ============================================================

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", args.local_port))

    target = (args.ip, args.port)
    local_ck = frame_checksum(data) if args.ack else None

    attempts = max(1, args.retry) if args.ack else 1
    verdict = None

    for attempt in range(1, attempts + 1):
        if attempt > 1:
            print()
            print("=" * 60)
            print(f"重传 第 {attempt}/{attempts} 次"
                  f"（上一帧板端没有确认完整）")
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
        print(f"发送包数   : {len(packets)}（{total_pkts} DATA + START + END）")
        print(f"发送字节   : {sent_bytes} Byte ({sent_bytes / 1024 / 1024:.3f} MiB)")
        print(f"耗时       : {dt:.3f} s")

        if dt > 0:
            print(f"速率       : {sent_bytes * 8 / dt / 1e6:.1f} Mbps"
                  f"  ({sent_bytes / 1024 / dt:.0f} KiB/s)")

        print("=" * 60)

        if not args.ack:
            break

        # ============================================================
        # 5. 等板端回执并判定
        # ============================================================

        print()
        print(f"等 FPGA 回执（最多 {args.ack_timeout}s）...")
        ack = wait_for_ack(sock, frame_id, args.ack_timeout)
        verdict = report_ack(ack, chunk_size, dt, local_ck)

        if verdict is None:
            print()
            print("[NOTE] 没收到回执，无法判断 —— 不再重传（重传也是一样）。")
            break

        if verdict:
            break

        if attempt == attempts:
            print()
            print(f"[FAIL] 重传 {attempts} 次仍未收全。建议加大包间隔后重来：")
            print(f"       --gap {max(args.gap * 5, 0.001):.4f}")

    # ============================================================
    # 7. 可选：监听回环
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
