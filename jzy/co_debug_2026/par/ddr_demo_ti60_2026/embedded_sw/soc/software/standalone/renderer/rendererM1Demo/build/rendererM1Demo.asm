
build/rendererM1Demo.elf:     file format elf32-littleriscv


Disassembly of section .init:

00001000 <_start>:

_start:
#ifdef USE_GP
.option push
.option norelax
	la gp, __global_pointer$
    1000:	00004197          	auipc	gp,0x4
    1004:	c7818193          	addi	gp,gp,-904 # 4c78 <__global_pointer$>

00001008 <init>:
	sw a0, smp_lottery_lock, a1
    ret
#endif

init:
	la sp, _sp
    1008:	00005117          	auipc	sp,0x5
    100c:	a6810113          	addi	sp,sp,-1432 # 5a70 <__freertos_irq_stack_top>

	/* Load data section */
	la a0, _data_lma
    1010:	00003517          	auipc	a0,0x3
    1014:	ee450513          	addi	a0,a0,-284 # 3ef4 <_data>
	la a1, _data
    1018:	00003597          	auipc	a1,0x3
    101c:	edc58593          	addi	a1,a1,-292 # 3ef4 <_data>
	la a2, _edata
    1020:	00003617          	auipc	a2,0x3
    1024:	47460613          	addi	a2,a2,1140 # 4494 <__bss_start>
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
    1040:	00003517          	auipc	a0,0x3
    1044:	45450513          	addi	a0,a0,1108 # 4494 <__bss_start>
	la a1, _end
    1048:	00004597          	auipc	a1,0x4
    104c:	a2858593          	addi	a1,a1,-1496 # 4a70 <_end>
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
    1064:	17c000ef          	jal	11e0 <main>

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
    107c:	00003797          	auipc	a5,0x3
    1080:	e7878793          	addi	a5,a5,-392 # 3ef4 <_data>
    1084:	00003417          	auipc	s0,0x3
    1088:	e7040413          	addi	s0,s0,-400 # 3ef4 <_data>
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
    10b8:	00003797          	auipc	a5,0x3
    10bc:	e3c78793          	addi	a5,a5,-452 # 3ef4 <_data>
    10c0:	00003417          	auipc	s0,0x3
    10c4:	e3440413          	addi	s0,s0,-460 # 3ef4 <_data>
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

00001104 <memset>:
    1104:	00f00313          	li	t1,15
    1108:	00050713          	mv	a4,a0
    110c:	02c37e63          	bgeu	t1,a2,1148 <memset+0x44>
    1110:	00f77793          	andi	a5,a4,15
    1114:	0a079063          	bnez	a5,11b4 <memset+0xb0>
    1118:	08059263          	bnez	a1,119c <memset+0x98>
    111c:	ff067693          	andi	a3,a2,-16
    1120:	00f67613          	andi	a2,a2,15
    1124:	00e686b3          	add	a3,a3,a4
    1128:	00b72023          	sw	a1,0(a4)
    112c:	00b72223          	sw	a1,4(a4)
    1130:	00b72423          	sw	a1,8(a4)
    1134:	00b72623          	sw	a1,12(a4)
    1138:	01070713          	addi	a4,a4,16
    113c:	fed766e3          	bltu	a4,a3,1128 <memset+0x24>
    1140:	00061463          	bnez	a2,1148 <memset+0x44>
    1144:	00008067          	ret
    1148:	40c306b3          	sub	a3,t1,a2
    114c:	00269693          	slli	a3,a3,0x2
    1150:	00000297          	auipc	t0,0x0
    1154:	005686b3          	add	a3,a3,t0
    1158:	00c68067          	jr	12(a3)
    115c:	00b70723          	sb	a1,14(a4)
    1160:	00b706a3          	sb	a1,13(a4)
    1164:	00b70623          	sb	a1,12(a4)
    1168:	00b705a3          	sb	a1,11(a4)
    116c:	00b70523          	sb	a1,10(a4)
    1170:	00b704a3          	sb	a1,9(a4)
    1174:	00b70423          	sb	a1,8(a4)
    1178:	00b703a3          	sb	a1,7(a4)
    117c:	00b70323          	sb	a1,6(a4)
    1180:	00b702a3          	sb	a1,5(a4)
    1184:	00b70223          	sb	a1,4(a4)
    1188:	00b701a3          	sb	a1,3(a4)
    118c:	00b70123          	sb	a1,2(a4)
    1190:	00b700a3          	sb	a1,1(a4)
    1194:	00b70023          	sb	a1,0(a4)
    1198:	00008067          	ret
    119c:	0ff5f593          	zext.b	a1,a1
    11a0:	00859693          	slli	a3,a1,0x8
    11a4:	00d5e5b3          	or	a1,a1,a3
    11a8:	01059693          	slli	a3,a1,0x10
    11ac:	00d5e5b3          	or	a1,a1,a3
    11b0:	f6dff06f          	j	111c <memset+0x18>
    11b4:	00279693          	slli	a3,a5,0x2
    11b8:	00000297          	auipc	t0,0x0
    11bc:	005686b3          	add	a3,a3,t0
    11c0:	00008293          	mv	t0,ra
    11c4:	fa0680e7          	jalr	-96(a3)
    11c8:	00028093          	mv	ra,t0
    11cc:	ff078793          	addi	a5,a5,-16
    11d0:	40f70733          	sub	a4,a4,a5
    11d4:	00f60633          	add	a2,a2,a5
    11d8:	f6c378e3          	bgeu	t1,a2,1148 <memset+0x44>
    11dc:	f3dff06f          	j	1118 <memset+0x14>

000011e0 <main>:


/* ------------------------------------------------------------------ */

void main(void)
{
    11e0:	ff010113          	addi	sp,sp,-16
    11e4:	00112623          	sw	ra,12(sp)
    11e8:	00812423          	sw	s0,8(sp)
    bsp_init();
    11ec:	378000ef          	jal	1564 <bsp_init>

    reset_canvas();
    11f0:	3e8000ef          	jal	15d8 <reset_canvas>

    bsp_printf("\r\n=== M1 Renderer Board Smoke Test ===\r\n");
    11f4:	00004537          	lui	a0,0x4
    11f8:	19850513          	addi	a0,a0,408 # 4198 <_data+0x2a4>
    11fc:	50c000ef          	jal	1708 <bsp_printf>
    bsp_printf("pixel_t = %d bytes (expect 4), RENDER_PIXEL_BYTES = %d\r\n",
    1200:	00400613          	li	a2,4
    1204:	00400593          	li	a1,4
    1208:	00004537          	lui	a0,0x4
    120c:	1c450513          	addi	a0,a0,452 # 41c4 <_data+0x2d0>
    1210:	4f8000ef          	jal	1708 <bsp_printf>
               (int)sizeof(pixel_t), (int)RENDER_PIXEL_BYTES);
    bsp_printf("canvas %dx%d stride_px=%d (%d guard cols) rows=%d (%d guard rows)\r\n",
    1214:	00400813          	li	a6,4
    1218:	01000793          	li	a5,16
    121c:	00400713          	li	a4,4
    1220:	01400693          	li	a3,20
    1224:	00c00613          	li	a2,12
    1228:	01000593          	li	a1,16
    122c:	00004537          	lui	a0,0x4
    1230:	20050513          	addi	a0,a0,512 # 4200 <_data+0x30c>
    1234:	4d4000ef          	jal	1708 <bsp_printf>
               FB_W, FB_H, FB_STRIDE, FB_STRIDE - FB_W, FB_ROWS, FB_ROWS - FB_H);
    bsp_printf("backend = CPU only; no BitBlt register access in this build\r\n\r\n");
    1238:	00004537          	lui	a0,0x4
    123c:	24450513          	addi	a0,a0,580 # 4244 <_data+0x350>
    1240:	4c8000ef          	jal	1708 <bsp_printf>

    test_t1_pixel_size();
    1244:	664000ef          	jal	18a8 <test_t1_pixel_size>
    test_t2_default_backend();
    1248:	750000ef          	jal	1998 <test_t2_default_backend>
    test_t3_fill_normal();
    124c:	445000ef          	jal	1e90 <test_t3_fill_normal>
    test_t4a_fill_clip_left_top();
    1250:	731000ef          	jal	2180 <test_t4a_fill_clip_left_top>
    test_t4b_fill_clip_right_bottom();
    1254:	120010ef          	jal	2374 <test_t4b_fill_clip_right_bottom>
    test_t5_blit_normal();
    1258:	364010ef          	jal	25bc <test_t5_blit_normal>
    test_t6_blit_clip();
    125c:	3e0010ef          	jal	263c <test_t6_blit_clip>
    test_t7_stride_not_equal_width();
    1260:	4ec010ef          	jal	274c <test_t7_stride_not_equal_width>
    test_t8_padding_intact();
    1264:	211000ef          	jal	1c74 <test_t8_padding_intact>
    test_t9_fpga_backend_inert();
    1268:	038010ef          	jal	22a0 <test_t9_fpga_backend_inert>
    test_t10_clip_rect_geometry();
    126c:	70c010ef          	jal	2978 <test_t10_clip_rect_geometry>

    bsp_printf("\r\nPASS = %d\r\n", g_pass);
    1270:	8301a583          	lw	a1,-2000(gp) # 44a8 <g_pass>
    1274:	00004537          	lui	a0,0x4
    1278:	28450513          	addi	a0,a0,644 # 4284 <_data+0x390>
    127c:	48c000ef          	jal	1708 <bsp_printf>
    bsp_printf("FAIL = %d\r\n", g_fail);
    1280:	82c1a583          	lw	a1,-2004(gp) # 44a4 <g_fail>
    1284:	00004537          	lui	a0,0x4
    1288:	29450513          	addi	a0,a0,660 # 4294 <_data+0x3a0>
    128c:	47c000ef          	jal	1708 <bsp_printf>

    if (g_fail == 0)
    1290:	82c1a783          	lw	a5,-2004(gp) # 44a4 <g_fail>
    1294:	00079a63          	bnez	a5,12a8 <main+0xc8>
    {
        bsp_printf("M1 BOARD TEST PASSED\r\n");
    1298:	00004537          	lui	a0,0x4
    129c:	2a050513          	addi	a0,a0,672 # 42a0 <_data+0x3ac>
    12a0:	468000ef          	jal	1708 <bsp_printf>
    else
    {
        bsp_printf("M1 BOARD TEST FAILED\r\n");
    }

    while (1)
    12a4:	0000006f          	j	12a4 <main+0xc4>
        bsp_printf("M1 BOARD TEST FAILED\r\n");
    12a8:	00004537          	lui	a0,0x4
    12ac:	2b850513          	addi	a0,a0,696 # 42b8 <_data+0x3c4>
    12b0:	458000ef          	jal	1708 <bsp_printf>
    12b4:	ff1ff06f          	j	12a4 <main+0xc4>

000012b8 <uart_writeAvailability>:
#include "type.h"
#include "soc.h"


    static inline u32 read_u32(u32 address){
        return *((volatile u32*) address);
    12b8:	00452503          	lw	a0,4(a0)
*          of available spaces for writing data from bits 23 to 16. It then
*          returns this value after masking with 0xFF.
*
******************************************************************************/
    static u32 uart_writeAvailability(u32 reg){
        return (read_u32(reg + UART_STATUS) >> 16) & 0xFF;
    12bc:	01055513          	srli	a0,a0,0x10
    }
    12c0:	0ff57513          	zext.b	a0,a0
    12c4:	00008067          	ret

000012c8 <uart_write>:
* @note    The function waits until there is available space in the UART buffer
*          for writing data. Once space is available, it writes the character
*          data to the UART data register.
*
******************************************************************************/
    static void uart_write(u32 reg, char data){
    12c8:	ff010113          	addi	sp,sp,-16
    12cc:	00112623          	sw	ra,12(sp)
    12d0:	00812423          	sw	s0,8(sp)
    12d4:	00912223          	sw	s1,4(sp)
    12d8:	00050413          	mv	s0,a0
    12dc:	00058493          	mv	s1,a1
        while(uart_writeAvailability(reg) == 0);
    12e0:	00040513          	mv	a0,s0
    12e4:	fd5ff0ef          	jal	12b8 <uart_writeAvailability>
    12e8:	fe050ce3          	beqz	a0,12e0 <uart_write+0x18>
    }
    
    static inline void write_u32(u32 data, u32 address){
        *((volatile u32*) address) = data;
    12ec:	00942023          	sw	s1,0(s0)
        write_u32(data, reg + UART_DATA);
    }
    12f0:	00c12083          	lw	ra,12(sp)
    12f4:	00812403          	lw	s0,8(sp)
    12f8:	00412483          	lw	s1,4(sp)
    12fc:	01010113          	addi	sp,sp,16
    1300:	00008067          	ret

00001304 <uart_applyConfig>:
*          value using data length, parity, and stop bit settings from the configuration
*          structure, and writes this value to the UART frame configuration register.
*
******************************************************************************/
    static void uart_applyConfig(u32 reg, Uart_Config *config){
        write_u32(config->clockDivider, reg + UART_CLOCK_DIVIDER);
    1304:	00c5a783          	lw	a5,12(a1)
    1308:	00f52423          	sw	a5,8(a0)
        write_u32(((config->dataLength-1) << 0) | (config->parity << 8) | (config->stop << 16), reg + UART_FRAME_CONFIG);
    130c:	0005a783          	lw	a5,0(a1)
    1310:	fff78793          	addi	a5,a5,-1
    1314:	0045a703          	lw	a4,4(a1)
    1318:	00871713          	slli	a4,a4,0x8
    131c:	00e7e7b3          	or	a5,a5,a4
    1320:	0085a703          	lw	a4,8(a1)
    1324:	01071713          	slli	a4,a4,0x10
    1328:	00e7e7b3          	or	a5,a5,a4
    132c:	00f52623          	sw	a5,12(a0)
    }
    1330:	00008067          	ret

00001334 <_putchar>:
#include <math.h>
#include <string.h>
#include "bsp.h"

#if (ENABLE_BSP_PRINTF)
    static void _putchar(char character){
    1334:	ff010113          	addi	sp,sp,-16
    1338:	00112623          	sw	ra,12(sp)
    133c:	00050593          	mv	a1,a0
        #if (ENABLE_SEMIHOSTING_PRINT == 1)
            sh_writec(character);
        #else
            bsp_putChar(character);
    1340:	f8010537          	lui	a0,0xf8010
    1344:	f85ff0ef          	jal	12c8 <uart_write>
        #endif // (ENABLE_SEMIHOSTING_PRINT == 1)
    }
    1348:	00c12083          	lw	ra,12(sp)
    134c:	01010113          	addi	sp,sp,16
    1350:	00008067          	ret

00001354 <_putchar_s>:

    static void _putchar_s(char *p)
    {
    1354:	ff010113          	addi	sp,sp,-16
    1358:	00112623          	sw	ra,12(sp)
    135c:	00812423          	sw	s0,8(sp)
    1360:	00050413          	mv	s0,a0
    #if (ENABLE_SEMIHOSTING_PRINT == 1)
        sh_write0(p);
    #else
        while (*p)
    1364:	00c0006f          	j	1370 <_putchar_s+0x1c>
            _putchar(*(p++));
    1368:	00140413          	addi	s0,s0,1
    136c:	fc9ff0ef          	jal	1334 <_putchar>
        while (*p)
    1370:	00044503          	lbu	a0,0(s0)
    1374:	fe051ae3          	bnez	a0,1368 <_putchar_s+0x14>
    #endif // (ENABLE_SEMIHOSTING_PRINT == 1)
    }
    1378:	00c12083          	lw	ra,12(sp)
    137c:	00812403          	lw	s0,8(sp)
    1380:	01010113          	addi	sp,sp,16
    1384:	00008067          	ret

00001388 <bsp_printHex>:

        static void bsp_printHex(uint32_t val)
    {
    1388:	ff010113          	addi	sp,sp,-16
    138c:	00112623          	sw	ra,12(sp)
    1390:	00812423          	sw	s0,8(sp)
    1394:	00912223          	sw	s1,4(sp)
    1398:	00050493          	mv	s1,a0
        uint32_t digits;
        digits =8;

        for (int i = (4*digits)-4; i >= 0; i -= 4) {
    139c:	01c00413          	li	s0,28
    13a0:	0240006f          	j	13c4 <bsp_printHex+0x3c>
            _putchar("0123456789ABCDEF"[(val >> i) % 16]);
    13a4:	0084d733          	srl	a4,s1,s0
    13a8:	00f77713          	andi	a4,a4,15
    13ac:	000047b7          	lui	a5,0x4
    13b0:	ef478793          	addi	a5,a5,-268 # 3ef4 <_data>
    13b4:	00e787b3          	add	a5,a5,a4
    13b8:	0007c503          	lbu	a0,0(a5)
    13bc:	f79ff0ef          	jal	1334 <_putchar>
        for (int i = (4*digits)-4; i >= 0; i -= 4) {
    13c0:	ffc40413          	addi	s0,s0,-4
    13c4:	fe0450e3          	bgez	s0,13a4 <bsp_printHex+0x1c>
        }
    }
    13c8:	00c12083          	lw	ra,12(sp)
    13cc:	00812403          	lw	s0,8(sp)
    13d0:	00412483          	lw	s1,4(sp)
    13d4:	01010113          	addi	sp,sp,16
    13d8:	00008067          	ret

000013dc <bsp_printHex_lower>:

    static void bsp_printHex_lower(uint32_t val)
    {
    13dc:	ff010113          	addi	sp,sp,-16
    13e0:	00112623          	sw	ra,12(sp)
    13e4:	00812423          	sw	s0,8(sp)
    13e8:	00912223          	sw	s1,4(sp)
    13ec:	00050493          	mv	s1,a0
        uint32_t digits;
        digits =8;

        for (int i = (4*digits)-4; i >= 0; i -= 4) {
    13f0:	01c00413          	li	s0,28
    13f4:	0240006f          	j	1418 <bsp_printHex_lower+0x3c>
            _putchar("0123456789abcdef"[(val >> i) % 16]);
    13f8:	0084d733          	srl	a4,s1,s0
    13fc:	00f77713          	andi	a4,a4,15
    1400:	000047b7          	lui	a5,0x4
    1404:	f0878793          	addi	a5,a5,-248 # 3f08 <_data+0x14>
    1408:	00e787b3          	add	a5,a5,a4
    140c:	0007c503          	lbu	a0,0(a5)
    1410:	f25ff0ef          	jal	1334 <_putchar>
        for (int i = (4*digits)-4; i >= 0; i -= 4) {
    1414:	ffc40413          	addi	s0,s0,-4
    1418:	fe0450e3          	bgez	s0,13f8 <bsp_printHex_lower+0x1c>

        }
    }
    141c:	00c12083          	lw	ra,12(sp)
    1420:	00812403          	lw	s0,8(sp)
    1424:	00412483          	lw	s1,4(sp)
    1428:	01010113          	addi	sp,sp,16
    142c:	00008067          	ret

00001430 <bsp_printf_c>:
*
* @param c: The character to be output.
*
******************************************************************************/
    static void bsp_printf_c(int c)
    {
    1430:	ff010113          	addi	sp,sp,-16
    1434:	00112623          	sw	ra,12(sp)
        _putchar(c);
    1438:	0ff57513          	zext.b	a0,a0
    143c:	ef9ff0ef          	jal	1334 <_putchar>
    }
    1440:	00c12083          	lw	ra,12(sp)
    1444:	01010113          	addi	sp,sp,16
    1448:	00008067          	ret

0000144c <bsp_printf_s>:
*
* @param s: A pointer to the null-terminated string to be output.
*
*******************************************************************************/
    static void bsp_printf_s(char *p)
    {
    144c:	ff010113          	addi	sp,sp,-16
    1450:	00112623          	sw	ra,12(sp)
        _putchar_s(p);
    1454:	f01ff0ef          	jal	1354 <_putchar_s>
    }
    1458:	00c12083          	lw	ra,12(sp)
    145c:	01010113          	addi	sp,sp,16
    1460:	00008067          	ret

00001464 <bsp_printf_d>:
* - Handles negative numbers by printing a '-' sign.
* - Uses the 'bsp_printf_c' function to print each character.
*
******************************************************************************/
    static void bsp_printf_d(int val)
    {
    1464:	fd010113          	addi	sp,sp,-48
    1468:	02112623          	sw	ra,44(sp)
    146c:	02812423          	sw	s0,40(sp)
    1470:	02912223          	sw	s1,36(sp)
    1474:	00050493          	mv	s1,a0
        char buffer[32];
        char *p = buffer;
        if (val < 0) {
    1478:	00054663          	bltz	a0,1484 <bsp_printf_d+0x20>
    {
    147c:	00010413          	mv	s0,sp
    1480:	02c0006f          	j	14ac <bsp_printf_d+0x48>
            bsp_printf_c('-');
    1484:	02d00513          	li	a0,45
    1488:	fa9ff0ef          	jal	1430 <bsp_printf_c>
            val = -val;
    148c:	409004b3          	neg	s1,s1
    1490:	fedff06f          	j	147c <bsp_printf_d+0x18>
        }
        while (val || p == buffer) {
            *(p++) = '0' + val % 10;
    1494:	00a00713          	li	a4,10
    1498:	02e4e7b3          	rem	a5,s1,a4
    149c:	03078793          	addi	a5,a5,48
    14a0:	00f40023          	sb	a5,0(s0)
            val = val / 10;
    14a4:	02e4c4b3          	div	s1,s1,a4
            *(p++) = '0' + val % 10;
    14a8:	00140413          	addi	s0,s0,1
        while (val || p == buffer) {
    14ac:	fe0494e3          	bnez	s1,1494 <bsp_printf_d+0x30>
    14b0:	00010793          	mv	a5,sp
    14b4:	fef400e3          	beq	s0,a5,1494 <bsp_printf_d+0x30>
        }
        while (p != buffer)
    14b8:	00010793          	mv	a5,sp
    14bc:	00f40a63          	beq	s0,a5,14d0 <bsp_printf_d+0x6c>
            bsp_printf_c(*(--p));
    14c0:	fff40413          	addi	s0,s0,-1
    14c4:	00044503          	lbu	a0,0(s0)
    14c8:	f69ff0ef          	jal	1430 <bsp_printf_c>
    14cc:	fedff06f          	j	14b8 <bsp_printf_d+0x54>
    }
    14d0:	02c12083          	lw	ra,44(sp)
    14d4:	02812403          	lw	s0,40(sp)
    14d8:	02412483          	lw	s1,36(sp)
    14dc:	03010113          	addi	sp,sp,48
    14e0:	00008067          	ret

000014e4 <bsp_printf_x>:
* - Calls 'bsp_printHex_lower' to print the hexadecimal representation.
* - Determines the number of leading zeros to be printed based on the value.
*
******************************************************************************/
    static void bsp_printf_x(int val)
    {
    14e4:	ff010113          	addi	sp,sp,-16
    14e8:	00112623          	sw	ra,12(sp)
        int i,digi=2;

        for(i=0;i<8;i++)
    14ec:	00000713          	li	a4,0
    14f0:	00700793          	li	a5,7
    14f4:	02e7c063          	blt	a5,a4,1514 <bsp_printf_x+0x30>
        {
            if((val & (0xFFFFFFF0 <<(4*i))) == 0)
    14f8:	00271693          	slli	a3,a4,0x2
    14fc:	ff000793          	li	a5,-16
    1500:	00d797b3          	sll	a5,a5,a3
    1504:	00f577b3          	and	a5,a0,a5
    1508:	00078663          	beqz	a5,1514 <bsp_printf_x+0x30>
        for(i=0;i<8;i++)
    150c:	00170713          	addi	a4,a4,1
    1510:	fe1ff06f          	j	14f0 <bsp_printf_x+0xc>
            {
                digi=i+1;
                break;
            }
        }
        bsp_printHex_lower(val);
    1514:	ec9ff0ef          	jal	13dc <bsp_printHex_lower>
    }
    1518:	00c12083          	lw	ra,12(sp)
    151c:	01010113          	addi	sp,sp,16
    1520:	00008067          	ret

00001524 <bsp_printf_X>:
* - Calls 'bsp_printHex' to print the uppercase hexadecimal representation.
* - Determines the number of leading zeros to be printed based on the value.
*
******************************************************************************/
    static void bsp_printf_X(int val)
        {
    1524:	ff010113          	addi	sp,sp,-16
    1528:	00112623          	sw	ra,12(sp)
            int i,digi=2;

            for(i=0;i<8;i++)
    152c:	00000713          	li	a4,0
    1530:	00700793          	li	a5,7
    1534:	02e7c063          	blt	a5,a4,1554 <bsp_printf_X+0x30>
            {
                if((val & (0xFFFFFFF0 <<(4*i))) == 0)
    1538:	00271693          	slli	a3,a4,0x2
    153c:	ff000793          	li	a5,-16
    1540:	00d797b3          	sll	a5,a5,a3
    1544:	00f577b3          	and	a5,a0,a5
    1548:	00078663          	beqz	a5,1554 <bsp_printf_X+0x30>
            for(i=0;i<8;i++)
    154c:	00170713          	addi	a4,a4,1
    1550:	fe1ff06f          	j	1530 <bsp_printf_X+0xc>
                {
                    digi=i+1;
                    break;
                }
            }
            bsp_printHex(val);
    1554:	e35ff0ef          	jal	1388 <bsp_printHex>
        }
    1558:	00c12083          	lw	ra,12(sp)
    155c:	01010113          	addi	sp,sp,16
    1560:	00008067          	ret

00001564 <bsp_init>:
    *   1. UART baudrate
    *   2. 
    */
////////////////////////////////////////////////////////////////////////////////
    static void bsp_init()
    {
    1564:	fe010113          	addi	sp,sp,-32
    1568:	00112e23          	sw	ra,28(sp)
        Uart_Config uartConfig;
        uartConfig.dataLength   = BITS_8;
    156c:	00800793          	li	a5,8
    1570:	00f12023          	sw	a5,0(sp)
        uartConfig.parity       = NONE;
    1574:	00012223          	sw	zero,4(sp)
        uartConfig.stop         = ONE;
    1578:	00012423          	sw	zero,8(sp)
        uartConfig.clockDivider = BSP_CLINT_HZ/(BSP_UART_BAUDRATE*BSP_UART_DATA_LEN)-1;
    157c:	06b00793          	li	a5,107
    1580:	00f12623          	sw	a5,12(sp)
        uart_applyConfig(BSP_UART_TERMINAL, &uartConfig);    
    1584:	00010593          	mv	a1,sp
    1588:	f8010537          	lui	a0,0xf8010
    158c:	d79ff0ef          	jal	1304 <uart_applyConfig>
    }
    1590:	01c12083          	lw	ra,28(sp)
    1594:	02010113          	addi	sp,sp,32
    1598:	00008067          	ret

0000159c <str_eq>:
    while (*a != '\0' && *a == *b)
    159c:	00c0006f          	j	15a8 <str_eq+0xc>
        a++;
    15a0:	00150513          	addi	a0,a0,1 # f8010001 <__freertos_irq_stack_top+0xf800a591>
        b++;
    15a4:	00158593          	addi	a1,a1,1
    while (*a != '\0' && *a == *b)
    15a8:	00054783          	lbu	a5,0(a0)
    15ac:	00078663          	beqz	a5,15b8 <str_eq+0x1c>
    15b0:	0005c703          	lbu	a4,0(a1)
    15b4:	fee786e3          	beq	a5,a4,15a0 <str_eq+0x4>
    return *a == *b;
    15b8:	0005c703          	lbu	a4,0(a1)
    15bc:	40e78533          	sub	a0,a5,a4
}
    15c0:	00153513          	seqz	a0,a0
    15c4:	00008067          	ret

000015c8 <t_begin>:
    t_fail = 0;
    15c8:	8201a423          	sw	zero,-2008(gp) # 44a0 <t_fail>
    t_printed = 0;
    15cc:	8201a223          	sw	zero,-2012(gp) # 449c <t_printed>
    t_extra = 0;
    15d0:	8201a023          	sw	zero,-2016(gp) # 4498 <t_extra>
}
    15d4:	00008067          	ret

000015d8 <reset_canvas>:
    for (int y = 0; y < FB_ROWS; y++)
    15d8:	00000613          	li	a2,0
    15dc:	0640006f          	j	1640 <reset_canvas+0x68>
            canvas[(uint32_t)y * FB_STRIDE + x] = visible ? COLOR_BG : COLOR_GUARD;
    15e0:	00abd5b7          	lui	a1,0xabd
    15e4:	def58593          	addi	a1,a1,-529 # abcdef <__freertos_irq_stack_top+0xab737f>
    15e8:	00c0006f          	j	15f4 <reset_canvas+0x1c>
    15ec:	00abd5b7          	lui	a1,0xabd
    15f0:	def58593          	addi	a1,a1,-529 # abcdef <__freertos_irq_stack_top+0xab737f>
    15f4:	00261713          	slli	a4,a2,0x2
    15f8:	00c70733          	add	a4,a4,a2
    15fc:	00271793          	slli	a5,a4,0x2
    1600:	00f687b3          	add	a5,a3,a5
    1604:	00004737          	lui	a4,0x4
    1608:	00279793          	slli	a5,a5,0x2
    160c:	53870713          	addi	a4,a4,1336 # 4538 <canvas>
    1610:	00f707b3          	add	a5,a4,a5
    1614:	00b7a023          	sw	a1,0(a5)
        for (int x = 0; x < FB_STRIDE; x++)
    1618:	00168693          	addi	a3,a3,1
    161c:	01300793          	li	a5,19
    1620:	00d7ce63          	blt	a5,a3,163c <reset_canvas+0x64>
            int visible = (x < FB_W && y < FB_H);
    1624:	00f00793          	li	a5,15
    1628:	fcd7c2e3          	blt	a5,a3,15ec <reset_canvas+0x14>
    162c:	00b00793          	li	a5,11
    1630:	fac7c8e3          	blt	a5,a2,15e0 <reset_canvas+0x8>
            canvas[(uint32_t)y * FB_STRIDE + x] = visible ? COLOR_BG : COLOR_GUARD;
    1634:	00000593          	li	a1,0
    1638:	fbdff06f          	j	15f4 <reset_canvas+0x1c>
    for (int y = 0; y < FB_ROWS; y++)
    163c:	00160613          	addi	a2,a2,1
    1640:	00f00793          	li	a5,15
    1644:	00c7c663          	blt	a5,a2,1650 <reset_canvas+0x78>
        for (int x = 0; x < FB_STRIDE; x++)
    1648:	00000693          	li	a3,0
    164c:	fd1ff06f          	j	161c <reset_canvas+0x44>
}
    1650:	00008067          	ret

00001654 <reset_sprite>:
    for (int i = 0; i < SPR_STRIDE * SPR_H; i++)
    1654:	00000713          	li	a4,0
    1658:	0240006f          	j	167c <reset_sprite+0x28>
        sprite[i] = (pixel_t)(SPR_BASE + (uint32_t)i);
    165c:	000106b7          	lui	a3,0x10
    1660:	00d706b3          	add	a3,a4,a3
    1664:	000047b7          	lui	a5,0x4
    1668:	00271613          	slli	a2,a4,0x2
    166c:	4b878793          	addi	a5,a5,1208 # 44b8 <sprite>
    1670:	00c787b3          	add	a5,a5,a2
    1674:	00d7a023          	sw	a3,0(a5)
    for (int i = 0; i < SPR_STRIDE * SPR_H; i++)
    1678:	00170713          	addi	a4,a4,1
    167c:	01f00793          	li	a5,31
    1680:	fce7dee3          	bge	a5,a4,165c <reset_sprite+0x8>
}
    1684:	00008067          	ret

00001688 <make_canvas_surface>:
    s.pixels = canvas;
    1688:	00004737          	lui	a4,0x4
    168c:	53870713          	addi	a4,a4,1336 # 4538 <canvas>
    1690:	00e52023          	sw	a4,0(a0)
    s.width = FB_W;
    1694:	01000713          	li	a4,16
    1698:	00e52223          	sw	a4,4(a0)
    s.height = FB_H;
    169c:	00c00713          	li	a4,12
    16a0:	00e52423          	sw	a4,8(a0)
    s.stride_px = FB_STRIDE;
    16a4:	01400713          	li	a4,20
    16a8:	00e52623          	sw	a4,12(a0)
    s.phys_base = 0;
    16ac:	00052823          	sw	zero,16(a0)
}
    16b0:	00008067          	ret

000016b4 <make_sprite_surface>:
    s.pixels = sprite;
    16b4:	00004737          	lui	a4,0x4
    16b8:	4b870713          	addi	a4,a4,1208 # 44b8 <sprite>
    16bc:	00e52023          	sw	a4,0(a0)
    s.width = SPR_W;
    16c0:	00500713          	li	a4,5
    16c4:	00e52223          	sw	a4,4(a0)
    s.height = SPR_H;
    16c8:	00400713          	li	a4,4
    16cc:	00e52423          	sw	a4,8(a0)
    s.stride_px = SPR_STRIDE;
    16d0:	00800713          	li	a4,8
    16d4:	00e52623          	sw	a4,12(a0)
    s.phys_base = 0;
    16d8:	00052823          	sw	zero,16(a0)
}
    16dc:	00008067          	ret

000016e0 <make_rect>:
    r.x = x;
    16e0:	00b52023          	sw	a1,0(a0)
    r.y = y;
    16e4:	00c52223          	sw	a2,4(a0)
    r.w = w;
    16e8:	00d52423          	sw	a3,8(a0)
    r.h = h;
    16ec:	00e52623          	sw	a4,12(a0)
}
    16f0:	00008067          	ret

