# jzy/riscv_game —— 聚合 Makefile
#
#   make test               全部 host 测试（冻结基线 + 统一层 + BitBlt 适配层
#                           + 像素格式 + 换帧状态机）
#   make test-legacy        同上，但切到 XRGB8888 历史格式跑一遍（回退路径）
#   make native-test        冻结的 M1 基线测试（委托给 tests/Makefile）
#   make api-test           统一渲染层 + BitBlt 驱动/适配层
#   make riscv-build        RISC-V 交叉编译验证
#   make riscv-build-hw     额外开启 BITBLT_ENABLE_HW_ACCESS 做编译检查
#   make check              静态约束检查（寄存器引用隔离、无硬编码地址、
#                           板端 printf 转换符）
#   make clean
#
# 完整回归请统一从 scripts/regress.sh {quick|contract|full} 进入；
# 下面的目标保留为该脚本的可组合基础步骤。
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
TEST_FORMAT := $(TESTS_DIR)/test_pixel_format.c
TEST_SWAP   := $(TESTS_DIR)/test_frame_swap.c
TEST_CONTRACT := $(TESTS_DIR)/test_contract.c
TEST_BOARD  := $(TESTS_DIR)/test_bitblt_board.c
MUTATION_TEST := $(TESTS_DIR)/run_mutation_tests.sh

# 像素格式开关。
#   空                      -> RGB565（renderer_sw.h 里的默认）
#   -DRENDER_PIXEL_FORMAT_RGB565=0 -> XRGB8888 历史基线
# 回退路径必须同样能编能跑：B 组 RGB565 位流落地前，那是唯一能上板的路。
FORMAT_DEF ?=

# 板端测试的 host 替身环境（见 tests/host_board/ 的说明）。
# 它把 test_bitblt_board.c 原样编到宿主机上跑，用来在没有板子的时候
# 验证测试自己的判定逻辑 —— 不是真硬件的替代品。
BOARD_LOGIC_DIR   := $(TESTS_DIR)/host_board
BOARD_LOGIC_BUILD := $(API_BUILD)/board_logic


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

CFLAGS := -std=c99 -O1 -g $(WARNFLAGS) $(SANFLAGS) $(INCFLAGS) $(FORMAT_DEF)


# ---- RISC-V 交叉编译 ----
# 默认参数取自 2026.1 BSP 实际产物的 Tag_RISCV_arch：
#   rv32i2p1_m2p0_zicsr2p0_zifencei2p0_zmmul1p0，ABI 为 ilp32
CROSS_CC     ?= $(HOME)/efinity/efinity-riscv-ide-2026.1/toolchain/bin/riscv-none-elf-gcc
CROSS_PREFIX := $(patsubst %gcc,%,$(CROSS_CC))
CROSS_SIZE   := $(CROSS_PREFIX)size

RV_ARCH ?= rv32im_zicsr_zifencei
RV_ABI  ?= ilp32

CROSS_CFLAGS := -std=c99 -Os -g $(WARNFLAGS) -march=$(RV_ARCH) -mabi=$(RV_ABI) $(INCFLAGS) $(FORMAT_DEF)


.PHONY: all test test-legacy native-test api-test board-logic-test mutation-test \
        contract-test FORCE riscv-build riscv-build-api riscv-build-hw \
        check check-hw-isolation check-no-addresses check-board-printf check-format-switch \
        check-cross clean

# 交叉编译器存在性检查；所有交叉编译目标都依赖它
check-cross:
	@command -v $(CROSS_CC) >/dev/null 2>&1 || { \
	  echo "找不到交叉编译器：$(CROSS_CC)"; \
	  echo "可用 make CROSS_CC=/path/to/riscv-none-elf-gcc 指定"; \
	  exit 1; }

all: test


# ---- 本机测试 ----

test: native-test api-test board-logic-test

# 回退路径回归：整套 host 测试在 XRGB8888 下再跑一遍。
# 产物另放一个目录，避免和默认格式的目标文件互相覆盖。
test-legacy:
	@$(MAKE) test FORMAT_DEF=-DRENDER_PIXEL_FORMAT_RGB565=0 \
	    API_BUILD=$(TESTS_DIR)/build/api-legacy

native-test:
	@$(MAKE) -C $(TESTS_DIR) native-test FORMAT_DEF="$(FORMAT_DEF)"

