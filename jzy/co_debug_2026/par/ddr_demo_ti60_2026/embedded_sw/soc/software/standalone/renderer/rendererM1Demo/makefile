################################################################################
# rendererM1Demo —— M1 渲染层板端 smoke test
#
# 基于官方 uartEchoDemo 的结构新建，不改动 uartEchoDemo 原件。
# 与 uartEchoDemo 的差别只有两处：
#   1. 源文件除了 common/start.S 与 common/trap.S，还包含渲染层与本次测试
#   2. 增加渲染层头文件搜索路径
#
# 构建（在 Efinity RISC-V IDE 里等同于 Build；命令行等价写法）：
#   make BSP=EfxSapphireSoc
#
# BSP 变量没有默认值，必须由调用方给定（IDE 会自动传）。
################################################################################

PROJ_NAME=rendererM1Demo

STANDALONE =../..

# 渲染层源码根目录（本仓库的 jzy/riscv_game）。
#
# 这里刻意【不复制】渲染层源码 —— 板端跑的就是 host 测试验证过的那一份，
# 免得出现第二份需要同步的副本。目录不同就覆盖：
#   make BSP=EfxSapphireSoc RENDER_ROOT=/path/to/riscv_game
RENDER_ROOT ?= $(HOME)/code/fpga/jzy/riscv_game

# B 组权威头文件目录：bitblt_api.h / bitblt_regs.h / framebuffer_layout.h。
# 渲染层直接引用它们，不复制、不软链。
BITBLT_INC_DIR ?= $(HOME)/code/fpga/04_project/bitblt_accel/sw/driver

ifeq ($(wildcard $(RENDER_ROOT)/render/renderer_sw.c),)
$(error 找不到渲染层源码 $(RENDER_ROOT)/render/renderer_sw.c；请用 RENDER_ROOT=/path/to/riscv_game 指定)
endif

ifeq ($(wildcard $(BITBLT_INC_DIR)/bitblt_api.h),)
$(error 找不到 B 的驱动头文件 $(BITBLT_INC_DIR)/bitblt_api.h；请用 BITBLT_INC_DIR=/path/to/driver 指定)
endif

# 注意：standalone.mk 会把所有源文件按 basename 平铺到 $(OBJDIR)/obj_files/，
# 所以加入的文件不能重名。下面这些 basename 互不冲突。
SRCS = 	$(RENDER_ROOT)/tests/test_render_board.c \
	$(wildcard $(RENDER_ROOT)/render/*.c) \
	$(wildcard $(RENDER_ROOT)/driver/*.c) \
	${STANDALONE}/common/start.S \
	${STANDALONE}/common/trap.S

CFLAGS += -I$(RENDER_ROOT)/render
CFLAGS += -I$(RENDER_ROOT)/driver
CFLAGS += -I$(BITBLT_INC_DIR)

# 注意：不要在这里定义 BITBLT_ENABLE_HW_ACCESS。
# 本 smoke test 只验证 CPU 后端，不访问 FPGA BitBlt 寄存器。

include ${STANDALONE}/common/bsp.mk
include ${STANDALONE}/common/riscv64-unknown-elf.mk
include ${STANDALONE}/common/standalone.mk

# BSP 没有默认值，必须由调用方给定（IDE 会自动传）。
# 这个检查要放在 include bsp.mk 之后：BSP_PATH 由 bsp.mk 定义。
ifeq ($(wildcard ${BSP_PATH}/include/bsp.h),)
$(error 找不到 BSP（BSP_PATH=${BSP_PATH}）；请用 BSP=EfxSapphireSoc 指定)
endif

LDSCRIPT = ${BSP_PATH}/linker/default.ld