000016f4 <sprite_at>:
    return SPR_BASE + (uint32_t)(sy * SPR_STRIDE + sx);
    16f4:	00359593          	slli	a1,a1,0x3
    16f8:	00a585b3          	add	a1,a1,a0
}
    16fc:	00010537          	lui	a0,0x10
    1700:	00a58533          	add	a0,a1,a0
    1704:	00008067          	ret

00001708 <bsp_printf>:
* - Handles each format specifier by calling the appropriate helper function.
* - If floating-point support is disabled, prints a warning for the 'f' specifier.
*
******************************************************************************/
    static void bsp_printf(const char *format, ...)
    {
    1708:	fc010113          	addi	sp,sp,-64
    170c:	00112e23          	sw	ra,28(sp)
    1710:	00812c23          	sw	s0,24(sp)
    1714:	00912a23          	sw	s1,20(sp)
    1718:	00050493          	mv	s1,a0
    171c:	02b12223          	sw	a1,36(sp)
    1720:	02c12423          	sw	a2,40(sp)
    1724:	02d12623          	sw	a3,44(sp)
    1728:	02e12823          	sw	a4,48(sp)
    172c:	02f12a23          	sw	a5,52(sp)
    1730:	03012c23          	sw	a6,56(sp)
    1734:	03112e23          	sw	a7,60(sp)
        int i;
        va_list ap;

        va_start(ap, format);
    1738:	02410793          	addi	a5,sp,36
    173c:	00f12623          	sw	a5,12(sp)

        for (i = 0; format[i]; i++)
    1740:	00000413          	li	s0,0
    1744:	01c0006f          	j	1760 <bsp_printf+0x58>
            if (format[i] == '%') {
                while (format[++i]) {
                    if (format[i] == 'c') {
                        bsp_printf_c(va_arg(ap,int));
    1748:	00c12783          	lw	a5,12(sp)
    174c:	00478713          	addi	a4,a5,4
    1750:	00e12623          	sw	a4,12(sp)
    1754:	0007a503          	lw	a0,0(a5)
    1758:	cd9ff0ef          	jal	1430 <bsp_printf_c>
        for (i = 0; format[i]; i++)
    175c:	00140413          	addi	s0,s0,1
    1760:	008487b3          	add	a5,s1,s0
    1764:	0007c503          	lbu	a0,0(a5)
    1768:	0a050e63          	beqz	a0,1824 <bsp_printf+0x11c>
            if (format[i] == '%') {
    176c:	02500793          	li	a5,37
    1770:	06f50e63          	beq	a0,a5,17ec <bsp_printf+0xe4>
                        break;
                    }
#endif //#if (ENABLE_FLOATING_POINT_SUPPORT)
                }
            } else
                bsp_printf_c(format[i]);
    1774:	cbdff0ef          	jal	1430 <bsp_printf_c>
    1778:	fe5ff06f          	j	175c <bsp_printf+0x54>
                        bsp_printf_s(va_arg(ap,char*));
    177c:	00c12783          	lw	a5,12(sp)
    1780:	00478713          	addi	a4,a5,4
    1784:	00e12623          	sw	a4,12(sp)
    1788:	0007a503          	lw	a0,0(a5)
    178c:	cc1ff0ef          	jal	144c <bsp_printf_s>
                        break;
    1790:	fcdff06f          	j	175c <bsp_printf+0x54>
                        bsp_printf_d(va_arg(ap,int));
    1794:	00c12783          	lw	a5,12(sp)
    1798:	00478713          	addi	a4,a5,4
    179c:	00e12623          	sw	a4,12(sp)
    17a0:	0007a503          	lw	a0,0(a5)
    17a4:	cc1ff0ef          	jal	1464 <bsp_printf_d>
                        break;
    17a8:	fb5ff06f          	j	175c <bsp_printf+0x54>
                        bsp_printf_X(va_arg(ap,int));
    17ac:	00c12783          	lw	a5,12(sp)
    17b0:	00478713          	addi	a4,a5,4
    17b4:	00e12623          	sw	a4,12(sp)
    17b8:	0007a503          	lw	a0,0(a5)
    17bc:	d69ff0ef          	jal	1524 <bsp_printf_X>
                        break;
    17c0:	f9dff06f          	j	175c <bsp_printf+0x54>
                        bsp_printf_x(va_arg(ap,int));
    17c4:	00c12783          	lw	a5,12(sp)
    17c8:	00478713          	addi	a4,a5,4
    17cc:	00e12623          	sw	a4,12(sp)
    17d0:	0007a503          	lw	a0,0(a5)
    17d4:	d11ff0ef          	jal	14e4 <bsp_printf_x>
                        break;
    17d8:	f85ff06f          	j	175c <bsp_printf+0x54>
                        bsp_printf_s("<Floating point printing not enable. Please Enable it at bsp.h first...>");
    17dc:	00004537          	lui	a0,0x4
    17e0:	f1c50513          	addi	a0,a0,-228 # 3f1c <_data+0x28>
    17e4:	c69ff0ef          	jal	144c <bsp_printf_s>
                        break;
    17e8:	f75ff06f          	j	175c <bsp_printf+0x54>
                while (format[++i]) {
    17ec:	00140413          	addi	s0,s0,1
    17f0:	008487b3          	add	a5,s1,s0
    17f4:	0007c783          	lbu	a5,0(a5)
    17f8:	f60782e3          	beqz	a5,175c <bsp_printf+0x54>
                    if (format[i] == 'c') {
    17fc:	fa878793          	addi	a5,a5,-88
    1800:	0ff7f693          	zext.b	a3,a5
    1804:	02000713          	li	a4,32
    1808:	fed762e3          	bltu	a4,a3,17ec <bsp_printf+0xe4>
    180c:	00269793          	slli	a5,a3,0x2
    1810:	00004737          	lui	a4,0x4
    1814:	39870713          	addi	a4,a4,920 # 4398 <_data+0x4a4>
    1818:	00e787b3          	add	a5,a5,a4
    181c:	0007a783          	lw	a5,0(a5)
    1820:	00078067          	jr	a5

        va_end(ap);
    }
    1824:	01c12083          	lw	ra,28(sp)
    1828:	01812403          	lw	s0,24(sp)
    182c:	01412483          	lw	s1,20(sp)
    1830:	04010113          	addi	sp,sp,64
    1834:	00008067          	ret

00001838 <t_end>:
{
    1838:	ff010113          	addi	sp,sp,-16
    183c:	00112623          	sw	ra,12(sp)
    1840:	00812423          	sw	s0,8(sp)
    1844:	00050413          	mv	s0,a0
    if (t_extra > 0)
    1848:	8201a603          	lw	a2,-2016(gp) # 4498 <t_extra>
    184c:	02c04463          	bgtz	a2,1874 <t_end+0x3c>
    if (t_fail == 0)
    1850:	8281a783          	lw	a5,-2008(gp) # 44a0 <t_fail>
    1854:	02078a63          	beqz	a5,1888 <t_end+0x50>
        g_fail++;
    1858:	82c1a783          	lw	a5,-2004(gp) # 44a4 <g_fail>
    185c:	00178793          	addi	a5,a5,1
    1860:	82f1a623          	sw	a5,-2004(gp) # 44a4 <g_fail>
}
    1864:	00c12083          	lw	ra,12(sp)
    1868:	00812403          	lw	s0,8(sp)
    186c:	01010113          	addi	sp,sp,16
    1870:	00008067          	ret
        bsp_printf("[FAIL] %s 另有 %d 处不符未逐条列出\r\n", name, t_extra);
    1874:	00050593          	mv	a1,a0
    1878:	00004537          	lui	a0,0x4
    187c:	f6850513          	addi	a0,a0,-152 # 3f68 <_data+0x74>
    1880:	e89ff0ef          	jal	1708 <bsp_printf>
    1884:	fcdff06f          	j	1850 <t_end+0x18>
        g_pass++;
    1888:	8301a783          	lw	a5,-2000(gp) # 44a8 <g_pass>
    188c:	00178793          	addi	a5,a5,1
    1890:	82f1a823          	sw	a5,-2000(gp) # 44a8 <g_pass>
        bsp_printf("[PASS] %s\r\n", name);
    1894:	00040593          	mv	a1,s0
    1898:	00004537          	lui	a0,0x4
    189c:	f9c50513          	addi	a0,a0,-100 # 3f9c <_data+0xa8>
    18a0:	e69ff0ef          	jal	1708 <bsp_printf>
    18a4:	fc1ff06f          	j	1864 <t_end+0x2c>

000018a8 <test_t1_pixel_size>:
{
    18a8:	ff010113          	addi	sp,sp,-16
    18ac:	00112623          	sw	ra,12(sp)
    t_begin();
    18b0:	d19ff0ef          	jal	15c8 <t_begin>
    t_end(name);
    18b4:	00004537          	lui	a0,0x4
    18b8:	fa850513          	addi	a0,a0,-88 # 3fa8 <_data+0xb4>
    18bc:	f7dff0ef          	jal	1838 <t_end>
}
    18c0:	00c12083          	lw	ra,12(sp)
    18c4:	01010113          	addi	sp,sp,16
    18c8:	00008067          	ret

000018cc <fail_text>:
    if (t_printed < MAX_DIAG_PER_TEST)
    18cc:	8241a703          	lw	a4,-2012(gp) # 449c <t_printed>
    18d0:	00700793          	li	a5,7
    18d4:	02e7d063          	bge	a5,a4,18f4 <fail_text+0x28>
        t_extra++;
    18d8:	8201a783          	lw	a5,-2016(gp) # 4498 <t_extra>
    18dc:	00178793          	addi	a5,a5,1
    18e0:	82f1a023          	sw	a5,-2016(gp) # 4498 <t_extra>
    t_fail++;
    18e4:	8281a783          	lw	a5,-2008(gp) # 44a0 <t_fail>
    18e8:	00178793          	addi	a5,a5,1
    18ec:	82f1a423          	sw	a5,-2008(gp) # 44a0 <t_fail>
    18f0:	00008067          	ret
{
    18f4:	ff010113          	addi	sp,sp,-16
    18f8:	00112623          	sw	ra,12(sp)
        bsp_printf("[FAIL] %s expected=%s actual=%s\r\n", name, expected, actual);
    18fc:	00060693          	mv	a3,a2
    1900:	00058613          	mv	a2,a1
    1904:	00050593          	mv	a1,a0
    1908:	00004537          	lui	a0,0x4
    190c:	fc050513          	addi	a0,a0,-64 # 3fc0 <_data+0xcc>
    1910:	df9ff0ef          	jal	1708 <bsp_printf>
        t_printed++;
    1914:	8241a783          	lw	a5,-2012(gp) # 449c <t_printed>
    1918:	00178793          	addi	a5,a5,1
    191c:	82f1a223          	sw	a5,-2012(gp) # 449c <t_printed>
    t_fail++;
    1920:	8281a783          	lw	a5,-2008(gp) # 44a0 <t_fail>
    1924:	00178793          	addi	a5,a5,1
    1928:	82f1a423          	sw	a5,-2008(gp) # 44a0 <t_fail>
}
    192c:	00c12083          	lw	ra,12(sp)
    1930:	01010113          	addi	sp,sp,16
    1934:	00008067          	ret

00001938 <expect_status>:
    if (got != want)
    1938:	00c59463          	bne	a1,a2,1940 <expect_status+0x8>
    193c:	00008067          	ret
{
    1940:	ff010113          	addi	sp,sp,-16
    1944:	00112623          	sw	ra,12(sp)
    1948:	00812423          	sw	s0,8(sp)
    194c:	00912223          	sw	s1,4(sp)
    1950:	01212023          	sw	s2,0(sp)
    1954:	00050493          	mv	s1,a0
    1958:	00058413          	mv	s0,a1
        fail_text(name, render_strstatus(want), render_strstatus(got));
    195c:	00060513          	mv	a0,a2
    1960:	795010ef          	jal	38f4 <render_strstatus>
    1964:	00050913          	mv	s2,a0
    1968:	00040513          	mv	a0,s0
    196c:	789010ef          	jal	38f4 <render_strstatus>
    1970:	00050613          	mv	a2,a0
    1974:	00090593          	mv	a1,s2
    1978:	00048513          	mv	a0,s1
    197c:	f51ff0ef          	jal	18cc <fail_text>
}
    1980:	00c12083          	lw	ra,12(sp)
    1984:	00812403          	lw	s0,8(sp)
    1988:	00412483          	lw	s1,4(sp)
    198c:	00012903          	lw	s2,0(sp)
    1990:	01010113          	addi	sp,sp,16
    1994:	00008067          	ret

00001998 <test_t2_default_backend>:
{
    1998:	fb010113          	addi	sp,sp,-80
    199c:	04112623          	sw	ra,76(sp)
    19a0:	04812423          	sw	s0,72(sp)
    t_begin();
    19a4:	c25ff0ef          	jal	15c8 <t_begin>
    (void)render_select_ops(0);
    19a8:	00000513          	li	a0,0
    19ac:	5d4010ef          	jal	2f80 <render_select_ops>
        render_surface_t s = make_canvas_surface();
    19b0:	01c10513          	addi	a0,sp,28
    19b4:	cd5ff0ef          	jal	1688 <make_canvas_surface>
        render_status_t st = render_fill_rect(&s, make_rect(0, 0, 4, 4), COLOR_RED);
    19b8:	00400713          	li	a4,4
    19bc:	00400693          	li	a3,4
    19c0:	00000613          	li	a2,0
    19c4:	00000593          	li	a1,0
    19c8:	03010513          	addi	a0,sp,48
    19cc:	d15ff0ef          	jal	16e0 <make_rect>
    19d0:	03012783          	lw	a5,48(sp)
    19d4:	00f12023          	sw	a5,0(sp)
    19d8:	03412783          	lw	a5,52(sp)
    19dc:	00f12223          	sw	a5,4(sp)
    19e0:	03812783          	lw	a5,56(sp)
    19e4:	00f12423          	sw	a5,8(sp)
    19e8:	03c12783          	lw	a5,60(sp)
    19ec:	00f12623          	sw	a5,12(sp)
    19f0:	00ff0637          	lui	a2,0xff0
    19f4:	00010593          	mv	a1,sp
    19f8:	01c10513          	addi	a0,sp,28
    19fc:	065010ef          	jal	3260 <render_fill_rect>
    1a00:	00050593          	mv	a1,a0
        expect_status(name, st, RENDER_ERR_NO_BACKEND);
    1a04:	00200613          	li	a2,2
    1a08:	00004537          	lui	a0,0x4
    1a0c:	fec50513          	addi	a0,a0,-20 # 3fec <_data+0xf8>
    1a10:	f29ff0ef          	jal	1938 <expect_status>
    render_init();
    1a14:	550010ef          	jal	2f64 <render_init>
    got = render_backend_name();
    1a18:	574010ef          	jal	2f8c <render_backend_name>
    if (got == 0 || !str_eq(got, "cpu"))
    1a1c:	04050663          	beqz	a0,1a68 <test_t2_default_backend+0xd0>
    1a20:	00050413          	mv	s0,a0
    1a24:	000045b7          	lui	a1,0x4
    1a28:	00858593          	addi	a1,a1,8 # 4008 <_data+0x114>
    1a2c:	b71ff0ef          	jal	159c <str_eq>
    1a30:	00051e63          	bnez	a0,1a4c <test_t2_default_backend+0xb4>
        fail_text(name, "cpu", got ? got : "(null)");
    1a34:	00040613          	mv	a2,s0
    1a38:	000045b7          	lui	a1,0x4
    1a3c:	00858593          	addi	a1,a1,8 # 4008 <_data+0x114>
    1a40:	00004537          	lui	a0,0x4
    1a44:	fec50513          	addi	a0,a0,-20 # 3fec <_data+0xf8>
    1a48:	e85ff0ef          	jal	18cc <fail_text>
    t_end(name);
    1a4c:	00004537          	lui	a0,0x4
    1a50:	fec50513          	addi	a0,a0,-20 # 3fec <_data+0xf8>
    1a54:	de5ff0ef          	jal	1838 <t_end>
}
    1a58:	04c12083          	lw	ra,76(sp)
    1a5c:	04812403          	lw	s0,72(sp)
    1a60:	05010113          	addi	sp,sp,80
    1a64:	00008067          	ret
        fail_text(name, "cpu", got ? got : "(null)");
    1a68:	00004437          	lui	s0,0x4
    1a6c:	fe440413          	addi	s0,s0,-28 # 3fe4 <_data+0xf0>
    1a70:	fc5ff06f          	j	1a34 <test_t2_default_backend+0x9c>

00001a74 <expect_color>:
    uint32_t got = (uint32_t)canvas[(uint32_t)y * FB_STRIDE + x];
    1a74:	00261793          	slli	a5,a2,0x2
    1a78:	00c787b3          	add	a5,a5,a2
    1a7c:	00279793          	slli	a5,a5,0x2
    1a80:	00f587b3          	add	a5,a1,a5
    1a84:	00004837          	lui	a6,0x4
    1a88:	00279793          	slli	a5,a5,0x2
    1a8c:	53880813          	addi	a6,a6,1336 # 4538 <canvas>
    1a90:	00f807b3          	add	a5,a6,a5
    1a94:	0007a783          	lw	a5,0(a5)
    if (got == want)
    1a98:	06d78a63          	beq	a5,a3,1b0c <expect_color+0x98>
    1a9c:	00068713          	mv	a4,a3
    if (t_printed < MAX_DIAG_PER_TEST)
    1aa0:	8241a803          	lw	a6,-2012(gp) # 449c <t_printed>
    1aa4:	00700693          	li	a3,7
    1aa8:	0306d063          	bge	a3,a6,1ac8 <expect_color+0x54>
        t_extra++;
    1aac:	8201a783          	lw	a5,-2016(gp) # 4498 <t_extra>
    1ab0:	00178793          	addi	a5,a5,1
    1ab4:	82f1a023          	sw	a5,-2016(gp) # 4498 <t_extra>
    t_fail++;
    1ab8:	8281a783          	lw	a5,-2008(gp) # 44a0 <t_fail>
    1abc:	00178793          	addi	a5,a5,1
    1ac0:	82f1a423          	sw	a5,-2008(gp) # 44a0 <t_fail>
    1ac4:	00008067          	ret
{
    1ac8:	ff010113          	addi	sp,sp,-16
    1acc:	00112623          	sw	ra,12(sp)
        bsp_printf("[FAIL] %s x=%d y=%d expected=0x%08X actual=0x%08X\r\n",
    1ad0:	00060693          	mv	a3,a2
    1ad4:	00058613          	mv	a2,a1
    1ad8:	00050593          	mv	a1,a0
    1adc:	00004537          	lui	a0,0x4
    1ae0:	00c50513          	addi	a0,a0,12 # 400c <_data+0x118>
    1ae4:	c25ff0ef          	jal	1708 <bsp_printf>
        t_printed++;
    1ae8:	8241a783          	lw	a5,-2012(gp) # 449c <t_printed>
    1aec:	00178793          	addi	a5,a5,1
    1af0:	82f1a223          	sw	a5,-2012(gp) # 449c <t_printed>
    t_fail++;
    1af4:	8281a783          	lw	a5,-2008(gp) # 44a0 <t_fail>
    1af8:	00178793          	addi	a5,a5,1
    1afc:	82f1a423          	sw	a5,-2008(gp) # 44a0 <t_fail>
}
    1b00:	00c12083          	lw	ra,12(sp)
    1b04:	01010113          	addi	sp,sp,16
    1b08:	00008067          	ret
    1b0c:	00008067          	ret

00001b10 <expect_rect>:
{
    1b10:	fd010113          	addi	sp,sp,-48
    1b14:	02112623          	sw	ra,44(sp)
    1b18:	02812423          	sw	s0,40(sp)
    1b1c:	02912223          	sw	s1,36(sp)
    1b20:	03212023          	sw	s2,32(sp)
    1b24:	01312e23          	sw	s3,28(sp)
    1b28:	01412c23          	sw	s4,24(sp)
    1b2c:	01512a23          	sw	s5,20(sp)
    1b30:	01612823          	sw	s6,16(sp)
    1b34:	01712623          	sw	s7,12(sp)
    1b38:	00050993          	mv	s3,a0
    1b3c:	00058913          	mv	s2,a1
    1b40:	00060a93          	mv	s5,a2
    1b44:	00068a13          	mv	s4,a3
    1b48:	00070b13          	mv	s6,a4
    1b4c:	00078b93          	mv	s7,a5
    for (int y = 0; y < FB_H; y++)
    1b50:	00000493          	li	s1,0
    1b54:	0600006f          	j	1bb4 <expect_rect+0xa4>
            expect_color(name, x, y, inside ? want : COLOR_BG);
    1b58:	00000693          	li	a3,0
    1b5c:	00048613          	mv	a2,s1
    1b60:	00040593          	mv	a1,s0
    1b64:	00098513          	mv	a0,s3
    1b68:	f0dff0ef          	jal	1a74 <expect_color>
        for (int x = 0; x < FB_W; x++)
    1b6c:	00140413          	addi	s0,s0,1
    1b70:	00f00813          	li	a6,15
    1b74:	02884e63          	blt	a6,s0,1bb0 <expect_rect+0xa0>
            int inside = (x >= rx && x < rx + rw && y >= ry && y < ry + rh);
    1b78:	ff2440e3          	blt	s0,s2,1b58 <expect_rect+0x48>
    1b7c:	014905b3          	add	a1,s2,s4
    1b80:	00b45c63          	bge	s0,a1,1b98 <expect_rect+0x88>
    1b84:	0154ce63          	blt	s1,s5,1ba0 <expect_rect+0x90>
    1b88:	016a86b3          	add	a3,s5,s6
    1b8c:	00d4ce63          	blt	s1,a3,1ba8 <expect_rect+0x98>
            expect_color(name, x, y, inside ? want : COLOR_BG);
    1b90:	00000693          	li	a3,0
    1b94:	fc9ff06f          	j	1b5c <expect_rect+0x4c>
    1b98:	00000693          	li	a3,0
    1b9c:	fc1ff06f          	j	1b5c <expect_rect+0x4c>
    1ba0:	00000693          	li	a3,0
    1ba4:	fb9ff06f          	j	1b5c <expect_rect+0x4c>
    1ba8:	000b8693          	mv	a3,s7
    1bac:	fb1ff06f          	j	1b5c <expect_rect+0x4c>
    for (int y = 0; y < FB_H; y++)
    1bb0:	00148493          	addi	s1,s1,1
    1bb4:	00b00793          	li	a5,11
    1bb8:	0097c663          	blt	a5,s1,1bc4 <expect_rect+0xb4>
        for (int x = 0; x < FB_W; x++)
    1bbc:	00000413          	li	s0,0
    1bc0:	fb1ff06f          	j	1b70 <expect_rect+0x60>
}
    1bc4:	02c12083          	lw	ra,44(sp)
    1bc8:	02812403          	lw	s0,40(sp)
    1bcc:	02412483          	lw	s1,36(sp)
    1bd0:	02012903          	lw	s2,32(sp)
    1bd4:	01c12983          	lw	s3,28(sp)
    1bd8:	01812a03          	lw	s4,24(sp)
    1bdc:	01412a83          	lw	s5,20(sp)
    1be0:	01012b03          	lw	s6,16(sp)
    1be4:	00c12b83          	lw	s7,12(sp)
    1be8:	03010113          	addi	sp,sp,48
    1bec:	00008067          	ret

00001bf0 <expect_padding_intact>:
{
    1bf0:	ff010113          	addi	sp,sp,-16
    1bf4:	00112623          	sw	ra,12(sp)
    1bf8:	00812423          	sw	s0,8(sp)
    1bfc:	00912223          	sw	s1,4(sp)
    1c00:	01212023          	sw	s2,0(sp)
    1c04:	00050913          	mv	s2,a0
    for (int y = 0; y < FB_ROWS; y++)
    1c08:	00000493          	li	s1,0
    1c0c:	0400006f          	j	1c4c <expect_padding_intact+0x5c>
                expect_color(name, x, y, COLOR_GUARD);
    1c10:	00abd6b7          	lui	a3,0xabd
    1c14:	def68693          	addi	a3,a3,-529 # abcdef <__freertos_irq_stack_top+0xab737f>
    1c18:	00048613          	mv	a2,s1
    1c1c:	00040593          	mv	a1,s0
    1c20:	00090513          	mv	a0,s2
    1c24:	e51ff0ef          	jal	1a74 <expect_color>
        for (int x = 0; x < FB_STRIDE; x++)
    1c28:	00140413          	addi	s0,s0,1
    1c2c:	01300793          	li	a5,19
    1c30:	0087cc63          	blt	a5,s0,1c48 <expect_padding_intact+0x58>
            if (x >= FB_W || y >= FB_H)
    1c34:	00f00793          	li	a5,15
    1c38:	fc87cce3          	blt	a5,s0,1c10 <expect_padding_intact+0x20>
    1c3c:	00b00793          	li	a5,11
    1c40:	fe97d4e3          	bge	a5,s1,1c28 <expect_padding_intact+0x38>
    1c44:	fcdff06f          	j	1c10 <expect_padding_intact+0x20>
    for (int y = 0; y < FB_ROWS; y++)
    1c48:	00148493          	addi	s1,s1,1
    1c4c:	00f00793          	li	a5,15
    1c50:	0097c663          	blt	a5,s1,1c5c <expect_padding_intact+0x6c>
        for (int x = 0; x < FB_STRIDE; x++)
    1c54:	00000413          	li	s0,0
    1c58:	fd5ff06f          	j	1c2c <expect_padding_intact+0x3c>
}
    1c5c:	00c12083          	lw	ra,12(sp)
    1c60:	00812403          	lw	s0,8(sp)
    1c64:	00412483          	lw	s1,4(sp)
    1c68:	00012903          	lw	s2,0(sp)
    1c6c:	01010113          	addi	sp,sp,16
    1c70:	00008067          	ret

00001c74 <test_t8_padding_intact>:
{
    1c74:	f7010113          	addi	sp,sp,-144
    1c78:	08112623          	sw	ra,140(sp)
    1c7c:	08812423          	sw	s0,136(sp)
    render_surface_t dst = make_canvas_surface();
    1c80:	02c10513          	addi	a0,sp,44
    1c84:	a05ff0ef          	jal	1688 <make_canvas_surface>
    render_surface_t src = make_sprite_surface();
    1c88:	01810513          	addi	a0,sp,24
    1c8c:	a29ff0ef          	jal	16b4 <make_sprite_surface>
    t_begin();
    1c90:	939ff0ef          	jal	15c8 <t_begin>
    reset_canvas();
    1c94:	945ff0ef          	jal	15d8 <reset_canvas>
    reset_sprite();
    1c98:	9bdff0ef          	jal	1654 <reset_sprite>
    expect_status(name, render_fill_rect(&dst, make_rect(0, 0, FB_W, FB_H), COLOR_BG),
    1c9c:	00c00713          	li	a4,12
    1ca0:	01000693          	li	a3,16
    1ca4:	00000613          	li	a2,0
    1ca8:	00000593          	li	a1,0
    1cac:	04010513          	addi	a0,sp,64
    1cb0:	a31ff0ef          	jal	16e0 <make_rect>
    1cb4:	04012783          	lw	a5,64(sp)
    1cb8:	00f12023          	sw	a5,0(sp)
    1cbc:	04412783          	lw	a5,68(sp)
    1cc0:	00f12223          	sw	a5,4(sp)
    1cc4:	04812783          	lw	a5,72(sp)
    1cc8:	00f12423          	sw	a5,8(sp)
    1ccc:	04c12783          	lw	a5,76(sp)
    1cd0:	00f12623          	sw	a5,12(sp)
    1cd4:	00000613          	li	a2,0
    1cd8:	00010593          	mv	a1,sp
    1cdc:	02c10513          	addi	a0,sp,44
    1ce0:	580010ef          	jal	3260 <render_fill_rect>
    1ce4:	00050593          	mv	a1,a0
    1ce8:	00000613          	li	a2,0
    1cec:	00004437          	lui	s0,0x4
    1cf0:	04040513          	addi	a0,s0,64 # 4040 <_data+0x14c>
    1cf4:	c45ff0ef          	jal	1938 <expect_status>
    expect_status(name, render_fill_rect(&dst, make_rect(-5, -5, 20, 20), COLOR_RED),
    1cf8:	01400713          	li	a4,20
    1cfc:	01400693          	li	a3,20
    1d00:	ffb00613          	li	a2,-5
    1d04:	ffb00593          	li	a1,-5
    1d08:	05010513          	addi	a0,sp,80
    1d0c:	9d5ff0ef          	jal	16e0 <make_rect>
    1d10:	05012783          	lw	a5,80(sp)
    1d14:	00f12023          	sw	a5,0(sp)
    1d18:	05412783          	lw	a5,84(sp)
    1d1c:	00f12223          	sw	a5,4(sp)
    1d20:	05812783          	lw	a5,88(sp)
    1d24:	00f12423          	sw	a5,8(sp)
    1d28:	05c12783          	lw	a5,92(sp)
    1d2c:	00f12623          	sw	a5,12(sp)
    1d30:	00ff0637          	lui	a2,0xff0
    1d34:	00010593          	mv	a1,sp
    1d38:	02c10513          	addi	a0,sp,44
    1d3c:	524010ef          	jal	3260 <render_fill_rect>
    1d40:	00050593          	mv	a1,a0
    1d44:	00000613          	li	a2,0
    1d48:	04040513          	addi	a0,s0,64
    1d4c:	bedff0ef          	jal	1938 <expect_status>
    expect_status(name, render_fill_rect(&dst, make_rect(FB_W - 1, FB_H - 1, 100, 100),
    1d50:	06400713          	li	a4,100
    1d54:	06400693          	li	a3,100
    1d58:	00b00613          	li	a2,11
    1d5c:	00f00593          	li	a1,15
    1d60:	06010513          	addi	a0,sp,96
    1d64:	97dff0ef          	jal	16e0 <make_rect>
    1d68:	06012783          	lw	a5,96(sp)
    1d6c:	00f12023          	sw	a5,0(sp)
    1d70:	06412783          	lw	a5,100(sp)
    1d74:	00f12223          	sw	a5,4(sp)
    1d78:	06812783          	lw	a5,104(sp)
    1d7c:	00f12423          	sw	a5,8(sp)
    1d80:	06c12783          	lw	a5,108(sp)
    1d84:	00f12623          	sw	a5,12(sp)
    1d88:	00010637          	lui	a2,0x10
    1d8c:	f0060613          	addi	a2,a2,-256 # ff00 <__freertos_irq_stack_top+0xa490>
    1d90:	00010593          	mv	a1,sp
    1d94:	02c10513          	addi	a0,sp,44
    1d98:	4c8010ef          	jal	3260 <render_fill_rect>
    1d9c:	00050593          	mv	a1,a0
    1da0:	00000613          	li	a2,0
    1da4:	04040513          	addi	a0,s0,64
    1da8:	b91ff0ef          	jal	1938 <expect_status>
    expect_status(name, render_blit(&dst, &src, -3, 2), RENDER_OK);
    1dac:	00200693          	li	a3,2
    1db0:	ffd00613          	li	a2,-3
    1db4:	01810593          	addi	a1,sp,24
    1db8:	02c10513          	addi	a0,sp,44
    1dbc:	588010ef          	jal	3344 <render_blit>
    1dc0:	00050593          	mv	a1,a0
    1dc4:	00000613          	li	a2,0
    1dc8:	04040513          	addi	a0,s0,64
    1dcc:	b6dff0ef          	jal	1938 <expect_status>
    expect_status(name, render_blit(&dst, &src, FB_W - 3, FB_H - 3), RENDER_OK);
    1dd0:	00900693          	li	a3,9
    1dd4:	00d00613          	li	a2,13
    1dd8:	01810593          	addi	a1,sp,24
    1ddc:	02c10513          	addi	a0,sp,44
    1de0:	564010ef          	jal	3344 <render_blit>
    1de4:	00050593          	mv	a1,a0
    1de8:	00000613          	li	a2,0
    1dec:	04040513          	addi	a0,s0,64
    1df0:	b49ff0ef          	jal	1938 <expect_status>
    expect_status(name, render_fill_rect(&dst, make_rect(0, 0, 0, 0), COLOR_BLUE),
    1df4:	00000713          	li	a4,0
    1df8:	00000693          	li	a3,0
    1dfc:	00000613          	li	a2,0
    1e00:	00000593          	li	a1,0
    1e04:	07010513          	addi	a0,sp,112
    1e08:	8d9ff0ef          	jal	16e0 <make_rect>
    1e0c:	07012783          	lw	a5,112(sp)
    1e10:	00f12023          	sw	a5,0(sp)
    1e14:	07412783          	lw	a5,116(sp)
    1e18:	00f12223          	sw	a5,4(sp)
    1e1c:	07812783          	lw	a5,120(sp)
    1e20:	00f12423          	sw	a5,8(sp)
    1e24:	07c12783          	lw	a5,124(sp)
    1e28:	00f12623          	sw	a5,12(sp)
    1e2c:	0ff00613          	li	a2,255
    1e30:	00010593          	mv	a1,sp
    1e34:	02c10513          	addi	a0,sp,44
    1e38:	428010ef          	jal	3260 <render_fill_rect>
    1e3c:	00050593          	mv	a1,a0
    1e40:	00000613          	li	a2,0
    1e44:	04040513          	addi	a0,s0,64
    1e48:	af1ff0ef          	jal	1938 <expect_status>
    expect_status(name, render_blit(&dst, &src, -100, -100), RENDER_OK);
    1e4c:	f9c00693          	li	a3,-100
    1e50:	f9c00613          	li	a2,-100
    1e54:	01810593          	addi	a1,sp,24
    1e58:	02c10513          	addi	a0,sp,44
    1e5c:	4e8010ef          	jal	3344 <render_blit>
    1e60:	00050593          	mv	a1,a0
    1e64:	00000613          	li	a2,0
    1e68:	04040513          	addi	a0,s0,64
    1e6c:	acdff0ef          	jal	1938 <expect_status>
    expect_padding_intact(name);
    1e70:	04040513          	addi	a0,s0,64
    1e74:	d7dff0ef          	jal	1bf0 <expect_padding_intact>
    t_end(name);
    1e78:	04040513          	addi	a0,s0,64
    1e7c:	9bdff0ef          	jal	1838 <t_end>
}
    1e80:	08c12083          	lw	ra,140(sp)
    1e84:	08812403          	lw	s0,136(sp)
    1e88:	09010113          	addi	sp,sp,144
    1e8c:	00008067          	ret

00001e90 <test_t3_fill_normal>:
{
    1e90:	f8010113          	addi	sp,sp,-128
    1e94:	06112e23          	sw	ra,124(sp)
    1e98:	06812c23          	sw	s0,120(sp)
    1e9c:	06912a23          	sw	s1,116(sp)
    1ea0:	07212823          	sw	s2,112(sp)
    render_surface_t s = make_canvas_surface();
    1ea4:	01c10513          	addi	a0,sp,28
    1ea8:	fe0ff0ef          	jal	1688 <make_canvas_surface>
    t_begin();
    1eac:	f1cff0ef          	jal	15c8 <t_begin>
    reset_canvas();
    1eb0:	f28ff0ef          	jal	15d8 <reset_canvas>
    st = render_fill_rect(&s, make_rect(4, 3, 5, 4), COLOR_RED);
    1eb4:	00400713          	li	a4,4
    1eb8:	00500693          	li	a3,5
    1ebc:	00300613          	li	a2,3
    1ec0:	00400593          	li	a1,4
    1ec4:	03010513          	addi	a0,sp,48
    1ec8:	819ff0ef          	jal	16e0 <make_rect>
    1ecc:	03012783          	lw	a5,48(sp)
    1ed0:	00f12023          	sw	a5,0(sp)
    1ed4:	03412783          	lw	a5,52(sp)
    1ed8:	00f12223          	sw	a5,4(sp)
    1edc:	03812783          	lw	a5,56(sp)
    1ee0:	00f12423          	sw	a5,8(sp)
    1ee4:	03c12783          	lw	a5,60(sp)
    1ee8:	00f12623          	sw	a5,12(sp)
    1eec:	00ff0637          	lui	a2,0xff0
    1ef0:	00010593          	mv	a1,sp
    1ef4:	01c10513          	addi	a0,sp,28
    1ef8:	368010ef          	jal	3260 <render_fill_rect>
    1efc:	00050593          	mv	a1,a0
    expect_status(name, st, RENDER_OK);
    1f00:	00000613          	li	a2,0
    1f04:	00004437          	lui	s0,0x4
    1f08:	06440513          	addi	a0,s0,100 # 4064 <_data+0x170>
    1f0c:	a2dff0ef          	jal	1938 <expect_status>
    expect_rect(name, 4, 3, 5, 4, COLOR_RED);
    1f10:	00ff07b7          	lui	a5,0xff0
    1f14:	00400713          	li	a4,4
    1f18:	00500693          	li	a3,5
    1f1c:	00300613          	li	a2,3
    1f20:	00400593          	li	a1,4
    1f24:	06440513          	addi	a0,s0,100
    1f28:	be9ff0ef          	jal	1b10 <expect_rect>
    expect_padding_intact(name);
    1f2c:	06440513          	addi	a0,s0,100
    1f30:	cc1ff0ef          	jal	1bf0 <expect_padding_intact>
    reset_canvas();
    1f34:	ea4ff0ef          	jal	15d8 <reset_canvas>
    st = render_fill_rect(&s, make_rect(0, 0, 16, 4), COLOR_RED);
    1f38:	00400713          	li	a4,4
    1f3c:	01000693          	li	a3,16
    1f40:	00000613          	li	a2,0
    1f44:	00000593          	li	a1,0
    1f48:	04010513          	addi	a0,sp,64
    1f4c:	f94ff0ef          	jal	16e0 <make_rect>
    1f50:	04012783          	lw	a5,64(sp)
    1f54:	00f12023          	sw	a5,0(sp)
    1f58:	04412783          	lw	a5,68(sp)
    1f5c:	00f12223          	sw	a5,4(sp)
    1f60:	04812783          	lw	a5,72(sp)
    1f64:	00f12423          	sw	a5,8(sp)
    1f68:	04c12783          	lw	a5,76(sp)
    1f6c:	00f12623          	sw	a5,12(sp)
    1f70:	00ff0637          	lui	a2,0xff0
    1f74:	00010593          	mv	a1,sp
    1f78:	01c10513          	addi	a0,sp,28
    1f7c:	2e4010ef          	jal	3260 <render_fill_rect>
    1f80:	00050593          	mv	a1,a0
    expect_status(name, st, RENDER_OK);
    1f84:	00000613          	li	a2,0
    1f88:	06440513          	addi	a0,s0,100
    1f8c:	9adff0ef          	jal	1938 <expect_status>
    st = render_fill_rect(&s, make_rect(0, 4, 16, 4), COLOR_GREEN);
    1f90:	00400713          	li	a4,4
    1f94:	01000693          	li	a3,16
    1f98:	00400613          	li	a2,4
    1f9c:	00000593          	li	a1,0
    1fa0:	05010513          	addi	a0,sp,80
    1fa4:	f3cff0ef          	jal	16e0 <make_rect>
    1fa8:	05012783          	lw	a5,80(sp)
    1fac:	00f12023          	sw	a5,0(sp)
    1fb0:	05412783          	lw	a5,84(sp)
    1fb4:	00f12223          	sw	a5,4(sp)
    1fb8:	05812783          	lw	a5,88(sp)
    1fbc:	00f12423          	sw	a5,8(sp)
    1fc0:	05c12783          	lw	a5,92(sp)
    1fc4:	00f12623          	sw	a5,12(sp)
    1fc8:	00010637          	lui	a2,0x10
    1fcc:	f0060613          	addi	a2,a2,-256 # ff00 <__freertos_irq_stack_top+0xa490>
    1fd0:	00010593          	mv	a1,sp
    1fd4:	01c10513          	addi	a0,sp,28
    1fd8:	288010ef          	jal	3260 <render_fill_rect>
    1fdc:	00050593          	mv	a1,a0
    expect_status(name, st, RENDER_OK);
    1fe0:	00000613          	li	a2,0
    1fe4:	06440513          	addi	a0,s0,100
    1fe8:	951ff0ef          	jal	1938 <expect_status>
    st = render_fill_rect(&s, make_rect(0, 8, 16, 4), COLOR_BLUE);
    1fec:	00400713          	li	a4,4
    1ff0:	01000693          	li	a3,16
    1ff4:	00800613          	li	a2,8
    1ff8:	00000593          	li	a1,0
    1ffc:	06010513          	addi	a0,sp,96
    2000:	ee0ff0ef          	jal	16e0 <make_rect>
    2004:	06012783          	lw	a5,96(sp)
    2008:	00f12023          	sw	a5,0(sp)
    200c:	06412783          	lw	a5,100(sp)
    2010:	00f12223          	sw	a5,4(sp)
    2014:	06812783          	lw	a5,104(sp)
    2018:	00f12423          	sw	a5,8(sp)
    201c:	06c12783          	lw	a5,108(sp)
    2020:	00f12623          	sw	a5,12(sp)
    2024:	0ff00613          	li	a2,255
    2028:	00010593          	mv	a1,sp
    202c:	01c10513          	addi	a0,sp,28
    2030:	230010ef          	jal	3260 <render_fill_rect>
    2034:	00050593          	mv	a1,a0
    expect_status(name, st, RENDER_OK);
    2038:	00000613          	li	a2,0
    203c:	06440513          	addi	a0,s0,100
    2040:	8f9ff0ef          	jal	1938 <expect_status>
    for (int y = 0; y < FB_H; y++)
    2044:	00000493          	li	s1,0
    2048:	03c0006f          	j	2084 <test_t3_fill_normal+0x1f4>
        uint32_t want = (y < 4) ? COLOR_RED : ((y < 8) ? COLOR_GREEN : COLOR_BLUE);
    204c:	00ff0937          	lui	s2,0xff0
    2050:	0540006f          	j	20a4 <test_t3_fill_normal+0x214>
    2054:	0ff00913          	li	s2,255
    2058:	04c0006f          	j	20a4 <test_t3_fill_normal+0x214>
            expect_color(name, x, y, want);
    205c:	00090693          	mv	a3,s2
    2060:	00048613          	mv	a2,s1
    2064:	00040593          	mv	a1,s0
    2068:	00004537          	lui	a0,0x4
    206c:	06450513          	addi	a0,a0,100 # 4064 <_data+0x170>
    2070:	a05ff0ef          	jal	1a74 <expect_color>
        for (int x = 0; x < FB_W; x++)
    2074:	00140413          	addi	s0,s0,1
    2078:	00f00793          	li	a5,15
    207c:	fe87d0e3          	bge	a5,s0,205c <test_t3_fill_normal+0x1cc>
    for (int y = 0; y < FB_H; y++)
    2080:	00148493          	addi	s1,s1,1
    2084:	00b00793          	li	a5,11
    2088:	0297c263          	blt	a5,s1,20ac <test_t3_fill_normal+0x21c>
        uint32_t want = (y < 4) ? COLOR_RED : ((y < 8) ? COLOR_GREEN : COLOR_BLUE);
    208c:	00300793          	li	a5,3
    2090:	fa97dee3          	bge	a5,s1,204c <test_t3_fill_normal+0x1bc>
    2094:	00700793          	li	a5,7
    2098:	fa97cee3          	blt	a5,s1,2054 <test_t3_fill_normal+0x1c4>
    209c:	00010937          	lui	s2,0x10
    20a0:	f0090913          	addi	s2,s2,-256 # ff00 <__freertos_irq_stack_top+0xa490>
        for (int x = 0; x < FB_W; x++)
    20a4:	00000413          	li	s0,0
    20a8:	fd1ff06f          	j	2078 <test_t3_fill_normal+0x1e8>
    expect_padding_intact(name);
    20ac:	00004437          	lui	s0,0x4
    20b0:	06440513          	addi	a0,s0,100 # 4064 <_data+0x170>
    20b4:	b3dff0ef          	jal	1bf0 <expect_padding_intact>
    t_end(name);
    20b8:	06440513          	addi	a0,s0,100
    20bc:	f7cff0ef          	jal	1838 <t_end>
}
    20c0:	07c12083          	lw	ra,124(sp)
    20c4:	07812403          	lw	s0,120(sp)
    20c8:	07412483          	lw	s1,116(sp)
    20cc:	07012903          	lw	s2,112(sp)
    20d0:	08010113          	addi	sp,sp,128
    20d4:	00008067          	ret

000020d8 <expect_all_visible>:
{
    20d8:	fe010113          	addi	sp,sp,-32
    20dc:	00112e23          	sw	ra,28(sp)
    20e0:	00812c23          	sw	s0,24(sp)
    20e4:	00912a23          	sw	s1,20(sp)
    20e8:	01212823          	sw	s2,16(sp)
    20ec:	01312623          	sw	s3,12(sp)
    20f0:	00050993          	mv	s3,a0
    20f4:	00058913          	mv	s2,a1
    for (int y = 0; y < FB_H; y++)
    20f8:	00000493          	li	s1,0
    20fc:	0280006f          	j	2124 <expect_all_visible+0x4c>
            expect_color(name, x, y, want);
    2100:	00090693          	mv	a3,s2
    2104:	00048613          	mv	a2,s1
    2108:	00040593          	mv	a1,s0
    210c:	00098513          	mv	a0,s3
    2110:	965ff0ef          	jal	1a74 <expect_color>
        for (int x = 0; x < FB_W; x++)
    2114:	00140413          	addi	s0,s0,1
    2118:	00f00793          	li	a5,15
    211c:	fe87d2e3          	bge	a5,s0,2100 <expect_all_visible+0x28>
    for (int y = 0; y < FB_H; y++)
    2120:	00148493          	addi	s1,s1,1
    2124:	00b00793          	li	a5,11
    2128:	0097c663          	blt	a5,s1,2134 <expect_all_visible+0x5c>
        for (int x = 0; x < FB_W; x++)
    212c:	00000413          	li	s0,0
    2130:	fe9ff06f          	j	2118 <expect_all_visible+0x40>
}
    2134:	01c12083          	lw	ra,28(sp)
    2138:	01812403          	lw	s0,24(sp)
    213c:	01412483          	lw	s1,20(sp)
    2140:	01012903          	lw	s2,16(sp)
    2144:	00c12983          	lw	s3,12(sp)
    2148:	02010113          	addi	sp,sp,32
    214c:	00008067          	ret

00002150 <expect_nothing_drawn>:
{
    2150:	ff010113          	addi	sp,sp,-16
    2154:	00112623          	sw	ra,12(sp)
    2158:	00812423          	sw	s0,8(sp)
    215c:	00050413          	mv	s0,a0
    expect_all_visible(name, COLOR_BG);
    2160:	00000593          	li	a1,0
    2164:	f75ff0ef          	jal	20d8 <expect_all_visible>
    expect_padding_intact(name);
    2168:	00040513          	mv	a0,s0
    216c:	a85ff0ef          	jal	1bf0 <expect_padding_intact>
}
    2170:	00c12083          	lw	ra,12(sp)
    2174:	00812403          	lw	s0,8(sp)
    2178:	01010113          	addi	sp,sp,16
    217c:	00008067          	ret

00002180 <test_t4a_fill_clip_left_top>:
{
    2180:	fa010113          	addi	sp,sp,-96
    2184:	04112e23          	sw	ra,92(sp)
    2188:	04812c23          	sw	s0,88(sp)
    render_surface_t s = make_canvas_surface();
    218c:	01c10513          	addi	a0,sp,28
    2190:	cf8ff0ef          	jal	1688 <make_canvas_surface>
    t_begin();
    2194:	c34ff0ef          	jal	15c8 <t_begin>
    reset_canvas();
    2198:	c40ff0ef          	jal	15d8 <reset_canvas>
    st = render_fill_rect(&s, make_rect(-3, -2, 6, 5), COLOR_GREEN);
    219c:	00500713          	li	a4,5
    21a0:	00600693          	li	a3,6
    21a4:	ffe00613          	li	a2,-2
    21a8:	ffd00593          	li	a1,-3
    21ac:	03010513          	addi	a0,sp,48
    21b0:	d30ff0ef          	jal	16e0 <make_rect>
    21b4:	03012783          	lw	a5,48(sp)
    21b8:	00f12023          	sw	a5,0(sp)
    21bc:	03412783          	lw	a5,52(sp)
    21c0:	00f12223          	sw	a5,4(sp)
    21c4:	03812783          	lw	a5,56(sp)
    21c8:	00f12423          	sw	a5,8(sp)
    21cc:	03c12783          	lw	a5,60(sp)
    21d0:	00f12623          	sw	a5,12(sp)
    21d4:	00010637          	lui	a2,0x10
    21d8:	f0060613          	addi	a2,a2,-256 # ff00 <__freertos_irq_stack_top+0xa490>
    21dc:	00010593          	mv	a1,sp
    21e0:	01c10513          	addi	a0,sp,28
    21e4:	07c010ef          	jal	3260 <render_fill_rect>
    21e8:	00050593          	mv	a1,a0
    expect_status(name, st, RENDER_OK);
    21ec:	00000613          	li	a2,0
    21f0:	00004437          	lui	s0,0x4
    21f4:	07840513          	addi	a0,s0,120 # 4078 <_data+0x184>
    21f8:	f40ff0ef          	jal	1938 <expect_status>
    expect_rect(name, 0, 0, 3, 3, COLOR_GREEN);
    21fc:	000107b7          	lui	a5,0x10
    2200:	f0078793          	addi	a5,a5,-256 # ff00 <__freertos_irq_stack_top+0xa490>
    2204:	00300713          	li	a4,3
    2208:	00300693          	li	a3,3
    220c:	00000613          	li	a2,0
    2210:	00000593          	li	a1,0
    2214:	07840513          	addi	a0,s0,120
    2218:	8f9ff0ef          	jal	1b10 <expect_rect>
    expect_padding_intact(name);
    221c:	07840513          	addi	a0,s0,120
    2220:	9d1ff0ef          	jal	1bf0 <expect_padding_intact>
    reset_canvas();
    2224:	bb4ff0ef          	jal	15d8 <reset_canvas>
    st = render_fill_rect(&s, make_rect(-100, -100, 10, 10), COLOR_RED);
    2228:	00a00713          	li	a4,10
    222c:	00a00693          	li	a3,10
    2230:	f9c00613          	li	a2,-100
    2234:	f9c00593          	li	a1,-100
    2238:	04010513          	addi	a0,sp,64
    223c:	ca4ff0ef          	jal	16e0 <make_rect>
    2240:	04012783          	lw	a5,64(sp)
    2244:	00f12023          	sw	a5,0(sp)
    2248:	04412783          	lw	a5,68(sp)
    224c:	00f12223          	sw	a5,4(sp)
    2250:	04812783          	lw	a5,72(sp)
    2254:	00f12423          	sw	a5,8(sp)
    2258:	04c12783          	lw	a5,76(sp)
    225c:	00f12623          	sw	a5,12(sp)
    2260:	00ff0637          	lui	a2,0xff0
    2264:	00010593          	mv	a1,sp
    2268:	01c10513          	addi	a0,sp,28
    226c:	7f5000ef          	jal	3260 <render_fill_rect>
    2270:	00050593          	mv	a1,a0
    expect_status(name, st, RENDER_OK);
    2274:	00000613          	li	a2,0
    2278:	07840513          	addi	a0,s0,120
    227c:	ebcff0ef          	jal	1938 <expect_status>
    expect_nothing_drawn(name);
    2280:	07840513          	addi	a0,s0,120
    2284:	ecdff0ef          	jal	2150 <expect_nothing_drawn>
    t_end(name);
    2288:	07840513          	addi	a0,s0,120
    228c:	dacff0ef          	jal	1838 <t_end>
}
    2290:	05c12083          	lw	ra,92(sp)
    2294:	05812403          	lw	s0,88(sp)
    2298:	06010113          	addi	sp,sp,96
    229c:	00008067          	ret

000022a0 <test_t9_fpga_backend_inert>:
{
    22a0:	fb010113          	addi	sp,sp,-80
    22a4:	04112623          	sw	ra,76(sp)
    22a8:	04812423          	sw	s0,72(sp)
    render_surface_t s = make_canvas_surface();
    22ac:	01c10513          	addi	a0,sp,28
    22b0:	bd8ff0ef          	jal	1688 <make_canvas_surface>
    t_begin();
    22b4:	b14ff0ef          	jal	15c8 <t_begin>
    reset_canvas();
    22b8:	b20ff0ef          	jal	15d8 <reset_canvas>
    (void)render_select(RENDER_BACKEND_FPGA);
    22bc:	00100513          	li	a0,1
    22c0:	46d000ef          	jal	2f2c <render_select>
    st = render_fill_rect(&s, make_rect(0, 0, 4, 4), COLOR_RED);
    22c4:	00400713          	li	a4,4
    22c8:	00400693          	li	a3,4
    22cc:	00000613          	li	a2,0
    22d0:	00000593          	li	a1,0
    22d4:	03010513          	addi	a0,sp,48
    22d8:	c08ff0ef          	jal	16e0 <make_rect>
    22dc:	03012783          	lw	a5,48(sp)
    22e0:	00f12023          	sw	a5,0(sp)
    22e4:	03412783          	lw	a5,52(sp)
    22e8:	00f12223          	sw	a5,4(sp)
    22ec:	03812783          	lw	a5,56(sp)
    22f0:	00f12423          	sw	a5,8(sp)
    22f4:	03c12783          	lw	a5,60(sp)
    22f8:	00f12623          	sw	a5,12(sp)
    22fc:	00ff0637          	lui	a2,0xff0
    2300:	00010593          	mv	a1,sp
    2304:	01c10513          	addi	a0,sp,28
    2308:	759000ef          	jal	3260 <render_fill_rect>
    if (st != RENDER_ERR_NOT_READY)
    230c:	00c00793          	li	a5,12
    2310:	02f51663          	bne	a0,a5,233c <test_t9_fpga_backend_inert+0x9c>
    expect_nothing_drawn(name);
    2314:	00004437          	lui	s0,0x4
    2318:	09040513          	addi	a0,s0,144 # 4090 <_data+0x19c>
    231c:	e35ff0ef          	jal	2150 <expect_nothing_drawn>
    render_init();
    2320:	445000ef          	jal	2f64 <render_init>
    t_end(name);
    2324:	09040513          	addi	a0,s0,144
    2328:	d10ff0ef          	jal	1838 <t_end>
}
    232c:	04c12083          	lw	ra,76(sp)
    2330:	04812403          	lw	s0,72(sp)
    2334:	05010113          	addi	sp,sp,80
    2338:	00008067          	ret
    233c:	04912223          	sw	s1,68(sp)
    2340:	00050413          	mv	s0,a0
        fail_text(name, render_strstatus(RENDER_ERR_NOT_READY),
    2344:	00c00513          	li	a0,12
    2348:	5ac010ef          	jal	38f4 <render_strstatus>
    234c:	00050493          	mv	s1,a0
    2350:	00040513          	mv	a0,s0
    2354:	5a0010ef          	jal	38f4 <render_strstatus>
    2358:	00050613          	mv	a2,a0
    235c:	00048593          	mv	a1,s1
    2360:	00004537          	lui	a0,0x4
    2364:	09050513          	addi	a0,a0,144 # 4090 <_data+0x19c>
    2368:	d64ff0ef          	jal	18cc <fail_text>
    236c:	04412483          	lw	s1,68(sp)
    2370:	fa5ff06f          	j	2314 <test_t9_fpga_backend_inert+0x74>

00002374 <test_t4b_fill_clip_right_bottom>:
{
    2374:	f9010113          	addi	sp,sp,-112
    2378:	06112623          	sw	ra,108(sp)
    237c:	06812423          	sw	s0,104(sp)
    render_surface_t s = make_canvas_surface();
    2380:	01c10513          	addi	a0,sp,28
    2384:	b04ff0ef          	jal	1688 <make_canvas_surface>
    t_begin();
    2388:	a40ff0ef          	jal	15c8 <t_begin>
    reset_canvas();
    238c:	a4cff0ef          	jal	15d8 <reset_canvas>
    st = render_fill_rect(&s, make_rect(FB_W - 3, FB_H - 2, 50, 50), COLOR_BLUE);
    2390:	03200713          	li	a4,50
    2394:	03200693          	li	a3,50
    2398:	00a00613          	li	a2,10
    239c:	00d00593          	li	a1,13
    23a0:	03010513          	addi	a0,sp,48
    23a4:	b3cff0ef          	jal	16e0 <make_rect>
    23a8:	03012783          	lw	a5,48(sp)
    23ac:	00f12023          	sw	a5,0(sp)
    23b0:	03412783          	lw	a5,52(sp)
    23b4:	00f12223          	sw	a5,4(sp)
    23b8:	03812783          	lw	a5,56(sp)
    23bc:	00f12423          	sw	a5,8(sp)
    23c0:	03c12783          	lw	a5,60(sp)
    23c4:	00f12623          	sw	a5,12(sp)
    23c8:	0ff00613          	li	a2,255
    23cc:	00010593          	mv	a1,sp
    23d0:	01c10513          	addi	a0,sp,28
    23d4:	68d000ef          	jal	3260 <render_fill_rect>
    23d8:	00050593          	mv	a1,a0
    expect_status(name, st, RENDER_OK);
    23dc:	00000613          	li	a2,0
    23e0:	00004437          	lui	s0,0x4
    23e4:	0a840513          	addi	a0,s0,168 # 40a8 <_data+0x1b4>
    23e8:	d50ff0ef          	jal	1938 <expect_status>
    expect_rect(name, FB_W - 3, FB_H - 2, 3, 2, COLOR_BLUE);
    23ec:	0ff00793          	li	a5,255
    23f0:	00200713          	li	a4,2
    23f4:	00300693          	li	a3,3
    23f8:	00a00613          	li	a2,10
    23fc:	00d00593          	li	a1,13
    2400:	0a840513          	addi	a0,s0,168
    2404:	f0cff0ef          	jal	1b10 <expect_rect>
    expect_padding_intact(name);
    2408:	0a840513          	addi	a0,s0,168
    240c:	fe4ff0ef          	jal	1bf0 <expect_padding_intact>
    reset_canvas();
    2410:	9c8ff0ef          	jal	15d8 <reset_canvas>
    st = render_fill_rect(&s, make_rect(0, 0, FB_W, FB_H), COLOR_RED);
    2414:	00c00713          	li	a4,12
    2418:	01000693          	li	a3,16
    241c:	00000613          	li	a2,0
    2420:	00000593          	li	a1,0
    2424:	04010513          	addi	a0,sp,64
    2428:	ab8ff0ef          	jal	16e0 <make_rect>
    242c:	04012783          	lw	a5,64(sp)
    2430:	00f12023          	sw	a5,0(sp)
    2434:	04412783          	lw	a5,68(sp)
    2438:	00f12223          	sw	a5,4(sp)
    243c:	04812783          	lw	a5,72(sp)
    2440:	00f12423          	sw	a5,8(sp)
    2444:	04c12783          	lw	a5,76(sp)
    2448:	00f12623          	sw	a5,12(sp)
    244c:	00ff0637          	lui	a2,0xff0
    2450:	00010593          	mv	a1,sp
    2454:	01c10513          	addi	a0,sp,28
    2458:	609000ef          	jal	3260 <render_fill_rect>
    245c:	00050593          	mv	a1,a0
    expect_status(name, st, RENDER_OK);
    2460:	00000613          	li	a2,0
    2464:	0a840513          	addi	a0,s0,168
    2468:	cd0ff0ef          	jal	1938 <expect_status>
    expect_all_visible(name, COLOR_RED);
    246c:	00ff05b7          	lui	a1,0xff0
    2470:	0a840513          	addi	a0,s0,168
    2474:	c65ff0ef          	jal	20d8 <expect_all_visible>
    expect_padding_intact(name);
    2478:	0a840513          	addi	a0,s0,168
    247c:	f74ff0ef          	jal	1bf0 <expect_padding_intact>
    reset_canvas();
    2480:	958ff0ef          	jal	15d8 <reset_canvas>
    st = render_fill_rect(&s, make_rect(FB_W + 10, FB_H + 10, 10, 10), COLOR_GREEN);
    2484:	00a00713          	li	a4,10
    2488:	00a00693          	li	a3,10
    248c:	01600613          	li	a2,22
    2490:	01a00593          	li	a1,26
    2494:	05010513          	addi	a0,sp,80
    2498:	a48ff0ef          	jal	16e0 <make_rect>
    249c:	05012783          	lw	a5,80(sp)
    24a0:	00f12023          	sw	a5,0(sp)
    24a4:	05412783          	lw	a5,84(sp)
    24a8:	00f12223          	sw	a5,4(sp)
    24ac:	05812783          	lw	a5,88(sp)
    24b0:	00f12423          	sw	a5,8(sp)
    24b4:	05c12783          	lw	a5,92(sp)
    24b8:	00f12623          	sw	a5,12(sp)
    24bc:	00010637          	lui	a2,0x10
    24c0:	f0060613          	addi	a2,a2,-256 # ff00 <__freertos_irq_stack_top+0xa490>
    24c4:	00010593          	mv	a1,sp
    24c8:	01c10513          	addi	a0,sp,28
    24cc:	595000ef          	jal	3260 <render_fill_rect>
    24d0:	00050593          	mv	a1,a0
    expect_status(name, st, RENDER_OK);
    24d4:	00000613          	li	a2,0
    24d8:	0a840513          	addi	a0,s0,168
    24dc:	c5cff0ef          	jal	1938 <expect_status>
    expect_nothing_drawn(name);
    24e0:	0a840513          	addi	a0,s0,168
    24e4:	c6dff0ef          	jal	2150 <expect_nothing_drawn>
    t_end(name);
    24e8:	0a840513          	addi	a0,s0,168
    24ec:	b4cff0ef          	jal	1838 <t_end>
}
    24f0:	06c12083          	lw	ra,108(sp)
    24f4:	06812403          	lw	s0,104(sp)
    24f8:	07010113          	addi	sp,sp,112
    24fc:	00008067          	ret

00002500 <expect_blit>:
{
    2500:	fe010113          	addi	sp,sp,-32
    2504:	00112e23          	sw	ra,28(sp)
    2508:	00812c23          	sw	s0,24(sp)
    250c:	00912a23          	sw	s1,20(sp)
    2510:	01212823          	sw	s2,16(sp)
    2514:	01312623          	sw	s3,12(sp)
    2518:	01412423          	sw	s4,8(sp)
    251c:	00050a13          	mv	s4,a0
    2520:	00058993          	mv	s3,a1
    2524:	00060913          	mv	s2,a2
    for (int y = 0; y < FB_H; y++)
    2528:	00000493          	li	s1,0
    252c:	0600006f          	j	258c <expect_blit+0x8c>
                expect_color(name, x, y, COLOR_BG);
    2530:	00000693          	li	a3,0
    2534:	00048613          	mv	a2,s1
    2538:	00040593          	mv	a1,s0
    253c:	000a0513          	mv	a0,s4
    2540:	d34ff0ef          	jal	1a74 <expect_color>
        for (int x = 0; x < FB_W; x++)
    2544:	00140413          	addi	s0,s0,1
    2548:	00f00793          	li	a5,15
    254c:	0287ce63          	blt	a5,s0,2588 <expect_blit+0x88>
            int sx = x - dst_x;
    2550:	41340533          	sub	a0,s0,s3
            int sy = y - dst_y;
    2554:	412485b3          	sub	a1,s1,s2
            if (sx >= 0 && sx < SPR_W && sy >= 0 && sy < SPR_H)
    2558:	00400793          	li	a5,4
    255c:	fca7eae3          	bltu	a5,a0,2530 <expect_blit+0x30>
    2560:	fc05c8e3          	bltz	a1,2530 <expect_blit+0x30>
    2564:	00300793          	li	a5,3
    2568:	fcb7c4e3          	blt	a5,a1,2530 <expect_blit+0x30>
                expect_color(name, x, y, sprite_at(sx, sy));
    256c:	988ff0ef          	jal	16f4 <sprite_at>
    2570:	00050693          	mv	a3,a0
    2574:	00048613          	mv	a2,s1
    2578:	00040593          	mv	a1,s0
    257c:	000a0513          	mv	a0,s4
    2580:	cf4ff0ef          	jal	1a74 <expect_color>
    2584:	fc1ff06f          	j	2544 <expect_blit+0x44>
    for (int y = 0; y < FB_H; y++)
    2588:	00148493          	addi	s1,s1,1
    258c:	00b00793          	li	a5,11
    2590:	0097c663          	blt	a5,s1,259c <expect_blit+0x9c>
        for (int x = 0; x < FB_W; x++)
    2594:	00000413          	li	s0,0
    2598:	fb1ff06f          	j	2548 <expect_blit+0x48>
}
    259c:	01c12083          	lw	ra,28(sp)
    25a0:	01812403          	lw	s0,24(sp)
    25a4:	01412483          	lw	s1,20(sp)
    25a8:	01012903          	lw	s2,16(sp)
    25ac:	00c12983          	lw	s3,12(sp)
    25b0:	00812a03          	lw	s4,8(sp)
    25b4:	02010113          	addi	sp,sp,32
    25b8:	00008067          	ret

000025bc <test_t5_blit_normal>:
{
    25bc:	fc010113          	addi	sp,sp,-64
    25c0:	02112e23          	sw	ra,60(sp)
    25c4:	02812c23          	sw	s0,56(sp)
    render_surface_t dst = make_canvas_surface();
    25c8:	01c10513          	addi	a0,sp,28
    25cc:	8bcff0ef          	jal	1688 <make_canvas_surface>
    render_surface_t src = make_sprite_surface();
    25d0:	00810513          	addi	a0,sp,8
    25d4:	8e0ff0ef          	jal	16b4 <make_sprite_surface>
    t_begin();
    25d8:	ff1fe0ef          	jal	15c8 <t_begin>
    reset_canvas();
    25dc:	ffdfe0ef          	jal	15d8 <reset_canvas>
    reset_sprite();
    25e0:	874ff0ef          	jal	1654 <reset_sprite>
    st = render_blit(&dst, &src, 6, 4);
    25e4:	00400693          	li	a3,4
    25e8:	00600613          	li	a2,6
    25ec:	00810593          	addi	a1,sp,8
    25f0:	01c10513          	addi	a0,sp,28
    25f4:	551000ef          	jal	3344 <render_blit>
    25f8:	00050593          	mv	a1,a0
    expect_status(name, st, RENDER_OK);
    25fc:	00000613          	li	a2,0
    2600:	00004437          	lui	s0,0x4
    2604:	0c440513          	addi	a0,s0,196 # 40c4 <_data+0x1d0>
    2608:	b30ff0ef          	jal	1938 <expect_status>
    expect_blit(name, 6, 4);
    260c:	00400613          	li	a2,4
    2610:	00600593          	li	a1,6
    2614:	0c440513          	addi	a0,s0,196
    2618:	ee9ff0ef          	jal	2500 <expect_blit>
    expect_padding_intact(name);
    261c:	0c440513          	addi	a0,s0,196
    2620:	dd0ff0ef          	jal	1bf0 <expect_padding_intact>
    t_end(name);
    2624:	0c440513          	addi	a0,s0,196
    2628:	a10ff0ef          	jal	1838 <t_end>
}
    262c:	03c12083          	lw	ra,60(sp)
    2630:	03812403          	lw	s0,56(sp)
    2634:	04010113          	addi	sp,sp,64
    2638:	00008067          	ret

0000263c <test_t6_blit_clip>:
{
    263c:	fc010113          	addi	sp,sp,-64
    2640:	02112e23          	sw	ra,60(sp)
    2644:	02812c23          	sw	s0,56(sp)
    render_surface_t dst = make_canvas_surface();
    2648:	01c10513          	addi	a0,sp,28
    264c:	83cff0ef          	jal	1688 <make_canvas_surface>
    render_surface_t src = make_sprite_surface();
    2650:	00810513          	addi	a0,sp,8
    2654:	860ff0ef          	jal	16b4 <make_sprite_surface>
    t_begin();
    2658:	f71fe0ef          	jal	15c8 <t_begin>
    reset_canvas();
    265c:	f7dfe0ef          	jal	15d8 <reset_canvas>
    reset_sprite();
    2660:	ff5fe0ef          	jal	1654 <reset_sprite>
    expect_status(name, render_blit(&dst, &src, -2, -3), RENDER_OK);
    2664:	ffd00693          	li	a3,-3
    2668:	ffe00613          	li	a2,-2
    266c:	00810593          	addi	a1,sp,8
    2670:	01c10513          	addi	a0,sp,28
    2674:	4d1000ef          	jal	3344 <render_blit>
    2678:	00050593          	mv	a1,a0
    267c:	00000613          	li	a2,0
    2680:	00004437          	lui	s0,0x4
    2684:	0d440513          	addi	a0,s0,212 # 40d4 <_data+0x1e0>
    2688:	ab0ff0ef          	jal	1938 <expect_status>
    expect_blit(name, -2, -3);
    268c:	ffd00613          	li	a2,-3
    2690:	ffe00593          	li	a1,-2
    2694:	0d440513          	addi	a0,s0,212
    2698:	e69ff0ef          	jal	2500 <expect_blit>
    expect_padding_intact(name);
    269c:	0d440513          	addi	a0,s0,212
    26a0:	d50ff0ef          	jal	1bf0 <expect_padding_intact>
    t_end(name);
    26a4:	0d440513          	addi	a0,s0,212
    26a8:	990ff0ef          	jal	1838 <t_end>
    t_begin();
    26ac:	f1dfe0ef          	jal	15c8 <t_begin>
    reset_canvas();
    26b0:	f29fe0ef          	jal	15d8 <reset_canvas>
    expect_status(name, render_blit(&dst, &src, FB_W - 2, FB_H - 2), RENDER_OK);
    26b4:	00a00693          	li	a3,10
    26b8:	00e00613          	li	a2,14
    26bc:	00810593          	addi	a1,sp,8
    26c0:	01c10513          	addi	a0,sp,28
    26c4:	481000ef          	jal	3344 <render_blit>
    26c8:	00050593          	mv	a1,a0
    26cc:	00000613          	li	a2,0
    26d0:	00004437          	lui	s0,0x4
    26d4:	0ec40513          	addi	a0,s0,236 # 40ec <_data+0x1f8>
    26d8:	a60ff0ef          	jal	1938 <expect_status>
    expect_blit(name, FB_W - 2, FB_H - 2);
    26dc:	00a00613          	li	a2,10
    26e0:	00e00593          	li	a1,14
    26e4:	0ec40513          	addi	a0,s0,236
    26e8:	e19ff0ef          	jal	2500 <expect_blit>
    expect_padding_intact(name);
    26ec:	0ec40513          	addi	a0,s0,236
    26f0:	d00ff0ef          	jal	1bf0 <expect_padding_intact>
    t_end(name);
    26f4:	0ec40513          	addi	a0,s0,236
    26f8:	940ff0ef          	jal	1838 <t_end>
    t_begin();
    26fc:	ecdfe0ef          	jal	15c8 <t_begin>
    reset_canvas();
    2700:	ed9fe0ef          	jal	15d8 <reset_canvas>
    expect_status(name, render_blit(&dst, &src, -100, -100), RENDER_OK);
    2704:	f9c00693          	li	a3,-100
    2708:	f9c00613          	li	a2,-100
    270c:	00810593          	addi	a1,sp,8
    2710:	01c10513          	addi	a0,sp,28
    2714:	431000ef          	jal	3344 <render_blit>
    2718:	00050593          	mv	a1,a0
    271c:	00000613          	li	a2,0
    2720:	00004437          	lui	s0,0x4
    2724:	10840513          	addi	a0,s0,264 # 4108 <_data+0x214>
    2728:	a10ff0ef          	jal	1938 <expect_status>
    expect_nothing_drawn(name);
    272c:	10840513          	addi	a0,s0,264
    2730:	a21ff0ef          	jal	2150 <expect_nothing_drawn>
    t_end(name);
    2734:	10840513          	addi	a0,s0,264
    2738:	900ff0ef          	jal	1838 <t_end>
}
    273c:	03c12083          	lw	ra,60(sp)
    2740:	03812403          	lw	s0,56(sp)
    2744:	04010113          	addi	sp,sp,64
    2748:	00008067          	ret

0000274c <test_t7_stride_not_equal_width>:
{
    274c:	fa010113          	addi	sp,sp,-96
    2750:	04112e23          	sw	ra,92(sp)
    2754:	04812c23          	sw	s0,88(sp)
    2758:	04912a23          	sw	s1,84(sp)
    render_surface_t s = make_canvas_surface();
    275c:	01c10513          	addi	a0,sp,28
    2760:	f29fe0ef          	jal	1688 <make_canvas_surface>
    t_begin();
    2764:	e65fe0ef          	jal	15c8 <t_begin>
    reset_canvas();
    2768:	e71fe0ef          	jal	15d8 <reset_canvas>
    st = render_fill_rect(&s, make_rect(0, 0, FB_W, FB_H), COLOR_BLUE);
    276c:	00c00713          	li	a4,12
    2770:	01000693          	li	a3,16
    2774:	00000613          	li	a2,0
    2778:	00000593          	li	a1,0
    277c:	03010513          	addi	a0,sp,48
    2780:	f61fe0ef          	jal	16e0 <make_rect>
    2784:	03012783          	lw	a5,48(sp)
    2788:	00f12023          	sw	a5,0(sp)
    278c:	03412783          	lw	a5,52(sp)
    2790:	00f12223          	sw	a5,4(sp)
    2794:	03812783          	lw	a5,56(sp)
    2798:	00f12423          	sw	a5,8(sp)
    279c:	03c12783          	lw	a5,60(sp)
    27a0:	00f12623          	sw	a5,12(sp)
    27a4:	0ff00613          	li	a2,255
    27a8:	00010593          	mv	a1,sp
    27ac:	01c10513          	addi	a0,sp,28
    27b0:	2b1000ef          	jal	3260 <render_fill_rect>
    27b4:	00050593          	mv	a1,a0
    expect_status(name, st, RENDER_OK);
    27b8:	00000613          	li	a2,0
    27bc:	00004437          	lui	s0,0x4
    27c0:	12040513          	addi	a0,s0,288 # 4120 <_data+0x22c>
    27c4:	974ff0ef          	jal	1938 <expect_status>
    expect_all_visible(name, COLOR_BLUE);
    27c8:	0ff00593          	li	a1,255
    27cc:	12040513          	addi	a0,s0,288
    27d0:	909ff0ef          	jal	20d8 <expect_all_visible>
    expect_padding_intact(name);
    27d4:	12040513          	addi	a0,s0,288
    27d8:	c18ff0ef          	jal	1bf0 <expect_padding_intact>
    reset_canvas();
    27dc:	dfdfe0ef          	jal	15d8 <reset_canvas>
    for (int y = 0; y < FB_H; y++)
    27e0:	00000613          	li	a2,0
    27e4:	0680006f          	j	284c <test_t7_stride_not_equal_width+0x100>
        uint32_t c = 0x00010000u * (uint32_t)(y + 1);
    27e8:	00160413          	addi	s0,a2,1
    27ec:	01041493          	slli	s1,s0,0x10
        st = render_fill_rect(&s, make_rect(FB_W - 1, y, 1, 1), c);
    27f0:	00100713          	li	a4,1
    27f4:	00100693          	li	a3,1
    27f8:	00f00593          	li	a1,15
    27fc:	04010513          	addi	a0,sp,64
    2800:	ee1fe0ef          	jal	16e0 <make_rect>
    2804:	04012783          	lw	a5,64(sp)
    2808:	00f12023          	sw	a5,0(sp)
    280c:	04412783          	lw	a5,68(sp)
    2810:	00f12223          	sw	a5,4(sp)
    2814:	04812783          	lw	a5,72(sp)
    2818:	00f12423          	sw	a5,8(sp)
    281c:	04c12783          	lw	a5,76(sp)
    2820:	00f12623          	sw	a5,12(sp)
    2824:	00048613          	mv	a2,s1
    2828:	00010593          	mv	a1,sp
    282c:	01c10513          	addi	a0,sp,28
    2830:	231000ef          	jal	3260 <render_fill_rect>
    2834:	00050593          	mv	a1,a0
        expect_status(name, st, RENDER_OK);
    2838:	00000613          	li	a2,0
    283c:	00004537          	lui	a0,0x4
    2840:	12050513          	addi	a0,a0,288 # 4120 <_data+0x22c>
    2844:	8f4ff0ef          	jal	1938 <expect_status>
    for (int y = 0; y < FB_H; y++)
    2848:	00040613          	mv	a2,s0
    284c:	00b00793          	li	a5,11
    2850:	f8c7dce3          	bge	a5,a2,27e8 <test_t7_stride_not_equal_width+0x9c>
    for (int y = 0; y < FB_H; y++)
    2854:	00000613          	li	a2,0
    2858:	0200006f          	j	2878 <test_t7_stride_not_equal_width+0x12c>
        uint32_t c = 0x00010000u * (uint32_t)(y + 1);
    285c:	00160413          	addi	s0,a2,1
        expect_color(name, FB_W - 1, y, c);
    2860:	01041693          	slli	a3,s0,0x10
    2864:	00f00593          	li	a1,15
    2868:	00004537          	lui	a0,0x4
    286c:	12050513          	addi	a0,a0,288 # 4120 <_data+0x22c>
    2870:	a04ff0ef          	jal	1a74 <expect_color>
    for (int y = 0; y < FB_H; y++)
    2874:	00040613          	mv	a2,s0
    2878:	00b00793          	li	a5,11
    287c:	fec7d0e3          	bge	a5,a2,285c <test_t7_stride_not_equal_width+0x110>
    for (int y = 0; y < FB_H; y++)
    2880:	00000493          	li	s1,0
    2884:	02c0006f          	j	28b0 <test_t7_stride_not_equal_width+0x164>
            expect_color(name, x, y, COLOR_BG);
    2888:	00000693          	li	a3,0
    288c:	00048613          	mv	a2,s1
    2890:	00040593          	mv	a1,s0
    2894:	00004537          	lui	a0,0x4
    2898:	12050513          	addi	a0,a0,288 # 4120 <_data+0x22c>
    289c:	9d8ff0ef          	jal	1a74 <expect_color>
        for (int x = 0; x < FB_W - 1; x++)
    28a0:	00140413          	addi	s0,s0,1
    28a4:	00e00793          	li	a5,14
    28a8:	fe87d0e3          	bge	a5,s0,2888 <test_t7_stride_not_equal_width+0x13c>
    for (int y = 0; y < FB_H; y++)
    28ac:	00148493          	addi	s1,s1,1
    28b0:	00b00793          	li	a5,11
    28b4:	0097c663          	blt	a5,s1,28c0 <test_t7_stride_not_equal_width+0x174>
        for (int x = 0; x < FB_W - 1; x++)
    28b8:	00000413          	li	s0,0
    28bc:	fe9ff06f          	j	28a4 <test_t7_stride_not_equal_width+0x158>
    expect_padding_intact(name);
    28c0:	00004437          	lui	s0,0x4
    28c4:	12040513          	addi	a0,s0,288 # 4120 <_data+0x22c>
    28c8:	b28ff0ef          	jal	1bf0 <expect_padding_intact>
    t_end(name);
    28cc:	12040513          	addi	a0,s0,288
    28d0:	f69fe0ef          	jal	1838 <t_end>
}
    28d4:	05c12083          	lw	ra,92(sp)
    28d8:	05812403          	lw	s0,88(sp)
    28dc:	05412483          	lw	s1,84(sp)
    28e0:	06010113          	addi	sp,sp,96
    28e4:	00008067          	ret

000028e8 <fail_num>:
    if (t_printed < MAX_DIAG_PER_TEST)
    28e8:	8241a703          	lw	a4,-2012(gp) # 449c <t_printed>
    28ec:	00700793          	li	a5,7
    28f0:	02e7d063          	bge	a5,a4,2910 <fail_num+0x28>
        t_extra++;
    28f4:	8201a783          	lw	a5,-2016(gp) # 4498 <t_extra>
    28f8:	00178793          	addi	a5,a5,1
    28fc:	82f1a023          	sw	a5,-2016(gp) # 4498 <t_extra>
    t_fail++;
    2900:	8281a783          	lw	a5,-2008(gp) # 44a0 <t_fail>
    2904:	00178793          	addi	a5,a5,1
    2908:	82f1a423          	sw	a5,-2008(gp) # 44a0 <t_fail>
    290c:	00008067          	ret
{
    2910:	ff010113          	addi	sp,sp,-16
    2914:	00112623          	sw	ra,12(sp)
        bsp_printf("[FAIL] %s field=%s expected=%d actual=%d\r\n",
    2918:	00068713          	mv	a4,a3
    291c:	00060693          	mv	a3,a2
    2920:	00058613          	mv	a2,a1
    2924:	00050593          	mv	a1,a0
    2928:	00004537          	lui	a0,0x4
    292c:	13c50513          	addi	a0,a0,316 # 413c <_data+0x248>
    2930:	dd9fe0ef          	jal	1708 <bsp_printf>
        t_printed++;
    2934:	8241a783          	lw	a5,-2012(gp) # 449c <t_printed>
    2938:	00178793          	addi	a5,a5,1
    293c:	82f1a223          	sw	a5,-2012(gp) # 449c <t_printed>
    t_fail++;
    2940:	8281a783          	lw	a5,-2008(gp) # 44a0 <t_fail>
    2944:	00178793          	addi	a5,a5,1
    2948:	82f1a423          	sw	a5,-2008(gp) # 44a0 <t_fail>
}
    294c:	00c12083          	lw	ra,12(sp)
    2950:	01010113          	addi	sp,sp,16
    2954:	00008067          	ret

00002958 <expect_int>:
    if (expected != actual)
    2958:	00d61463          	bne	a2,a3,2960 <expect_int+0x8>
    295c:	00008067          	ret
{
    2960:	ff010113          	addi	sp,sp,-16
    2964:	00112623          	sw	ra,12(sp)
        fail_num(name, what, expected, actual);
    2968:	f81ff0ef          	jal	28e8 <fail_num>
}
    296c:	00c12083          	lw	ra,12(sp)
    2970:	01010113          	addi	sp,sp,16
    2974:	00008067          	ret

00002978 <test_t10_clip_rect_geometry>:
{
    2978:	f4010113          	addi	sp,sp,-192
    297c:	0a112e23          	sw	ra,188(sp)
    2980:	0a812c23          	sw	s0,184(sp)
    t_begin();
    2984:	c45fe0ef          	jal	15c8 <t_begin>
    visible = render_clip_rect(FB_W, FB_H, make_rect(-3, -2, 6, 5), &out);
    2988:	00500713          	li	a4,5
    298c:	00600693          	li	a3,6
    2990:	ffe00613          	li	a2,-2
    2994:	ffd00593          	li	a1,-3
    2998:	02010513          	addi	a0,sp,32
    299c:	d45fe0ef          	jal	16e0 <make_rect>
    29a0:	02012783          	lw	a5,32(sp)
    29a4:	00f12023          	sw	a5,0(sp)
    29a8:	02412783          	lw	a5,36(sp)
    29ac:	00f12223          	sw	a5,4(sp)
    29b0:	02812783          	lw	a5,40(sp)
    29b4:	00f12423          	sw	a5,8(sp)
    29b8:	02c12783          	lw	a5,44(sp)
    29bc:	00f12623          	sw	a5,12(sp)
    29c0:	01010693          	addi	a3,sp,16
    29c4:	00010613          	mv	a2,sp
    29c8:	00c00593          	li	a1,12
    29cc:	01000513          	li	a0,16
    29d0:	62c000ef          	jal	2ffc <render_clip_rect>
    if (!visible)
    29d4:	30051c63          	bnez	a0,2cec <test_t10_clip_rect_geometry+0x374>
        fail_text(name, "visible", "not visible");
    29d8:	00004637          	lui	a2,0x4
    29dc:	16860613          	addi	a2,a2,360 # 4168 <_data+0x274>
    29e0:	000045b7          	lui	a1,0x4
    29e4:	16c58593          	addi	a1,a1,364 # 416c <_data+0x278>
    29e8:	00004537          	lui	a0,0x4
    29ec:	17450513          	addi	a0,a0,372 # 4174 <_data+0x280>
    29f0:	eddfe0ef          	jal	18cc <fail_text>
    visible = render_clip_rect(FB_W, FB_H, make_rect(FB_W - 3, FB_H - 2, 50, 50), &out);
    29f4:	03200713          	li	a4,50
    29f8:	03200693          	li	a3,50
    29fc:	00a00613          	li	a2,10
    2a00:	00d00593          	li	a1,13
    2a04:	03010513          	addi	a0,sp,48
    2a08:	cd9fe0ef          	jal	16e0 <make_rect>
    2a0c:	03012783          	lw	a5,48(sp)
    2a10:	00f12023          	sw	a5,0(sp)
    2a14:	03412783          	lw	a5,52(sp)
    2a18:	00f12223          	sw	a5,4(sp)
    2a1c:	03812783          	lw	a5,56(sp)
    2a20:	00f12423          	sw	a5,8(sp)
    2a24:	03c12783          	lw	a5,60(sp)
    2a28:	00f12623          	sw	a5,12(sp)
    2a2c:	01010693          	addi	a3,sp,16
    2a30:	00010613          	mv	a2,sp
    2a34:	00c00593          	li	a1,12
    2a38:	01000513          	li	a0,16
    2a3c:	5c0000ef          	jal	2ffc <render_clip_rect>
    if (!visible)
    2a40:	30051a63          	bnez	a0,2d54 <test_t10_clip_rect_geometry+0x3dc>
        fail_text(name, "visible", "not visible");
    2a44:	00004637          	lui	a2,0x4
    2a48:	16860613          	addi	a2,a2,360 # 4168 <_data+0x274>
    2a4c:	000045b7          	lui	a1,0x4
    2a50:	16c58593          	addi	a1,a1,364 # 416c <_data+0x278>
    2a54:	00004537          	lui	a0,0x4
    2a58:	17450513          	addi	a0,a0,372 # 4174 <_data+0x280>
    2a5c:	e71fe0ef          	jal	18cc <fail_text>
    visible = render_clip_rect(FB_W, FB_H, make_rect(0, 0, FB_W, FB_H), &out);
    2a60:	00c00713          	li	a4,12
    2a64:	01000693          	li	a3,16
    2a68:	00000613          	li	a2,0
    2a6c:	00000593          	li	a1,0
    2a70:	04010513          	addi	a0,sp,64
    2a74:	c6dfe0ef          	jal	16e0 <make_rect>
    2a78:	04012783          	lw	a5,64(sp)
    2a7c:	00f12023          	sw	a5,0(sp)
    2a80:	04412783          	lw	a5,68(sp)
    2a84:	00f12223          	sw	a5,4(sp)
    2a88:	04812783          	lw	a5,72(sp)
    2a8c:	00f12423          	sw	a5,8(sp)
    2a90:	04c12783          	lw	a5,76(sp)
    2a94:	00f12623          	sw	a5,12(sp)
    2a98:	01010693          	addi	a3,sp,16
    2a9c:	00010613          	mv	a2,sp
    2aa0:	00c00593          	li	a1,12
    2aa4:	01000513          	li	a0,16
    2aa8:	554000ef          	jal	2ffc <render_clip_rect>
    if (!visible)
    2aac:	30051863          	bnez	a0,2dbc <test_t10_clip_rect_geometry+0x444>
        fail_text(name, "visible", "not visible");
    2ab0:	00004637          	lui	a2,0x4
    2ab4:	16860613          	addi	a2,a2,360 # 4168 <_data+0x274>
    2ab8:	000045b7          	lui	a1,0x4
    2abc:	16c58593          	addi	a1,a1,364 # 416c <_data+0x278>
    2ac0:	00004537          	lui	a0,0x4
    2ac4:	17450513          	addi	a0,a0,372 # 4174 <_data+0x280>
    2ac8:	e05fe0ef          	jal	18cc <fail_text>
    if (render_clip_rect(FB_W, FB_H, make_rect(-100, -100, 10, 10), &out))
    2acc:	00a00713          	li	a4,10
    2ad0:	00a00693          	li	a3,10
    2ad4:	f9c00613          	li	a2,-100
    2ad8:	f9c00593          	li	a1,-100
    2adc:	05010513          	addi	a0,sp,80
    2ae0:	c01fe0ef          	jal	16e0 <make_rect>
    2ae4:	05012783          	lw	a5,80(sp)
    2ae8:	00f12023          	sw	a5,0(sp)
    2aec:	05412783          	lw	a5,84(sp)
    2af0:	00f12223          	sw	a5,4(sp)
    2af4:	05812783          	lw	a5,88(sp)
    2af8:	00f12423          	sw	a5,8(sp)
    2afc:	05c12783          	lw	a5,92(sp)
    2b00:	00f12623          	sw	a5,12(sp)
    2b04:	01010693          	addi	a3,sp,16
    2b08:	00010613          	mv	a2,sp
    2b0c:	00c00593          	li	a1,12
    2b10:	01000513          	li	a0,16
    2b14:	4e8000ef          	jal	2ffc <render_clip_rect>
    2b18:	30051663          	bnez	a0,2e24 <test_t10_clip_rect_geometry+0x4ac>
    if (render_clip_rect(FB_W, FB_H, make_rect(FB_W + 10, FB_H + 10, 10, 10), &out))
    2b1c:	00a00713          	li	a4,10
    2b20:	00a00693          	li	a3,10
    2b24:	01600613          	li	a2,22
    2b28:	01a00593          	li	a1,26
    2b2c:	06010513          	addi	a0,sp,96
    2b30:	bb1fe0ef          	jal	16e0 <make_rect>
    2b34:	06012783          	lw	a5,96(sp)
    2b38:	00f12023          	sw	a5,0(sp)
    2b3c:	06412783          	lw	a5,100(sp)
    2b40:	00f12223          	sw	a5,4(sp)
    2b44:	06812783          	lw	a5,104(sp)
    2b48:	00f12423          	sw	a5,8(sp)
    2b4c:	06c12783          	lw	a5,108(sp)
    2b50:	00f12623          	sw	a5,12(sp)
    2b54:	01010693          	addi	a3,sp,16
    2b58:	00010613          	mv	a2,sp
    2b5c:	00c00593          	li	a1,12
    2b60:	01000513          	li	a0,16
    2b64:	498000ef          	jal	2ffc <render_clip_rect>
    2b68:	2c051e63          	bnez	a0,2e44 <test_t10_clip_rect_geometry+0x4cc>
    if (render_clip_rect(FB_W, FB_H, make_rect(2, 2, 0, 4), &out))
    2b6c:	00400713          	li	a4,4
    2b70:	00000693          	li	a3,0
    2b74:	00200613          	li	a2,2
    2b78:	00200593          	li	a1,2
    2b7c:	07010513          	addi	a0,sp,112
    2b80:	b61fe0ef          	jal	16e0 <make_rect>
    2b84:	07012783          	lw	a5,112(sp)
    2b88:	00f12023          	sw	a5,0(sp)
    2b8c:	07412783          	lw	a5,116(sp)
    2b90:	00f12223          	sw	a5,4(sp)
    2b94:	07812783          	lw	a5,120(sp)
    2b98:	00f12423          	sw	a5,8(sp)
    2b9c:	07c12783          	lw	a5,124(sp)
    2ba0:	00f12623          	sw	a5,12(sp)
    2ba4:	01010693          	addi	a3,sp,16
    2ba8:	00010613          	mv	a2,sp
    2bac:	00c00593          	li	a1,12
    2bb0:	01000513          	li	a0,16
    2bb4:	448000ef          	jal	2ffc <render_clip_rect>
    2bb8:	2a051663          	bnez	a0,2e64 <test_t10_clip_rect_geometry+0x4ec>
    if (render_clip_rect(FB_W, FB_H, make_rect(2, 2, -4, -4), &out))
    2bbc:	ffc00713          	li	a4,-4
    2bc0:	ffc00693          	li	a3,-4
    2bc4:	00200613          	li	a2,2
    2bc8:	00200593          	li	a1,2
    2bcc:	08010513          	addi	a0,sp,128
    2bd0:	b11fe0ef          	jal	16e0 <make_rect>
    2bd4:	08012783          	lw	a5,128(sp)
    2bd8:	00f12023          	sw	a5,0(sp)
    2bdc:	08412783          	lw	a5,132(sp)
    2be0:	00f12223          	sw	a5,4(sp)
    2be4:	08812783          	lw	a5,136(sp)
    2be8:	00f12423          	sw	a5,8(sp)
    2bec:	08c12783          	lw	a5,140(sp)
    2bf0:	00f12623          	sw	a5,12(sp)
    2bf4:	01010693          	addi	a3,sp,16
    2bf8:	00010613          	mv	a2,sp
    2bfc:	00c00593          	li	a1,12
    2c00:	01000513          	li	a0,16
    2c04:	3f8000ef          	jal	2ffc <render_clip_rect>
    2c08:	26051e63          	bnez	a0,2e84 <test_t10_clip_rect_geometry+0x50c>
    if (render_clip_rect(FB_W, FB_H, make_rect(INT_MIN, INT_MIN, INT_MAX, INT_MAX), &out))
    2c0c:	80000737          	lui	a4,0x80000
    2c10:	fff70713          	addi	a4,a4,-1 # 7fffffff <__freertos_irq_stack_top+0x7fffa58f>
    2c14:	00070693          	mv	a3,a4
    2c18:	80000637          	lui	a2,0x80000
    2c1c:	800005b7          	lui	a1,0x80000
    2c20:	09010513          	addi	a0,sp,144
    2c24:	abdfe0ef          	jal	16e0 <make_rect>
    2c28:	09012783          	lw	a5,144(sp)
    2c2c:	00f12023          	sw	a5,0(sp)
    2c30:	09412783          	lw	a5,148(sp)
    2c34:	00f12223          	sw	a5,4(sp)
    2c38:	09812783          	lw	a5,152(sp)
    2c3c:	00f12423          	sw	a5,8(sp)
    2c40:	09c12783          	lw	a5,156(sp)
    2c44:	00f12623          	sw	a5,12(sp)
    2c48:	01010693          	addi	a3,sp,16
    2c4c:	00010613          	mv	a2,sp
    2c50:	00c00593          	li	a1,12
    2c54:	01000513          	li	a0,16
    2c58:	3a4000ef          	jal	2ffc <render_clip_rect>
    2c5c:	24051463          	bnez	a0,2ea4 <test_t10_clip_rect_geometry+0x52c>
    visible = render_clip_rect(FB_W, FB_H,
    2c60:	80000737          	lui	a4,0x80000
    2c64:	fff70713          	addi	a4,a4,-1 # 7fffffff <__freertos_irq_stack_top+0x7fffa58f>
    2c68:	00070693          	mv	a3,a4
    2c6c:	c0000637          	lui	a2,0xc0000
    2c70:	c00005b7          	lui	a1,0xc0000
    2c74:	0a010513          	addi	a0,sp,160
    2c78:	a69fe0ef          	jal	16e0 <make_rect>
    2c7c:	0a012783          	lw	a5,160(sp)
    2c80:	00f12023          	sw	a5,0(sp)
    2c84:	0a412783          	lw	a5,164(sp)
    2c88:	00f12223          	sw	a5,4(sp)
    2c8c:	0a812783          	lw	a5,168(sp)
    2c90:	00f12423          	sw	a5,8(sp)
    2c94:	0ac12783          	lw	a5,172(sp)
    2c98:	00f12623          	sw	a5,12(sp)
    2c9c:	01010693          	addi	a3,sp,16
    2ca0:	00010613          	mv	a2,sp
    2ca4:	00c00593          	li	a1,12
    2ca8:	01000513          	li	a0,16
    2cac:	350000ef          	jal	2ffc <render_clip_rect>
    if (!visible)
    2cb0:	20051a63          	bnez	a0,2ec4 <test_t10_clip_rect_geometry+0x54c>
        fail_text(name, "visible", "not visible");
    2cb4:	00004637          	lui	a2,0x4
    2cb8:	16860613          	addi	a2,a2,360 # 4168 <_data+0x274>
    2cbc:	000045b7          	lui	a1,0x4
    2cc0:	16c58593          	addi	a1,a1,364 # 416c <_data+0x278>
    2cc4:	00004537          	lui	a0,0x4
    2cc8:	17450513          	addi	a0,a0,372 # 4174 <_data+0x280>
    2ccc:	c01fe0ef          	jal	18cc <fail_text>
    t_end(name);
    2cd0:	00004537          	lui	a0,0x4
    2cd4:	17450513          	addi	a0,a0,372 # 4174 <_data+0x280>
    2cd8:	b61fe0ef          	jal	1838 <t_end>
}
    2cdc:	0bc12083          	lw	ra,188(sp)
    2ce0:	0b812403          	lw	s0,184(sp)
    2ce4:	0c010113          	addi	sp,sp,192
    2ce8:	00008067          	ret
        expect_int(name, "x", 0, out.x);
    2cec:	01012683          	lw	a3,16(sp)
    2cf0:	00000613          	li	a2,0
    2cf4:	000045b7          	lui	a1,0x4
    2cf8:	18c58593          	addi	a1,a1,396 # 418c <_data+0x298>
    2cfc:	00004437          	lui	s0,0x4
    2d00:	17440513          	addi	a0,s0,372 # 4174 <_data+0x280>
    2d04:	c55ff0ef          	jal	2958 <expect_int>
        expect_int(name, "y", 0, out.y);
    2d08:	01412683          	lw	a3,20(sp)
    2d0c:	00000613          	li	a2,0
    2d10:	000045b7          	lui	a1,0x4
    2d14:	19058593          	addi	a1,a1,400 # 4190 <_data+0x29c>
    2d18:	17440513          	addi	a0,s0,372
    2d1c:	c3dff0ef          	jal	2958 <expect_int>
        expect_int(name, "w", 3, out.w);
    2d20:	01812683          	lw	a3,24(sp)
    2d24:	00300613          	li	a2,3
    2d28:	000045b7          	lui	a1,0x4
    2d2c:	19458593          	addi	a1,a1,404 # 4194 <_data+0x2a0>
    2d30:	17440513          	addi	a0,s0,372
    2d34:	c25ff0ef          	jal	2958 <expect_int>
        expect_int(name, "h", 3, out.h);
    2d38:	01c12683          	lw	a3,28(sp)
    2d3c:	00300613          	li	a2,3
    2d40:	000045b7          	lui	a1,0x4
    2d44:	13858593          	addi	a1,a1,312 # 4138 <_data+0x244>
    2d48:	17440513          	addi	a0,s0,372
    2d4c:	c0dff0ef          	jal	2958 <expect_int>
    2d50:	ca5ff06f          	j	29f4 <test_t10_clip_rect_geometry+0x7c>
        expect_int(name, "x", FB_W - 3, out.x);
    2d54:	01012683          	lw	a3,16(sp)
    2d58:	00d00613          	li	a2,13
    2d5c:	000045b7          	lui	a1,0x4
    2d60:	18c58593          	addi	a1,a1,396 # 418c <_data+0x298>
    2d64:	00004437          	lui	s0,0x4
    2d68:	17440513          	addi	a0,s0,372 # 4174 <_data+0x280>
    2d6c:	bedff0ef          	jal	2958 <expect_int>
        expect_int(name, "y", FB_H - 2, out.y);
    2d70:	01412683          	lw	a3,20(sp)
    2d74:	00a00613          	li	a2,10
    2d78:	000045b7          	lui	a1,0x4
    2d7c:	19058593          	addi	a1,a1,400 # 4190 <_data+0x29c>
    2d80:	17440513          	addi	a0,s0,372
    2d84:	bd5ff0ef          	jal	2958 <expect_int>
        expect_int(name, "w", 3, out.w);
    2d88:	01812683          	lw	a3,24(sp)
    2d8c:	00300613          	li	a2,3
    2d90:	000045b7          	lui	a1,0x4
    2d94:	19458593          	addi	a1,a1,404 # 4194 <_data+0x2a0>
    2d98:	17440513          	addi	a0,s0,372
    2d9c:	bbdff0ef          	jal	2958 <expect_int>
        expect_int(name, "h", 2, out.h);
    2da0:	01c12683          	lw	a3,28(sp)
    2da4:	00200613          	li	a2,2
    2da8:	000045b7          	lui	a1,0x4
    2dac:	13858593          	addi	a1,a1,312 # 4138 <_data+0x244>
    2db0:	17440513          	addi	a0,s0,372
    2db4:	ba5ff0ef          	jal	2958 <expect_int>
    2db8:	ca9ff06f          	j	2a60 <test_t10_clip_rect_geometry+0xe8>
        expect_int(name, "x", 0, out.x);
    2dbc:	01012683          	lw	a3,16(sp)
    2dc0:	00000613          	li	a2,0
    2dc4:	000045b7          	lui	a1,0x4
    2dc8:	18c58593          	addi	a1,a1,396 # 418c <_data+0x298>
    2dcc:	00004437          	lui	s0,0x4
    2dd0:	17440513          	addi	a0,s0,372 # 4174 <_data+0x280>
    2dd4:	b85ff0ef          	jal	2958 <expect_int>
        expect_int(name, "y", 0, out.y);
    2dd8:	01412683          	lw	a3,20(sp)
    2ddc:	00000613          	li	a2,0
    2de0:	000045b7          	lui	a1,0x4
    2de4:	19058593          	addi	a1,a1,400 # 4190 <_data+0x29c>
    2de8:	17440513          	addi	a0,s0,372
    2dec:	b6dff0ef          	jal	2958 <expect_int>
        expect_int(name, "w", FB_W, out.w);
    2df0:	01812683          	lw	a3,24(sp)
    2df4:	01000613          	li	a2,16
    2df8:	000045b7          	lui	a1,0x4
    2dfc:	19458593          	addi	a1,a1,404 # 4194 <_data+0x2a0>
    2e00:	17440513          	addi	a0,s0,372
    2e04:	b55ff0ef          	jal	2958 <expect_int>
        expect_int(name, "h", FB_H, out.h);
    2e08:	01c12683          	lw	a3,28(sp)
    2e0c:	00c00613          	li	a2,12
    2e10:	000045b7          	lui	a1,0x4
    2e14:	13858593          	addi	a1,a1,312 # 4138 <_data+0x244>
    2e18:	17440513          	addi	a0,s0,372
    2e1c:	b3dff0ef          	jal	2958 <expect_int>
    2e20:	cadff06f          	j	2acc <test_t10_clip_rect_geometry+0x154>
        fail_text(name, "not visible", "visible");
    2e24:	00004637          	lui	a2,0x4
    2e28:	16c60613          	addi	a2,a2,364 # 416c <_data+0x278>
    2e2c:	000045b7          	lui	a1,0x4
    2e30:	16858593          	addi	a1,a1,360 # 4168 <_data+0x274>
    2e34:	00004537          	lui	a0,0x4
    2e38:	17450513          	addi	a0,a0,372 # 4174 <_data+0x280>
    2e3c:	a91fe0ef          	jal	18cc <fail_text>
    2e40:	cddff06f          	j	2b1c <test_t10_clip_rect_geometry+0x1a4>
        fail_text(name, "not visible", "visible");
    2e44:	00004637          	lui	a2,0x4
    2e48:	16c60613          	addi	a2,a2,364 # 416c <_data+0x278>
    2e4c:	000045b7          	lui	a1,0x4
    2e50:	16858593          	addi	a1,a1,360 # 4168 <_data+0x274>
    2e54:	00004537          	lui	a0,0x4
    2e58:	17450513          	addi	a0,a0,372 # 4174 <_data+0x280>
    2e5c:	a71fe0ef          	jal	18cc <fail_text>
    2e60:	d0dff06f          	j	2b6c <test_t10_clip_rect_geometry+0x1f4>
        fail_text(name, "not visible", "visible");
    2e64:	00004637          	lui	a2,0x4
    2e68:	16c60613          	addi	a2,a2,364 # 416c <_data+0x278>
    2e6c:	000045b7          	lui	a1,0x4
    2e70:	16858593          	addi	a1,a1,360 # 4168 <_data+0x274>
    2e74:	00004537          	lui	a0,0x4
    2e78:	17450513          	addi	a0,a0,372 # 4174 <_data+0x280>
    2e7c:	a51fe0ef          	jal	18cc <fail_text>
    2e80:	d3dff06f          	j	2bbc <test_t10_clip_rect_geometry+0x244>
        fail_text(name, "not visible", "visible");
    2e84:	00004637          	lui	a2,0x4
    2e88:	16c60613          	addi	a2,a2,364 # 416c <_data+0x278>
    2e8c:	000045b7          	lui	a1,0x4
    2e90:	16858593          	addi	a1,a1,360 # 4168 <_data+0x274>
    2e94:	00004537          	lui	a0,0x4
    2e98:	17450513          	addi	a0,a0,372 # 4174 <_data+0x280>
    2e9c:	a31fe0ef          	jal	18cc <fail_text>
    2ea0:	d6dff06f          	j	2c0c <test_t10_clip_rect_geometry+0x294>
        fail_text(name, "not visible", "visible");
    2ea4:	00004637          	lui	a2,0x4
    2ea8:	16c60613          	addi	a2,a2,364 # 416c <_data+0x278>
    2eac:	000045b7          	lui	a1,0x4
    2eb0:	16858593          	addi	a1,a1,360 # 4168 <_data+0x274>
    2eb4:	00004537          	lui	a0,0x4
    2eb8:	17450513          	addi	a0,a0,372 # 4174 <_data+0x280>
    2ebc:	a11fe0ef          	jal	18cc <fail_text>
    2ec0:	da1ff06f          	j	2c60 <test_t10_clip_rect_geometry+0x2e8>
        expect_int(name, "x", 0, out.x);
    2ec4:	01012683          	lw	a3,16(sp)
    2ec8:	00000613          	li	a2,0
    2ecc:	000045b7          	lui	a1,0x4
    2ed0:	18c58593          	addi	a1,a1,396 # 418c <_data+0x298>
    2ed4:	00004437          	lui	s0,0x4
    2ed8:	17440513          	addi	a0,s0,372 # 4174 <_data+0x280>
    2edc:	a7dff0ef          	jal	2958 <expect_int>
        expect_int(name, "y", 0, out.y);
    2ee0:	01412683          	lw	a3,20(sp)
    2ee4:	00000613          	li	a2,0
    2ee8:	000045b7          	lui	a1,0x4
    2eec:	19058593          	addi	a1,a1,400 # 4190 <_data+0x29c>
    2ef0:	17440513          	addi	a0,s0,372
    2ef4:	a65ff0ef          	jal	2958 <expect_int>
        expect_int(name, "w", FB_W, out.w);
    2ef8:	01812683          	lw	a3,24(sp)
    2efc:	01000613          	li	a2,16
    2f00:	000045b7          	lui	a1,0x4
    2f04:	19458593          	addi	a1,a1,404 # 4194 <_data+0x2a0>
    2f08:	17440513          	addi	a0,s0,372
    2f0c:	a4dff0ef          	jal	2958 <expect_int>
        expect_int(name, "h", FB_H, out.h);
    2f10:	01c12683          	lw	a3,28(sp)
    2f14:	00c00613          	li	a2,12
    2f18:	000045b7          	lui	a1,0x4
    2f1c:	13858593          	addi	a1,a1,312 # 4138 <_data+0x244>
    2f20:	17440513          	addi	a0,s0,372
    2f24:	a35ff0ef          	jal	2958 <expect_int>
    2f28:	da9ff06f          	j	2cd0 <test_t10_clip_rect_geometry+0x358>

00002f2c <render_select>:
}


render_status_t render_select(render_backend_t which)
{
    switch (which)
    2f2c:	00050a63          	beqz	a0,2f40 <render_select+0x14>
    2f30:	00100793          	li	a5,1
    2f34:	00f50e63          	beq	a0,a5,2f50 <render_select+0x24>
    2f38:	00100513          	li	a0,1
    2f3c:	00008067          	ret
    {
    case RENDER_BACKEND_CPU:
        g_ops = &renderer_ops_cpu;
    2f40:	000047b7          	lui	a5,0x4
    2f44:	43c78793          	addi	a5,a5,1084 # 443c <renderer_ops_cpu>
    2f48:	82f1aa23          	sw	a5,-1996(gp) # 44ac <g_ops>
        return RENDER_OK;
    2f4c:	00008067          	ret
        /*
         * 这里允许选中，即使当前像素格式下它画不了任何东西。
         * 理由是选 FPGA 之后仍然要能查名字、等待格式定案；
         * 真正下发时的失败由后端返回 FORMAT_MISMATCH，那样错误码才带得上原因。
         */
        g_ops = &renderer_ops_fpga;
    2f50:	000047b7          	lui	a5,0x4
    2f54:	43078793          	addi	a5,a5,1072 # 4430 <renderer_ops_fpga>
    2f58:	82f1aa23          	sw	a5,-1996(gp) # 44ac <g_ops>
        return RENDER_OK;
    2f5c:	00000513          	li	a0,0
    }

    return RENDER_ERR_INVALID_ARG;
}
    2f60:	00008067          	ret

00002f64 <render_init>:
{
    2f64:	ff010113          	addi	sp,sp,-16
    2f68:	00112623          	sw	ra,12(sp)
    (void)render_select(RENDER_BACKEND_CPU);
    2f6c:	00000513          	li	a0,0
    2f70:	fbdff0ef          	jal	2f2c <render_select>
}
    2f74:	00c12083          	lw	ra,12(sp)
    2f78:	01010113          	addi	sp,sp,16
    2f7c:	00008067          	ret

00002f80 <render_select_ops>:


render_status_t render_select_ops(const renderer_ops_t *ops)
{
    g_ops = ops;
    2f80:	82a1aa23          	sw	a0,-1996(gp) # 44ac <g_ops>
    return RENDER_OK;
}
    2f84:	00000513          	li	a0,0
    2f88:	00008067          	ret

00002f8c <render_backend_name>:


const char *render_backend_name(void)
{
    return g_ops ? g_ops->name : "(none)";
    2f8c:	8341a783          	lw	a5,-1996(gp) # 44ac <g_ops>
    2f90:	00078663          	beqz	a5,2f9c <render_backend_name+0x10>
    2f94:	0007a503          	lw	a0,0(a5)
    2f98:	00008067          	ret
    2f9c:	00004537          	lui	a0,0x4
    2fa0:	2d050513          	addi	a0,a0,720 # 42d0 <_data+0x3dc>
}
    2fa4:	00008067          	ret

00002fa8 <render_surface_valid>:
/* 工具函数                                                            */
/* ------------------------------------------------------------------ */

int render_surface_valid(const render_surface_t *s)
{
    if (s == 0 || s->pixels == 0)
    2fa8:	02050663          	beqz	a0,2fd4 <render_surface_valid+0x2c>
    2fac:	00052783          	lw	a5,0(a0)
    2fb0:	02078663          	beqz	a5,2fdc <render_surface_valid+0x34>
        return 0;

    if (s->width <= 0 || s->height <= 0)
    2fb4:	00452783          	lw	a5,4(a0)
    2fb8:	02f05663          	blez	a5,2fe4 <render_surface_valid+0x3c>
    2fbc:	00852703          	lw	a4,8(a0)
    2fc0:	02e05663          	blez	a4,2fec <render_surface_valid+0x44>
        return 0;

    /* stride 比宽度小意味着行与行重叠，读会串行、写会踩到别人 */
    if (s->stride_px < s->width)
    2fc4:	00c52703          	lw	a4,12(a0)
    2fc8:	02f74663          	blt	a4,a5,2ff4 <render_surface_valid+0x4c>
        return 0;

    return 1;
    2fcc:	00100513          	li	a0,1
    2fd0:	00008067          	ret
        return 0;
    2fd4:	00000513          	li	a0,0
    2fd8:	00008067          	ret
    2fdc:	00000513          	li	a0,0
    2fe0:	00008067          	ret
        return 0;
    2fe4:	00000513          	li	a0,0
    2fe8:	00008067          	ret
    2fec:	00000513          	li	a0,0
    2ff0:	00008067          	ret
        return 0;
    2ff4:	00000513          	li	a0,0
}
    2ff8:	00008067          	ret

00002ffc <render_clip_rect>:

int render_clip_rect(int fb_width, int fb_height, render_rect_t req, render_rect_t *out)
{
    int64_t x0, y0, x1, y1;

    if (out == 0 || fb_width <= 0 || fb_height <= 0)
    2ffc:	10068a63          	beqz	a3,3110 <render_clip_rect+0x114>
    3000:	10a05c63          	blez	a0,3118 <render_clip_rect+0x11c>
    3004:	10b05e63          	blez	a1,3120 <render_clip_rect+0x124>
        return 0;

    if (req.w <= 0 || req.h <= 0)
    3008:	00862783          	lw	a5,8(a2)
    300c:	10f05e63          	blez	a5,3128 <render_clip_rect+0x12c>
    3010:	00c62703          	lw	a4,12(a2)
    3014:	10e05e63          	blez	a4,3130 <render_clip_rect+0x134>
{
    3018:	ff010113          	addi	sp,sp,-16
    301c:	00812623          	sw	s0,12(sp)
     *
     * 冻结的 sw_fill_rect 内部是 int x1 = x + width，x 很大时会有符号溢出 UB。
     * 本层先裁剪，冻结函数就永远看不到接近 INT_MAX 的操作数；
     * 这里自己也不能溢出，否则裁剪本身就不可信。
     */
    x0 = req.x;
    3020:	00062883          	lw	a7,0(a2)
    3024:	41f8d813          	srai	a6,a7,0x1f
    y0 = req.y;
    3028:	00462603          	lw	a2,4(a2)
    302c:	41f65313          	srai	t1,a2,0x1f
    x1 = (int64_t)req.x + (int64_t)req.w;
    3030:	41f7de13          	srai	t3,a5,0x1f
    3034:	01178f33          	add	t5,a5,a7
    3038:	00ff37b3          	sltu	a5,t5,a5
    303c:	010e0e33          	add	t3,t3,a6
    3040:	01c787b3          	add	a5,a5,t3
    3044:	000f0413          	mv	s0,t5
    3048:	00078293          	mv	t0,a5
    y1 = (int64_t)req.y + (int64_t)req.h;
    304c:	41f75e13          	srai	t3,a4,0x1f
    3050:	00c70eb3          	add	t4,a4,a2
    3054:	00eeb733          	sltu	a4,t4,a4
    3058:	006e0e33          	add	t3,t3,t1
    305c:	01c70733          	add	a4,a4,t3
    3060:	000e8393          	mv	t2,t4
    3064:	00070f93          	mv	t6,a4

    if (x0 < 0)
    3068:	06084863          	bltz	a6,30d8 <render_clip_rect+0xdc>
        x0 = 0;

    if (y0 < 0)
    306c:	06034c63          	bltz	t1,30e4 <render_clip_rect+0xe8>
        y0 = 0;

    if (x1 > fb_width)
    3070:	00050e13          	mv	t3,a0
    3074:	41f55513          	srai	a0,a0,0x1f
    3078:	00554a63          	blt	a0,t0,308c <render_clip_rect+0x90>
    307c:	00a29463          	bne	t0,a0,3084 <render_clip_rect+0x88>
    3080:	008e6663          	bltu	t3,s0,308c <render_clip_rect+0x90>
    x1 = (int64_t)req.x + (int64_t)req.w;
    3084:	000f0e13          	mv	t3,t5
    3088:	00078513          	mv	a0,a5
        x1 = fb_width;

    if (y1 > fb_height)
    308c:	00058793          	mv	a5,a1
    3090:	41f5d593          	srai	a1,a1,0x1f
    3094:	01f5ca63          	blt	a1,t6,30a8 <render_clip_rect+0xac>
    3098:	00bf9463          	bne	t6,a1,30a0 <render_clip_rect+0xa4>
    309c:	0077e663          	bltu	a5,t2,30a8 <render_clip_rect+0xac>
    y1 = (int64_t)req.y + (int64_t)req.h;
    30a0:	000e8793          	mv	a5,t4
    30a4:	00070593          	mv	a1,a4
        y1 = fb_height;

    if (x0 >= x1 || y0 >= y1)
    30a8:	04a85463          	bge	a6,a0,30f0 <render_clip_rect+0xf4>
    30ac:	04b35a63          	bge	t1,a1,3100 <render_clip_rect+0x104>
        return 0;

    out->x = (int)x0;
    30b0:	0116a023          	sw	a7,0(a3)
    out->y = (int)y0;
    30b4:	00c6a223          	sw	a2,4(a3)
    out->w = (int)(x1 - x0);
    30b8:	411e0e33          	sub	t3,t3,a7
    30bc:	01c6a423          	sw	t3,8(a3)
    out->h = (int)(y1 - y0);
    30c0:	40c787b3          	sub	a5,a5,a2
    30c4:	00f6a623          	sw	a5,12(a3)

    return 1;
    30c8:	00100513          	li	a0,1
}
    30cc:	00c12403          	lw	s0,12(sp)
    30d0:	01010113          	addi	sp,sp,16
    30d4:	00008067          	ret
        x0 = 0;
    30d8:	00000893          	li	a7,0
    30dc:	00000813          	li	a6,0
    30e0:	f8dff06f          	j	306c <render_clip_rect+0x70>
        y0 = 0;
    30e4:	00000613          	li	a2,0
    30e8:	00000313          	li	t1,0
    30ec:	f85ff06f          	j	3070 <render_clip_rect+0x74>
    if (x0 >= x1 || y0 >= y1)
    30f0:	01051463          	bne	a0,a6,30f8 <render_clip_rect+0xfc>
    30f4:	fbc8ece3          	bltu	a7,t3,30ac <render_clip_rect+0xb0>
        return 0;
    30f8:	00000513          	li	a0,0
    30fc:	fd1ff06f          	j	30cc <render_clip_rect+0xd0>
    if (x0 >= x1 || y0 >= y1)
    3100:	00659463          	bne	a1,t1,3108 <render_clip_rect+0x10c>
    3104:	faf666e3          	bltu	a2,a5,30b0 <render_clip_rect+0xb4>
        return 0;
    3108:	00000513          	li	a0,0
    310c:	fc1ff06f          	j	30cc <render_clip_rect+0xd0>
        return 0;
    3110:	00000513          	li	a0,0
    3114:	00008067          	ret
    3118:	00000513          	li	a0,0
    311c:	00008067          	ret
    3120:	00000513          	li	a0,0
    3124:	00008067          	ret
        return 0;
    3128:	00000513          	li	a0,0
    312c:	00008067          	ret
    3130:	00000513          	li	a0,0
}
    3134:	00008067          	ret

00003138 <render_surface_view>:


render_surface_t render_surface_view(const render_surface_t *parent,
                                     int x, int y, int w, int h)
{
    3138:	fe010113          	addi	sp,sp,-32
    313c:	00112e23          	sw	ra,28(sp)
    3140:	00812c23          	sw	s0,24(sp)
    3144:	00912a23          	sw	s1,20(sp)
    3148:	01212823          	sw	s2,16(sp)
    314c:	01312623          	sw	s3,12(sp)
    3150:	01412423          	sw	s4,8(sp)
    3154:	01512223          	sw	s5,4(sp)
    3158:	00050413          	mv	s0,a0
    315c:	00058493          	mv	s1,a1
    3160:	00060a93          	mv	s5,a2
    3164:	00068a13          	mv	s4,a3
    3168:	00070913          	mv	s2,a4
    316c:	00078993          	mv	s3,a5
    render_surface_t view;

    view.pixels = 0;
    3170:	00052023          	sw	zero,0(a0)
    view.width = 0;
    3174:	00052223          	sw	zero,4(a0)
    view.height = 0;
    3178:	00052423          	sw	zero,8(a0)
    view.stride_px = 0;
    317c:	00052623          	sw	zero,12(a0)
    view.phys_base = 0;
    3180:	00052823          	sw	zero,16(a0)

    if (!render_surface_valid(parent))
    3184:	00058513          	mv	a0,a1
    3188:	e21ff0ef          	jal	2fa8 <render_surface_valid>
    318c:	08050e63          	beqz	a0,3228 <render_surface_view+0xf0>
        return view;

    if (w <= 0 || h <= 0 || x < 0 || y < 0)
    3190:	09205c63          	blez	s2,3228 <render_surface_view+0xf0>
    3194:	09305a63          	blez	s3,3228 <render_surface_view+0xf0>
    3198:	080ac863          	bltz	s5,3228 <render_surface_view+0xf0>
    319c:	080a4663          	bltz	s4,3228 <render_surface_view+0xf0>
        return view;

    if ((int64_t)x + w > parent->width)
    31a0:	41fad613          	srai	a2,s5,0x1f
    31a4:	41f95793          	srai	a5,s2,0x1f
    31a8:	015906b3          	add	a3,s2,s5
    31ac:	0126b733          	sltu	a4,a3,s2
    31b0:	00c787b3          	add	a5,a5,a2
    31b4:	00f707b3          	add	a5,a4,a5
    31b8:	0044a603          	lw	a2,4(s1)
    31bc:	41f65713          	srai	a4,a2,0x1f
    31c0:	06f74463          	blt	a4,a5,3228 <render_surface_view+0xf0>
    31c4:	08e78663          	beq	a5,a4,3250 <render_surface_view+0x118>
        return view;

    if ((int64_t)y + h > parent->height)
    31c8:	41fa5613          	srai	a2,s4,0x1f
    31cc:	41f9d793          	srai	a5,s3,0x1f
    31d0:	014986b3          	add	a3,s3,s4
    31d4:	0136b733          	sltu	a4,a3,s3
    31d8:	00c787b3          	add	a5,a5,a2
    31dc:	00f707b3          	add	a5,a4,a5
    31e0:	0084a603          	lw	a2,8(s1)
    31e4:	41f65713          	srai	a4,a2,0x1f
    31e8:	04f74063          	blt	a4,a5,3228 <render_surface_view+0xf0>
    31ec:	06e78663          	beq	a5,a4,3258 <render_surface_view+0x120>
        return view;

    view.pixels = parent->pixels
    31f0:	0004a783          	lw	a5,0(s1)
                + (size_t)y * (size_t)parent->stride_px
    31f4:	00c4a703          	lw	a4,12(s1)
    31f8:	034706b3          	mul	a3,a4,s4
                + (size_t)x;
    31fc:	00da86b3          	add	a3,s5,a3
    3200:	00269613          	slli	a2,a3,0x2
    3204:	00c787b3          	add	a5,a5,a2
    view.pixels = parent->pixels
    3208:	00f42023          	sw	a5,0(s0)
    view.width = w;
    320c:	01242223          	sw	s2,4(s0)
    view.height = h;
    3210:	01342423          	sw	s3,8(s0)
    view.stride_px = parent->stride_px;
    3214:	00e42623          	sw	a4,12(s0)

    /* phys_base 为 0 表示"与 pixels 同址"，视图继承这个语义 */
    if (parent->phys_base != 0)
    3218:	0104a783          	lw	a5,16(s1)
    321c:	00078663          	beqz	a5,3228 <render_surface_view+0xf0>
    {
        view.phys_base = parent->phys_base
                       + (uintptr_t)y * (uintptr_t)parent->stride_px * RENDER_PIXEL_BYTES
                       + (uintptr_t)x * RENDER_PIXEL_BYTES;
    3220:	00f60633          	add	a2,a2,a5
        view.phys_base = parent->phys_base
    3224:	00c42823          	sw	a2,16(s0)
    }

    return view;
}
    3228:	00040513          	mv	a0,s0
    322c:	01c12083          	lw	ra,28(sp)
    3230:	01812403          	lw	s0,24(sp)
    3234:	01412483          	lw	s1,20(sp)
    3238:	01012903          	lw	s2,16(sp)
    323c:	00c12983          	lw	s3,12(sp)
    3240:	00812a03          	lw	s4,8(sp)
    3244:	00412a83          	lw	s5,4(sp)
    3248:	02010113          	addi	sp,sp,32
    324c:	00008067          	ret
    if ((int64_t)x + w > parent->width)
    3250:	f6d67ce3          	bgeu	a2,a3,31c8 <render_surface_view+0x90>
    3254:	fd5ff06f          	j	3228 <render_surface_view+0xf0>
    if ((int64_t)y + h > parent->height)
    3258:	f8d67ce3          	bgeu	a2,a3,31f0 <render_surface_view+0xb8>
    325c:	fcdff06f          	j	3228 <render_surface_view+0xf0>

00003260 <render_fill_rect>:
                                 pixel_t color)
{
    render_op_t op;
    render_rect_t clipped;

    if (g_ops == 0)
    3260:	8341a783          	lw	a5,-1996(gp) # 44ac <g_ops>
    3264:	0c078863          	beqz	a5,3334 <render_fill_rect+0xd4>
{
    3268:	fa010113          	addi	sp,sp,-96
    326c:	04112e23          	sw	ra,92(sp)
    3270:	04812c23          	sw	s0,88(sp)
    3274:	04912a23          	sw	s1,84(sp)
    3278:	05212823          	sw	s2,80(sp)
    327c:	00050413          	mv	s0,a0
    3280:	00058493          	mv	s1,a1
    3284:	00060913          	mv	s2,a2
        return RENDER_ERR_NO_BACKEND;

    if (!render_surface_valid(dst))
    3288:	d21ff0ef          	jal	2fa8 <render_surface_valid>
    328c:	02051063          	bnez	a0,32ac <render_fill_rect+0x4c>
        return RENDER_ERR_INVALID_ARG;
    3290:	00100513          	li	a0,1
    op.src_rect.w = clipped.w;
    op.src_rect.h = clipped.h;
    op.color = color;

    return g_ops->fill(&op);
}
    3294:	05c12083          	lw	ra,92(sp)
    3298:	05812403          	lw	s0,88(sp)
    329c:	05412483          	lw	s1,84(sp)
    32a0:	05012903          	lw	s2,80(sp)
    32a4:	06010113          	addi	sp,sp,96
    32a8:	00008067          	ret
    if (!render_clip_rect(dst->width, dst->height, rect, &clipped))
    32ac:	0004a603          	lw	a2,0(s1)
    32b0:	0044a683          	lw	a3,4(s1)
    32b4:	0084a703          	lw	a4,8(s1)
    32b8:	00c4a783          	lw	a5,12(s1)
    32bc:	00c12023          	sw	a2,0(sp)
    32c0:	00d12223          	sw	a3,4(sp)
    32c4:	00e12423          	sw	a4,8(sp)
    32c8:	00f12623          	sw	a5,12(sp)
    32cc:	01410693          	addi	a3,sp,20
    32d0:	00010613          	mv	a2,sp
    32d4:	00842583          	lw	a1,8(s0)
    32d8:	00442503          	lw	a0,4(s0)
    32dc:	d21ff0ef          	jal	2ffc <render_clip_rect>
    32e0:	04050e63          	beqz	a0,333c <render_fill_rect+0xdc>
    op.dst = dst;
    32e4:	02812223          	sw	s0,36(sp)
    op.src = 0;
    32e8:	02012423          	sw	zero,40(sp)
    op.dst_rect = clipped;
    32ec:	01c12703          	lw	a4,28(sp)
    32f0:	02012783          	lw	a5,32(sp)
    32f4:	01412683          	lw	a3,20(sp)
    32f8:	02d12623          	sw	a3,44(sp)
    32fc:	01812683          	lw	a3,24(sp)
    3300:	02d12823          	sw	a3,48(sp)
    3304:	02e12a23          	sw	a4,52(sp)
    3308:	02f12c23          	sw	a5,56(sp)
    op.src_rect.x = 0;
    330c:	02012e23          	sw	zero,60(sp)
    op.src_rect.y = 0;
    3310:	04012023          	sw	zero,64(sp)
    op.src_rect.w = clipped.w;
    3314:	04e12223          	sw	a4,68(sp)
    op.src_rect.h = clipped.h;
    3318:	04f12423          	sw	a5,72(sp)
    op.color = color;
    331c:	05212623          	sw	s2,76(sp)
    return g_ops->fill(&op);
    3320:	8341a783          	lw	a5,-1996(gp) # 44ac <g_ops>
    3324:	0047a783          	lw	a5,4(a5)
    3328:	02410513          	addi	a0,sp,36
    332c:	000780e7          	jalr	a5
    3330:	f65ff06f          	j	3294 <render_fill_rect+0x34>
        return RENDER_ERR_NO_BACKEND;
    3334:	00200513          	li	a0,2
}
    3338:	00008067          	ret
        return RENDER_OK;
    333c:	00000513          	li	a0,0
    3340:	f55ff06f          	j	3294 <render_fill_rect+0x34>

00003344 <render_blit>:
{
    render_op_t op;
    render_rect_t req;
    render_rect_t clipped;

    if (g_ops == 0)
    3344:	8341a783          	lw	a5,-1996(gp) # 44ac <g_ops>
    3348:	0e078063          	beqz	a5,3428 <render_blit+0xe4>
{
    334c:	f8010113          	addi	sp,sp,-128
    3350:	06112e23          	sw	ra,124(sp)
    3354:	06812c23          	sw	s0,120(sp)
    3358:	06912a23          	sw	s1,116(sp)
    335c:	07212823          	sw	s2,112(sp)
    3360:	07312623          	sw	s3,108(sp)
    3364:	00050413          	mv	s0,a0
    3368:	00058493          	mv	s1,a1
    336c:	00060993          	mv	s3,a2
    3370:	00068913          	mv	s2,a3
        return RENDER_ERR_NO_BACKEND;

    if (!render_surface_valid(dst) || !render_surface_valid(src))
    3374:	c35ff0ef          	jal	2fa8 <render_surface_valid>
    3378:	0a050c63          	beqz	a0,3430 <render_blit+0xec>
    337c:	00048513          	mv	a0,s1
    3380:	c29ff0ef          	jal	2fa8 <render_surface_valid>
    3384:	00051663          	bnez	a0,3390 <render_blit+0x4c>
        return RENDER_ERR_INVALID_ARG;
    3388:	00100513          	li	a0,1
    338c:	0a80006f          	j	3434 <render_blit+0xf0>

    req.x = dst_x;
    3390:	03312223          	sw	s3,36(sp)
    req.y = dst_y;
    3394:	03212423          	sw	s2,40(sp)
    req.w = src->width;
    3398:	0044a703          	lw	a4,4(s1)
    339c:	02e12623          	sw	a4,44(sp)
    req.h = src->height;
    33a0:	0084a783          	lw	a5,8(s1)
    33a4:	02f12823          	sw	a5,48(sp)

    if (!render_clip_rect(dst->width, dst->height, req, &clipped))
    33a8:	01312023          	sw	s3,0(sp)
    33ac:	01212223          	sw	s2,4(sp)
    33b0:	00e12423          	sw	a4,8(sp)
    33b4:	00f12623          	sw	a5,12(sp)
    33b8:	01410693          	addi	a3,sp,20
    33bc:	00010613          	mv	a2,sp
    33c0:	00842583          	lw	a1,8(s0)
    33c4:	00442503          	lw	a0,4(s0)
    33c8:	c35ff0ef          	jal	2ffc <render_clip_rect>
    33cc:	08050263          	beqz	a0,3450 <render_blit+0x10c>
        return RENDER_OK;

    op.dst = dst;
    33d0:	02812a23          	sw	s0,52(sp)
    op.src = src;
    33d4:	02912c23          	sw	s1,56(sp)
    op.dst_rect = clipped;
    33d8:	01412703          	lw	a4,20(sp)
    33dc:	01812783          	lw	a5,24(sp)
    33e0:	01c12603          	lw	a2,28(sp)
    33e4:	02012683          	lw	a3,32(sp)
    33e8:	02e12e23          	sw	a4,60(sp)
    33ec:	04f12023          	sw	a5,64(sp)
    33f0:	04c12223          	sw	a2,68(sp)
    33f4:	04d12423          	sw	a3,72(sp)
     * 源就要跟着偏移多少。
     *
     * 用 64 位相减：dst_x 为 INT_MIN 时，0 - INT_MIN 会溢出 int。
     * 结果必然落在 [0, src->width] 内，转回 int 是安全的。
     */
    op.src_rect.x = (int)((int64_t)clipped.x - (int64_t)dst_x);
    33f8:	41370733          	sub	a4,a4,s3
    33fc:	04e12623          	sw	a4,76(sp)
    op.src_rect.y = (int)((int64_t)clipped.y - (int64_t)dst_y);
    3400:	412787b3          	sub	a5,a5,s2
    3404:	04f12823          	sw	a5,80(sp)
    op.src_rect.w = clipped.w;
    3408:	04c12a23          	sw	a2,84(sp)
    op.src_rect.h = clipped.h;
    340c:	04d12c23          	sw	a3,88(sp)
    op.color = 0;
    3410:	04012e23          	sw	zero,92(sp)

    return g_ops->copy(&op);
    3414:	8341a783          	lw	a5,-1996(gp) # 44ac <g_ops>
    3418:	0087a783          	lw	a5,8(a5)
    341c:	03410513          	addi	a0,sp,52
    3420:	000780e7          	jalr	a5
    3424:	0100006f          	j	3434 <render_blit+0xf0>
        return RENDER_ERR_NO_BACKEND;
    3428:	00200513          	li	a0,2
}
    342c:	00008067          	ret
        return RENDER_ERR_INVALID_ARG;
    3430:	00100513          	li	a0,1
}
    3434:	07c12083          	lw	ra,124(sp)
    3438:	07812403          	lw	s0,120(sp)
    343c:	07412483          	lw	s1,116(sp)
    3440:	07012903          	lw	s2,112(sp)
    3444:	06c12983          	lw	s3,108(sp)
    3448:	08010113          	addi	sp,sp,128
    344c:	00008067          	ret
        return RENDER_OK;
    3450:	00000513          	li	a0,0
    3454:	fe1ff06f          	j	3434 <render_blit+0xf0>

00003458 <sw_fill_rect>:
    int y,
    int width,
    int height,
    pixel_t color
)
{
    3458:	00012e03          	lw	t3,0(sp)
    if (framebuffer == 0)
    345c:	06050a63          	beqz	a0,34d0 <sw_fill_rect+0x78>
        return;

    if (width <= 0 || height <= 0)
    3460:	07005863          	blez	a6,34d0 <sw_fill_rect+0x78>
    3464:	07105663          	blez	a7,34d0 <sw_fill_rect+0x78>
     * 裁剪：
     * 防止矩形跑出屏幕以后写坏别的内存。
     */
    int x0 = x;
    int y0 = y;
    int x1 = x + width;
    3468:	00e80833          	add	a6,a6,a4
    int y1 = y + height;
    346c:	00f888b3          	add	a7,a7,a5

    if (x0 < 0)
    3470:	02074263          	bltz	a4,3494 <sw_fill_rect+0x3c>
        x0 = 0;

    if (y0 < 0)
    3474:	0207c463          	bltz	a5,349c <sw_fill_rect+0x44>
        y0 = 0;

    if (x1 > fb_width)
    3478:	0105c463          	blt	a1,a6,3480 <sw_fill_rect+0x28>
    int x1 = x + width;
    347c:	00080593          	mv	a1,a6
        x1 = fb_width;

    if (y1 > fb_height)
    3480:	01164463          	blt	a2,a7,3488 <sw_fill_rect+0x30>
    int y1 = y + height;
    3484:	00088613          	mv	a2,a7
        y1 = fb_height;

    if (x0 >= x1 || y0 >= y1)
    3488:	04b75463          	bge	a4,a1,34d0 <sw_fill_rect+0x78>
    348c:	02c7ca63          	blt	a5,a2,34c0 <sw_fill_rect+0x68>
    3490:	00008067          	ret
        x0 = 0;
    3494:	00000713          	li	a4,0
    3498:	fddff06f          	j	3474 <sw_fill_rect+0x1c>
        y0 = 0;
    349c:	00000793          	li	a5,0
    34a0:	fd9ff06f          	j	3478 <sw_fill_rect+0x20>
    {
        pixel_t *row = framebuffer + py * fb_stride;

        for (int px = x0; px < x1; px++)
        {
            row[px] = color;
    34a4:	01130833          	add	a6,t1,a7
    34a8:	00281813          	slli	a6,a6,0x2
    34ac:	01050833          	add	a6,a0,a6
    34b0:	01c82023          	sw	t3,0(a6)
        for (int px = x0; px < x1; px++)
    34b4:	00188893          	addi	a7,a7,1
    34b8:	feb8c6e3          	blt	a7,a1,34a4 <sw_fill_rect+0x4c>
    for (int py = y0; py < y1; py++)
    34bc:	00178793          	addi	a5,a5,1
    34c0:	00c7d863          	bge	a5,a2,34d0 <sw_fill_rect+0x78>
        pixel_t *row = framebuffer + py * fb_stride;
    34c4:	02d78333          	mul	t1,a5,a3
        for (int px = x0; px < x1; px++)
    34c8:	00070893          	mv	a7,a4
    34cc:	fedff06f          	j	34b8 <sw_fill_rect+0x60>
        }
    }
}
    34d0:	00008067          	ret

000034d4 <sw_blit>:
    int src_stride,

    int dst_x,
    int dst_y
)
{
    34d4:	ff010113          	addi	sp,sp,-16
    34d8:	00812623          	sw	s0,12(sp)
    34dc:	01012383          	lw	t2,16(sp)
    34e0:	01412403          	lw	s0,20(sp)
    if (framebuffer == 0 || src == 0)
    34e4:	06050663          	beqz	a0,3550 <sw_blit+0x7c>
    34e8:	06070463          	beqz	a4,3550 <sw_blit+0x7c>
        return;

    for (int sy = 0; sy < src_height; sy++)
    34ec:	00000f93          	li	t6,0
    34f0:	0480006f          	j	3538 <sw_blit+0x64>
        int dy = dst_y + sy;

        if (dy < 0 || dy >= fb_height)
            continue;

        for (int sx = 0; sx < src_width; sx++)
    34f4:	00130313          	addi	t1,t1,1
    34f8:	02f35e63          	bge	t1,a5,3534 <sw_blit+0x60>
        {
            int dx = dst_x + sx;
    34fc:	00730f33          	add	t5,t1,t2

            if (dx < 0 || dx >= fb_width)
    3500:	fe0f4ae3          	bltz	t5,34f4 <sw_blit+0x20>
    3504:	febf58e3          	bge	t5,a1,34f4 <sw_blit+0x20>

            framebuffer[
                dy * fb_stride + dx
            ] =
            src[
                sy * src_stride + sx
    3508:	031f8eb3          	mul	t4,t6,a7
    350c:	006e8eb3          	add	t4,t4,t1
                dy * fb_stride + dx
    3510:	02d28e33          	mul	t3,t0,a3
    3514:	01ee0e33          	add	t3,t3,t5
            framebuffer[
    3518:	002e1e13          	slli	t3,t3,0x2
    351c:	01c50e33          	add	t3,a0,t3
            src[
    3520:	002e9e93          	slli	t4,t4,0x2
    3524:	01d70eb3          	add	t4,a4,t4
    3528:	000eae83          	lw	t4,0(t4)
            ] =
    352c:	01de2023          	sw	t4,0(t3)
    3530:	fc5ff06f          	j	34f4 <sw_blit+0x20>
    for (int sy = 0; sy < src_height; sy++)
    3534:	001f8f93          	addi	t6,t6,1
    3538:	010fdc63          	bge	t6,a6,3550 <sw_blit+0x7c>
        int dy = dst_y + sy;
    353c:	008f82b3          	add	t0,t6,s0
        if (dy < 0 || dy >= fb_height)
    3540:	fe02cae3          	bltz	t0,3534 <sw_blit+0x60>
    3544:	fec2d8e3          	bge	t0,a2,3534 <sw_blit+0x60>
        for (int sx = 0; sx < src_width; sx++)
    3548:	00000313          	li	t1,0
    354c:	fadff06f          	j	34f8 <sw_blit+0x24>
            ];
        }
    }
}
    3550:	00c12403          	lw	s0,12(sp)
    3554:	01010113          	addi	sp,sp,16
    3558:	00008067          	ret

0000355c <surface_base>:
}


/* 硬件要的是 DDR 物理地址；phys_base 为 0 表示画布就在指针指向的地方 */
static uintptr_t surface_base(const render_surface_t *s)
{
    355c:	00050793          	mv	a5,a0
    return (s->phys_base != 0) ? s->phys_base : (uintptr_t)s->pixels;
    3560:	01052503          	lw	a0,16(a0)
    3564:	00051463          	bnez	a0,356c <surface_base+0x10>
    3568:	0007a503          	lw	a0,0(a5)
}
    356c:	00008067          	ret

00003570 <fpga_gate>:
static render_status_t fpga_gate(void)
{
    if (!RENDER_FPGA_USABLE)
        return RENDER_ERR_FORMAT_MISMATCH;

    if (!g_limits_set)
    3570:	8381a783          	lw	a5,-1992(gp) # 44b0 <g_limits_set>
    3574:	00078663          	beqz	a5,3580 <fpga_gate+0x10>
        return RENDER_ERR_NOT_READY;

    return RENDER_OK;
    3578:	00000513          	li	a0,0
    357c:	00008067          	ret
        return RENDER_ERR_NOT_READY;
    3580:	00c00513          	li	a0,12
}
    3584:	00008067          	ret

00003588 <render_timeout_ms_to_ticks>:
    return (uint64_t)timeout_ms * 100000ULL;
    3588:	000187b7          	lui	a5,0x18
    358c:	6a078793          	addi	a5,a5,1696 # 186a0 <__freertos_irq_stack_top+0x12c30>
    3590:	02f535b3          	mulhu	a1,a0,a5
}
    3594:	02f50533          	mul	a0,a0,a5
    3598:	00008067          	ret

0000359c <render_status_from_bitblt>:
    switch (r)
    359c:	00450513          	addi	a0,a0,4
    35a0:	00400793          	li	a5,4
    35a4:	02a7ee63          	bltu	a5,a0,35e0 <render_status_from_bitblt+0x44>
    35a8:	00251513          	slli	a0,a0,0x2
    35ac:	000047b7          	lui	a5,0x4
    35b0:	41c78793          	addi	a5,a5,1052 # 441c <_data+0x528>
    35b4:	00f50533          	add	a0,a0,a5
    35b8:	00052783          	lw	a5,0(a0)
    35bc:	00078067          	jr	a5
    35c0:	00000513          	li	a0,0
    35c4:	00008067          	ret
    case BITBLT_EBUSY:    return RENDER_ERR_BUSY;
    35c8:	00d00513          	li	a0,13
    35cc:	00008067          	ret
    case BITBLT_ETIMEOUT: return RENDER_ERR_TIMEOUT;
    35d0:	00f00513          	li	a0,15
    35d4:	00008067          	ret
    case BITBLT_EHW:      return RENDER_ERR_HW_ERROR;
    35d8:	00e00513          	li	a0,14
    35dc:	00008067          	ret
    return RENDER_ERR_HW_ERROR;
    35e0:	00e00513          	li	a0,14
    35e4:	00008067          	ret
    case BITBLT_EINVAL:   return RENDER_ERR_INVALID_ARG;
    35e8:	00100513          	li	a0,1
}
    35ec:	00008067          	ret

000035f0 <render_pixel_to_hw_color>:
}
    35f0:	00008067          	ret

000035f4 <render_fpga_build_request>:
    if (op == 0 || op->dst == 0 || out == 0)
    35f4:	10050463          	beqz	a0,36fc <render_fpga_build_request+0x108>
{
    35f8:	fe010113          	addi	sp,sp,-32
    35fc:	00112e23          	sw	ra,28(sp)
    3600:	00812c23          	sw	s0,24(sp)
    3604:	00912a23          	sw	s1,20(sp)
    3608:	01212823          	sw	s2,16(sp)
    360c:	00050413          	mv	s0,a0
    3610:	00058913          	mv	s2,a1
    3614:	00060493          	mv	s1,a2
    if (op == 0 || op->dst == 0 || out == 0)
    3618:	00052783          	lw	a5,0(a0)
    361c:	0e078463          	beqz	a5,3704 <render_fpga_build_request+0x110>
    3620:	0e060663          	beqz	a2,370c <render_fpga_build_request+0x118>
    if (is_copy && op->src == 0)
    3624:	00058663          	beqz	a1,3630 <render_fpga_build_request+0x3c>
    3628:	00452703          	lw	a4,4(a0)
    362c:	0e070463          	beqz	a4,3714 <render_fpga_build_request+0x120>
    3630:	01312623          	sw	s3,12(sp)
    dst_pitch = (uint32_t)op->dst->stride_px * RENDER_PIXEL_BYTES;
    3634:	00c7a983          	lw	s3,12(a5)
    3638:	00299993          	slli	s3,s3,0x2
    memset(out, 0, sizeof(*out));
    363c:	02000613          	li	a2,32
    3640:	00000593          	li	a1,0
    3644:	00048513          	mv	a0,s1
    3648:	abdfd0ef          	jal	1104 <memset>
    out->dst_stride_bytes = dst_pitch;
    364c:	0134a223          	sw	s3,4(s1)
    out->dst_addr_bytes = (uint32_t)(surface_base(op->dst)
    3650:	00042503          	lw	a0,0(s0)
    3654:	f09ff0ef          	jal	355c <surface_base>
                                     + (uintptr_t)op->dst_rect.x * RENDER_PIXEL_BYTES);
    3658:	00842783          	lw	a5,8(s0)
    365c:	00279793          	slli	a5,a5,0x2
                                     + (uintptr_t)op->dst_rect.y * (uintptr_t)dst_pitch
    3660:	00c42703          	lw	a4,12(s0)
    3664:	03370733          	mul	a4,a4,s3
                                     + (uintptr_t)op->dst_rect.x * RENDER_PIXEL_BYTES);
    3668:	00e787b3          	add	a5,a5,a4
    366c:	00a787b3          	add	a5,a5,a0
    out->dst_addr_bytes = (uint32_t)(surface_base(op->dst)
    3670:	00f4a023          	sw	a5,0(s1)
    out->width = (uint32_t)op->dst_rect.w;
    3674:	01042783          	lw	a5,16(s0)
    3678:	00f4a823          	sw	a5,16(s1)
    out->height = (uint32_t)op->dst_rect.h;
    367c:	01442783          	lw	a5,20(s0)
    3680:	00f4aa23          	sw	a5,20(s1)
    out->color = render_pixel_to_hw_color(op->color);
    3684:	02842503          	lw	a0,40(s0)
    3688:	f69ff0ef          	jal	35f0 <render_pixel_to_hw_color>
    368c:	00a4ac23          	sw	a0,24(s1)
    out->operation = is_copy ? GPU_OP_COPY : GPU_OP_FILL;
    3690:	06090263          	beqz	s2,36f4 <render_fpga_build_request+0x100>
    3694:	00100793          	li	a5,1
    3698:	00f4ae23          	sw	a5,28(s1)
    if (is_copy)
    369c:	08090063          	beqz	s2,371c <render_fpga_build_request+0x128>
        uint32_t src_pitch = (uint32_t)op->src->stride_px * RENDER_PIXEL_BYTES;
    36a0:	00442783          	lw	a5,4(s0)
    36a4:	00c7a903          	lw	s2,12(a5)
    36a8:	00291913          	slli	s2,s2,0x2
        out->src_stride_bytes = src_pitch;
    36ac:	0124a623          	sw	s2,12(s1)
        out->src_addr_bytes = (uint32_t)(surface_base(op->src)
    36b0:	00442503          	lw	a0,4(s0)
    36b4:	ea9ff0ef          	jal	355c <surface_base>
                                         + (uintptr_t)op->src_rect.x * RENDER_PIXEL_BYTES);
    36b8:	01842783          	lw	a5,24(s0)
    36bc:	00279793          	slli	a5,a5,0x2
                                         + (uintptr_t)op->src_rect.y * (uintptr_t)src_pitch
    36c0:	01c42703          	lw	a4,28(s0)
    36c4:	03270733          	mul	a4,a4,s2
                                         + (uintptr_t)op->src_rect.x * RENDER_PIXEL_BYTES);
    36c8:	00e787b3          	add	a5,a5,a4
    36cc:	00a787b3          	add	a5,a5,a0
        out->src_addr_bytes = (uint32_t)(surface_base(op->src)
    36d0:	00f4a423          	sw	a5,8(s1)
    return RENDER_OK;
    36d4:	00000513          	li	a0,0
    36d8:	00c12983          	lw	s3,12(sp)
}
    36dc:	01c12083          	lw	ra,28(sp)
    36e0:	01812403          	lw	s0,24(sp)
    36e4:	01412483          	lw	s1,20(sp)
    36e8:	01012903          	lw	s2,16(sp)
    36ec:	02010113          	addi	sp,sp,32
    36f0:	00008067          	ret
    out->operation = is_copy ? GPU_OP_COPY : GPU_OP_FILL;
    36f4:	00000793          	li	a5,0
    36f8:	fa1ff06f          	j	3698 <render_fpga_build_request+0xa4>
        return RENDER_ERR_INVALID_ARG;
    36fc:	00100513          	li	a0,1
}
    3700:	00008067          	ret
        return RENDER_ERR_INVALID_ARG;
    3704:	00100513          	li	a0,1
    3708:	fd5ff06f          	j	36dc <render_fpga_build_request+0xe8>
    370c:	00100513          	li	a0,1
    3710:	fcdff06f          	j	36dc <render_fpga_build_request+0xe8>
        return RENDER_ERR_INVALID_ARG;
    3714:	00100513          	li	a0,1
    3718:	fc5ff06f          	j	36dc <render_fpga_build_request+0xe8>
    return RENDER_OK;
    371c:	00000513          	li	a0,0
    3720:	00c12983          	lw	s3,12(sp)
    3724:	fb9ff06f          	j	36dc <render_fpga_build_request+0xe8>

00003728 <fpga_copy>:
                    render_timeout_ms_to_ticks(RENDER_FPGA_TIMEOUT_MS)));
}


