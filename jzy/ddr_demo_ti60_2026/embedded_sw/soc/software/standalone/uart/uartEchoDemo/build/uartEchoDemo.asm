
build/uartEchoDemo.elf:     file format elf32-littleriscv


Disassembly of section .init:

00001000 <_start>:

_start:
#ifdef USE_GP
.option push
.option norelax
	la gp, __global_pointer$
    1000:	00001197          	auipc	gp,0x1
    1004:	f4018193          	addi	gp,gp,-192 # 1f40 <__global_pointer$>
.global smp_lottery_target
.global smp_lottery_lock
.global smp_slave


  sw x0, smp_lottery_lock, a1
    1008:	8201a023          	sw	zero,-2016(gp) # 1760 <smp_lottery_lock>

0000100c <smp_tyranny>:

smp_tyranny:
  csrr a0, mhartid
    100c:	f1402573          	csrr	a0,mhartid
  beqz a0, init
    1010:	02050e63          	beqz	a0,104c <init>

00001014 <smp_slave>:

smp_slave:
	lw a0, smp_lottery_lock
    1014:	8201a503          	lw	a0,-2016(gp) # 1760 <smp_lottery_lock>
	beqz a0, smp_slave
    1018:	fe050ee3          	beqz	a0,1014 <smp_slave>

	fence r, r
    101c:	0220000f          	fence	r,r
    1020:	0000100f          	.word	0x0000100f
	//li a1, -1
	//amoadd.w x0, a1,(a0)

	.word(0x100F) //i$ flush
	lw a5, smp_lottery_target
    1024:	81c1a783          	lw	a5,-2020(gp) # 175c <__bss_start>
	li a0, 0
    1028:	00000513          	li	a0,0
	li a1, 0
    102c:	00000593          	li	a1,0
	li a2, 0
    1030:	00000613          	li	a2,0
	jr a5
    1034:	00078067          	jr	a5

00001038 <smp_unlock>:

.global   smp_unlock
.type    smp_unlock,%function
smp_unlock:
	sw a0, smp_lottery_target, a1
    1038:	80a1ae23          	sw	a0,-2020(gp) # 175c <__bss_start>
	fence w, w
    103c:	0110000f          	fence	w,w
	li a0, 1
    1040:	00100513          	li	a0,1
	sw a0, smp_lottery_lock, a1
    1044:	82a1a023          	sw	a0,-2016(gp) # 1760 <smp_lottery_lock>
    ret
    1048:	00008067          	ret

0000104c <init>:
#endif

init:
	la sp, _sp
    104c:	00001117          	auipc	sp,0x1
    1050:	72410113          	addi	sp,sp,1828 # 2770 <__freertos_irq_stack_top>

	/* Load data section */
	la a0, _data_lma
    1054:	00000517          	auipc	a0,0x0
    1058:	59850513          	addi	a0,a0,1432 # 15ec <_data>
	la a1, _data
    105c:	00000597          	auipc	a1,0x0
    1060:	59058593          	addi	a1,a1,1424 # 15ec <_data>
	la a2, _edata
    1064:	00000617          	auipc	a2,0x0
    1068:	6f860613          	addi	a2,a2,1784 # 175c <__bss_start>
	bgeu a1, a2, 2f
    106c:	00c5fc63          	bgeu	a1,a2,1084 <init+0x38>
1:
	lw t0, (a0)
    1070:	00052283          	lw	t0,0(a0)
	sw t0, (a1)
    1074:	0055a023          	sw	t0,0(a1)
	addi a0, a0, 4
    1078:	00450513          	addi	a0,a0,4
	addi a1, a1, 4
    107c:	00458593          	addi	a1,a1,4
	bltu a1, a2, 1b
    1080:	fec5e8e3          	bltu	a1,a2,1070 <init+0x24>
2:

	/* Clear bss section */
	la a0, __bss_start
    1084:	00000517          	auipc	a0,0x0
    1088:	6d850513          	addi	a0,a0,1752 # 175c <__bss_start>
	la a1, _end
    108c:	00000597          	auipc	a1,0x0
    1090:	6dc58593          	addi	a1,a1,1756 # 1768 <_end>
	bgeu a0, a1, 2f
    1094:	00b57863          	bgeu	a0,a1,10a4 <init+0x58>
