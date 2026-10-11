// libEGLproxy: sits between libgl4es_114 and MetalANGLE. Re-exports everything from MetalANGLE and overrides a few
// EGL lifetime calls to log (with a backtrace) who is destroying the display/context/surface.
#include <dlfcn.h>
#include <execinfo.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

#define EXPORT __attribute__((visibility("default"), used))
typedef void *H; typedef unsigned U; typedef int I;

static void *real(const char *name) {
    static void *lib;
    if (!lib) lib = dlopen("@rpath/MetalANGLE.framework/MetalANGLE", RTLD_NOW | RTLD_NOLOAD);
    return lib ? dlsym(lib, name) : NULL;
}
static void trace(const char *what) {
    char nm[64] = ""; pthread_getname_np(pthread_self(), nm, sizeof nm);
    fprintf(stderr, "[eglproxy] %s on thread %p/%s\n", what, (void *)pthread_self(), nm);
    void *bt[24]; int n = backtrace(bt, 24);
    for (int i = 1; i < n; i++) { Dl_info d; if (dladdr(bt[i], &d)) fprintf(stderr, "[eglproxy]   #%d %s %s+0x%lx\n", i, d.dli_fname ? d.dli_fname : "?", d.dli_sname ? d.dli_sname : "?", (unsigned long)((char *)bt[i] - (char *)(d.dli_saddr ? d.dli_saddr : bt[i]))); }
}

EXPORT U eglTerminate(H dpy)               { trace("eglTerminate");        return ((U (*)(H))real("eglTerminate"))(dpy); }
EXPORT U eglReleaseThread(void)            { trace("eglReleaseThread");    return ((U (*)(void))real("eglReleaseThread"))(); }
EXPORT U eglDestroyContext(H d, H c)       { trace("eglDestroyContext");   return ((U (*)(H, H))real("eglDestroyContext"))(d, c); }
EXPORT U eglDestroySurface(H d, H s)       { trace("eglDestroySurface");   return ((U (*)(H, H))real("eglDestroySurface"))(d, s); }
EXPORT U eglMakeCurrent(H d, H dr, H rd, H c) {
    U r = ((U (*)(H, H, H, H))real("eglMakeCurrent"))(d, dr, rd, c);
    if (!r || !c) { char b[64]; snprintf(b, sizeof b, "eglMakeCurrent(ctx=%p) -> %u", c, r); trace(b); }
    return r;
}
