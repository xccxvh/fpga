PROJ_NAME=bitbltColorKeyDemo
STANDALONE = ../..
SRCS = $(wildcard src/*.c) \
       ${STANDALONE}/common/start.S \
       ${STANDALONE}/common/trap.S
CFLAGS += -I../driver
CFLAGS_ARGS += -march=rv32im_zicsr
include ${STANDALONE}/common/bsp.mk
include ${STANDALONE}/common/riscv64-unknown-elf.mk
include ${STANDALONE}/common/standalone.mk
LDSCRIPT = ${BSP_PATH}/linker/default.ld