1:
	sw zero, (a0)
    1098:	00052023          	sw	zero,0(a0)
	addi a0, a0, 4
    109c:	00450513          	addi	a0,a0,4
	bltu a0, a1, 1b
    10a0:	feb56ce3          	bltu	a0,a1,1098 <init+0x4c>
2:

#ifndef NO_LIBC_INIT_ARRAY
	call __libc_init_array
    10a4:	010000ef          	jal	10b4 <__libc_init_array>
#endif

	call main
    10a8:	0a0000ef          	jal	1148 <main>

000010ac <mainDone>:
mainDone:
    j mainDone
    10ac:	0000006f          	j	10ac <mainDone>

000010b0 <_init>:


	.globl _init
_init:
    ret
    10b0:	00008067          	ret

Disassembly of section .text:

000010b4 <__libc_init_array>:
    10b4:	ff010113          	addi	sp,sp,-16
    10b8:	00812423          	sw	s0,8(sp)
    10bc:	01212023          	sw	s2,0(sp)
    10c0:	00000797          	auipc	a5,0x0
    10c4:	52c78793          	addi	a5,a5,1324 # 15ec <_data>
    10c8:	00000417          	auipc	s0,0x0
    10cc:	52440413          	addi	s0,s0,1316 # 15ec <_data>
    10d0:	00112623          	sw	ra,12(sp)
    10d4:	00912223          	sw	s1,4(sp)
    10d8:	40878933          	sub	s2,a5,s0
    10dc:	02878063          	beq	a5,s0,10fc <__libc_init_array+0x48>
    10e0:	40295913          	srai	s2,s2,0x2
    10e4:	00000493          	li	s1,0
    10e8:	00042783          	lw	a5,0(s0)
    10ec:	00148493          	addi	s1,s1,1
    10f0:	00440413          	addi	s0,s0,4
    10f4:	000780e7          	jalr	a5
    10f8:	ff24e8e3          	bltu	s1,s2,10e8 <__libc_init_array+0x34>
    10fc:	00000797          	auipc	a5,0x0
    1100:	4f078793          	addi	a5,a5,1264 # 15ec <_data>
    1104:	00000417          	auipc	s0,0x0
    1108:	4e840413          	addi	s0,s0,1256 # 15ec <_data>
    110c:	40878933          	sub	s2,a5,s0
    1110:	40295913          	srai	s2,s2,0x2
    1114:	00878e63          	beq	a5,s0,1130 <__libc_init_array+0x7c>
    1118:	00000493          	li	s1,0
    111c:	00042783          	lw	a5,0(s0)
    1120:	00148493          	addi	s1,s1,1
    1124:	00440413          	addi	s0,s0,4
    1128:	000780e7          	jalr	a5
    112c:	ff24e8e3          	bltu	s1,s2,111c <__libc_init_array+0x68>
    1130:	00c12083          	lw	ra,12(sp)
    1134:	00812403          	lw	s0,8(sp)
    1138:	00412483          	lw	s1,4(sp)
    113c:	00012903          	lw	s2,0(sp)
    1140:	01010113          	addi	sp,sp,16
    1144:	00008067          	ret

