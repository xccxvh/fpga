# jzy/riscv_game —— 聚合 Makefile
#
#   make test               两套测试都跑（冻结基线 + 统一层）
#   make native-test        冻结的 M1 基线测试（委托给 tests/Makefile）
#   make api-test           统一渲染层 / 后端分发 / 约束校验 / 驱动骨架
#   make riscv-build        RISC-V 交叉编译验证（冻结基线 + 统一层）
#   make riscv-build-hw     额外开启 BITBLT_ENABLE_HW_ACCESS 做编译检查
#   make check              静态约束检查（寄存器引用隔离、无硬编码地址）
#   make clean
#
# 注意：测试依赖 assert 判定，构建时禁止定义 NDEBUG。
#       源码里各有 #error 兜底，误加会直接编译失败。
#
# 本文件不改动 tests/Makefile —— 那套冻结基线的构建方式保持原样。

TOP        := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
RENDER_DIR := $(TOP)/render
DRIVER_DIR := $(TOP)/driver
TESTS_DIR  := $(TOP)/tests

# 统一层的构建产物放在冻结基线的 build 目录下，这样无需改动 .gitignore
API_BUILD  := $(TESTS_DIR)/build/api

LIB_SRCS := $(wildcard $(RENDER_DIR)/*.c) $(wildcard $(DRIVER_DIR)/*.c)
API_TEST := $(TESTS_DIR)/test_render_api.c

# ---- 本机编译 ----
# 需要换编译器时用 make api-test CC=clang
CC := gcc

# 严格警告。个别环境需要临时放宽时用 make api-test WERROR=
WERROR    ?= -Werror
WARNFLAGS := -Wall -Wextra -Wpedantic $(WERROR)

# ASan 抓数组之外的越界，UBSan 抓未定义行为。
# -fno-sanitize-recover=all 让 UBSan 命中后直接终止，否则只打警告、退出码仍是 0。
SANFLAGS := -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer

CFLAGS := -std=c99 -O1 -g $(WARNFLAGS) $(SANFLAGS) -I$(RENDER_DIR) -I$(DRIVER_DIR)


# ---- RISC-V 交叉编译 ----
# 默认参数取自 2026.1 BSP 实际产物的 Tag_RISCV_arch：
#   rv32i2p1_m2p0_zicsr2p0_zifencei2p0_zmmul1p0，ABI 为 ilp32
CROSS_CC     ?= $(HOME)/efinity/efinity-riscv-ide-2026.1/toolchain/bin/riscv-none-elf-gcc
CROSS_PREFIX := $(patsubst %gcc,%,$(CROSS_CC))
CROSS_SIZE   := $(CROSS_PREFIX)size

RV_ARCH ?= rv32im_zicsr_zifencei
RV_ABI  ?= ilp32

CROSS_CFLAGS := -std=c99 -Os -g $(WARNFLAGS) -march=$(RV_ARCH) -mabi=$(RV_ABI)

# B 组的寄存器定义位置。不复制、不软链，只加 include 路径。
# 拷进 BSP 后这个头文件在 standalone/driver/，standalone.mk 已经加过该路径。
BITBLT_INC_DIR ?= $(TOP)/../../04_project/bitblt_accel/sw/driver


.PHONY: all test native-test api-test riscv-build riscv-build-hw check \
        check-hw-isolation check-no-addresses clean

all: test


# ---- 本机测试 ----

test: native-test api-test

native-test:
	@$(MAKE) -C $(TESTS_DIR) native-test

api-test: $(API_BUILD)/test_render_api
	@echo "== 运行统一渲染层测试（CC=$(CC)，ASan/UBSan 已开启）=="
	@$(API_BUILD)/test_render_api
	@echo "== 统一渲染层测试通过 =="

$(API_BUILD)/test_render_api: $(API_TEST) $(LIB_SRCS)
	@mkdir -p $(API_BUILD)
	$(CC) $(CFLAGS) $(API_TEST) $(LIB_SRCS) -o $@


# ---- RISC-V 交叉编译验证（只证明能编能链，产物不在本机运行）----

riscv-build: riscv-build-api
	@$(MAKE) -C $(TESTS_DIR) riscv-build
	@echo "== RISC-V 交叉编译验证通过（冻结基线 + 统一层）=="

riscv-build-api: $(API_BUILD)/test_render_api.elf

$(API_BUILD)/test_render_api.elf: $(API_TEST) $(LIB_SRCS)
	@command -v $(CROSS_CC) >/dev/null 2>&1 || { \
	  echo "找不到交叉编译器：$(CROSS_CC)"; \
	  echo "可用 make riscv-build CROSS_CC=/path/to/riscv-none-elf-gcc 指定"; \
	  exit 1; \
	}
	@mkdir -p $(API_BUILD)
	$(CROSS_CC) $(CROSS_CFLAGS) -I$(RENDER_DIR) -I$(DRIVER_DIR) \
	  $(API_TEST) $(LIB_SRCS) -static -o $@
	@$(CROSS_SIZE) $@


# ---- 开启硬件分支的编译检查 ----
# 只编译库，不含测试（测试里禁止 BITBLT_ENABLE_HW_ACCESS）。
# 这一步确保 gpu.c 里被 #ifdef 包住的真实寄存器分支不是死代码。

riscv-build-hw:
	@command -v $(CROSS_CC) >/dev/null 2>&1 || { \
	  echo "找不到交叉编译器：$(CROSS_CC)"; exit 1; }
	@test -f $(BITBLT_INC_DIR)/bitblt_regs.h || { \
	  echo "找不到 bitblt_regs.h：$(BITBLT_INC_DIR)"; \
	  echo "可用 make riscv-build-hw BITBLT_INC_DIR=/path/to/driver 指定"; \
	  exit 1; }
	@mkdir -p $(API_BUILD)/hw
	cd $(API_BUILD)/hw && $(CROSS_CC) $(CROSS_CFLAGS) \
	  -DBITBLT_ENABLE_HW_ACCESS -I$(RENDER_DIR) -I$(DRIVER_DIR) \
	  -I$(BITBLT_INC_DIR) -c $(abspath $(LIB_SRCS))
	@echo "== 硬件分支编译检查通过（BITBLT_ENABLE_HW_ACCESS）=="


# ---- 静态约束检查 ----

check: check-hw-isolation check-no-addresses

# 全树只允许一个文件引用 B 组的寄存器定义，杜绝第二份寄存器真相源。
check-hw-isolation:
	@files=$$(grep -rlE '^[[:space:]]*#[[:space:]]*include[[:space:]]*"bitblt_regs\.h"' \
	    $(RENDER_DIR) $(DRIVER_DIR) || true); \
	count=$$(printf '%s\n' "$$files" | grep -c . || true); \
	if [ "$$count" -ne 1 ]; then \
	  echo "失败：应有且仅有 1 个文件引用 bitblt_regs.h，实际 $$count 个"; \
	  printf '%s\n' "$$files"; \
	  exit 1; \
	fi; \
	case "$$files" in \
	  */driver/gpu.c) echo "通过：只有 driver/gpu.c 引用 bitblt_regs.h";; \
	  *) echo "失败：引用点是 $$files，应为 driver/gpu.c"; exit 1;; \
	esac

# 库代码里不得出现任何已知的真实地址——地址都由参数传入或由平台代码填写。
check-no-addresses:
	@if grep -rnE '0x[Ee]1000000|0x01100000|0x01200000' \
	    $(RENDER_DIR) $(DRIVER_DIR) 2>/dev/null; then \
	  echo "失败：库代码里出现了硬编码的真实地址"; \
	  exit 1; \
	fi
	@echo "通过：render/ 与 driver/ 里没有硬编码的真实地址"


clean:
	@$(MAKE) -C $(TESTS_DIR) clean
	rm -rf $(API_BUILD)
	@echo "已清理 $(API_BUILD)"