static render_status_t fpga_copy(const render_op_t *op)
{
    3728:	fd010113          	addi	sp,sp,-48
    372c:	02112623          	sw	ra,44(sp)
    3730:	02812423          	sw	s0,40(sp)
    3734:	00050413          	mv	s0,a0
    gpu_params_t req;
    render_status_t st = fpga_gate();
    3738:	e39ff0ef          	jal	3570 <fpga_gate>

    if (st != RENDER_OK)
    373c:	00050a63          	beqz	a0,3750 <fpga_copy+0x28>
                    req.width,
                    req.height,
                    req.src_stride_bytes,
                    req.dst_stride_bytes,
                    render_timeout_ms_to_ticks(RENDER_FPGA_TIMEOUT_MS)));
}
    3740:	02c12083          	lw	ra,44(sp)
    3744:	02812403          	lw	s0,40(sp)
    3748:	03010113          	addi	sp,sp,48
    374c:	00008067          	ret
    st = render_fpga_build_request(op, 1, &req);
    3750:	00010613          	mv	a2,sp
    3754:	00100593          	li	a1,1
    3758:	00040513          	mv	a0,s0
    375c:	e99ff0ef          	jal	35f4 <render_fpga_build_request>
    if (st != RENDER_OK)
    3760:	fe0510e3          	bnez	a0,3740 <fpga_copy+0x18>
    st = gpu_validate_copy(&g_limits, &req);
    3764:	00010593          	mv	a1,sp
    3768:	dc018513          	addi	a0,gp,-576 # 4a38 <g_limits>
    376c:	468000ef          	jal	3bd4 <gpu_validate_copy>
    if (st != RENDER_OK)
    3770:	fc0518e3          	bnez	a0,3740 <fpga_copy+0x18>
    return render_status_from_bitblt(
    3774:	06400513          	li	a0,100
    3778:	e11ff0ef          	jal	3588 <render_timeout_ms_to_ticks>
    377c:	00050813          	mv	a6,a0
    3780:	00058893          	mv	a7,a1
    3784:	00412783          	lw	a5,4(sp)
    3788:	00c12703          	lw	a4,12(sp)
    378c:	01412683          	lw	a3,20(sp)
    3790:	01012603          	lw	a2,16(sp)
    3794:	00012583          	lw	a1,0(sp)
    3798:	00812503          	lw	a0,8(sp)
    379c:	72c000ef          	jal	3ec8 <bitblt_copy>
    37a0:	dfdff0ef          	jal	359c <render_status_from_bitblt>
    37a4:	f9dff06f          	j	3740 <fpga_copy+0x18>

000037a8 <fpga_fill>:
{
    37a8:	fd010113          	addi	sp,sp,-48
    37ac:	02112623          	sw	ra,44(sp)
    37b0:	02812423          	sw	s0,40(sp)
    37b4:	00050413          	mv	s0,a0
    render_status_t st = fpga_gate();
    37b8:	db9ff0ef          	jal	3570 <fpga_gate>
    if (st != RENDER_OK)
    37bc:	00050a63          	beqz	a0,37d0 <fpga_fill+0x28>
}
    37c0:	02c12083          	lw	ra,44(sp)
    37c4:	02812403          	lw	s0,40(sp)
    37c8:	03010113          	addi	sp,sp,48
    37cc:	00008067          	ret
    st = render_fpga_build_request(op, 0, &req);
    37d0:	00010613          	mv	a2,sp
    37d4:	00000593          	li	a1,0
    37d8:	00040513          	mv	a0,s0
    37dc:	e19ff0ef          	jal	35f4 <render_fpga_build_request>
    if (st != RENDER_OK)
    37e0:	fe0510e3          	bnez	a0,37c0 <fpga_fill+0x18>
    st = gpu_validate_fill(&g_limits, &req);
    37e4:	00010593          	mv	a1,sp
    37e8:	dc018513          	addi	a0,gp,-576 # 4a38 <g_limits>
    37ec:	378000ef          	jal	3b64 <gpu_validate_fill>
    if (st != RENDER_OK)
    37f0:	fc0518e3          	bnez	a0,37c0 <fpga_fill+0x18>
    return render_status_from_bitblt(
    37f4:	06400513          	li	a0,100
    37f8:	d91ff0ef          	jal	3588 <render_timeout_ms_to_ticks>
    37fc:	00050793          	mv	a5,a0
    3800:	00058813          	mv	a6,a1
    3804:	01812703          	lw	a4,24(sp)
    3808:	00412683          	lw	a3,4(sp)
    380c:	01412603          	lw	a2,20(sp)
    3810:	01012583          	lw	a1,16(sp)
    3814:	00012503          	lw	a0,0(sp)
    3818:	66c000ef          	jal	3e84 <bitblt_fill>
    381c:	d81ff0ef          	jal	359c <render_status_from_bitblt>
    3820:	fa1ff06f          	j	37c0 <fpga_fill+0x18>

00003824 <cpu_copy>:
    return RENDER_OK;
}


static render_status_t cpu_copy(const render_op_t *op)
{
    3824:	fc010113          	addi	sp,sp,-64
    3828:	02112e23          	sw	ra,60(sp)
    382c:	02812c23          	sw	s0,56(sp)
    3830:	00050413          	mv	s0,a0
     * 一旦目标被裁剪，源也必须跟着偏移，所以这里用子视图把源里对应的
     * 那一块单独表达出来，再把它画到裁剪后的目标位置。
     *
     * 没有发生裁剪时 src_rect 就是整张源图，视图与 op->src 等价，是纯直通。
     */
    render_surface_t src_view = render_surface_view(op->src,
    3834:	02452783          	lw	a5,36(a0)
    3838:	02052703          	lw	a4,32(a0)
    383c:	01c52683          	lw	a3,28(a0)
    3840:	01852603          	lw	a2,24(a0)
    3844:	00452583          	lw	a1,4(a0)
    3848:	01c10513          	addi	a0,sp,28
    384c:	8edff0ef          	jal	3138 <render_surface_view>
                                                    op->src_rect.x,
                                                    op->src_rect.y,
                                                    op->src_rect.w,
                                                    op->src_rect.h);

    if (src_view.pixels == 0)
    3850:	01c12703          	lw	a4,28(sp)
    3854:	04070663          	beqz	a4,38a0 <cpu_copy+0x7c>
        return RENDER_ERR_INVALID_ARG;

    sw_blit(op->dst->pixels,
    3858:	00042783          	lw	a5,0(s0)
    385c:	0007a503          	lw	a0,0(a5)
            op->dst->width,
    3860:	0047a583          	lw	a1,4(a5)
            op->dst->height,
    3864:	0087a603          	lw	a2,8(a5)
            op->dst->stride_px,
    3868:	00c7a683          	lw	a3,12(a5)
            src_view.pixels,
            src_view.width,
            src_view.height,
            src_view.stride_px,

            op->dst_rect.x,
    386c:	00842783          	lw	a5,8(s0)
            op->dst_rect.y);
    3870:	00c42803          	lw	a6,12(s0)
    sw_blit(op->dst->pixels,
    3874:	01012223          	sw	a6,4(sp)
    3878:	00f12023          	sw	a5,0(sp)
    387c:	02812883          	lw	a7,40(sp)
    3880:	02412803          	lw	a6,36(sp)
    3884:	02012783          	lw	a5,32(sp)
    3888:	c4dff0ef          	jal	34d4 <sw_blit>

    return RENDER_OK;
    388c:	00000513          	li	a0,0
}
    3890:	03c12083          	lw	ra,60(sp)
    3894:	03812403          	lw	s0,56(sp)
    3898:	04010113          	addi	sp,sp,64
    389c:	00008067          	ret
        return RENDER_ERR_INVALID_ARG;
    38a0:	00100513          	li	a0,1
    38a4:	fedff06f          	j	3890 <cpu_copy+0x6c>

000038a8 <cpu_fill>:
{
    38a8:	fe010113          	addi	sp,sp,-32
    38ac:	00112e23          	sw	ra,28(sp)
    38b0:	00050713          	mv	a4,a0
    sw_fill_rect(op->dst->pixels,
    38b4:	00052783          	lw	a5,0(a0)
    38b8:	0007a503          	lw	a0,0(a5)
                 op->dst->width,
    38bc:	0047a583          	lw	a1,4(a5)
                 op->dst->height,
    38c0:	0087a603          	lw	a2,8(a5)
                 op->dst->stride_px,
    38c4:	00c7a683          	lw	a3,12(a5)
                 op->color);
    38c8:	02872783          	lw	a5,40(a4)
    sw_fill_rect(op->dst->pixels,
    38cc:	00f12023          	sw	a5,0(sp)
    38d0:	01472883          	lw	a7,20(a4)
    38d4:	01072803          	lw	a6,16(a4)
    38d8:	00c72783          	lw	a5,12(a4)
    38dc:	00872703          	lw	a4,8(a4)
    38e0:	b79ff0ef          	jal	3458 <sw_fill_rect>
}
    38e4:	00000513          	li	a0,0
    38e8:	01c12083          	lw	ra,28(sp)
    38ec:	02010113          	addi	sp,sp,32
    38f0:	00008067          	ret

000038f4 <render_strstatus>:
{
    /*
     * 用 switch 而不是查表：新增枚举项时编译器会以 -Wswitch 提醒补上，
     * 查表则会在运行期静默返回错位的字符串。
     */
    switch (status)
    38f4:	00f00793          	li	a5,15
    38f8:	0ca7e863          	bltu	a5,a0,39c8 <render_strstatus+0xd4>
    38fc:	00251513          	slli	a0,a0,0x2
    3900:	000047b7          	lui	a5,0x4
    3904:	44878793          	addi	a5,a5,1096 # 4448 <renderer_ops_cpu+0xc>
    3908:	00f50533          	add	a0,a0,a5
    390c:	00052783          	lw	a5,0(a0)
    3910:	00078067          	jr	a5
    3914:	00004537          	lui	a0,0x4
    3918:	2e050513          	addi	a0,a0,736 # 42e0 <_data+0x3ec>
    391c:	00008067          	ret
    {
    case RENDER_OK:                  return "OK";
    case RENDER_ERR_INVALID_ARG:     return "INVALID_ARG";
    case RENDER_ERR_NO_BACKEND:      return "NO_BACKEND";
    3920:	00004537          	lui	a0,0x4
    3924:	2f050513          	addi	a0,a0,752 # 42f0 <_data+0x3fc>
    3928:	00008067          	ret
    case RENDER_ERR_UNSUPPORTED:     return "UNSUPPORTED";
    392c:	00004537          	lui	a0,0x4
    3930:	2fc50513          	addi	a0,a0,764 # 42fc <_data+0x408>
    3934:	00008067          	ret
    case RENDER_ERR_FORMAT_MISMATCH: return "FORMAT_MISMATCH";
    3938:	00004537          	lui	a0,0x4
    393c:	30850513          	addi	a0,a0,776 # 4308 <_data+0x414>
    3940:	00008067          	ret
    case RENDER_ERR_BAD_OPERATION:   return "BAD_OPERATION";
    3944:	00004537          	lui	a0,0x4
    3948:	31850513          	addi	a0,a0,792 # 4318 <_data+0x424>
    394c:	00008067          	ret
    case RENDER_ERR_BAD_WIDTH:       return "BAD_WIDTH";
    3950:	00004537          	lui	a0,0x4
    3954:	32850513          	addi	a0,a0,808 # 4328 <_data+0x434>
    3958:	00008067          	ret
    case RENDER_ERR_BAD_HEIGHT:      return "BAD_HEIGHT";
    395c:	00004537          	lui	a0,0x4
    3960:	33450513          	addi	a0,a0,820 # 4334 <_data+0x440>
    3964:	00008067          	ret
    case RENDER_ERR_BAD_ALIGN:       return "BAD_ALIGN";
    3968:	00004537          	lui	a0,0x4
    396c:	34050513          	addi	a0,a0,832 # 4340 <_data+0x44c>
    3970:	00008067          	ret
    case RENDER_ERR_BAD_STRIDE:      return "BAD_STRIDE";
    3974:	00004537          	lui	a0,0x4
    3978:	34c50513          	addi	a0,a0,844 # 434c <_data+0x458>
    397c:	00008067          	ret
    case RENDER_ERR_OVERLAP:         return "OVERLAP";
    3980:	00004537          	lui	a0,0x4
    3984:	35850513          	addi	a0,a0,856 # 4358 <_data+0x464>
    3988:	00008067          	ret
    case RENDER_ERR_RANGE:           return "RANGE";
    398c:	00004537          	lui	a0,0x4
    3990:	36050513          	addi	a0,a0,864 # 4360 <_data+0x46c>
    3994:	00008067          	ret
    case RENDER_ERR_NOT_READY:       return "NOT_READY";
    3998:	00004537          	lui	a0,0x4
    399c:	36850513          	addi	a0,a0,872 # 4368 <_data+0x474>
    39a0:	00008067          	ret
    case RENDER_ERR_BUSY:            return "BUSY";
    39a4:	00004537          	lui	a0,0x4
    39a8:	37450513          	addi	a0,a0,884 # 4374 <_data+0x480>
    39ac:	00008067          	ret
    case RENDER_ERR_HW_ERROR:        return "HW_ERROR";
    39b0:	00004537          	lui	a0,0x4
    39b4:	37c50513          	addi	a0,a0,892 # 437c <_data+0x488>
    39b8:	00008067          	ret
    case RENDER_ERR_TIMEOUT:         return "TIMEOUT";
    39bc:	00004537          	lui	a0,0x4
    39c0:	38850513          	addi	a0,a0,904 # 4388 <_data+0x494>
    39c4:	00008067          	ret
    }

    return "UNKNOWN";
    39c8:	00004537          	lui	a0,0x4
    39cc:	39050513          	addi	a0,a0,912 # 4390 <_data+0x49c>
    39d0:	00008067          	ret
    case RENDER_ERR_INVALID_ARG:     return "INVALID_ARG";
    39d4:	00004537          	lui	a0,0x4
    39d8:	2e450513          	addi	a0,a0,740 # 42e4 <_data+0x3f0>
}
    39dc:	00008067          	ret

000039e0 <region_end>:
 */
static uint64_t region_end(uint32_t addr, uint32_t stride, uint32_t width, uint32_t height)
{
    return (uint64_t)addr
         + (uint64_t)(height - 1u) * (uint64_t)stride
         + (uint64_t)width * (uint64_t)GPU_HW_PIXEL_BYTES;
    39e0:	01e65713          	srli	a4,a2,0x1e
    39e4:	00261613          	slli	a2,a2,0x2
         + (uint64_t)(height - 1u) * (uint64_t)stride
    39e8:	fff68693          	addi	a3,a3,-1
    39ec:	02b687b3          	mul	a5,a3,a1
    39f0:	02b6b6b3          	mulhu	a3,a3,a1
         + (uint64_t)width * (uint64_t)GPU_HW_PIXEL_BYTES;
    39f4:	00f607b3          	add	a5,a2,a5
    39f8:	00c7b633          	sltu	a2,a5,a2
    39fc:	00d70733          	add	a4,a4,a3
    3a00:	00e60633          	add	a2,a2,a4
    3a04:	00a78533          	add	a0,a5,a0
    3a08:	00f535b3          	sltu	a1,a0,a5
}
    3a0c:	00c585b3          	add	a1,a1,a2
    3a10:	00008067          	ret

00003a14 <check_region>:
 *
 * 这里只做区间合法性判断，不关心它是源还是目标。
 */
static render_status_t check_region(const gpu_limits_t *lim, uint64_t lo, uint64_t hi)
{
    uint64_t win_lo = (uint64_t)lim->ddr_base;
    3a14:	00052303          	lw	t1,0(a0)
    3a18:	00000893          	li	a7,0
    uint64_t win_hi = (uint64_t)lim->ddr_base + (uint64_t)lim->ddr_size;
    3a1c:	00452803          	lw	a6,4(a0)
    3a20:	006807b3          	add	a5,a6,t1
    3a24:	00078e13          	mv	t3,a5
    3a28:	0107b7b3          	sltu	a5,a5,a6

    /* 越过 32 位地址空间顶端：地址算术已经回绕，直接判非法 */
    if (hi > 0x100000000ull)
    3a2c:	00100813          	li	a6,1
    3a30:	04e86263          	bltu	a6,a4,3a74 <check_region+0x60>
    3a34:	03070e63          	beq	a4,a6,3a70 <check_region+0x5c>
        return RENDER_ERR_RANGE;

    if (lo < win_lo || hi > win_hi)
    3a38:	05166463          	bltu	a2,a7,3a80 <check_region+0x6c>
    3a3c:	04c88063          	beq	a7,a2,3a7c <check_region+0x68>
    3a40:	04e7e663          	bltu	a5,a4,3a8c <check_region+0x78>
    3a44:	04f70263          	beq	a4,a5,3a88 <check_region+0x74>
        return RENDER_ERR_RANGE;

    /* 保留区判交：lo == hi 或逆序一律视为没有保留区 */
    if (lim->reserved_lo < lim->reserved_hi)
    3a48:	00852803          	lw	a6,8(a0)
    3a4c:	00c52783          	lw	a5,12(a0)
    3a50:	04f87863          	bgeu	a6,a5,3aa0 <check_region+0x8c>
    {
        uint64_t r_lo = (uint64_t)lim->reserved_lo;
    3a54:	00000513          	li	a0,0
        uint64_t r_hi = (uint64_t)lim->reserved_hi;

        if (lo < r_hi && r_lo < hi)
    3a58:	04061863          	bnez	a2,3aa8 <check_region+0x94>
    3a5c:	04f5f663          	bgeu	a1,a5,3aa8 <check_region+0x94>
    3a60:	02e56c63          	bltu	a0,a4,3a98 <check_region+0x84>
    3a64:	02a70863          	beq	a4,a0,3a94 <check_region+0x80>
            return RENDER_ERR_RANGE;
    }

    return RENDER_OK;
    3a68:	00000513          	li	a0,0
    3a6c:	00008067          	ret
    if (hi > 0x100000000ull)
    3a70:	fc0684e3          	beqz	a3,3a38 <check_region+0x24>
        return RENDER_ERR_RANGE;
    3a74:	00b00513          	li	a0,11
    3a78:	00008067          	ret
    if (lo < win_lo || hi > win_hi)
    3a7c:	fc65f2e3          	bgeu	a1,t1,3a40 <check_region+0x2c>
        return RENDER_ERR_RANGE;
    3a80:	00b00513          	li	a0,11
    3a84:	00008067          	ret
    if (lo < win_lo || hi > win_hi)
    3a88:	fcde70e3          	bgeu	t3,a3,3a48 <check_region+0x34>
        return RENDER_ERR_RANGE;
    3a8c:	00b00513          	li	a0,11
    3a90:	00008067          	ret
        if (lo < r_hi && r_lo < hi)
    3a94:	fcd87ae3          	bgeu	a6,a3,3a68 <check_region+0x54>
            return RENDER_ERR_RANGE;
    3a98:	00b00513          	li	a0,11
}
    3a9c:	00008067          	ret
    return RENDER_OK;
    3aa0:	00000513          	li	a0,0
    3aa4:	00008067          	ret
    3aa8:	00000513          	li	a0,0
    3aac:	00008067          	ret

00003ab0 <check_common>:
 */
static render_status_t check_common(const gpu_limits_t *lim,
                                    const gpu_params_t *p,
                                    uint32_t expected_operation)
{
    if (lim == 0 || p == 0)
    3ab0:	06050663          	beqz	a0,3b1c <check_common+0x6c>
    3ab4:	06058863          	beqz	a1,3b24 <check_common+0x74>
        return RENDER_ERR_INVALID_ARG;

    if (lim->ddr_size == 0u)
    3ab8:	00452783          	lw	a5,4(a0)
    3abc:	06078863          	beqz	a5,3b2c <check_common+0x7c>
        return RENDER_ERR_NOT_READY;

    if (p->operation != expected_operation)
    3ac0:	01c5a783          	lw	a5,28(a1)
    3ac4:	06c79863          	bne	a5,a2,3b34 <check_common+0x84>
        return RENDER_ERR_BAD_OPERATION;

    if (p->width == 0u || (p->width % GPU_WIDTH_GRANULARITY) != 0u)
    3ac8:	0105a783          	lw	a5,16(a1)
    3acc:	06078863          	beqz	a5,3b3c <check_common+0x8c>
    3ad0:	0037f713          	andi	a4,a5,3
    3ad4:	06071863          	bnez	a4,3b44 <check_common+0x94>
        return RENDER_ERR_BAD_WIDTH;

    if (p->height == 0u)
    3ad8:	0145a703          	lw	a4,20(a1)
    3adc:	06070863          	beqz	a4,3b4c <check_common+0x9c>
        return RENDER_ERR_BAD_HEIGHT;

    if ((p->dst_addr_bytes % GPU_ALIGN_BYTES) != 0u)
    3ae0:	0005a703          	lw	a4,0(a1)
    3ae4:	00f77713          	andi	a4,a4,15
    3ae8:	06071663          	bnez	a4,3b54 <check_common+0xa4>
        return RENDER_ERR_BAD_ALIGN;

    if ((p->dst_stride_bytes % GPU_ALIGN_BYTES) != 0u)
    3aec:	0045a703          	lw	a4,4(a1)
    3af0:	00f77513          	andi	a0,a4,15
    3af4:	06051463          	bnez	a0,3b5c <check_common+0xac>
        return RENDER_ERR_BAD_ALIGN;

    if ((uint64_t)p->dst_stride_bytes < (uint64_t)p->width * GPU_HW_PIXEL_BYTES)
    3af8:	00000613          	li	a2,0
    3afc:	01e7d693          	srli	a3,a5,0x1e
    3b00:	00279793          	slli	a5,a5,0x2
    3b04:	00069863          	bnez	a3,3b14 <check_common+0x64>
    3b08:	00c68463          	beq	a3,a2,3b10 <check_common+0x60>
        return RENDER_ERR_BAD_STRIDE;

    return RENDER_OK;
}
    3b0c:	00008067          	ret
    if ((uint64_t)p->dst_stride_bytes < (uint64_t)p->width * GPU_HW_PIXEL_BYTES)
    3b10:	fef77ee3          	bgeu	a4,a5,3b0c <check_common+0x5c>
        return RENDER_ERR_BAD_STRIDE;
    3b14:	00900513          	li	a0,9
    3b18:	00008067          	ret
        return RENDER_ERR_INVALID_ARG;
    3b1c:	00100513          	li	a0,1
    3b20:	00008067          	ret
    3b24:	00100513          	li	a0,1
    3b28:	00008067          	ret
        return RENDER_ERR_NOT_READY;
    3b2c:	00c00513          	li	a0,12
    3b30:	00008067          	ret
        return RENDER_ERR_BAD_OPERATION;
    3b34:	00500513          	li	a0,5
    3b38:	00008067          	ret
        return RENDER_ERR_BAD_WIDTH;
    3b3c:	00600513          	li	a0,6
    3b40:	00008067          	ret
    3b44:	00600513          	li	a0,6
    3b48:	00008067          	ret
        return RENDER_ERR_BAD_HEIGHT;
    3b4c:	00700513          	li	a0,7
    3b50:	00008067          	ret
        return RENDER_ERR_BAD_ALIGN;
    3b54:	00800513          	li	a0,8
    3b58:	00008067          	ret
        return RENDER_ERR_BAD_ALIGN;
    3b5c:	00800513          	li	a0,8
    3b60:	00008067          	ret

00003b64 <gpu_validate_fill>:


render_status_t gpu_validate_fill(const gpu_limits_t *lim, const gpu_params_t *p)
{
    3b64:	ff010113          	addi	sp,sp,-16
    3b68:	00112623          	sw	ra,12(sp)
    3b6c:	00812423          	sw	s0,8(sp)
    3b70:	00912223          	sw	s1,4(sp)
    3b74:	00050493          	mv	s1,a0
    3b78:	00058413          	mv	s0,a1
    render_status_t st = check_common(lim, p, GPU_OP_FILL);
    3b7c:	00000613          	li	a2,0
    3b80:	f31ff0ef          	jal	3ab0 <check_common>

    if (st != RENDER_OK)
    3b84:	02051e63          	bnez	a0,3bc0 <gpu_validate_fill+0x5c>
    3b88:	01212023          	sw	s2,0(sp)
        return st;

    /* FILL 忽略源侧参数，只用目标区间 */
    return check_region(lim,
                        p->dst_addr_bytes,
    3b8c:	00042903          	lw	s2,0(s0)
    return check_region(lim,
    3b90:	01442683          	lw	a3,20(s0)
    3b94:	01042603          	lw	a2,16(s0)
    3b98:	00442583          	lw	a1,4(s0)
    3b9c:	00090513          	mv	a0,s2
    3ba0:	e41ff0ef          	jal	39e0 <region_end>
    3ba4:	00050693          	mv	a3,a0
    3ba8:	00058713          	mv	a4,a1
    3bac:	00090593          	mv	a1,s2
    3bb0:	00000613          	li	a2,0
    3bb4:	00048513          	mv	a0,s1
    3bb8:	e5dff0ef          	jal	3a14 <check_region>
    3bbc:	00012903          	lw	s2,0(sp)
                        region_end(p->dst_addr_bytes, p->dst_stride_bytes,
                                   p->width, p->height));
}
    3bc0:	00c12083          	lw	ra,12(sp)
    3bc4:	00812403          	lw	s0,8(sp)
    3bc8:	00412483          	lw	s1,4(sp)
    3bcc:	01010113          	addi	sp,sp,16
    3bd0:	00008067          	ret

00003bd4 <gpu_validate_copy>:


render_status_t gpu_validate_copy(const gpu_limits_t *lim, const gpu_params_t *p)
{
    3bd4:	fd010113          	addi	sp,sp,-48
    3bd8:	02112623          	sw	ra,44(sp)
    3bdc:	02812423          	sw	s0,40(sp)
    3be0:	02912223          	sw	s1,36(sp)
    3be4:	00050413          	mv	s0,a0
    3be8:	00058493          	mv	s1,a1
    uint64_t dst_lo, dst_hi, src_lo, src_hi;
    render_status_t st = check_common(lim, p, GPU_OP_COPY);
    3bec:	00100613          	li	a2,1
    3bf0:	ec1ff0ef          	jal	3ab0 <check_common>

    if (st != RENDER_OK)
    3bf4:	16051063          	bnez	a0,3d54 <gpu_validate_copy+0x180>
    3bf8:	01912223          	sw	s9,4(sp)
        return st;

    /* COPY 才有源侧的对齐与 stride 约束 */
    if ((p->src_addr_bytes % GPU_ALIGN_BYTES) != 0u)
    3bfc:	0084ac83          	lw	s9,8(s1)
    3c00:	00fcf793          	andi	a5,s9,15
    3c04:	14079463          	bnez	a5,3d4c <gpu_validate_copy+0x178>
    3c08:	01412c23          	sw	s4,24(sp)
        return RENDER_ERR_BAD_ALIGN;

    if ((p->src_stride_bytes % GPU_ALIGN_BYTES) != 0u)
    3c0c:	00c4aa03          	lw	s4,12(s1)
    3c10:	00fa7793          	andi	a5,s4,15
    3c14:	14079a63          	bnez	a5,3d68 <gpu_validate_copy+0x194>
    3c18:	01312e23          	sw	s3,28(sp)
        return RENDER_ERR_BAD_ALIGN;

    if ((uint64_t)p->src_stride_bytes < (uint64_t)p->width * GPU_HW_PIXEL_BYTES)
    3c1c:	00000713          	li	a4,0
    3c20:	0104a983          	lw	s3,16(s1)
    3c24:	01e9d793          	srli	a5,s3,0x1e
    3c28:	00299613          	slli	a2,s3,0x2
    3c2c:	0e079063          	bnez	a5,3d0c <gpu_validate_copy+0x138>
    3c30:	0ce78c63          	beq	a5,a4,3d08 <gpu_validate_copy+0x134>
    3c34:	03212023          	sw	s2,32(sp)
    3c38:	01512a23          	sw	s5,20(sp)
    3c3c:	01612823          	sw	s6,16(sp)
    3c40:	01712623          	sw	s7,12(sp)
    3c44:	01812423          	sw	s8,8(sp)
    3c48:	01a12023          	sw	s10,0(sp)
        return RENDER_ERR_BAD_STRIDE;

    dst_lo = p->dst_addr_bytes;
    3c4c:	0004aa83          	lw	s5,0(s1)
    3c50:	00000b93          	li	s7,0
    dst_hi = region_end(p->dst_addr_bytes, p->dst_stride_bytes, p->width, p->height);
    3c54:	0144ad03          	lw	s10,20(s1)
    3c58:	000d0693          	mv	a3,s10
    3c5c:	00098613          	mv	a2,s3
    3c60:	0044a583          	lw	a1,4(s1)
    3c64:	000a8513          	mv	a0,s5
    3c68:	d79ff0ef          	jal	39e0 <region_end>
    3c6c:	00050913          	mv	s2,a0
    3c70:	00058493          	mv	s1,a1
    src_lo = p->src_addr_bytes;
    3c74:	00000b13          	li	s6,0
    src_hi = region_end(p->src_addr_bytes, p->src_stride_bytes, p->width, p->height);
    3c78:	000d0693          	mv	a3,s10
    3c7c:	00098613          	mv	a2,s3
    3c80:	000a0593          	mv	a1,s4
    3c84:	000c8513          	mv	a0,s9
    3c88:	d59ff0ef          	jal	39e0 <region_end>
    3c8c:	00050a13          	mv	s4,a0
    3c90:	00058993          	mv	s3,a1

    st = check_region(lim, dst_lo, dst_hi);
    3c94:	00090693          	mv	a3,s2
    3c98:	00048713          	mv	a4,s1
    3c9c:	000a8593          	mv	a1,s5
    3ca0:	00000613          	li	a2,0
    3ca4:	00040513          	mv	a0,s0
    3ca8:	d6dff0ef          	jal	3a14 <check_region>
    if (st != RENDER_OK)
    3cac:	0e051c63          	bnez	a0,3da4 <gpu_validate_copy+0x1d0>
        return st;

    st = check_region(lim, src_lo, src_hi);
    3cb0:	000a0693          	mv	a3,s4
    3cb4:	00098713          	mv	a4,s3
    3cb8:	000c8593          	mv	a1,s9
    3cbc:	00000613          	li	a2,0
    3cc0:	00040513          	mv	a0,s0
    3cc4:	d51ff0ef          	jal	3a14 <check_region>
    if (st != RENDER_OK)
    3cc8:	10051263          	bnez	a0,3dcc <gpu_validate_copy+0x1f8>
     * 硬件不保证 memmove 语义，所以重叠必须拒绝。用包围盒而不是逐行区间，
     * 意味着可能误拒某些实际不重叠的交错布局——这是有意的取舍：
     * 误报只是让某个合法请求退回 CPU 画，漏报则是内存损坏。
     * 将来要收紧成逐行区间比较，不需要改接口。
     */
    if (src_lo < dst_hi && dst_lo < src_hi)
    3ccc:	009b6663          	bltu	s6,s1,3cd8 <gpu_validate_copy+0x104>
    3cd0:	13649263          	bne	s1,s6,3df4 <gpu_validate_copy+0x220>
    3cd4:	152cf463          	bgeu	s9,s2,3e1c <gpu_validate_copy+0x248>
    3cd8:	0b3be063          	bltu	s7,s3,3d78 <gpu_validate_copy+0x1a4>
    3cdc:	05798263          	beq	s3,s7,3d20 <gpu_validate_copy+0x14c>
    3ce0:	02012903          	lw	s2,32(sp)
    3ce4:	01c12983          	lw	s3,28(sp)
    3ce8:	01812a03          	lw	s4,24(sp)
    3cec:	01412a83          	lw	s5,20(sp)
    3cf0:	01012b03          	lw	s6,16(sp)
    3cf4:	00c12b83          	lw	s7,12(sp)
    3cf8:	00812c03          	lw	s8,8(sp)
    3cfc:	00412c83          	lw	s9,4(sp)
    3d00:	00012d03          	lw	s10,0(sp)
    3d04:	0500006f          	j	3d54 <gpu_validate_copy+0x180>
    if ((uint64_t)p->src_stride_bytes < (uint64_t)p->width * GPU_HW_PIXEL_BYTES)
    3d08:	f2ca76e3          	bgeu	s4,a2,3c34 <gpu_validate_copy+0x60>
        return RENDER_ERR_BAD_STRIDE;
    3d0c:	00900513          	li	a0,9
    3d10:	01c12983          	lw	s3,28(sp)
    3d14:	01812a03          	lw	s4,24(sp)
    3d18:	00412c83          	lw	s9,4(sp)
    3d1c:	0380006f          	j	3d54 <gpu_validate_copy+0x180>
    if (src_lo < dst_hi && dst_lo < src_hi)
    3d20:	054aec63          	bltu	s5,s4,3d78 <gpu_validate_copy+0x1a4>
    3d24:	02012903          	lw	s2,32(sp)
    3d28:	01c12983          	lw	s3,28(sp)
    3d2c:	01812a03          	lw	s4,24(sp)
    3d30:	01412a83          	lw	s5,20(sp)
    3d34:	01012b03          	lw	s6,16(sp)
    3d38:	00c12b83          	lw	s7,12(sp)
    3d3c:	00812c03          	lw	s8,8(sp)
    3d40:	00412c83          	lw	s9,4(sp)
    3d44:	00012d03          	lw	s10,0(sp)
    3d48:	00c0006f          	j	3d54 <gpu_validate_copy+0x180>
        return RENDER_ERR_BAD_ALIGN;
    3d4c:	00800513          	li	a0,8
    3d50:	00412c83          	lw	s9,4(sp)
        return RENDER_ERR_OVERLAP;

    return RENDER_OK;
}
    3d54:	02c12083          	lw	ra,44(sp)
    3d58:	02812403          	lw	s0,40(sp)
    3d5c:	02412483          	lw	s1,36(sp)
    3d60:	03010113          	addi	sp,sp,48
    3d64:	00008067          	ret
        return RENDER_ERR_BAD_ALIGN;
    3d68:	00800513          	li	a0,8
    3d6c:	01812a03          	lw	s4,24(sp)
    3d70:	00412c83          	lw	s9,4(sp)
    3d74:	fe1ff06f          	j	3d54 <gpu_validate_copy+0x180>
        return RENDER_ERR_OVERLAP;
    3d78:	00a00513          	li	a0,10
    3d7c:	02012903          	lw	s2,32(sp)
    3d80:	01c12983          	lw	s3,28(sp)
    3d84:	01812a03          	lw	s4,24(sp)
    3d88:	01412a83          	lw	s5,20(sp)
    3d8c:	01012b03          	lw	s6,16(sp)
    3d90:	00c12b83          	lw	s7,12(sp)
    3d94:	00812c03          	lw	s8,8(sp)
    3d98:	00412c83          	lw	s9,4(sp)
    3d9c:	00012d03          	lw	s10,0(sp)
    3da0:	fb5ff06f          	j	3d54 <gpu_validate_copy+0x180>
    3da4:	02012903          	lw	s2,32(sp)
    3da8:	01c12983          	lw	s3,28(sp)
    3dac:	01812a03          	lw	s4,24(sp)
    3db0:	01412a83          	lw	s5,20(sp)
    3db4:	01012b03          	lw	s6,16(sp)
    3db8:	00c12b83          	lw	s7,12(sp)
    3dbc:	00812c03          	lw	s8,8(sp)
    3dc0:	00412c83          	lw	s9,4(sp)
    3dc4:	00012d03          	lw	s10,0(sp)
    3dc8:	f8dff06f          	j	3d54 <gpu_validate_copy+0x180>
    3dcc:	02012903          	lw	s2,32(sp)
    3dd0:	01c12983          	lw	s3,28(sp)
    3dd4:	01812a03          	lw	s4,24(sp)
    3dd8:	01412a83          	lw	s5,20(sp)
    3ddc:	01012b03          	lw	s6,16(sp)
    3de0:	00c12b83          	lw	s7,12(sp)
    3de4:	00812c03          	lw	s8,8(sp)
    3de8:	00412c83          	lw	s9,4(sp)
    3dec:	00012d03          	lw	s10,0(sp)
    3df0:	f65ff06f          	j	3d54 <gpu_validate_copy+0x180>
    3df4:	02012903          	lw	s2,32(sp)
    3df8:	01c12983          	lw	s3,28(sp)
    3dfc:	01812a03          	lw	s4,24(sp)
    3e00:	01412a83          	lw	s5,20(sp)
    3e04:	01012b03          	lw	s6,16(sp)
    3e08:	00c12b83          	lw	s7,12(sp)
    3e0c:	00812c03          	lw	s8,8(sp)
    3e10:	00412c83          	lw	s9,4(sp)
    3e14:	00012d03          	lw	s10,0(sp)
    3e18:	f3dff06f          	j	3d54 <gpu_validate_copy+0x180>
    3e1c:	02012903          	lw	s2,32(sp)
    3e20:	01c12983          	lw	s3,28(sp)
    3e24:	01812a03          	lw	s4,24(sp)
    3e28:	01412a83          	lw	s5,20(sp)
    3e2c:	01012b03          	lw	s6,16(sp)
    3e30:	00c12b83          	lw	s7,12(sp)
    3e34:	00812c03          	lw	s8,8(sp)
    3e38:	00412c83          	lw	s9,4(sp)
    3e3c:	00012d03          	lw	s10,0(sp)
    3e40:	f15ff06f          	j	3d54 <gpu_validate_copy+0x180>

00003e44 <record_call>:
                        uint32_t width, uint32_t height,
                        uint32_t src_stride, uint32_t dst_stride,
                        uint32_t color, int is_copy,
                        uint64_t timeout_ticks)
{
    g_last_call.dst_addr_bytes  = dst_addr;
    3e44:	dd018313          	addi	t1,gp,-560 # 4a48 <g_last_call>
    3e48:	00b32023          	sw	a1,0(t1)
    g_last_call.dst_stride_bytes = dst_stride;
    3e4c:	00f32223          	sw	a5,4(t1)
    g_last_call.src_addr_bytes  = src_addr;
    3e50:	00a32423          	sw	a0,8(t1)
    g_last_call.src_stride_bytes = src_stride;
    3e54:	00e32623          	sw	a4,12(t1)
    g_last_call.width           = width;
    3e58:	00c32823          	sw	a2,16(t1)
    g_last_call.height          = height;
    3e5c:	00d32a23          	sw	a3,20(t1)
    g_last_call.color           = color;
    3e60:	01032c23          	sw	a6,24(t1)
    g_last_call.is_copy         = is_copy;
    3e64:	01132e23          	sw	a7,28(t1)
    g_last_call.timeout_ticks   = timeout_ticks;
    3e68:	00012703          	lw	a4,0(sp)
    3e6c:	00412783          	lw	a5,4(sp)
    3e70:	02e32023          	sw	a4,32(t1)
    3e74:	02f32223          	sw	a5,36(t1)
    g_has_call = 1;
    3e78:	00100713          	li	a4,1
    3e7c:	82e1ae23          	sw	a4,-1988(gp) # 44b4 <g_has_call>
}
    3e80:	00008067          	ret

00003e84 <bitblt_fill>:

bitblt_result_t bitblt_fill(uint32_t dst_addr,
                            uint32_t width, uint32_t height,
                            uint32_t dst_stride, uint32_t color,
                            uint64_t timeout_ticks)
{
    3e84:	fe010113          	addi	sp,sp,-32
    3e88:	00112e23          	sw	ra,28(sp)
#ifdef BITBLT_ENABLE_HW_ACCESS
    return submit(0u, dst_addr, width, height, 0u, dst_stride,
                  color, BITBLT_OP_FILL, 0, timeout_ticks);
#else
    record_call(0u, dst_addr, width, height, 0u, dst_stride,
    3e8c:	00f12023          	sw	a5,0(sp)
    3e90:	01012223          	sw	a6,4(sp)
    3e94:	00000893          	li	a7,0
    3e98:	00070813          	mv	a6,a4
    3e9c:	00068793          	mv	a5,a3
    3ea0:	00000713          	li	a4,0
    3ea4:	00060693          	mv	a3,a2
    3ea8:	00058613          	mv	a2,a1
    3eac:	00050593          	mv	a1,a0
    3eb0:	00000513          	li	a0,0
    3eb4:	f91ff0ef          	jal	3e44 <record_call>
                color, 0, timeout_ticks);
    return BITBLT_EHW;
#endif
}
    3eb8:	ffc00513          	li	a0,-4
    3ebc:	01c12083          	lw	ra,28(sp)
    3ec0:	02010113          	addi	sp,sp,32
    3ec4:	00008067          	ret

00003ec8 <bitblt_copy>:

bitblt_result_t bitblt_copy(uint32_t src_addr, uint32_t dst_addr,
                            uint32_t width, uint32_t height,
                            uint32_t src_stride, uint32_t dst_stride,
                            uint64_t timeout_ticks)
{
    3ec8:	fe010113          	addi	sp,sp,-32
    3ecc:	00112e23          	sw	ra,28(sp)
#ifdef BITBLT_ENABLE_HW_ACCESS
    return submit(src_addr, dst_addr, width, height, src_stride, dst_stride,
                  0u, BITBLT_OP_COPY, 1, timeout_ticks);
#else
    record_call(src_addr, dst_addr, width, height, src_stride, dst_stride,
    3ed0:	01012023          	sw	a6,0(sp)
    3ed4:	01112223          	sw	a7,4(sp)
    3ed8:	00100893          	li	a7,1
    3edc:	00000813          	li	a6,0
    3ee0:	f65ff0ef          	jal	3e44 <record_call>
                0u, 1, timeout_ticks);
    return BITBLT_EHW;
#endif
}
    3ee4:	ffc00513          	li	a0,-4
    3ee8:	01c12083          	lw	ra,28(sp)
    3eec:	02010113          	addi	sp,sp,32
    3ef0:	00008067          	ret
