
#include "lua.h"

#if defined(__i386) || defined(__i386__) || defined(_M_IX86)

#define ARCHP_ARCH_NAME	"x86"
#elif defined(__x86_64__) || defined(__x86_64) || defined(_M_X64) || defined(_M_AMD64)

#define ARCHP_ARCH_NAME	"x64"
#elif defined(__arm__) || defined(__arm) || defined(__ARM__) || defined(__ARM)

#define ARCHP_ARCH_NAME	"ARM"
#elif defined(__aarch64__)

#define ARCHP_ARCH_NAME	"ARM64"
#elif defined(__ppc__) || defined(__ppc) || defined(__PPC__) || defined(__PPC) || defined(__powerpc__) || defined(__powerpc) || defined(__POWERPC__) || defined(__POWERPC) || defined(_M_PPC)

#define ARCHP_ARCH_NAME	"PPC"
#elif defined(__mips64__) || defined(__mips64) || defined(__MIPS64__) || defined(__MIPS64)

#define ARCHP_ARCH_NAME	"MIPS64"
#elif defined(__mips__) || defined(__mips) || defined(__MIPS__) || defined(__MIPS)

#define ARCHP_ARCH_NAME	"MIPS32"
#else
#define ARCHP_ARCH_NAME	"Unknown"
#endif


#if defined(_WIN32) && !defined(_XBOX_VER)
#define ARCHP_OS	"Windows"
#elif defined(__linux__)
#define ARCHP_OS	"Linux"
#elif defined(__MACH__) && defined(__APPLE__)
#define ARCHP_OS	"OSX"
#elif (defined(__FreeBSD__) || defined(__FreeBSD_kernel__) || \
       defined(__NetBSD__) || defined(__OpenBSD__) || \
       defined(__DragonFly__)) && !defined(__ORBIS__)
#define ARCHP_OS	"BSD"
#elif (defined(__sun__) && defined(__svr4__))
#define ARCHP_EXTRA "Solaris"
#define ARCHP_OS	"POSIX"
#elif defined(__HAIKU__)
#define ARCHP_OS	"POSIX"
#elif defined(__CYGWIN__)
#define ARCHP_EXTRA	"Cygwin"
#define ARCHP_OS	"POSIX"
#else
#define ARCHP_OS	"Other"
#endif

LUALIB_API  int luaopen_lacord_util_archp(lua_State* L) {
    lua_createtable(L, 0, 0);
    lua_pushstring(L, "os");
    lua_pushstring(L, ARCHP_OS);
    lua_settable(L, -3);
#if defined(ARCHP_EXTRA)
    lua_pushstring(L, "extra");
    lua_pushstring(L, ARCHP_EXTRA);
    lua_settable(L, -3);
#endif

    lua_pushstring(L, "arch");
    lua_pushstring(L, ARCHP_ARCH_NAME);
    lua_settable(L, -3);

    return 1;
}