api-test: $(API_BUILD)/test_render_api $(API_BUILD)/test_bitblt_api \
          $(API_BUILD)/test_pixel_format $(API_BUILD)/test_frame_swap
	@echo "== 运行统一渲染层测试（CC=$(CC)，ASan/UBSan 已开启）=="
	@$(API_BUILD)/test_render_api
	@echo "== 运行 BitBlt 驱动 / 适配层测试 =="
	@$(API_BUILD)/test_bitblt_api
	@echo "== 运行像素格式 / 几何 / Color Key / Alpha 测试 =="
	@$(API_BUILD)/test_pixel_format
	@echo "== 运行换帧状态机测试 =="
	@$(API_BUILD)/test_frame_swap
	@echo "== 统一层、适配层、像素格式与换帧测试通过 =="

# 将 CPU 参考实现中的两个关键语义做变异，确认现有测试会拒绝错误实现。
# 变异只发生在 mktemp 目录，不会改动工作树。
mutation-test:
	@CC="$(CC)" WERROR="$(WERROR)" $(MUTATION_TEST)

$(API_BUILD)/test_render_api: $(TEST_API) $(LIB_SRCS)
	@mkdir -p $(API_BUILD)
	$(CC) $(CFLAGS) $(TEST_API) $(LIB_SRCS) -o $@

$(API_BUILD)/test_bitblt_api: $(TEST_BITBLT) $(LIB_SRCS)
	@mkdir -p $(API_BUILD)
	$(CC) $(CFLAGS) $(TEST_BITBLT) $(LIB_SRCS) -o $@

$(API_BUILD)/test_pixel_format: $(TEST_FORMAT) $(LIB_SRCS)
	@mkdir -p $(API_BUILD)
	$(CC) $(CFLAGS) $(TEST_FORMAT) $(LIB_SRCS) -o $@

$(API_BUILD)/test_frame_swap: $(TEST_SWAP) $(LIB_SRCS)
	@mkdir -p $(API_BUILD)
	$(CC) $(CFLAGS) $(TEST_SWAP) $(LIB_SRCS) -o $@


# ---- 板端测试逻辑的 host 验证 ----
#
# 把 tests/test_bitblt_board.c 【原样】编到宿主机上跑：替身 bsp.h 提供
# BSP 符号，stub.c 在真实地址上 mmap 一片假内存并给一个 BitBlt 行为模型。
# test_bitblt_board.c 里的 main() 用 -Dmain=board_main 让位给 runner.c。
#
# 跑两边：正常路径必须 PASS，注入故障后必须 FAIL。
# 没接板子的时候，这是唯一能确认 T0~T3 判定逻辑没写错的办法。
#
# 不加 ASan/UBSan：替身要 mmap 固定的低位地址（SCRATCH_BASE 等），
# 会跟 sanitizer 的 shadow 映射打架。
#
# -Wno-int-to-pointer-cast：B 的 bitblt_regs.h 是按 RV32 写的，
# 里面是 (volatile uint32_t *)0xE1000000 这种 32 位常量转指针。
# 在 64 位宿主机上这必然报警，但那是"目标机是 32 位"的表达方式，
# 不是缺陷 —— 替身就是靠 mmap 到这些常量地址上工作的。其余警告照旧当错误。
BOARD_LOGIC_CFLAGS := -std=gnu99 -O1 -g -Wall -Wextra $(WERROR) \
                      -Wno-int-to-pointer-cast $(INCFLAGS) -I$(BOARD_LOGIC_DIR)

$(BOARD_LOGIC_BUILD)/m2_board_logic: $(TEST_BOARD) \
                                     $(BOARD_LOGIC_DIR)/stub.c \
                                     $(BOARD_LOGIC_DIR)/runner.c
	@mkdir -p $(BOARD_LOGIC_BUILD)
	$(CC) $(BOARD_LOGIC_CFLAGS) -c $(BOARD_LOGIC_DIR)/stub.c -o $(BOARD_LOGIC_BUILD)/stub.o
	$(CC) $(BOARD_LOGIC_CFLAGS) -c $(BOARD_LOGIC_DIR)/runner.c -o $(BOARD_LOGIC_BUILD)/runner.o
	$(CC) $(BOARD_LOGIC_CFLAGS) -Dmain=board_main -c $(TEST_BOARD) -o $(BOARD_LOGIC_BUILD)/board.o
	$(CC) $(BOARD_LOGIC_BUILD)/stub.o $(BOARD_LOGIC_BUILD)/runner.o \
	    $(BOARD_LOGIC_BUILD)/board.o -o $@

board-logic-test: $(BOARD_LOGIC_BUILD)/m2_board_logic
	@echo "== 运行板端测试逻辑的 host 场景（正常路径 + 故障注入）=="
	@$(BOARD_LOGIC_DIR)/run_scenarios.sh $(BOARD_LOGIC_BUILD)/m2_board_logic


