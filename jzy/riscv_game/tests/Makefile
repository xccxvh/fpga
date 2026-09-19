# CPU 渲染器测试（tests/）
#
#   make native-test   本机编译（严格警告 + ASan/UBSan）并运行全部测试
#   make riscv-build   RISC-V 交叉编译验证（只编译链接，不运行）
#   make clean         删除构建产物
#
# 注意：测试依赖 assert 判定，构建时禁止定义 NDEBUG。
#       定义了 NDEBUG 断言会被整体移除，测试将假通过（退出码仍然是 0）。
#       test_renderer.c 顶部有 #error 兜底，误加 NDEBUG 会直接编译失败。

# 本文件所在目录，支持从仓库任意位置执行：make -f tests/Makefile native-test
TEST_DIR   := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
RENDER_DIR := $(TEST_DIR)/../render
BUILD_DIR  := $(TEST_DIR)/build

# renderer_sw.h 必须列进依赖：它承载 pixel_t 与格式开关，
# 只改头文件不改 .c 时，没有这条依赖就不会重编，测试会跑旧二进制而"通过"——
# 那正是本项目最忌讳的假通过。
SRCS := $(TEST_DIR)/test_renderer.c $(RENDER_DIR)/renderer_sw.c
HDRS := $(RENDER_DIR)/renderer_sw.h


# ---- 本机编译 ----
# 需要换编译器时用 make native-test CC=clang
CC := gcc

# 严格警告。个别环境需要临时放宽时用：make native-test WERROR=
WERROR    ?= -Werror
WARNFLAGS := -Wall -Wextra -Wpedantic $(WERROR)

# ASan 抓数组之外的越界读写，UBSan 抓未定义行为。
# -fno-sanitize-recover=all 让 UBSan 命中后直接终止，否则它只打印一条
# 警告就继续跑，退出码仍然是 0，测试会假通过。
SANFLAGS := -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer

CFLAGS := -std=c99 -O1 -g $(WARNFLAGS) $(SANFLAGS)


# ---- RISC-V 交叉编译 ----
# 默认参数取自 2026.1 BSP 实际产物的 Tag_RISCV_arch：
#   rv32i2p1_m2p0_zicsr2p0_zifencei2p0_zmmul1p0，ABI 为 ilp32
# 如果 BSP 后续打开了其它扩展，用 RV_ARCH / RV_ABI 覆盖。
CROSS_CC     ?= $(HOME)/efinity/efinity-riscv-ide-2026.1/toolchain/bin/riscv-none-elf-gcc
CROSS_PREFIX := $(patsubst %gcc,%,$(CROSS_CC))
CROSS_SIZE   := $(CROSS_PREFIX)size

RV_ARCH ?= rv32im_zicsr_zifencei
RV_ABI  ?= ilp32

CROSS_CFLAGS := -std=c99 -Os -g $(WARNFLAGS) -march=$(RV_ARCH) -mabi=$(RV_ABI)


.PHONY: all native-test riscv-build clean

all: native-test


# ---- 本机测试：编译 + 运行 ----
native-test: $(BUILD_DIR)/test_renderer
	@echo "== 运行本机测试（CC=$(CC)，ASan/UBSan 已开启）=="
	@$(BUILD_DIR)/test_renderer
	@echo "== 本机测试通过 =="

$(BUILD_DIR)/test_renderer: $(SRCS) $(HDRS)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $(SRCS) -o $@


# ---- RISC-V 交叉编译验证：只证明能编能链，产物不在本机运行 ----
riscv-build: $(BUILD_DIR)/test_renderer.elf
	@echo "== RISC-V 交叉编译验证通过（$(RV_ARCH) / $(RV_ABI)）=="

$(BUILD_DIR)/test_renderer.elf: $(SRCS) $(HDRS)
	@command -v $(CROSS_CC) >/dev/null 2>&1 || { \
	  echo "找不到交叉编译器：$(CROSS_CC)"; \
	  echo "可用 make riscv-build CROSS_CC=/path/to/riscv-none-elf-gcc 指定"; \
	  exit 1; \
	}
	@mkdir -p $(BUILD_DIR)
	$(CROSS_CC) $(CROSS_CFLAGS) $(SRCS) -static -o $@
	@$(CROSS_SIZE) $@


clean:
	rm -rf $(BUILD_DIR)
	@echo "已删除 $(BUILD_DIR)"
