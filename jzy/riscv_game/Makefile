# jzy/riscv_game —— 聚合 Makefile
#
#   make test               三套测试都跑（冻结基线 + 统一层 + BitBlt 适配层）
#   make native-test        冻结的 M1 基线测试（委托给 tests/Makefile）
#   make api-test           统一渲染层 + BitBlt 驱动/适配层
#   make riscv-build        RISC-V 交叉编译验证
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

LIB_SRCS    := $(wildcard $(RENDER_DIR)/*.c) $(wildcard $(DRIVER_DIR)/*.c)
TEST_API    := $(TESTS_DIR)/test_render_api.c
TEST_BITBLT := $(TESTS_DIR)/test_bitblt_api.c


# ---- B 组权威头文件 ----
# bitblt_api.h / bitblt_regs.h / framebuffer_layout.h 的唯一来源。
# 不复制、不软链，只加 include 路径——复制会制造第二份真相源。
# 拷进 BSP 后这些头在 standalone/driver/，standalone.mk 已经加过该路径。
BITBLT_INC_DIR ?= $(TOP)/../../04_project/bitblt_accel/sw/driver


# ---- 本机编译 ----
# 需要换编译器时用 make api-test CC=clang
CC := gcc

# 严格警告。个别环境需要临时放宽时用 make api-test WERROR=
WERROR    ?= -Werror
WARNFLAGS := -Wall -Wextra -Wpedantic $(WERROR)

# ASan 抓数组之外的越界，UBSan 抓未定义行为。
# -fno-sanitize-recover=all 让 UBSan 命中后直接终止，否则只打警告、退出码仍是 0。
SANFLAGS := -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer

INCFLAGS := -I$(RENDER_DIR) -I$(DRIVER_DIR) -I$(BITBLT_INC_DIR)

CFLAGS := -std=c99 -O1 -g $(WARNFLAGS) $(SANFLAGS) $(INCFLAGS)


# ---- RISC-V 交叉编译 ----
# 默认参数取自 2026.1 BSP 实际产物的 Tag_RISCV_arch：
#   rv32i2p1_m2p0_zicsr2p0_zifencei2p0_zmmul1p0，ABI 为 ilp32
CROSS_CC     ?= $(HOME)/efinity/efinity-riscv-ide-2026.1/toolchain/bin/riscv-none-elf-gcc
CROSS_PREFIX := $(patsubst %gcc,%,$(CROSS_CC))
CROSS_SIZE   := $(CROSS_PREFIX)size

RV_ARCH ?= rv32im_zicsr_zifencei
RV_ABI  ?= ilp32

CROSS_CFLAGS := -std=c99 -Os -g $(WARNFLAGS) -march=$(RV_ARCH) -mabi=$(RV_ABI) $(INCFLAGS)


.PHONY: all test native-test api-test riscv-build riscv-build-api riscv-build-hw \
        check check-hw-isolation check-no-addresses check-cross clean

# 交叉编译器存在性检查；所有交叉编译目标都依赖它
check-cross:
	@command -v $(CROSS_CC) >/dev/null 2>&1 || { \
	  echo "找不到交叉编译器：$(CROSS_CC)"; \
	  echo "可用 make CROSS_CC=/path/to/riscv-none-elf-gcc 指定"; \
	  exit 1; }

all: test


# ---- 本机测试 ----

test: native-test api-test

native-test:
	@$(MAKE) -C $(TESTS_DIR) native-test

api-test: $(API_BUILD)/test_render_api $(API_BUILD)/test_bitblt_api
	@echo "== 运行统一渲染层测试（CC=$(CC)，ASan/UBSan 已开启）=="
	@$(API_BUILD)/test_render_api
	@echo "== 运行 BitBlt 驱动 / 适配层测试 =="
	@$(API_BUILD)/test_bitblt_api
	@echo "== 统一层与 BitBlt 适配层测试通过 =="

$(API_BUILD)/test_render_api: $(TEST_API) $(LIB_SRCS)
	@mkdir -p $(API_BUILD)
	$(CC) $(CFLAGS) $(TEST_API) $(LIB_SRCS) -o $@

$(API_BUILD)/test_bitblt_api: $(TEST_BITBLT) $(LIB_SRCS)
	@mkdir -p $(API_BUILD)
	$(CC) $(CFLAGS) $(TEST_BITBLT) $(LIB_SRCS) -o $@


# ---- RISC-V 交叉编译验证（只证明能编能链，产物不在本机运行）----

riscv-build: riscv-build-api
	@$(MAKE) -C $(TESTS_DIR) riscv-build
	@echo "== RISC-V 交叉编译验证通过（冻结基线 + 统一层 + 适配层）=="

riscv-build-api: $(API_BUILD)/test_render_api.elf $(API_BUILD)/test_bitblt_api.elf

$(API_BUILD)/test_render_api.elf: $(TEST_API) $(LIB_SRCS) check-cross
	@mkdir -p $(API_BUILD)
	$(CROSS_CC) $(CROSS_CFLAGS) $(TEST_API) $(LIB_SRCS) -static -o $@
	@$(CROSS_SIZE) $@

$(API_BUILD)/test_bitblt_api.elf: $(TEST_BITBLT) $(LIB_SRCS) check-cross
	@mkdir -p $(API_BUILD)
	$(CROSS_CC) $(CROSS_CFLAGS) $(TEST_BITBLT) $(LIB_SRCS) -static -o $@
	@$(CROSS_SIZE) $@


# ---- 开启硬件分支的编译检查 ----
# 只编译库，不含测试（测试里禁止 BITBLT_ENABLE_HW_ACCESS）。
# 这一步确保 bitblt_api.c 里被 #ifdef 包住的真实寄存器分支不是死代码：
# 它会真的 include B 的 bitblt_regs.h、用到 fence 指令和被寄存器枚举值。

riscv-build-hw: check-cross
	@test -f $(BITBLT_INC_DIR)/bitblt_api.h || { \
	  echo "找不到 bitblt_api.h：$(BITBLT_INC_DIR)"; \
	  echo "可用 make riscv-build-hw BITBLT_INC_DIR=/path/to/driver 指定"; \
	  exit 1; }
	@mkdir -p $(API_BUILD)/hw
	cd $(API_BUILD)/hw && $(CROSS_CC) $(CROSS_CFLAGS) \
	  -DBITBLT_ENABLE_HW_ACCESS -c $(abspath $(LIB_SRCS))
	@echo "== 硬件分支编译检查通过（BITBLT_ENABLE_HW_ACCESS）=="


# ---- 静态约束检查 ----

check: check-hw-isolation check-no-addresses

# 全树只允许一个文件引用 B 组的寄存器定义，杜绝第二份寄存器真相源。
# 寄存器访问现在集中在真正的驱动 bitblt_api.c 里；旧的 gpu.c 已降级为兼容层，
# 不再包含任何寄存器分支。
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
	  */driver/bitblt_api.c) echo "通过：只有 driver/bitblt_api.c 引用 bitblt_regs.h";; \
	  *) echo "失败：引用点是 $$files，应为 driver/bitblt_api.c"; exit 1;; \
	esac

# 库代码里不得出现任何已知的真实地址。
#
# 地址现在【已经冻结】——权威来源是 B 的 framebuffer_layout.h 与 bitblt_regs.h。
# 这条检查的意义不是"地址还没定"，而是"地址已定，但库代码仍不得硬编码它们"：
# 地址一律由参数传入（gpu_limits_t / render_surface_t.phys_base）或由
# render_limits_from_layout() 从权威头文件取。
check-no-addresses:
	@if grep -rnE '0x([Ee]1000000|[Ee]1100000|01000000|01800000|02000000|04000000|01100000|01200000)' \
	    $(RENDER_DIR) $(DRIVER_DIR) 2>/dev/null; then \
	  echo "失败：库代码里出现了硬编码的真实地址（应引用 framebuffer_layout.h / bitblt_regs.h）"; \
	  exit 1; \
	fi
	@echo "通过：render/ 与 driver/ 里没有硬编码的真实地址"


clean:
	@$(MAKE) -C $(TESTS_DIR) clean
	rm -rf $(API_BUILD)
	@echo "已清理 $(API_BUILD)"