# ---- RISC-V 交叉编译验证（只证明能编能链，产物不在本机运行）----

riscv-build: riscv-build-api
	@$(MAKE) -C $(TESTS_DIR) riscv-build
	@echo "== RISC-V 交叉编译验证通过（冻结基线 + 统一层 + 适配层）=="

riscv-build-api: $(API_BUILD)/test_render_api.elf $(API_BUILD)/test_bitblt_api.elf \
                 $(API_BUILD)/test_pixel_format.elf $(API_BUILD)/test_frame_swap.elf

$(API_BUILD)/test_render_api.elf: $(TEST_API) $(LIB_SRCS) check-cross
	@mkdir -p $(API_BUILD)
	$(CROSS_CC) $(CROSS_CFLAGS) $(TEST_API) $(LIB_SRCS) -static -o $@
	@$(CROSS_SIZE) $@

$(API_BUILD)/test_bitblt_api.elf: $(TEST_BITBLT) $(LIB_SRCS) check-cross
	@mkdir -p $(API_BUILD)
	$(CROSS_CC) $(CROSS_CFLAGS) $(TEST_BITBLT) $(LIB_SRCS) -static -o $@
	@$(CROSS_SIZE) $@

$(API_BUILD)/test_pixel_format.elf: $(TEST_FORMAT) $(LIB_SRCS) check-cross
	@mkdir -p $(API_BUILD)
	$(CROSS_CC) $(CROSS_CFLAGS) $(TEST_FORMAT) $(LIB_SRCS) -static -o $@
	@$(CROSS_SIZE) $@

$(API_BUILD)/test_frame_swap.elf: $(TEST_SWAP) $(LIB_SRCS) check-cross
	@mkdir -p $(API_BUILD)
	$(CROSS_CC) $(CROSS_CFLAGS) $(TEST_SWAP) $(LIB_SRCS) -static -o $@
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
	@mkdir -p $(API_BUILD)/hw
	cd $(API_BUILD)/hw && $(CROSS_CC) $(CROSS_CFLAGS) \
	  -DDISPLAY_ENABLE_HW_ACCESS -c $(abspath $(LIB_SRCS))
	@echo "== 硬件分支编译检查通过（BITBLT_ENABLE_HW_ACCESS + DISPLAY_ENABLE_HW_ACCESS）=="


# ---- B/C 编译期接口契约 ----
#
# 这个翻译单元直接 include B 组的三份权威头文件，并固定 C 组已接入的
# 寄存器偏移、错误码、函数类型、像素格式与 framebuffer 布局。只编译不运行，
# 因此可以用目标编译器同时检查 RV32 ABI。
CONTRACT_HEADERS := $(BITBLT_INC_DIR)/bitblt_regs.h \
                    $(BITBLT_INC_DIR)/bitblt_api.h \
                    $(BITBLT_INC_DIR)/framebuffer_layout.h

contract-test: $(API_BUILD)/test_contract.o
	@echo "== BitBlt / framebuffer API 契约测试通过 =="

$(API_BUILD)/test_contract.o: $(TEST_CONTRACT) $(CONTRACT_HEADERS) check-cross FORCE
	@echo "== 检查权威接口：$(BITBLT_INC_DIR) =="
	@mkdir -p $(API_BUILD)
	$(CROSS_CC) $(CROSS_CFLAGS) -c $(TEST_CONTRACT) -o $@

FORCE:


# ---- 静态约束检查 ----

check: check-hw-isolation check-no-addresses check-board-printf check-no-legacy-format

# 板端测试用的是 BSP 的 lite 版 bsp_printf（bsp.h 里 ENABLE_BSP_PRINTF_FULL = 0），
# 只认 c / s / d / x / X 五种转换符。
#
# 用了它不认识的转换符【不会编译报错】，但板上会出两种坏结果：
# 整行剩余内容被吞掉，且那个参数不会被取走 —— 后面所有参数整体错位。
# 这种错只有真板才看得出来，所以在编译期就机械挡住。
#
# 黑名单而不是白名单：源文件里 `TEST_STRIDE % 16u == 0u` 这类取模表达式
# 长得也像格式符，白名单扫描会误报。这里只抓"标准 printf 有、BSP 没有"
# 的那几个（无符号转换符、长度修饰符、指针、八进制、科学计数法）。
BOARD_TEST_SRCS := $(TESTS_DIR)/test_bitblt_board.c $(TESTS_DIR)/test_render_board.c

