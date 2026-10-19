/* Host description for running this GCC on Apple Silicon macOS (arm64, LP64).

   Mirrors i386/xm-i386.h + xm-linux.h, the host the original EE-GCC was built
   for, except that `long' and pointers are 64 bits here.  HOST_WIDE_INT is
   unaffected: the r5900 target forces it to `long long' (host_wint.h) on
   every host.  Code that depends on `long' being 32 bits is handled by the
   patches next to this file.  */

#define HOST_BITS_PER_CHAR 8
#define HOST_BITS_PER_SHORT 16
#define HOST_BITS_PER_INT 32
#define HOST_BITS_PER_LONG 64
#define HOST_BITS_PER_LONGLONG 64

#define FALSE 0
#define TRUE 1

#define SUCCESS_EXIT_CODE 0
#define FATAL_EXIT_CODE 33

#undef  HAVE_ATEXIT
#define HAVE_ATEXIT
#undef  POSIX
#define POSIX
#undef  BSTRING
#define BSTRING

#include "tm.h"
