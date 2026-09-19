/*
 * 板端 smoke 的宿主机驱动器。
 *
 * tests/test_bitblt_board.c 里的 main() 通过 -Dmain=board_main 改名后在这里被调用，
 * 于是板上跑的就是这份测试源的同一个翻译单元，不是副本。
 *
 * 板端程序跑完后停在 while(1) 等人工看串口，在宿主机上会一直转。
 * 用一个闹钟收尾：输出是不缓冲的，所以直接 _exit() 不会丢东西。
 */

#include <signal.h>
#include <unistd.h>

void board_main(void);

static void on_alarm(int sig)
{
    (void)sig;
    _exit(0);
}

int main(void)
{
    signal(SIGALRM, on_alarm);
    alarm(1);

    board_main();

    return 0;
}