check-board-printf:
	@bad=$$(grep -nE '%((l|h|z|j|t)*(u|i|o|p|e|g|n)|(l|h|z|j|t)+d)' \
	    $(BOARD_TEST_SRCS) 2>/dev/null || true); \
	if [ -n "$$bad" ]; then \
	  echo "失败：板端测试用了 BSP lite bsp_printf 不支持的转换符"; \
	  printf '%s\n' "$$bad"; \
	  echo "只支持 c / s / d / x / X；无符号量请先转 int 再按 d 打印"; \
	  exit 1; \
	fi
	@echo "通过：板端测试只用 c / s / d / x / X 转换符"

# 【生产代码】里只允许一个文件引用 B 组的寄存器定义，杜绝第二份寄存器真相源。
# 寄存器访问集中在真正的驱动 bitblt_api.c；旧的 gpu.c 已降级为兼容层，
# 不再包含任何寄存器分支。
#
# 范围刻意只覆盖 render/ 与 driver/：板级验证代码（tests/test_bitblt_board.c）
# 允许【只读】引用 bitblt_regs.h，用于 VERSION 这类硬件契约检查。
# 为读一个版本号去封装 bitblt_get_version() 反而不如直接读寄存器干净，
# 但那只属于"验证"，不属于生产路径。
check-hw-isolation:
	@for pair in "bitblt_regs.h:driver/bitblt_api.c" "display_regs.h:driver/display_api.c"; do \
	  hdr=$${pair%%:*}; want=$${pair##*:}; \
	  files=$$(grep -rlE "^[[:space:]]*#[[:space:]]*include[[:space:]]*\"$$hdr\"" \
	      $(RENDER_DIR) $(DRIVER_DIR) || true); \
	  count=$$(printf '%s\n' "$$files" | grep -c . || true); \
	  if [ "$$count" -ne 1 ]; then \
	    echo "失败：应有且仅有 1 个文件引用 $$hdr，实际 $$count 个"; \
	    printf '%s\n' "$$files"; \
	    exit 1; \
	  fi; \
	  case "$$files" in \
	    */$$want) ;; \
	    *) echo "失败：$$hdr 的引用点是 $$files，应为 $$want"; exit 1;; \
	  esac; \
	done
	@echo "通过：生产代码里 bitblt_regs.h 只由 bitblt_api.c、display_regs.h 只由 display_api.c 引用"

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


# 历史格式与旧通路的残留检查。
#
# 这一条把"迁移干净了没有"变成机械可重复的检查，而不是靠人肉 grep：
#   - APB 0xF8100000 那条路已被迁移文档明确否掉，库代码里不许再出现
#     （注释里提到它是为了说明"为什么不用"，那种行会被过滤掉）
#   - GPU_HW_PIXEL_BYTES 是"硬件像素宽度是编译期常量"的旧写法，
#     已改成 gpu_limits_t.bytes_per_pixel 运行期传入
#   - RENDER_PIXEL_BYTES 必须继续由 sizeof(pixel_t) 派生，
#     不许退回成一个写死的数字（那样软件格式与硬件格式又会漂移）
#
# 分辨率的旧数字（1920/1080/7680）刻意【不】在这里查：
# driver/framebuffer_format.h 的 XRGB8888 回退分支合法地持有它们，
# 那种值由 test_contract.c 按格式分支直接断言，比 grep 准确。
check-no-legacy-format:
	@bad=$$(grep -rnE '0x[Ff]8100000|GPU_HW_PIXEL_BYTES' \
	    $(RENDER_DIR) $(DRIVER_DIR) 2>/dev/null \
	    | grep -vE ':[[:space:]]*(\*|//|/\*)' || true); \
	if [ -n "$$bad" ]; then \
	  echo "失败：库代码里出现已废弃的 APB 通路地址或编译期像素宽度常量"; \
	  printf '%s\n' "$$bad"; \
	  exit 1; \
	fi
	@bad=$$(grep -rnE '^[[:space:]]*#[[:space:]]*define[[:space:]]+RENDER_PIXEL_BYTES[[:space:]]+[0-9]' \
	    $(RENDER_DIR) 2>/dev/null || true); \
	if [ -n "$$bad" ]; then \
	  echo "失败：RENDER_PIXEL_BYTES 被写死成字面量，应由 sizeof(pixel_t) 派生"; \
	  printf '%s\n' "$$bad"; \
	  exit 1; \
	fi
	@echo "通过：没有旧 APB 通路、没有编译期像素宽度常量"

clean:
	@$(MAKE) -C $(TESTS_DIR) clean
	rm -rf $(API_BUILD)
	@echo "已清理 $(API_BUILD)"
