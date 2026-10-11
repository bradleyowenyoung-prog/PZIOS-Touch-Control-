// C wrapper around ARM astc-encoder (Apache-2.0) for the GL shim: compress an RGBA8/BGRA8 image to ASTC LDR.
#include <pthread.h>
#include <unistd.h>
#include <stdint.h>
#include <string.h>
#include <vector>
#include "astcenc.h"

namespace {
struct Job { astcenc_context *ctx; astcenc_image *img; const astcenc_swizzle *sw; uint8_t *out; size_t len; unsigned idx; };
void *worker(void *p) { Job *j = (Job *)p; astcenc_compress_image(j->ctx, j->img, j->sw, j->out, j->len, j->idx); return nullptr; }
pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
struct Cached { unsigned block = 0; float quality = -1; astcenc_context *ctx = nullptr; unsigned threads = 0; } g_cache;
}

extern "C" size_t zo_astc_size(unsigned w, unsigned h, unsigned block) { return (size_t)((w + block - 1) / block) * ((h + block - 1) / block) * 16; }

// returns 1 on success. out must hold zo_astc_size(w, h, block) bytes.
extern "C" int zo_astc_compress(const uint8_t *pixels, unsigned w, unsigned h, int bgra, unsigned block, float quality, uint8_t *out) {
    pthread_mutex_lock(&g_lock);
    unsigned threads = (unsigned)sysconf(_SC_NPROCESSORS_ONLN); if (threads < 1) threads = 1; if (threads > 6) threads = 6;
    if (!g_cache.ctx || g_cache.block != block || g_cache.quality != quality) {
        if (g_cache.ctx) astcenc_context_free(g_cache.ctx);
        g_cache.ctx = nullptr;
        astcenc_config cfg;
        if (astcenc_config_init(ASTCENC_PRF_LDR, block, block, 1, quality, ASTCENC_FLG_USE_ALPHA_WEIGHT, &cfg) != ASTCENC_SUCCESS) { pthread_mutex_unlock(&g_lock); return 0; }
        if (astcenc_context_alloc(&cfg, threads, &g_cache.ctx, nullptr) != ASTCENC_SUCCESS) { g_cache.ctx = nullptr; pthread_mutex_unlock(&g_lock); return 0; }
        g_cache.block = block; g_cache.quality = quality; g_cache.threads = threads;
    }
    void *slice = (void *)pixels;
    astcenc_image img = { w, h, 1, ASTCENC_TYPE_U8, &slice };
    astcenc_swizzle sw = bgra ? astcenc_swizzle{ ASTCENC_SWZ_B, ASTCENC_SWZ_G, ASTCENC_SWZ_R, ASTCENC_SWZ_A }
                              : astcenc_swizzle{ ASTCENC_SWZ_R, ASTCENC_SWZ_G, ASTCENC_SWZ_B, ASTCENC_SWZ_A };
    size_t len = zo_astc_size(w, h, block);
    std::vector<pthread_t> th(g_cache.threads); std::vector<Job> jobs(g_cache.threads);
    for (unsigned t = 0; t < g_cache.threads; t++) { jobs[t] = { g_cache.ctx, &img, &sw, out, len, t }; pthread_create(&th[t], nullptr, worker, &jobs[t]); }
    for (unsigned t = 0; t < g_cache.threads; t++) pthread_join(th[t], nullptr);
    astcenc_compress_reset(g_cache.ctx);
    pthread_mutex_unlock(&g_lock);
    return 1;
}
