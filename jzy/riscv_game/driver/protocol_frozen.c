#include "protocol_frozen.h"


uint32_t proto_display_format_default(void)
{
    return PROTO_DISPLAY_FORMAT_RGB565;
}


int proto_display_version_compatible(uint32_t version)
{
    return version == PROTO_DISPLAY_VERSION_RGB565;
}


int proto_bitblt_version_compatible(uint32_t version)
{
    return version == PROTO_BITBLT_VERSION_RGB565;
}

