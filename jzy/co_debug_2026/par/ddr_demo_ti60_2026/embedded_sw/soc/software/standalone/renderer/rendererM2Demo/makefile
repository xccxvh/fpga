################################################################################
# rendererM2Demo -- real BitBlt + CLINT board smoke test
################################################################################

PROJ_NAME=rendererM2Demo
STANDALONE =../..

RENDER_ROOT ?= $(HOME)/code/fpga/jzy/riscv_game
BITBLT_INC_DIR ?= $(HOME)/code/fpga/04_project/bitblt_accel/sw/driver

ifeq ($(wildcard $(RENDER_ROOT)/tests/test_bitblt_board.c),)
$(error M2 board test not found: $(RENDER_ROOT)/tests/test_bitblt_board.c)
endif

ifeq ($(wildcard $(BITBLT_INC_DIR)/bitblt_api.h),)
$(error authoritative BitBlt headers not found: $(BITBLT_INC_DIR))
endif

SRCS = 	$(RENDER_ROOT)/tests/test_bitblt_board.c \
	$(RENDER_ROOT)/driver/bitblt_api.c \
	${STANDALONE}/common/start.S \
	${STANDALONE}/common/trap.S

CFLAGS += -I$(RENDER_ROOT)/driver
CFLAGS += -I$(BITBLT_INC_DIR)
CFLAGS += -DBITBLT_ENABLE_HW_ACCESS

include ${STANDALONE}/common/bsp.mk
include ${STANDALONE}/common/riscv64-unknown-elf.mk
include ${STANDALONE}/common/standalone.mk

ifeq ($(wildcard ${BSP_PATH}/include/bsp.h),)
$(error BSP not found (BSP_PATH=${BSP_PATH}); use BSP=efinix/EfxSapphireSoc)
endif

LDSCRIPT = ${BSP_PATH}/linker/default.ld
