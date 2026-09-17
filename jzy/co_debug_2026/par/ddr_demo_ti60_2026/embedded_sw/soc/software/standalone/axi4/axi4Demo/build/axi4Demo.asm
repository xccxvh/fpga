
build/axi4Demo.elf:     file format elf32-littleriscv


Disassembly of section .init:

00001000 <_start>:

_start:
#ifdef USE_GP
.option push
.option norelax
	la gp, __global_pointer$
    1000:	00001197          	auipc	gp,0x1
    1004:	1d818193          	addi	gp,gp,472 # 21d8 <__global_pointer$>

00001008 <init>:
	sw a0, smp_lottery_lock, a1
    ret
#endif

init:
	la sp, _sp
    1008:	00002117          	auipc	sp,0x2
    100c:	9f810113          	addi	sp,sp,-1544 # 2a00 <__freertos_irq_stack_top>

	/* Load data section */
	la a0, _data_lma
    1010:	00001517          	auipc	a0,0x1
    1014:	82050513          	addi	a0,a0,-2016 # 1830 <_data>
	la a1, _data
    1018:	00001597          	auipc	a1,0x1
    101c:	81858593          	addi	a1,a1,-2024 # 1830 <_data>
	la a2, _edata
    1020:	00001617          	auipc	a2,0x1
    1024:	9d460613          	addi	a2,a2,-1580 # 19f4 <__bss_start>
	bgeu a1, a2, 2f
    1028:	00c5fc63          	bgeu	a1,a2,1040 <init+0x38>
1:
	lw t0, (a0)
    102c:	00052283          	lw	t0,0(a0)
	sw t0, (a1)
    1030:	0055a023          	sw	t0,0(a1)
	addi a0, a0, 4
    1034:	00450513          	addi	a0,a0,4
	addi a1, a1, 4
    1038:	00458593          	addi	a1,a1,4
	bltu a1, a2, 1b
    103c:	fec5e8e3          	bltu	a1,a2,102c <init+0x24>
2:

	/* Clear bss section */
	la a0, __bss_start
    1040:	00001517          	auipc	a0,0x1
    1044:	9b450513          	addi	a0,a0,-1612 # 19f4 <__bss_start>
	la a1, _end
    1048:	00001597          	auipc	a1,0x1
    104c:	9b058593          	addi	a1,a1,-1616 # 19f8 <_end>
	bgeu a0, a1, 2f
    1050:	00b57863          	bgeu	a0,a1,1060 <init+0x58>
1:
	sw zero, (a0)
    1054:	00052023          	sw	zero,0(a0)
	addi a0, a0, 4
    1058:	00450513          	addi	a0,a0,4
	bltu a0, a1, 1b
    105c:	feb56ce3          	bltu	a0,a1,1054 <init+0x4c>
2:

#ifndef NO_LIBC_INIT_ARRAY
	call __libc_init_array
    1060:	010000ef          	jal	1070 <__libc_init_array>
#endif

	call main
    1064:	0a0000ef          	jal	1104 <main>

00001068 <mainDone>:
mainDone:
    j mainDone
    1068:	0000006f          	j	1068 <mainDone>

0000106c <_init>:


	.globl _init
_init:
    ret
    106c:	00008067          	ret

Disassembly of section .text:

00001070 <__libc_init_array>:
    1070:	ff010113          	addi	sp,sp,-16
    1074:	00812423          	sw	s0,8(sp)
    1078:	01212023          	sw	s2,0(sp)
    107c:	00000797          	auipc	a5,0x0
    1080:	7b478793          	addi	a5,a5,1972 # 1830 <_data>
    1084:	00000417          	auipc	s0,0x0
    1088:	7ac40413          	addi	s0,s0,1964 # 1830 <_data>
    108c:	00112623          	sw	ra,12(sp)
    1090:	00912223          	sw	s1,4(sp)
    1094:	40878933          	sub	s2,a5,s0
    1098:	02878063          	beq	a5,s0,10b8 <__libc_init_array+0x48>
    109c:	40295913          	srai	s2,s2,0x2
    10a0:	00000493          	li	s1,0
    10a4:	00042783          	lw	a5,0(s0)
    10a8:	00148493          	addi	s1,s1,1
    10ac:	00440413          	addi	s0,s0,4
    10b0:	000780e7          	jalr	a5
    10b4:	ff24e8e3          	bltu	s1,s2,10a4 <__libc_init_array+0x34>
    10b8:	00000797          	auipc	a5,0x0
    10bc:	77878793          	addi	a5,a5,1912 # 1830 <_data>
    10c0:	00000417          	auipc	s0,0x0
    10c4:	77040413          	addi	s0,s0,1904 # 1830 <_data>
    10c8:	40878933          	sub	s2,a5,s0
    10cc:	40295913          	srai	s2,s2,0x2
    10d0:	00878e63          	beq	a5,s0,10ec <__libc_init_array+0x7c>
    10d4:	00000493          	li	s1,0
    10d8:	00042783          	lw	a5,0(s0)
    10dc:	00148493          	addi	s1,s1,1
    10e0:	00440413          	addi	s0,s0,4
    10e4:	000780e7          	jalr	a5
    10e8:	ff24e8e3          	bltu	s1,s2,10d8 <__libc_init_array+0x68>
    10ec:	00c12083          	lw	ra,12(sp)
    10f0:	00812403          	lw	s0,8(sp)
    10f4:	00412483          	lw	s1,4(sp)
    10f8:	00012903          	lw	s2,0(sp)
    10fc:	01010113          	addi	sp,sp,16
    1100:	00008067          	ret

