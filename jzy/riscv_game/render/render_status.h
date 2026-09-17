#ifndef RENDER_STATUS_H
#define RENDER_STATUS_H

/*
 * 统一渲染层与 GPU 驱动的公共状态码。
 *
 * 这里刻意只有一套枚举：驱动的 TIMEOUT / BUSY / HW_ERROR 等状态原样上传到
 * 游戏代码，不再做一次翻译。少一层映射，待冻结的接口面也小一半。
 *
 * RENDER_OK 固定为 0，因此可以写 if (status) { 出错 }。
 */
typedef enum
{
    RENDER_OK = 0,

    /* 参数问题：空指针、宽高 <= 0、stride 小于宽度等 */
    RENDER_ERR_INVALID_ARG,

    /* 还没调用 render_select() 选后端 */
    RENDER_ERR_NO_BACKEND,

    /* 当前后端做不了这件事（骨架阶段的寄存器通路即返回此值） */
    RENDER_ERR_UNSUPPORTED,

    /* 软件像素宽度与已确认的硬件格式不一致。
       硬件格式已确认为 XRGB8888（32 bit）；当前 software pixel_t 仍是 16 bit，
       所以 FPGA 后端一律返回此码。这是已确认的待执行迁移项，不是未决问题，
       迁移步骤见 renderer.h 顶部。禁止用强制转换或截断绕过。 */
    RENDER_ERR_FORMAT_MISMATCH,

    /* OPERATION 取值非法 */
    RENDER_ERR_BAD_OPERATION,

    /* width == 0 或 width 不是 4 的倍数（硬件约束） */
    RENDER_ERR_BAD_WIDTH,

    /* height == 0（硬件约束） */
    RENDER_ERR_BAD_HEIGHT,

    /* 地址或 stride 未满足 16 字节对齐（硬件约束） */
    RENDER_ERR_BAD_ALIGN,

    /* stride 小于 width * 4（硬件约束） */
    RENDER_ERR_BAD_STRIDE,

    /* COPY 的源与目标区间相交，硬件没有 memmove 语义 */
    RENDER_ERR_OVERLAP,

    /* 越出 DDR 可访问窗口、踩到保留区，或地址回绕 32 位 */
    RENDER_ERR_RANGE,

    /* 尚未就绪：驱动未初始化、内存布局未填写、时基未注入 */
    RENDER_ERR_NOT_READY,

    /* 上一条命令还没完成，硬件没有命令 FIFO */
    RENDER_ERR_BUSY,

    /* 硬件 STATUS.ERROR 置位 */
    RENDER_ERR_HW_ERROR,

    /* 等待 DONE 超时 */
    RENDER_ERR_TIMEOUT
} render_status_t;


/*
 * 返回状态的 ASCII 标识符，例如 "BAD_ALIGN"、"OK"。
 *
 * 刻意返回标识符而不是整句说明：这些字符串会进串口日志和测试断言，
 * 标识符便于 grep，说明文字写在上面每个枚举项的注释里。
 */
const char *render_strstatus(render_status_t status);

#endif
