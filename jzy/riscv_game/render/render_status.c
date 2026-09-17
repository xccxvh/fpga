#include "render_status.h"


const char *render_strstatus(render_status_t status)
{
    /*
     * 用 switch 而不是查表：新增枚举项时编译器会以 -Wswitch 提醒补上，
     * 查表则会在运行期静默返回错位的字符串。
     */
    switch (status)
    {
    case RENDER_OK:                  return "OK";
    case RENDER_ERR_INVALID_ARG:     return "INVALID_ARG";
    case RENDER_ERR_NO_BACKEND:      return "NO_BACKEND";
    case RENDER_ERR_UNSUPPORTED:     return "UNSUPPORTED";
    case RENDER_ERR_FORMAT_MISMATCH: return "FORMAT_MISMATCH";
    case RENDER_ERR_BAD_OPERATION:   return "BAD_OPERATION";
    case RENDER_ERR_BAD_WIDTH:       return "BAD_WIDTH";
    case RENDER_ERR_BAD_HEIGHT:      return "BAD_HEIGHT";
    case RENDER_ERR_BAD_ALIGN:       return "BAD_ALIGN";
    case RENDER_ERR_BAD_STRIDE:      return "BAD_STRIDE";
    case RENDER_ERR_OVERLAP:         return "OVERLAP";
    case RENDER_ERR_RANGE:           return "RANGE";
    case RENDER_ERR_NOT_READY:       return "NOT_READY";
    case RENDER_ERR_BUSY:            return "BUSY";
    case RENDER_ERR_HW_ERROR:        return "HW_ERROR";
    case RENDER_ERR_TIMEOUT:         return "TIMEOUT";
    }

    return "UNKNOWN";
}