00001104 <main>:
* @brief This function perform write/read test for the internal BRAM and 
*        AXI4 master interrupt is triggered when the data written to AXI bus is 
*        0xABCD. 
*
******************************************************************************/
void main() {
    1104:	ff010113          	addi	sp,sp,-16
    1108:	00112623          	sw	ra,12(sp)
    u32 data;
    bsp_init();
    110c:	34c000ef          	jal	1458 <bsp_init>

#ifdef SYSTEM_AXI_A_BMB

    bsp_printf("axi4 master demo ! \r\n");
    1110:	00002537          	lui	a0,0x2
    1114:	8f050513          	addi	a0,a0,-1808 # 18f0 <_data+0xc0>
    1118:	424000ef          	jal	153c <bsp_printf>

    for (int i=0; i < AXI_SIZE ; i = i + 4 ){
    111c:	00000793          	li	a5,0
    1120:	0140006f          	j	1134 <main+0x30>
        write_u32(i, AXI + i);
    1124:	e1000737          	lui	a4,0xe1000
    1128:	00e78733          	add	a4,a5,a4
    static inline u32 read_u32(u32 address){
        return *((volatile u32*) address);
    }
    
    static inline void write_u32(u32 data, u32 address){
        *((volatile u32*) address) = data;
    112c:	00f72023          	sw	a5,0(a4) # e1000000 <__freertos_irq_stack_top+0xe0ffd600>
    for (int i=0; i < AXI_SIZE ; i = i + 4 ){
    1130:	00478793          	addi	a5,a5,4
    1134:	7ff00713          	li	a4,2047
    1138:	fef756e3          	bge	a4,a5,1124 <main+0x20>
    }

    for (int i=0; i < AXI_SIZE ; i = i + 4 ){
    113c:	00000593          	li	a1,0
    1140:	7ff00793          	li	a5,2047
    1144:	02b7c663          	blt	a5,a1,1170 <main+0x6c>
        data = read_u32(AXI + i);
    1148:	e10007b7          	lui	a5,0xe1000
    114c:	00f587b3          	add	a5,a1,a5
        return *((volatile u32*) address);
    1150:	0007a603          	lw	a2,0(a5) # e1000000 <__freertos_irq_stack_top+0xe0ffd600>
        if(i != data){
    1154:	00b61663          	bne	a2,a1,1160 <main+0x5c>
    for (int i=0; i < AXI_SIZE ; i = i + 4 ){
    1158:	00458593          	addi	a1,a1,4
    115c:	fe5ff06f          	j	1140 <main+0x3c>
            bsp_printf("Failed at address 0x%x with value 0x%x \r\n", i, data);
    1160:	00002537          	lui	a0,0x2
    1164:	90850513          	addi	a0,a0,-1784 # 1908 <_data+0xd8>
    1168:	3d4000ef          	jal	153c <bsp_printf>
            error_state();
    116c:	500000ef          	jal	166c <error_state>
        }
    }
    bsp_printf("Passed! \r\n");
    1170:	00002537          	lui	a0,0x2
    1174:	93450513          	addi	a0,a0,-1740 # 1934 <_data+0x104>
    1178:	3c4000ef          	jal	153c <bsp_printf>
    bsp_printf("axi4 master interrupt demo ! \r\n");
    117c:	00002537          	lui	a0,0x2
    1180:	94050513          	addi	a0,a0,-1728 # 1940 <_data+0x110>
    1184:	3b8000ef          	jal	153c <bsp_printf>
    intr_init();
    1188:	514000ef          	jal	169c <intr_init>
        *((volatile u32*) address) = data;
    118c:	e1000737          	lui	a4,0xe1000
    1190:	0000b7b7          	lui	a5,0xb
    1194:	bcd78793          	addi	a5,a5,-1075 # abcd <__freertos_irq_stack_top+0x81cd>
    1198:	00f72023          	sw	a5,0(a4) # e1000000 <__freertos_irq_stack_top+0xe0ffd600>
    119c:	00072023          	sw	zero,0(a4)

    bsp_printf("axi4 master is disabled, please enable it to run this app. \r\n");

#endif

}
    11a0:	00c12083          	lw	ra,12(sp)
    11a4:	01010113          	addi	sp,sp,16
    11a8:	00008067          	ret

000011ac <uart_writeAvailability>:
        return *((volatile u32*) address);
    11ac:	00452503          	lw	a0,4(a0)
*          of available spaces for writing data from bits 23 to 16. It then
*          returns this value after masking with 0xFF.
*
******************************************************************************/
    static u32 uart_writeAvailability(u32 reg){
        return (read_u32(reg + UART_STATUS) >> 16) & 0xFF;
    11b0:	01055513          	srli	a0,a0,0x10
    }
    11b4:	0ff57513          	zext.b	a0,a0
    11b8:	00008067          	ret

000011bc <uart_write>:
* @note    The function waits until there is available space in the UART buffer
*          for writing data. Once space is available, it writes the character
*          data to the UART data register.
*
******************************************************************************/
    static void uart_write(u32 reg, char data){
    11bc:	ff010113          	addi	sp,sp,-16
    11c0:	00112623          	sw	ra,12(sp)
    11c4:	00812423          	sw	s0,8(sp)
    11c8:	00912223          	sw	s1,4(sp)
    11cc:	00050413          	mv	s0,a0
    11d0:	00058493          	mv	s1,a1
        while(uart_writeAvailability(reg) == 0);
    11d4:	00040513          	mv	a0,s0
    11d8:	fd5ff0ef          	jal	11ac <uart_writeAvailability>
    11dc:	fe050ce3          	beqz	a0,11d4 <uart_write+0x18>
        *((volatile u32*) address) = data;
    11e0:	00942023          	sw	s1,0(s0)
        write_u32(data, reg + UART_DATA);
    }
    11e4:	00c12083          	lw	ra,12(sp)
    11e8:	00812403          	lw	s0,8(sp)
    11ec:	00412483          	lw	s1,4(sp)
    11f0:	01010113          	addi	sp,sp,16
    11f4:	00008067          	ret

000011f8 <uart_applyConfig>:
*          value using data length, parity, and stop bit settings from the configuration
*          structure, and writes this value to the UART frame configuration register.
*
******************************************************************************/
    static void uart_applyConfig(u32 reg, Uart_Config *config){
        write_u32(config->clockDivider, reg + UART_CLOCK_DIVIDER);
    11f8:	00c5a783          	lw	a5,12(a1)
    11fc:	00f52423          	sw	a5,8(a0)
        write_u32(((config->dataLength-1) << 0) | (config->parity << 8) | (config->stop << 16), reg + UART_FRAME_CONFIG);
    1200:	0005a783          	lw	a5,0(a1)
    1204:	fff78793          	addi	a5,a5,-1
    1208:	0045a703          	lw	a4,4(a1)
    120c:	00871713          	slli	a4,a4,0x8
    1210:	00e7e7b3          	or	a5,a5,a4
    1214:	0085a703          	lw	a4,8(a1)
    1218:	01071713          	slli	a4,a4,0x10
    121c:	00e7e7b3          	or	a5,a5,a4
    1220:	00f52623          	sw	a5,12(a0)
    }
    1224:	00008067          	ret

00001228 <_putchar>:
#include <math.h>
#include <string.h>
#include "bsp.h"

#if (ENABLE_BSP_PRINTF)
    static void _putchar(char character){
    1228:	ff010113          	addi	sp,sp,-16
    122c:	00112623          	sw	ra,12(sp)
    1230:	00050593          	mv	a1,a0
        #if (ENABLE_SEMIHOSTING_PRINT == 1)
            sh_writec(character);
        #else
            bsp_putChar(character);
    1234:	f8010537          	lui	a0,0xf8010
    1238:	f85ff0ef          	jal	11bc <uart_write>
        #endif // (ENABLE_SEMIHOSTING_PRINT == 1)
    }
    123c:	00c12083          	lw	ra,12(sp)
    1240:	01010113          	addi	sp,sp,16
    1244:	00008067          	ret

00001248 <_putchar_s>:

    static void _putchar_s(char *p)
    {
    1248:	ff010113          	addi	sp,sp,-16
    124c:	00112623          	sw	ra,12(sp)
    1250:	00812423          	sw	s0,8(sp)
    1254:	00050413          	mv	s0,a0
    #if (ENABLE_SEMIHOSTING_PRINT == 1)
        sh_write0(p);
    #else
        while (*p)
    1258:	00c0006f          	j	1264 <_putchar_s+0x1c>
            _putchar(*(p++));
    125c:	00140413          	addi	s0,s0,1
    1260:	fc9ff0ef          	jal	1228 <_putchar>
        while (*p)
    1264:	00044503          	lbu	a0,0(s0)
    1268:	fe051ae3          	bnez	a0,125c <_putchar_s+0x14>
    #endif // (ENABLE_SEMIHOSTING_PRINT == 1)
    }
    126c:	00c12083          	lw	ra,12(sp)
    1270:	00812403          	lw	s0,8(sp)
    1274:	01010113          	addi	sp,sp,16
    1278:	00008067          	ret

0000127c <bsp_printHex>:

        static void bsp_printHex(uint32_t val)
    {
    127c:	ff010113          	addi	sp,sp,-16
    1280:	00112623          	sw	ra,12(sp)
    1284:	00812423          	sw	s0,8(sp)
    1288:	00912223          	sw	s1,4(sp)
    128c:	00050493          	mv	s1,a0
        uint32_t digits;
        digits =8;

        for (int i = (4*digits)-4; i >= 0; i -= 4) {
    1290:	01c00413          	li	s0,28
    1294:	0240006f          	j	12b8 <bsp_printHex+0x3c>
            _putchar("0123456789ABCDEF"[(val >> i) % 16]);
    1298:	0084d733          	srl	a4,s1,s0
    129c:	00f77713          	andi	a4,a4,15
    12a0:	000027b7          	lui	a5,0x2
    12a4:	83078793          	addi	a5,a5,-2000 # 1830 <_data>
    12a8:	00e787b3          	add	a5,a5,a4
    12ac:	0007c503          	lbu	a0,0(a5)
    12b0:	f79ff0ef          	jal	1228 <_putchar>
        for (int i = (4*digits)-4; i >= 0; i -= 4) {
    12b4:	ffc40413          	addi	s0,s0,-4
    12b8:	fe0450e3          	bgez	s0,1298 <bsp_printHex+0x1c>
        }
    }
    12bc:	00c12083          	lw	ra,12(sp)
    12c0:	00812403          	lw	s0,8(sp)
    12c4:	00412483          	lw	s1,4(sp)
    12c8:	01010113          	addi	sp,sp,16
    12cc:	00008067          	ret

000012d0 <bsp_printHex_lower>:

    static void bsp_printHex_lower(uint32_t val)
    {
    12d0:	ff010113          	addi	sp,sp,-16
    12d4:	00112623          	sw	ra,12(sp)
    12d8:	00812423          	sw	s0,8(sp)
    12dc:	00912223          	sw	s1,4(sp)
    12e0:	00050493          	mv	s1,a0
        uint32_t digits;
        digits =8;

        for (int i = (4*digits)-4; i >= 0; i -= 4) {
    12e4:	01c00413          	li	s0,28
    12e8:	0240006f          	j	130c <bsp_printHex_lower+0x3c>
            _putchar("0123456789abcdef"[(val >> i) % 16]);
    12ec:	0084d733          	srl	a4,s1,s0
    12f0:	00f77713          	andi	a4,a4,15
    12f4:	000027b7          	lui	a5,0x2
    12f8:	84478793          	addi	a5,a5,-1980 # 1844 <_data+0x14>
    12fc:	00e787b3          	add	a5,a5,a4
    1300:	0007c503          	lbu	a0,0(a5)
    1304:	f25ff0ef          	jal	1228 <_putchar>
        for (int i = (4*digits)-4; i >= 0; i -= 4) {
    1308:	ffc40413          	addi	s0,s0,-4
    130c:	fe0450e3          	bgez	s0,12ec <bsp_printHex_lower+0x1c>

        }
    }
    1310:	00c12083          	lw	ra,12(sp)
    1314:	00812403          	lw	s0,8(sp)
    1318:	00412483          	lw	s1,4(sp)
    131c:	01010113          	addi	sp,sp,16
    1320:	00008067          	ret

00001324 <bsp_printf_c>:
*
* @param c: The character to be output.
*
******************************************************************************/
    static void bsp_printf_c(int c)
    {
    1324:	ff010113          	addi	sp,sp,-16
    1328:	00112623          	sw	ra,12(sp)
        _putchar(c);
    132c:	0ff57513          	zext.b	a0,a0
    1330:	ef9ff0ef          	jal	1228 <_putchar>
    }
    1334:	00c12083          	lw	ra,12(sp)
    1338:	01010113          	addi	sp,sp,16
    133c:	00008067          	ret

00001340 <bsp_printf_s>:
*
* @param s: A pointer to the null-terminated string to be output.
*
*******************************************************************************/
    static void bsp_printf_s(char *p)
    {
    1340:	ff010113          	addi	sp,sp,-16
    1344:	00112623          	sw	ra,12(sp)
        _putchar_s(p);
    1348:	f01ff0ef          	jal	1248 <_putchar_s>
    }
    134c:	00c12083          	lw	ra,12(sp)
    1350:	01010113          	addi	sp,sp,16
    1354:	00008067          	ret

00001358 <bsp_printf_d>:
* - Handles negative numbers by printing a '-' sign.
* - Uses the 'bsp_printf_c' function to print each character.
*
******************************************************************************/
    static void bsp_printf_d(int val)
    {
    1358:	fd010113          	addi	sp,sp,-48
    135c:	02112623          	sw	ra,44(sp)
    1360:	02812423          	sw	s0,40(sp)
    1364:	02912223          	sw	s1,36(sp)
    1368:	00050493          	mv	s1,a0
        char buffer[32];
        char *p = buffer;
        if (val < 0) {
    136c:	00054663          	bltz	a0,1378 <bsp_printf_d+0x20>
    {
    1370:	00010413          	mv	s0,sp
    1374:	02c0006f          	j	13a0 <bsp_printf_d+0x48>
            bsp_printf_c('-');
    1378:	02d00513          	li	a0,45
    137c:	fa9ff0ef          	jal	1324 <bsp_printf_c>
            val = -val;
    1380:	409004b3          	neg	s1,s1
    1384:	fedff06f          	j	1370 <bsp_printf_d+0x18>
        }
        while (val || p == buffer) {
            *(p++) = '0' + val % 10;
    1388:	00a00713          	li	a4,10
    138c:	02e4e7b3          	rem	a5,s1,a4
    1390:	03078793          	addi	a5,a5,48
    1394:	00f40023          	sb	a5,0(s0)
            val = val / 10;
    1398:	02e4c4b3          	div	s1,s1,a4
            *(p++) = '0' + val % 10;
    139c:	00140413          	addi	s0,s0,1
        while (val || p == buffer) {
    13a0:	fe0494e3          	bnez	s1,1388 <bsp_printf_d+0x30>
    13a4:	00010793          	mv	a5,sp
    13a8:	fef400e3          	beq	s0,a5,1388 <bsp_printf_d+0x30>
        }
        while (p != buffer)
    13ac:	00010793          	mv	a5,sp
    13b0:	00f40a63          	beq	s0,a5,13c4 <bsp_printf_d+0x6c>
            bsp_printf_c(*(--p));
    13b4:	fff40413          	addi	s0,s0,-1
    13b8:	00044503          	lbu	a0,0(s0)
    13bc:	f69ff0ef          	jal	1324 <bsp_printf_c>
    13c0:	fedff06f          	j	13ac <bsp_printf_d+0x54>
    }
    13c4:	02c12083          	lw	ra,44(sp)
    13c8:	02812403          	lw	s0,40(sp)
    13cc:	02412483          	lw	s1,36(sp)
    13d0:	03010113          	addi	sp,sp,48
    13d4:	00008067          	ret

000013d8 <bsp_printf_x>:
* - Calls 'bsp_printHex_lower' to print the hexadecimal representation.
* - Determines the number of leading zeros to be printed based on the value.
*
******************************************************************************/
    static void bsp_printf_x(int val)
    {
    13d8:	ff010113          	addi	sp,sp,-16
    13dc:	00112623          	sw	ra,12(sp)
        int i,digi=2;

        for(i=0;i<8;i++)
    13e0:	00000713          	li	a4,0
    13e4:	00700793          	li	a5,7
    13e8:	02e7c063          	blt	a5,a4,1408 <bsp_printf_x+0x30>
        {
            if((val & (0xFFFFFFF0 <<(4*i))) == 0)
    13ec:	00271693          	slli	a3,a4,0x2
    13f0:	ff000793          	li	a5,-16
    13f4:	00d797b3          	sll	a5,a5,a3
    13f8:	00f577b3          	and	a5,a0,a5
    13fc:	00078663          	beqz	a5,1408 <bsp_printf_x+0x30>
        for(i=0;i<8;i++)
    1400:	00170713          	addi	a4,a4,1
    1404:	fe1ff06f          	j	13e4 <bsp_printf_x+0xc>
            {
                digi=i+1;
                break;
            }
        }
        bsp_printHex_lower(val);
    1408:	ec9ff0ef          	jal	12d0 <bsp_printHex_lower>
    }
    140c:	00c12083          	lw	ra,12(sp)
    1410:	01010113          	addi	sp,sp,16
    1414:	00008067          	ret

00001418 <bsp_printf_X>:
* - Calls 'bsp_printHex' to print the uppercase hexadecimal representation.
* - Determines the number of leading zeros to be printed based on the value.
*
******************************************************************************/
    static void bsp_printf_X(int val)
        {
    1418:	ff010113          	addi	sp,sp,-16
    141c:	00112623          	sw	ra,12(sp)
            int i,digi=2;

            for(i=0;i<8;i++)
    1420:	00000713          	li	a4,0
    1424:	00700793          	li	a5,7
    1428:	02e7c063          	blt	a5,a4,1448 <bsp_printf_X+0x30>
            {
                if((val & (0xFFFFFFF0 <<(4*i))) == 0)
    142c:	00271693          	slli	a3,a4,0x2
    1430:	ff000793          	li	a5,-16
    1434:	00d797b3          	sll	a5,a5,a3
    1438:	00f577b3          	and	a5,a0,a5
    143c:	00078663          	beqz	a5,1448 <bsp_printf_X+0x30>
            for(i=0;i<8;i++)
    1440:	00170713          	addi	a4,a4,1
    1444:	fe1ff06f          	j	1424 <bsp_printf_X+0xc>
                {
                    digi=i+1;
                    break;
                }
            }
            bsp_printHex(val);
    1448:	e35ff0ef          	jal	127c <bsp_printHex>
        }
    144c:	00c12083          	lw	ra,12(sp)
    1450:	01010113          	addi	sp,sp,16
    1454:	00008067          	ret

00001458 <bsp_init>:
    *   1. UART baudrate
    *   2. 
    */
////////////////////////////////////////////////////////////////////////////////
    static void bsp_init()
    {
    1458:	fe010113          	addi	sp,sp,-32
    145c:	00112e23          	sw	ra,28(sp)
        Uart_Config uartConfig;
        uartConfig.dataLength   = BITS_8;
    1460:	00800793          	li	a5,8
    1464:	00f12023          	sw	a5,0(sp)
        uartConfig.parity       = NONE;
    1468:	00012223          	sw	zero,4(sp)
        uartConfig.stop         = ONE;
    146c:	00012423          	sw	zero,8(sp)
        uartConfig.clockDivider = BSP_CLINT_HZ/(BSP_UART_BAUDRATE*BSP_UART_DATA_LEN)-1;
    1470:	06b00793          	li	a5,107
    1474:	00f12623          	sw	a5,12(sp)
        uart_applyConfig(BSP_UART_TERMINAL, &uartConfig);    
    1478:	00010593          	mv	a1,sp
    147c:	f8010537          	lui	a0,0xf8010
    1480:	d79ff0ef          	jal	11f8 <uart_applyConfig>
    }
    1484:	01c12083          	lw	ra,28(sp)
    1488:	02010113          	addi	sp,sp,32
    148c:	00008067          	ret

00001490 <plic_set_priority>:
*          specified priority value to the calculated address, effectively
*          setting the priority for the specified interrupt gateway in the PLIC.
*
******************************************************************************/
    static void plic_set_priority(u32 plic, u32 gateway, u32 priority){
        write_u32(priority, plic + PLIC_PRIORITY_BASE + gateway*4);
    1490:	00259593          	slli	a1,a1,0x2
    1494:	00a585b3          	add	a1,a1,a0
    1498:	00c5a023          	sw	a2,0(a1)
    }
    149c:	00008067          	ret

000014a0 <plic_set_enable>:
*          to the enable register.
*
******************************************************************************/

    static void plic_set_enable(u32 plic, u32 target,u32 gateway, u32 enable){
        u32 word = plic + PLIC_ENABLE_BASE + target * PLIC_ENABLE_PER_HART + (gateway / 32 * 4);
    14a0:	00759593          	slli	a1,a1,0x7
    14a4:	00a585b3          	add	a1,a1,a0
    14a8:	00565793          	srli	a5,a2,0x5
    14ac:	00279793          	slli	a5,a5,0x2
    14b0:	00f587b3          	add	a5,a1,a5
    14b4:	00002737          	lui	a4,0x2
    14b8:	00e787b3          	add	a5,a5,a4
        u32 mask = 1 << (gateway % 32);
    14bc:	00100713          	li	a4,1
    14c0:	00c71633          	sll	a2,a4,a2
        if (enable)
    14c4:	00068a63          	beqz	a3,14d8 <plic_set_enable+0x38>
        return *((volatile u32*) address);
    14c8:	0007a703          	lw	a4,0(a5)
            write_u32(read_u32(word) | mask, word);
    14cc:	00e66633          	or	a2,a2,a4
        *((volatile u32*) address) = data;
    14d0:	00c7a023          	sw	a2,0(a5)
    }
    14d4:	00008067          	ret
        return *((volatile u32*) address);
    14d8:	0007a703          	lw	a4,0(a5)
        else
            write_u32(read_u32(word) & ~mask, word);
    14dc:	fff64613          	not	a2,a2
    14e0:	00e67633          	and	a2,a2,a4
        *((volatile u32*) address) = data;
    14e4:	00c7a023          	sw	a2,0(a5)
    }
    14e8:	00008067          	ret

000014ec <plic_set_threshold>:
*          to the calculated address, effectively setting the threshold for the
*          specified target in the PLIC.
*
******************************************************************************/   
    static void plic_set_threshold(u32 plic, u32 target, u32 threshold){
        write_u32(threshold, plic + PLIC_THRESHOLD_BASE + target*PLIC_CONTEXT_PER_HART);
    14ec:	00c59593          	slli	a1,a1,0xc
    14f0:	00a585b3          	add	a1,a1,a0
    14f4:	002007b7          	lui	a5,0x200
    14f8:	00f585b3          	add	a1,a1,a5
    14fc:	00c5a023          	sw	a2,0(a1)
    }
    1500:	00008067          	ret

00001504 <plic_claim>:
*          value from the calculated address, effectively claiming an interrupt
*          for the specified target in the PLIC.
*
******************************************************************************/
    static u32 plic_claim(u32 plic, u32 target){
        return read_u32(plic + PLIC_CLAIM_BASE + target*PLIC_CONTEXT_PER_HART);
    1504:	00c59593          	slli	a1,a1,0xc
    1508:	00a585b3          	add	a1,a1,a0
    150c:	002007b7          	lui	a5,0x200
    1510:	00478793          	addi	a5,a5,4 # 200004 <__freertos_irq_stack_top+0x1fd604>
    1514:	00f585b3          	add	a1,a1,a5
        return *((volatile u32*) address);
    1518:	0005a503          	lw	a0,0(a1)
    }
    151c:	00008067          	ret

00001520 <plic_release>:
*          to the calculated address, effectively releasing the claimed interrupt
*          for the specified target in the PLIC.
*
******************************************************************************/
    static void plic_release(u32 plic, u32 target, u32 gateway){
        write_u32(gateway,plic + PLIC_CLAIM_BASE + target*PLIC_CONTEXT_PER_HART);
    1520:	00c59593          	slli	a1,a1,0xc
    1524:	00a585b3          	add	a1,a1,a0
    1528:	002007b7          	lui	a5,0x200
    152c:	00478793          	addi	a5,a5,4 # 200004 <__freertos_irq_stack_top+0x1fd604>
    1530:	00f585b3          	add	a1,a1,a5
        *((volatile u32*) address) = data;
    1534:	00c5a023          	sw	a2,0(a1)
    }
    1538:	00008067          	ret

0000153c <bsp_printf>:
* - Handles each format specifier by calling the appropriate helper function.
* - If floating-point support is disabled, prints a warning for the 'f' specifier.
*
******************************************************************************/
    static void bsp_printf(const char *format, ...)
    {
    153c:	fc010113          	addi	sp,sp,-64
    1540:	00112e23          	sw	ra,28(sp)
    1544:	00812c23          	sw	s0,24(sp)
    1548:	00912a23          	sw	s1,20(sp)
    154c:	00050493          	mv	s1,a0
    1550:	02b12223          	sw	a1,36(sp)
    1554:	02c12423          	sw	a2,40(sp)
    1558:	02d12623          	sw	a3,44(sp)
    155c:	02e12823          	sw	a4,48(sp)
    1560:	02f12a23          	sw	a5,52(sp)
    1564:	03012c23          	sw	a6,56(sp)
    1568:	03112e23          	sw	a7,60(sp)
        int i;
        va_list ap;

        va_start(ap, format);
    156c:	02410793          	addi	a5,sp,36
    1570:	00f12623          	sw	a5,12(sp)

        for (i = 0; format[i]; i++)
    1574:	00000413          	li	s0,0
    1578:	01c0006f          	j	1594 <bsp_printf+0x58>
            if (format[i] == '%') {
                while (format[++i]) {
                    if (format[i] == 'c') {
                        bsp_printf_c(va_arg(ap,int));
    157c:	00c12783          	lw	a5,12(sp)
    1580:	00478713          	addi	a4,a5,4
    1584:	00e12623          	sw	a4,12(sp)
    1588:	0007a503          	lw	a0,0(a5)
    158c:	d99ff0ef          	jal	1324 <bsp_printf_c>
        for (i = 0; format[i]; i++)
    1590:	00140413          	addi	s0,s0,1
    1594:	008487b3          	add	a5,s1,s0
    1598:	0007c503          	lbu	a0,0(a5)
    159c:	0a050e63          	beqz	a0,1658 <bsp_printf+0x11c>
            if (format[i] == '%') {
    15a0:	02500793          	li	a5,37
    15a4:	06f50e63          	beq	a0,a5,1620 <bsp_printf+0xe4>
                        break;
                    }
#endif //#if (ENABLE_FLOATING_POINT_SUPPORT)
                }
            } else
                bsp_printf_c(format[i]);
    15a8:	d7dff0ef          	jal	1324 <bsp_printf_c>
    15ac:	fe5ff06f          	j	1590 <bsp_printf+0x54>
                        bsp_printf_s(va_arg(ap,char*));
    15b0:	00c12783          	lw	a5,12(sp)
    15b4:	00478713          	addi	a4,a5,4
    15b8:	00e12623          	sw	a4,12(sp)
    15bc:	0007a503          	lw	a0,0(a5)
    15c0:	d81ff0ef          	jal	1340 <bsp_printf_s>
                        break;
    15c4:	fcdff06f          	j	1590 <bsp_printf+0x54>
                        bsp_printf_d(va_arg(ap,int));
    15c8:	00c12783          	lw	a5,12(sp)
    15cc:	00478713          	addi	a4,a5,4
    15d0:	00e12623          	sw	a4,12(sp)
    15d4:	0007a503          	lw	a0,0(a5)
    15d8:	d81ff0ef          	jal	1358 <bsp_printf_d>
                        break;
    15dc:	fb5ff06f          	j	1590 <bsp_printf+0x54>
                        bsp_printf_X(va_arg(ap,int));
    15e0:	00c12783          	lw	a5,12(sp)
    15e4:	00478713          	addi	a4,a5,4
    15e8:	00e12623          	sw	a4,12(sp)
    15ec:	0007a503          	lw	a0,0(a5)
    15f0:	e29ff0ef          	jal	1418 <bsp_printf_X>
                        break;
    15f4:	f9dff06f          	j	1590 <bsp_printf+0x54>
                        bsp_printf_x(va_arg(ap,int));
    15f8:	00c12783          	lw	a5,12(sp)
    15fc:	00478713          	addi	a4,a5,4
    1600:	00e12623          	sw	a4,12(sp)
    1604:	0007a503          	lw	a0,0(a5)
    1608:	dd1ff0ef          	jal	13d8 <bsp_printf_x>
                        break;
    160c:	f85ff06f          	j	1590 <bsp_printf+0x54>
                        bsp_printf_s("<Floating point printing not enable. Please Enable it at bsp.h first...>");
    1610:	00002537          	lui	a0,0x2
    1614:	85850513          	addi	a0,a0,-1960 # 1858 <_data+0x28>
    1618:	d29ff0ef          	jal	1340 <bsp_printf_s>
                        break;
    161c:	f75ff06f          	j	1590 <bsp_printf+0x54>
                while (format[++i]) {
    1620:	00140413          	addi	s0,s0,1
    1624:	008487b3          	add	a5,s1,s0
    1628:	0007c783          	lbu	a5,0(a5)
    162c:	f60782e3          	beqz	a5,1590 <bsp_printf+0x54>
                    if (format[i] == 'c') {
    1630:	fa878793          	addi	a5,a5,-88
    1634:	0ff7f693          	zext.b	a3,a5
    1638:	02000713          	li	a4,32
    163c:	fed762e3          	bltu	a4,a3,1620 <bsp_printf+0xe4>
    1640:	00269793          	slli	a5,a3,0x2
    1644:	00002737          	lui	a4,0x2
    1648:	96070713          	addi	a4,a4,-1696 # 1960 <_data+0x130>
    164c:	00e787b3          	add	a5,a5,a4
    1650:	0007a783          	lw	a5,0(a5)
    1654:	00078067          	jr	a5

        va_end(ap);
    }
    1658:	01c12083          	lw	ra,28(sp)
    165c:	01812403          	lw	s0,24(sp)
    1660:	01412483          	lw	s1,20(sp)
    1664:	04010113          	addi	sp,sp,64
    1668:	00008067          	ret

0000166c <error_state>:
void error_state() {
    166c:	ff010113          	addi	sp,sp,-16
    1670:	00112623          	sw	ra,12(sp)
    bsp_printf("Failed! \r\n");
    1674:	00002537          	lui	a0,0x2
    1678:	8a450513          	addi	a0,a0,-1884 # 18a4 <_data+0x74>
    167c:	ec1ff0ef          	jal	153c <bsp_printf>
    while (1) {}
    1680:	0000006f          	j	1680 <error_state+0x14>

00001684 <crash>:
void crash(){
    1684:	ff010113          	addi	sp,sp,-16
    1688:	00112623          	sw	ra,12(sp)
    bsp_printf("\r\n*** CRASH ***\r\n");
    168c:	00002537          	lui	a0,0x2
    1690:	8b050513          	addi	a0,a0,-1872 # 18b0 <_data+0x80>
    1694:	ea9ff0ef          	jal	153c <bsp_printf>
    while(1);
    1698:	0000006f          	j	1698 <crash+0x14>

0000169c <intr_init>:
void intr_init(){
    169c:	ff010113          	addi	sp,sp,-16
    16a0:	00112623          	sw	ra,12(sp)
    plic_set_threshold(BSP_PLIC, BSP_PLIC_CPU_0, 0); 
    16a4:	00000613          	li	a2,0
    16a8:	00000593          	li	a1,0
    16ac:	f8c00537          	lui	a0,0xf8c00
    16b0:	e3dff0ef          	jal	14ec <plic_set_threshold>
    plic_set_enable(BSP_PLIC, BSP_PLIC_CPU_0, SYSTEM_PLIC_SYSTEM_AXI_A_INTERRUPT, 1);
    16b4:	00100693          	li	a3,1
    16b8:	01e00613          	li	a2,30
    16bc:	00000593          	li	a1,0
    16c0:	f8c00537          	lui	a0,0xf8c00
    16c4:	dddff0ef          	jal	14a0 <plic_set_enable>
    plic_set_priority(BSP_PLIC, SYSTEM_PLIC_SYSTEM_AXI_A_INTERRUPT, 1);
    16c8:	00100613          	li	a2,1
    16cc:	01e00593          	li	a1,30
    16d0:	f8c00537          	lui	a0,0xf8c00
    16d4:	dbdff0ef          	jal	1490 <plic_set_priority>
    csr_write(mtvec, trap_entry); 
    16d8:	000017b7          	lui	a5,0x1
    16dc:	7a078793          	addi	a5,a5,1952 # 17a0 <trap_entry>
    16e0:	30579073          	csrw	mtvec,a5
    csr_set(mie, MIE_MEIE); 
    16e4:	000017b7          	lui	a5,0x1
    16e8:	80078793          	addi	a5,a5,-2048 # 800 <CUSTOM2+0x7a5>
    16ec:	3047a073          	csrs	mie,a5
    csr_write(mstatus, csr_read(mstatus) | MSTATUS_MPP | MSTATUS_MIE);
    16f0:	300027f3          	csrr	a5,mstatus
    16f4:	00002737          	lui	a4,0x2
    16f8:	80870713          	addi	a4,a4,-2040 # 1808 <trap_entry+0x68>
    16fc:	00e7e7b3          	or	a5,a5,a4
    1700:	30079073          	csrw	mstatus,a5
}
    1704:	00c12083          	lw	ra,12(sp)
    1708:	01010113          	addi	sp,sp,16
    170c:	00008067          	ret

00001710 <axiInterrupt>:
void axiInterrupt(){
    1710:	ff010113          	addi	sp,sp,-16
    1714:	00112623          	sw	ra,12(sp)
    1718:	00812423          	sw	s0,8(sp)
    while(claim = plic_claim(BSP_PLIC, BSP_PLIC_CPU_0)){
    171c:	00000593          	li	a1,0
    1720:	f8c00537          	lui	a0,0xf8c00
    1724:	de1ff0ef          	jal	1504 <plic_claim>
    1728:	00050413          	mv	s0,a0
    172c:	02050863          	beqz	a0,175c <axiInterrupt+0x4c>
        switch(claim){
    1730:	01e00793          	li	a5,30
    1734:	02f41263          	bne	s0,a5,1758 <axiInterrupt+0x48>
            bsp_printf("Entered AXI Interrupt Routine, Passed! \r\n");
    1738:	00002537          	lui	a0,0x2
    173c:	8c450513          	addi	a0,a0,-1852 # 18c4 <_data+0x94>
    1740:	dfdff0ef          	jal	153c <bsp_printf>
        plic_release(BSP_PLIC, BSP_PLIC_CPU_0, claim); 
    1744:	00040613          	mv	a2,s0
    1748:	00000593          	li	a1,0
    174c:	f8c00537          	lui	a0,0xf8c00
    1750:	dd1ff0ef          	jal	1520 <plic_release>
    1754:	fc9ff06f          	j	171c <axiInterrupt+0xc>
        default: crash(); break;
    1758:	f2dff0ef          	jal	1684 <crash>
}
    175c:	00c12083          	lw	ra,12(sp)
    1760:	00812403          	lw	s0,8(sp)
    1764:	01010113          	addi	sp,sp,16
    1768:	00008067          	ret

0000176c <trap>:
void trap(){
    176c:	ff010113          	addi	sp,sp,-16
    1770:	00112623          	sw	ra,12(sp)
    int32_t mcause    = csr_read(mcause);
    1774:	342027f3          	csrr	a5,mcause
    if(interrupt){
    1778:	0207d263          	bgez	a5,179c <trap+0x30>
    177c:	00f7f713          	andi	a4,a5,15
        switch(cause){
    1780:	00b00793          	li	a5,11
    1784:	00f71a63          	bne	a4,a5,1798 <trap+0x2c>
        case CAUSE_MACHINE_EXTERNAL: axiInterrupt(); break;
    1788:	f89ff0ef          	jal	1710 <axiInterrupt>
}
    178c:	00c12083          	lw	ra,12(sp)
    1790:	01010113          	addi	sp,sp,16
    1794:	00008067          	ret
        default: crash(); break;
    1798:	eedff0ef          	jal	1684 <crash>
        crash();
    179c:	ee9ff0ef          	jal	1684 <crash>

000017a0 <trap_entry>:

trap_entry:
#ifdef __riscv_flen
  addi sp, sp, -STACK_SIZE
#else
  addi sp, sp, -64
    17a0:	fc010113          	addi	sp,sp,-64
#endif
  sw x1,   0*4(sp)
    17a4:	00112023          	sw	ra,0(sp)
  sw x5,   1*4(sp)
    17a8:	00512223          	sw	t0,4(sp)
  sw x6,   2*4(sp)
    17ac:	00612423          	sw	t1,8(sp)
  sw x7,   3*4(sp)
    17b0:	00712623          	sw	t2,12(sp)
  sw x10,  4*4(sp)
    17b4:	00a12823          	sw	a0,16(sp)
  sw x11,  5*4(sp)
    17b8:	00b12a23          	sw	a1,20(sp)
  sw x12,  6*4(sp)
    17bc:	00c12c23          	sw	a2,24(sp)
  sw x13,  7*4(sp)
    17c0:	00d12e23          	sw	a3,28(sp)
  sw x14,  8*4(sp)
    17c4:	02e12023          	sw	a4,32(sp)
  sw x15,  9*4(sp)
    17c8:	02f12223          	sw	a5,36(sp)
  sw x16, 10*4(sp)
    17cc:	03012423          	sw	a6,40(sp)
  sw x17, 11*4(sp)
    17d0:	03112623          	sw	a7,44(sp)
  sw x28, 12*4(sp)
    17d4:	03c12823          	sw	t3,48(sp)
  sw x29, 13*4(sp)
    17d8:	03d12a23          	sw	t4,52(sp)
  sw x30, 14*4(sp)
    17dc:	03e12c23          	sw	t5,56(sp)
  sw x31, 15*4(sp)
    17e0:	03f12e23          	sw	t6,60(sp)
  FSTORE f30, 64 + 18*FPR_SIZE(sp)
  FSTORE f31, 64 + 19*FPR_SIZE(sp)
  csrr t0, fcsr
  sw t0, 64 + 20*FPR_SIZE(sp)
#endif
  call trap
    17e4:	f89ff0ef          	jal	176c <trap>
  FLOAD f28, 64 + 16*FPR_SIZE(sp)
  FLOAD f29, 64 + 17*FPR_SIZE(sp)
  FLOAD f30, 64 + 18*FPR_SIZE(sp)
  FLOAD f31, 64 + 19*FPR_SIZE(sp)
#endif
  lw x1 ,  0*4(sp)
    17e8:	00012083          	lw	ra,0(sp)
  lw x5,   1*4(sp)
    17ec:	00412283          	lw	t0,4(sp)
  lw x6,   2*4(sp)
    17f0:	00812303          	lw	t1,8(sp)
  lw x7,   3*4(sp)
    17f4:	00c12383          	lw	t2,12(sp)
  lw x10,  4*4(sp)
    17f8:	01012503          	lw	a0,16(sp)
  lw x11,  5*4(sp)
    17fc:	01412583          	lw	a1,20(sp)
  lw x12,  6*4(sp)
    1800:	01812603          	lw	a2,24(sp)
  lw x13,  7*4(sp)
    1804:	01c12683          	lw	a3,28(sp)
  lw x14,  8*4(sp)
    1808:	02012703          	lw	a4,32(sp)
  lw x15,  9*4(sp)
    180c:	02412783          	lw	a5,36(sp)
  lw x16, 10*4(sp)
    1810:	02812803          	lw	a6,40(sp)
  lw x17, 11*4(sp)
    1814:	02c12883          	lw	a7,44(sp)
  lw x28, 12*4(sp)
    1818:	03012e03          	lw	t3,48(sp)
  lw x29, 13*4(sp)
    181c:	03412e83          	lw	t4,52(sp)
  lw x30, 14*4(sp)
    1820:	03812f03          	lw	t5,56(sp)
  lw x31, 15*4(sp)
    1824:	03c12f83          	lw	t6,60(sp)
#ifdef __riscv_flen
  addi sp, sp, STACK_SIZE
#else
  addi sp, sp, 64
    1828:	04010113          	addi	sp,sp,64
#endif
    182c:	30200073          	mret
