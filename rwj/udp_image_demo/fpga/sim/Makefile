#==========================================================================
# UDP 收图通路 RTL 回归测试
#
#   make test        跑全部
#   make hdr-parse   只跑包头解析
#   make clean
#
#--------------------------------------------------------------------------
# iverilog 从哪来
#
# 首选：sudo apt install -y iverilog      （装到 /usr/bin，下面自动用）
#
# 没有 sudo 也行 —— 这个包不需要 root，解出来直接用：
#     mkdir -p ~/.local/ivl && cd ~/.local/ivl
#     apt-get download iverilog && dpkg -x iverilog_*.deb .
#     make hdr-parse IVL_ROOT=~/.local/ivl/root
#
# IVL_ROOT 指定后，Makefile 会自动用里面的 iverilog/vvp，
# 并用 -B / -M 指到对应的标准库目录（否则它只会去 /usr/lib 找）。
#--------------------------------------------------------------------------
# 注意 iverilog 10.3 的 SystemVerilog 支持很有限，写 TB 时避开：
#   · task 的空参列表       task automatic foo;      不要写成 foo()
#   · 关联数组              logic x [ int ];
#   · 队列的两级索引        q[0][7:0]      先赋给临时变量
#==========================================================================

IVL_ROOT ?=
BUILD    := build
RTL      := ../rtl

ifeq ($(IVL_ROOT),)
  IVERILOG := iverilog
  VVP      := vvp
  IVL_B    :=
  VVP_M    :=
else
  IVERILOG := $(IVL_ROOT)/usr/bin/iverilog
  VVP      := $(IVL_ROOT)/usr/bin/vvp
  IVL_B    := -B $(IVL_ROOT)/usr/lib/x86_64-linux-gnu/ivl
  VVP_M    := -M $(IVL_ROOT)/usr/lib/x86_64-linux-gnu/ivl
endif

IVLFLAGS := -g2012 -Wall $(IVL_B)

.PHONY: test hdr-parse frame-status clean

test: hdr-parse frame-status

#--------------------------------------------------------------------------
# udp_hdr_parse —— 16 字节包头解析、magic 校验、128-bit 组装、溢出粘滞
#
# 只编译需要的两个文件：解析模块 + 真实的 dpram（1 拍读延迟）。
# 不涉及 MAC / RGMII —— 那两层用的是 Altera DDIO 原语，仿真不了，
# 也正是这段逻辑当初被提取出来的原因。
#--------------------------------------------------------------------------
hdr-parse: $(BUILD)/tb_udp_hdr_parse.vvp
	$(VVP) $(VVP_M) $<

$(BUILD)/tb_udp_hdr_parse.vvp: tb_udp_hdr_parse.sv \
	$(RTL)/ge/udp_hdr_parse.v $(RTL)/ge/mac/dpram.v | $(BUILD)
	$(IVERILOG) $(IVLFLAGS) -s tb_udp_hdr_parse -o $@ $^

$(BUILD):
	mkdir -p $@

#--------------------------------------------------------------------------
# frame_status_apb —— 快照 / ACK / ERR_STICKY / 跨时钟握手
#
# 两个时钟域刻意不同频（evt 108MHz / apb 100MHz），否则 CDC 问题测不出来。
# 覆盖 B/C 提的四个场景：ACK 与新帧同拍、SEQ 变化期间读取、
# BRESP 错误、SEQ 回绕。
#--------------------------------------------------------------------------
frame-status: $(BUILD)/tb_frame_status_apb.vvp
	$(VVP) $(VVP_M) $<

$(BUILD)/tb_frame_status_apb.vvp: tb_frame_status_apb.sv \
	$(RTL)/frame_status_apb_slave.v $(RTL)/frame_status_apb.v | $(BUILD)
	$(IVERILOG) $(IVLFLAGS) -s tb_frame_status_apb -o $@ $^

clean:
	rm -rf $(BUILD)