00001148 <main>:
*
* @brief This function capture the character that user asserted on keyboard and 
*        printed on the terminal. 
*
******************************************************************************/
void main() {
    1148:	ff010113          	addi	sp,sp,-16
    114c:	00112623          	sw	ra,12(sp)
    uint8_t dat;

    bsp_init();
    1150:	334000ef          	jal	1484 <bsp_init>
    
    bsp_printf("***FPGA Game RISC-V Ready*** \r\n");
    1154:	00001537          	lui	a0,0x1
    1158:	66050513          	addi	a0,a0,1632 # 1660 <_data+0x74>
    115c:	360000ef          	jal	14bc <bsp_printf>
    bsp_printf("Start typing on terminal to send character... \r\n");
    1160:	00001537          	lui	a0,0x1
    1164:	68050513          	addi	a0,a0,1664 # 1680 <_data+0x94>
    1168:	354000ef          	jal	14bc <bsp_printf>
    116c:	01c0006f          	j	1188 <main+0x40>
    while(1)
    {
        while(uart_readOccupancy(BSP_UART_TERMINAL)){
            dat=uart_read(BSP_UART_TERMINAL);
    1170:	f8010537          	lui	a0,0xf8010
    1174:	07c000ef          	jal	11f0 <uart_read>
    1178:	00050593          	mv	a1,a0
            bsp_printf("Echo character: %c \r\n", dat);
    117c:	00001537          	lui	a0,0x1
    1180:	6b450513          	addi	a0,a0,1716 # 16b4 <_data+0xc8>
    1184:	338000ef          	jal	14bc <bsp_printf>
        while(uart_readOccupancy(BSP_UART_TERMINAL)){
    1188:	f8010537          	lui	a0,0xf8010
    118c:	01c000ef          	jal	11a8 <uart_readOccupancy>
    1190:	fe050ce3          	beqz	a0,1188 <main+0x40>
    1194:	fddff06f          	j	1170 <main+0x28>

00001198 <uart_writeAvailability>:
#include "type.h"
#include "soc.h"


    static inline u32 read_u32(u32 address){
        return *((volatile u32*) address);
    1198:	00452503          	lw	a0,4(a0) # f8010004 <__freertos_irq_stack_top+0xf800d894>
*          of available spaces for writing data from bits 23 to 16. It then
*          returns this value after masking with 0xFF.
*
******************************************************************************/
    static u32 uart_writeAvailability(u32 reg){
        return (read_u32(reg + UART_STATUS) >> 16) & 0xFF;
    119c:	01055513          	srli	a0,a0,0x10
    }
    11a0:	0ff57513          	zext.b	a0,a0
    11a4:	00008067          	ret

000011a8 <uart_readOccupancy>:
    11a8:	00452503          	lw	a0,4(a0)
*          of occupied spaces for reading data from bits 31 to 24.
*
******************************************************************************/
    static u32 uart_readOccupancy(u32 reg){
        return read_u32(reg + UART_STATUS) >> 24;
    }
    11ac:	01855513          	srli	a0,a0,0x18
    11b0:	00008067          	ret

000011b4 <uart_write>:
* @note    The function waits until there is available space in the UART buffer
*          for writing data. Once space is available, it writes the character
*          data to the UART data register.
*
******************************************************************************/
    static void uart_write(u32 reg, char data){
    11b4:	ff010113          	addi	sp,sp,-16
    11b8:	00112623          	sw	ra,12(sp)
    11bc:	00812423          	sw	s0,8(sp)
    11c0:	00912223          	sw	s1,4(sp)
    11c4:	00050413          	mv	s0,a0
    11c8:	00058493          	mv	s1,a1
        while(uart_writeAvailability(reg) == 0);
    11cc:	00040513          	mv	a0,s0
    11d0:	fc9ff0ef          	jal	1198 <uart_writeAvailability>
    11d4:	fe050ce3          	beqz	a0,11cc <uart_write+0x18>
    }
    
    static inline void write_u32(u32 data, u32 address){
        *((volatile u32*) address) = data;
    11d8:	00942023          	sw	s1,0(s0)
        write_u32(data, reg + UART_DATA);
    }
    11dc:	00c12083          	lw	ra,12(sp)
    11e0:	00812403          	lw	s0,8(sp)
    11e4:	00412483          	lw	s1,4(sp)
    11e8:	01010113          	addi	sp,sp,16
    11ec:	00008067          	ret

000011f0 <uart_read>:
* @note    The function waits until there is data available in the UART buffer
*          for reading. Once data is available, it reads the character data from
*          the UART data register and returns it.
*
******************************************************************************/
    static char uart_read(u32 reg){
    11f0:	ff010113          	addi	sp,sp,-16
    11f4:	00112623          	sw	ra,12(sp)
    11f8:	00812423          	sw	s0,8(sp)
    11fc:	00050413          	mv	s0,a0
        while(uart_readOccupancy(reg) == 0);
    1200:	00040513          	mv	a0,s0
    1204:	fa5ff0ef          	jal	11a8 <uart_readOccupancy>
    1208:	fe050ce3          	beqz	a0,1200 <uart_read+0x10>
        return *((volatile u32*) address);
    120c:	00042503          	lw	a0,0(s0)
        return read_u32(reg + UART_DATA);
    }
    1210:	0ff57513          	zext.b	a0,a0
    1214:	00c12083          	lw	ra,12(sp)
    1218:	00812403          	lw	s0,8(sp)
    121c:	01010113          	addi	sp,sp,16
    1220:	00008067          	ret

00001224 <uart_applyConfig>:
*          value using data length, parity, and stop bit settings from the configuration
*          structure, and writes this value to the UART frame configuration register.
*
******************************************************************************/
    static void uart_applyConfig(u32 reg, Uart_Config *config){
        write_u32(config->clockDivider, reg + UART_CLOCK_DIVIDER);
    1224:	00c5a783          	lw	a5,12(a1)
        *((volatile u32*) address) = data;
    1228:	00f52423          	sw	a5,8(a0)
        write_u32(((config->dataLength-1) << 0) | (config->parity << 8) | (config->stop << 16), reg + UART_FRAME_CONFIG);
    122c:	0005a783          	lw	a5,0(a1)
    1230:	fff78793          	addi	a5,a5,-1
    1234:	0045a703          	lw	a4,4(a1)
    1238:	00871713          	slli	a4,a4,0x8
    123c:	00e7e7b3          	or	a5,a5,a4
    1240:	0085a703          	lw	a4,8(a1)
    1244:	01071713          	slli	a4,a4,0x10
    1248:	00e7e7b3          	or	a5,a5,a4
    124c:	00f52623          	sw	a5,12(a0)
    }
    1250:	00008067          	ret

00001254 <_putchar>:
#include <math.h>
#include <string.h>
#include "bsp.h"

#if (ENABLE_BSP_PRINTF)
    static void _putchar(char character){
    1254:	ff010113          	addi	sp,sp,-16
    1258:	00112623          	sw	ra,12(sp)
    125c:	00050593          	mv	a1,a0
        #if (ENABLE_SEMIHOSTING_PRINT == 1)
            sh_writec(character);
        #else
            bsp_putChar(character);
    1260:	f8010537          	lui	a0,0xf8010
    1264:	f51ff0ef          	jal	11b4 <uart_write>
        #endif // (ENABLE_SEMIHOSTING_PRINT == 1)
    }
    1268:	00c12083          	lw	ra,12(sp)
    126c:	01010113          	addi	sp,sp,16
    1270:	00008067          	ret

00001274 <_putchar_s>:

    static void _putchar_s(char *p)
    {
    1274:	ff010113          	addi	sp,sp,-16
    1278:	00112623          	sw	ra,12(sp)
    127c:	00812423          	sw	s0,8(sp)
    1280:	00050413          	mv	s0,a0
    #if (ENABLE_SEMIHOSTING_PRINT == 1)
        sh_write0(p);
    #else
        while (*p)
    1284:	00c0006f          	j	1290 <_putchar_s+0x1c>
            _putchar(*(p++));
    1288:	00140413          	addi	s0,s0,1
    128c:	fc9ff0ef          	jal	1254 <_putchar>
        while (*p)
    1290:	00044503          	lbu	a0,0(s0)
    1294:	fe051ae3          	bnez	a0,1288 <_putchar_s+0x14>
    #endif // (ENABLE_SEMIHOSTING_PRINT == 1)
    }
    1298:	00c12083          	lw	ra,12(sp)
    129c:	00812403          	lw	s0,8(sp)
    12a0:	01010113          	addi	sp,sp,16
    12a4:	00008067          	ret

000012a8 <bsp_printHex>:

        static void bsp_printHex(uint32_t val)
    {
    12a8:	ff010113          	addi	sp,sp,-16
    12ac:	00112623          	sw	ra,12(sp)
    12b0:	00812423          	sw	s0,8(sp)
    12b4:	00912223          	sw	s1,4(sp)
    12b8:	00050493          	mv	s1,a0
        uint32_t digits;
        digits =8;

        for (int i = (4*digits)-4; i >= 0; i -= 4) {
    12bc:	01c00413          	li	s0,28
    12c0:	0240006f          	j	12e4 <bsp_printHex+0x3c>
            _putchar("0123456789ABCDEF"[(val >> i) % 16]);
    12c4:	0084d733          	srl	a4,s1,s0
    12c8:	00f77713          	andi	a4,a4,15
    12cc:	000017b7          	lui	a5,0x1
    12d0:	5ec78793          	addi	a5,a5,1516 # 15ec <_data>
    12d4:	00e787b3          	add	a5,a5,a4
    12d8:	0007c503          	lbu	a0,0(a5)
    12dc:	f79ff0ef          	jal	1254 <_putchar>
        for (int i = (4*digits)-4; i >= 0; i -= 4) {
    12e0:	ffc40413          	addi	s0,s0,-4
    12e4:	fe0450e3          	bgez	s0,12c4 <bsp_printHex+0x1c>
        }
    }
    12e8:	00c12083          	lw	ra,12(sp)
    12ec:	00812403          	lw	s0,8(sp)
    12f0:	00412483          	lw	s1,4(sp)
    12f4:	01010113          	addi	sp,sp,16
    12f8:	00008067          	ret

000012fc <bsp_printHex_lower>:

    static void bsp_printHex_lower(uint32_t val)
    {
    12fc:	ff010113          	addi	sp,sp,-16
    1300:	00112623          	sw	ra,12(sp)
    1304:	00812423          	sw	s0,8(sp)
    1308:	00912223          	sw	s1,4(sp)
    130c:	00050493          	mv	s1,a0
        uint32_t digits;
        digits =8;

        for (int i = (4*digits)-4; i >= 0; i -= 4) {
    1310:	01c00413          	li	s0,28
    1314:	0240006f          	j	1338 <bsp_printHex_lower+0x3c>
            _putchar("0123456789abcdef"[(val >> i) % 16]);
    1318:	0084d733          	srl	a4,s1,s0
    131c:	00f77713          	andi	a4,a4,15
    1320:	000017b7          	lui	a5,0x1
    1324:	60078793          	addi	a5,a5,1536 # 1600 <_data+0x14>
    1328:	00e787b3          	add	a5,a5,a4
    132c:	0007c503          	lbu	a0,0(a5)
    1330:	f25ff0ef          	jal	1254 <_putchar>
        for (int i = (4*digits)-4; i >= 0; i -= 4) {
    1334:	ffc40413          	addi	s0,s0,-4
    1338:	fe0450e3          	bgez	s0,1318 <bsp_printHex_lower+0x1c>

        }
    }
    133c:	00c12083          	lw	ra,12(sp)
    1340:	00812403          	lw	s0,8(sp)
    1344:	00412483          	lw	s1,4(sp)
    1348:	01010113          	addi	sp,sp,16
    134c:	00008067          	ret

00001350 <bsp_printf_c>:
*
* @param c: The character to be output.
*
******************************************************************************/
    static void bsp_printf_c(int c)
    {
    1350:	ff010113          	addi	sp,sp,-16
    1354:	00112623          	sw	ra,12(sp)
        _putchar(c);
    1358:	0ff57513          	zext.b	a0,a0
    135c:	ef9ff0ef          	jal	1254 <_putchar>
    }
    1360:	00c12083          	lw	ra,12(sp)
    1364:	01010113          	addi	sp,sp,16
    1368:	00008067          	ret

0000136c <bsp_printf_s>:
*
* @param s: A pointer to the null-terminated string to be output.
*
*******************************************************************************/
    static void bsp_printf_s(char *p)
    {
    136c:	ff010113          	addi	sp,sp,-16
    1370:	00112623          	sw	ra,12(sp)
        _putchar_s(p);
    1374:	f01ff0ef          	jal	1274 <_putchar_s>
    }
    1378:	00c12083          	lw	ra,12(sp)
    137c:	01010113          	addi	sp,sp,16
    1380:	00008067          	ret

00001384 <bsp_printf_d>:
* - Handles negative numbers by printing a '-' sign.
* - Uses the 'bsp_printf_c' function to print each character.
*
******************************************************************************/
    static void bsp_printf_d(int val)
    {
    1384:	fd010113          	addi	sp,sp,-48
    1388:	02112623          	sw	ra,44(sp)
    138c:	02812423          	sw	s0,40(sp)
    1390:	02912223          	sw	s1,36(sp)
    1394:	00050493          	mv	s1,a0
        char buffer[32];
        char *p = buffer;
        if (val < 0) {
    1398:	00054663          	bltz	a0,13a4 <bsp_printf_d+0x20>
    {
    139c:	00010413          	mv	s0,sp
    13a0:	02c0006f          	j	13cc <bsp_printf_d+0x48>
            bsp_printf_c('-');
    13a4:	02d00513          	li	a0,45
    13a8:	fa9ff0ef          	jal	1350 <bsp_printf_c>
            val = -val;
    13ac:	409004b3          	neg	s1,s1
    13b0:	fedff06f          	j	139c <bsp_printf_d+0x18>
        }
        while (val || p == buffer) {
            *(p++) = '0' + val % 10;
    13b4:	00a00713          	li	a4,10
    13b8:	02e4e7b3          	rem	a5,s1,a4
    13bc:	03078793          	addi	a5,a5,48
    13c0:	00f40023          	sb	a5,0(s0)
            val = val / 10;
    13c4:	02e4c4b3          	div	s1,s1,a4
            *(p++) = '0' + val % 10;
    13c8:	00140413          	addi	s0,s0,1
        while (val || p == buffer) {
    13cc:	fe0494e3          	bnez	s1,13b4 <bsp_printf_d+0x30>
    13d0:	00010793          	mv	a5,sp
    13d4:	fef400e3          	beq	s0,a5,13b4 <bsp_printf_d+0x30>
        }
        while (p != buffer)
    13d8:	00010793          	mv	a5,sp
    13dc:	00f40a63          	beq	s0,a5,13f0 <bsp_printf_d+0x6c>
            bsp_printf_c(*(--p));
    13e0:	fff40413          	addi	s0,s0,-1
    13e4:	00044503          	lbu	a0,0(s0)
    13e8:	f69ff0ef          	jal	1350 <bsp_printf_c>
    13ec:	fedff06f          	j	13d8 <bsp_printf_d+0x54>
    }
    13f0:	02c12083          	lw	ra,44(sp)
    13f4:	02812403          	lw	s0,40(sp)
    13f8:	02412483          	lw	s1,36(sp)
    13fc:	03010113          	addi	sp,sp,48
    1400:	00008067          	ret

00001404 <bsp_printf_x>:
* - Calls 'bsp_printHex_lower' to print the hexadecimal representation.
* - Determines the number of leading zeros to be printed based on the value.
*
******************************************************************************/
    static void bsp_printf_x(int val)
    {
    1404:	ff010113          	addi	sp,sp,-16
    1408:	00112623          	sw	ra,12(sp)
        int i,digi=2;

        for(i=0;i<8;i++)
    140c:	00000713          	li	a4,0
    1410:	00700793          	li	a5,7
    1414:	02e7c063          	blt	a5,a4,1434 <bsp_printf_x+0x30>
        {
            if((val & (0xFFFFFFF0 <<(4*i))) == 0)
    1418:	00271693          	slli	a3,a4,0x2
    141c:	ff000793          	li	a5,-16
    1420:	00d797b3          	sll	a5,a5,a3
    1424:	00f577b3          	and	a5,a0,a5
    1428:	00078663          	beqz	a5,1434 <bsp_printf_x+0x30>
        for(i=0;i<8;i++)
    142c:	00170713          	addi	a4,a4,1
    1430:	fe1ff06f          	j	1410 <bsp_printf_x+0xc>
            {
                digi=i+1;
                break;
            }
        }
        bsp_printHex_lower(val);
    1434:	ec9ff0ef          	jal	12fc <bsp_printHex_lower>
    }
    1438:	00c12083          	lw	ra,12(sp)
    143c:	01010113          	addi	sp,sp,16
    1440:	00008067          	ret

00001444 <bsp_printf_X>:
* - Calls 'bsp_printHex' to print the uppercase hexadecimal representation.
* - Determines the number of leading zeros to be printed based on the value.
*
******************************************************************************/
    static void bsp_printf_X(int val)
        {
    1444:	ff010113          	addi	sp,sp,-16
    1448:	00112623          	sw	ra,12(sp)
            int i,digi=2;

            for(i=0;i<8;i++)
    144c:	00000713          	li	a4,0
    1450:	00700793          	li	a5,7
    1454:	02e7c063          	blt	a5,a4,1474 <bsp_printf_X+0x30>
            {
                if((val & (0xFFFFFFF0 <<(4*i))) == 0)
    1458:	00271693          	slli	a3,a4,0x2
    145c:	ff000793          	li	a5,-16
    1460:	00d797b3          	sll	a5,a5,a3
    1464:	00f577b3          	and	a5,a0,a5
    1468:	00078663          	beqz	a5,1474 <bsp_printf_X+0x30>
            for(i=0;i<8;i++)
    146c:	00170713          	addi	a4,a4,1
    1470:	fe1ff06f          	j	1450 <bsp_printf_X+0xc>
                {
                    digi=i+1;
                    break;
                }
            }
            bsp_printHex(val);
    1474:	e35ff0ef          	jal	12a8 <bsp_printHex>
        }
    1478:	00c12083          	lw	ra,12(sp)
    147c:	01010113          	addi	sp,sp,16
    1480:	00008067          	ret

00001484 <bsp_init>:
    *   1. UART baudrate
    *   2. 
    */
////////////////////////////////////////////////////////////////////////////////
    static void bsp_init()
    {
    1484:	fe010113          	addi	sp,sp,-32
    1488:	00112e23          	sw	ra,28(sp)
        Uart_Config uartConfig;
        uartConfig.dataLength   = BITS_8;
    148c:	00800793          	li	a5,8
    1490:	00f12023          	sw	a5,0(sp)
        uartConfig.parity       = NONE;
    1494:	00012223          	sw	zero,4(sp)
        uartConfig.stop         = ONE;
    1498:	00012423          	sw	zero,8(sp)
        uartConfig.clockDivider = BSP_CLINT_HZ/(BSP_UART_BAUDRATE*BSP_UART_DATA_LEN)-1;
    149c:	06b00793          	li	a5,107
    14a0:	00f12623          	sw	a5,12(sp)
        uart_applyConfig(BSP_UART_TERMINAL, &uartConfig);    
    14a4:	00010593          	mv	a1,sp
    14a8:	f8010537          	lui	a0,0xf8010
    14ac:	d79ff0ef          	jal	1224 <uart_applyConfig>
    }
    14b0:	01c12083          	lw	ra,28(sp)
    14b4:	02010113          	addi	sp,sp,32
    14b8:	00008067          	ret

000014bc <bsp_printf>:
* - Handles each format specifier by calling the appropriate helper function.
* - If floating-point support is disabled, prints a warning for the 'f' specifier.
*
******************************************************************************/
    static void bsp_printf(const char *format, ...)
    {
    14bc:	fc010113          	addi	sp,sp,-64
    14c0:	00112e23          	sw	ra,28(sp)
    14c4:	00812c23          	sw	s0,24(sp)
    14c8:	00912a23          	sw	s1,20(sp)
    14cc:	00050493          	mv	s1,a0
    14d0:	02b12223          	sw	a1,36(sp)
    14d4:	02c12423          	sw	a2,40(sp)
    14d8:	02d12623          	sw	a3,44(sp)
    14dc:	02e12823          	sw	a4,48(sp)
    14e0:	02f12a23          	sw	a5,52(sp)
    14e4:	03012c23          	sw	a6,56(sp)
    14e8:	03112e23          	sw	a7,60(sp)
        int i;
        va_list ap;

        va_start(ap, format);
    14ec:	02410793          	addi	a5,sp,36
    14f0:	00f12623          	sw	a5,12(sp)

        for (i = 0; format[i]; i++)
    14f4:	00000413          	li	s0,0
    14f8:	01c0006f          	j	1514 <bsp_printf+0x58>
            if (format[i] == '%') {
                while (format[++i]) {
                    if (format[i] == 'c') {
                        bsp_printf_c(va_arg(ap,int));
    14fc:	00c12783          	lw	a5,12(sp)
    1500:	00478713          	addi	a4,a5,4
    1504:	00e12623          	sw	a4,12(sp)
    1508:	0007a503          	lw	a0,0(a5)
    150c:	e45ff0ef          	jal	1350 <bsp_printf_c>
        for (i = 0; format[i]; i++)
    1510:	00140413          	addi	s0,s0,1
    1514:	008487b3          	add	a5,s1,s0
    1518:	0007c503          	lbu	a0,0(a5)
    151c:	0a050e63          	beqz	a0,15d8 <bsp_printf+0x11c>
            if (format[i] == '%') {
    1520:	02500793          	li	a5,37
    1524:	06f50e63          	beq	a0,a5,15a0 <bsp_printf+0xe4>
                        break;
                    }
#endif //#if (ENABLE_FLOATING_POINT_SUPPORT)
                }
            } else
                bsp_printf_c(format[i]);
    1528:	e29ff0ef          	jal	1350 <bsp_printf_c>
    152c:	fe5ff06f          	j	1510 <bsp_printf+0x54>
                        bsp_printf_s(va_arg(ap,char*));
    1530:	00c12783          	lw	a5,12(sp)
    1534:	00478713          	addi	a4,a5,4
    1538:	00e12623          	sw	a4,12(sp)
    153c:	0007a503          	lw	a0,0(a5)
    1540:	e2dff0ef          	jal	136c <bsp_printf_s>
                        break;
    1544:	fcdff06f          	j	1510 <bsp_printf+0x54>
                        bsp_printf_d(va_arg(ap,int));
    1548:	00c12783          	lw	a5,12(sp)
    154c:	00478713          	addi	a4,a5,4
    1550:	00e12623          	sw	a4,12(sp)
    1554:	0007a503          	lw	a0,0(a5)
    1558:	e2dff0ef          	jal	1384 <bsp_printf_d>
                        break;
    155c:	fb5ff06f          	j	1510 <bsp_printf+0x54>
                        bsp_printf_X(va_arg(ap,int));
    1560:	00c12783          	lw	a5,12(sp)
    1564:	00478713          	addi	a4,a5,4
    1568:	00e12623          	sw	a4,12(sp)
    156c:	0007a503          	lw	a0,0(a5)
    1570:	ed5ff0ef          	jal	1444 <bsp_printf_X>
                        break;
    1574:	f9dff06f          	j	1510 <bsp_printf+0x54>
                        bsp_printf_x(va_arg(ap,int));
    1578:	00c12783          	lw	a5,12(sp)
    157c:	00478713          	addi	a4,a5,4
    1580:	00e12623          	sw	a4,12(sp)
    1584:	0007a503          	lw	a0,0(a5)
    1588:	e7dff0ef          	jal	1404 <bsp_printf_x>
                        break;
    158c:	f85ff06f          	j	1510 <bsp_printf+0x54>
                        bsp_printf_s("<Floating point printing not enable. Please Enable it at bsp.h first...>");
    1590:	00001537          	lui	a0,0x1
    1594:	61450513          	addi	a0,a0,1556 # 1614 <_data+0x28>
    1598:	dd5ff0ef          	jal	136c <bsp_printf_s>
                        break;
    159c:	f75ff06f          	j	1510 <bsp_printf+0x54>
                while (format[++i]) {
    15a0:	00140413          	addi	s0,s0,1
    15a4:	008487b3          	add	a5,s1,s0
    15a8:	0007c783          	lbu	a5,0(a5)
    15ac:	f60782e3          	beqz	a5,1510 <bsp_printf+0x54>
                    if (format[i] == 'c') {
    15b0:	fa878793          	addi	a5,a5,-88
    15b4:	0ff7f693          	zext.b	a3,a5
    15b8:	02000713          	li	a4,32
    15bc:	fed762e3          	bltu	a4,a3,15a0 <bsp_printf+0xe4>
    15c0:	00269793          	slli	a5,a3,0x2
    15c4:	00001737          	lui	a4,0x1
    15c8:	6cc70713          	addi	a4,a4,1740 # 16cc <_data+0xe0>
    15cc:	00e787b3          	add	a5,a5,a4
    15d0:	0007a783          	lw	a5,0(a5)
    15d4:	00078067          	jr	a5

        va_end(ap);
    }
    15d8:	01c12083          	lw	ra,28(sp)
    15dc:	01812403          	lw	s0,24(sp)
    15e0:	01412483          	lw	s1,20(sp)
    15e4:	04010113          	addi	sp,sp,64
    15e8:	00008067          	ret
