// Developer Tools > "Zink Probe". Loads Mesa Zink (OpenGL on Vulkan) over MoltenVK from runtime/natives/zink,
// creates a GL 4.5 context and checks the features the Viewpoint mod needs; the report is saved as
// Documents/zink-probe.txt. Nothing here is used by the game's normal graphics path.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <unistd.h>
#import <fcntl.h>
#import <stdio.h>

typedef unsigned int GLenum, GLuint, GLbitfield; typedef int GLint, GLsizei; typedef float GLfloat; typedef unsigned char GLubyte; typedef long GLsizeiptr;
typedef void *EGLDisplay, *EGLConfig, *EGLContext, *EGLSurface; typedef int EGLint; typedef unsigned int EGLBoolean;
static void *(*pGetProc)(const char *);

static NSMutableString *g_out;
#define OUT(...) [g_out appendFormat:__VA_ARGS__]

static double footprint_mb(void) {
    task_vm_info_data_t v; mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&v, &n) != KERN_SUCCESS) return -1;
    return v.phys_footprint / 1048576.0;
}
static double now_ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e3 + t.tv_nsec / 1e6; }

#define FN(ret, name, args) static ret (*name) args
FN(const GLubyte *, glGetString, (GLenum)); FN(void, glGetIntegerv, (GLenum, GLint *)); FN(GLenum, glGetError, (void));
FN(GLuint, glCreateShader, (GLenum)); FN(void, glShaderSource, (GLuint, GLsizei, const char *const *, const GLint *)); FN(void, glCompileShader, (GLuint));
FN(void, glGetShaderiv, (GLuint, GLenum, GLint *)); FN(void, glGetShaderInfoLog, (GLuint, GLsizei, GLsizei *, char *));
FN(GLuint, glCreateProgram, (void)); FN(void, glAttachShader, (GLuint, GLuint)); FN(void, glLinkProgram, (GLuint));
FN(void, glGetProgramiv, (GLuint, GLenum, GLint *)); FN(void, glGetProgramInfoLog, (GLuint, GLsizei, GLsizei *, char *)); FN(void, glUseProgram, (GLuint));
FN(void, glCreateBuffers, (GLsizei, GLuint *)); FN(void, glNamedBufferStorage, (GLuint, GLsizeiptr, const void *, GLbitfield));
FN(void, glBindBufferBase, (GLenum, GLuint, GLuint)); FN(void, glBindBuffer, (GLenum, GLuint));
FN(void, glDispatchCompute, (GLuint, GLuint, GLuint)); FN(void, glMemoryBarrier, (GLbitfield));
FN(void, glGetNamedBufferSubData, (GLuint, long, GLsizeiptr, void *));
FN(void, glCreateTextures, (GLenum, GLsizei, GLuint *)); FN(void, glGenTextures, (GLsizei, GLuint *)); FN(void, glTextureStorage2D, (GLuint, GLsizei, GLenum, GLsizei, GLsizei));
FN(void, glBindImageTexture, (GLuint, GLuint, GLint, GLubyte, GLint, GLenum, GLenum)); FN(void, glGetTextureImage, (GLuint, GLint, GLenum, GLenum, GLsizei, void *));
FN(void, glCreateVertexArrays, (GLsizei, GLuint *)); FN(void, glBindVertexArray, (GLuint));
FN(void, glVertexArrayVertexBuffer, (GLuint, GLuint, GLuint, long, GLsizei)); FN(void, glVertexArrayAttribFormat, (GLuint, GLuint, GLint, GLenum, GLubyte, GLuint));
FN(void, glVertexArrayAttribBinding, (GLuint, GLuint, GLuint)); FN(void, glEnableVertexArrayAttrib, (GLuint, GLuint));
FN(void, glMultiDrawArraysIndirect, (GLenum, const void *, GLsizei, GLsizei));
FN(void, glCreateFramebuffers, (GLsizei, GLuint *)); FN(void, glNamedFramebufferTexture, (GLuint, GLenum, GLuint, GLint)); FN(GLenum, glCheckNamedFramebufferStatus, (GLuint, GLenum));
FN(void, glBindFramebuffer, (GLenum, GLuint)); FN(void, glViewport, (GLint, GLint, GLsizei, GLsizei)); FN(void, glClearColor, (GLfloat, GLfloat, GLfloat, GLfloat));
FN(void, glClear, (GLbitfield)); FN(void, glReadPixels, (GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void *));
FN(void, glPatchParameteri, (GLenum, GLint)); FN(void, glDrawArrays, (GLenum, GLint, GLsizei));
FN(void, glTextureView, (GLuint, GLenum, GLuint, GLenum, GLuint, GLuint, GLuint, GLuint));
FN(void, glCopyImageSubData, (GLuint, GLenum, GLint, GLint, GLint, GLint, GLuint, GLenum, GLint, GLint, GLint, GLint, GLsizei, GLsizei, GLsizei));
FN(void *, glMapNamedBufferRange, (GLuint, long, GLsizeiptr, GLbitfield)); FN(GLubyte, glUnmapNamedBuffer, (GLuint));
FN(void, glTextureBuffer, (GLuint, GLenum, GLuint)); FN(void, glFinish, (void));
FN(void, glCreateSamplers, (GLsizei, GLuint *)); FN(void, glCreateQueries, (GLenum, GLsizei, GLuint *));

static int load_gl(void) {
#define LD(n) do { n = pGetProc(#n); if (!n) { OUT(@"MISSING %s\n", #n); miss++; } } while (0)
    int miss = 0;
    LD(glGetString); LD(glGetIntegerv); LD(glGetError); LD(glCreateShader); LD(glShaderSource); LD(glCompileShader); LD(glGetShaderiv); LD(glGetShaderInfoLog);
    LD(glCreateProgram); LD(glAttachShader); LD(glLinkProgram); LD(glGetProgramiv); LD(glGetProgramInfoLog); LD(glUseProgram); LD(glCreateBuffers);
    LD(glNamedBufferStorage); LD(glBindBufferBase); LD(glBindBuffer); LD(glDispatchCompute); LD(glMemoryBarrier); LD(glGetNamedBufferSubData);
    LD(glCreateTextures); LD(glGenTextures); LD(glTextureStorage2D); LD(glBindImageTexture); LD(glGetTextureImage); LD(glCreateVertexArrays); LD(glBindVertexArray);
    LD(glVertexArrayVertexBuffer); LD(glVertexArrayAttribFormat); LD(glVertexArrayAttribBinding); LD(glEnableVertexArrayAttrib); LD(glMultiDrawArraysIndirect);
    LD(glCreateFramebuffers); LD(glNamedFramebufferTexture); LD(glCheckNamedFramebufferStatus); LD(glBindFramebuffer); LD(glViewport); LD(glClearColor); LD(glClear);
    LD(glReadPixels); LD(glPatchParameteri); LD(glDrawArrays); LD(glTextureView); LD(glCopyImageSubData); LD(glMapNamedBufferRange); LD(glUnmapNamedBuffer);
    LD(glTextureBuffer); LD(glFinish); LD(glCreateSamplers); LD(glCreateQueries);
    return miss;
}

static GLuint compile(GLenum type, const char *src, const char *what) {
    GLuint s = glCreateShader(type); glShaderSource(s, 1, &src, NULL); glCompileShader(s);
    GLint ok = 0; glGetShaderiv(s, 0x8B81, &ok);
    if (!ok) { char l[1024] = {0}; glGetShaderInfoLog(s, sizeof l, NULL, l); OUT(@"  %s compile FAILED: %.300s\n", what, l); return 0; }
    return s;
}
static GLuint link_prog(const char *name, GLuint a, GLuint b, GLuint c, GLuint d) {
    GLuint p = glCreateProgram(); GLuint sh[4] = {a, b, c, d};
    for (int i = 0; i < 4; i++) if (sh[i]) glAttachShader(p, sh[i]);
    glLinkProgram(p); GLint ok = 0; glGetProgramiv(p, 0x8B82, &ok);
    if (!ok) { char l[1024] = {0}; glGetProgramInfoLog(p, sizeof l, NULL, l); OUT(@"  %s link FAILED: %.300s\n", name, l); return 0; }
    return p;
}
static void result(const char *name, int pass, double t0) {
    GLenum e = glGetError();
    OUT(@"%@ %s  (%.0f ms%@)\n", pass ? @"PASS" : @"FAIL", name, now_ms() - t0, e ? [NSString stringWithFormat:@", glError 0x%x", e] : @"");
}

int zom_zink_probe(char *outBuf, size_t cap) {
    @autoreleasepool {
        g_out = [NSMutableString string];
        double fp0 = footprint_mb();
        NSString *dir = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"runtime/natives/zink"];
        NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        NSString *cache = [caches stringByAppendingPathComponent:@"mesa-shader-cache"]; [[NSFileManager defaultManager] createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:nil error:nil];
        setenv("ZINK_VK_LIB", [dir stringByAppendingPathComponent:@"libMoltenVK.dylib"].UTF8String, 1);
        setenv("LIBGL_DRIVERS_PATH", dir.UTF8String, 1);
        setenv("GALLIUM_DRIVER", "zink", 1); setenv("MESA_LOADER_DRIVER_OVERRIDE", "zink", 1); setenv("ZINK_NO_NULLDESC_OK", "1", 1);
        setenv("MESA_GL_VERSION_OVERRIDE", "4.5", 1); setenv("MESA_GLSL_VERSION_OVERRIDE", "450", 1);
        setenv("MESA_SHADER_CACHE_DIR", cache.UTF8String, 1);
        // capture Mesa's stderr messages into the report
        NSString *errPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"zink-stderr.txt"];
        fflush(stderr); int savedErr = dup(2); int ef = open(errPath.UTF8String, O_WRONLY | O_CREAT | O_TRUNC, 0644); dup2(ef, 2); close(ef);

        OUT(@"pziOS Zink probe\nfootprint at start: %.0f MB\n", fp0);
        void *egl = dlopen([dir stringByAppendingPathComponent:@"libEGL.1.dylib"].UTF8String, RTLD_NOW | RTLD_LOCAL);
        if (!egl) { OUT(@"dlopen libEGL failed: %s\n", dlerror()); goto done; }
        EGLDisplay (*eglGetDisplay)(void *) = dlsym(egl, "eglGetDisplay");
        EGLBoolean (*eglInitialize)(EGLDisplay, EGLint *, EGLint *) = dlsym(egl, "eglInitialize");
        EGLBoolean (*eglBindAPI)(unsigned) = dlsym(egl, "eglBindAPI");
        EGLBoolean (*eglChooseConfig)(EGLDisplay, const EGLint *, EGLConfig *, EGLint, EGLint *) = dlsym(egl, "eglChooseConfig");
        EGLContext (*eglCreateContext)(EGLDisplay, EGLConfig, EGLContext, const EGLint *) = dlsym(egl, "eglCreateContext");
        EGLSurface (*eglCreatePbufferSurface)(EGLDisplay, EGLConfig, const EGLint *) = dlsym(egl, "eglCreatePbufferSurface");
        EGLBoolean (*eglMakeCurrent)(EGLDisplay, EGLSurface, EGLSurface, EGLContext) = dlsym(egl, "eglMakeCurrent");
        EGLint (*eglGetError)(void) = dlsym(egl, "eglGetError");
        pGetProc = dlsym(egl, "eglGetProcAddress");
        if (!eglGetDisplay || !pGetProc) { OUT(@"EGL symbols missing\n"); goto done; }
        EGLDisplay d = eglGetDisplay(NULL); EGLint M = 0, m = 0;
        double t0 = now_ms();
        if (!eglInitialize(d, &M, &m)) { OUT(@"eglInitialize failed 0x%x\n", eglGetError()); goto done; }
        OUT(@"EGL %d.%d initialised in %.0f ms, footprint %.0f MB\n", M, m, now_ms() - t0, footprint_mb());
        eglBindAPI(0x30A2);
        EGLint ca[] = {0x3033, 0x1, 0x3040, 0x8, 0x3038}, cnt = 0; EGLConfig cfg = NULL;   // PBUFFER_BIT, OPENGL_BIT
        { EGLint a[] = {0x3033, 1, 0x3040, 8, 0x3038}; eglChooseConfig(d, a, &cfg, 1, &cnt); }
        (void)ca;
        EGLint ctxa[] = {0x3098, 4, 0x30FB, 5, 0x30FD, 1, 0x3038};     // MAJOR 4, MINOR 5, CORE profile
        EGLContext ctx = eglCreateContext(d, cfg, NULL, ctxa);
        EGLint pa[] = {0x3057, 64, 0x3056, 64, 0x3038};
        EGLSurface surf = eglCreatePbufferSurface(d, cfg, pa);
        if (!ctx || !eglMakeCurrent(d, surf, surf, ctx)) { OUT(@"context creation/make current failed: ctx=%p err=0x%x\n", ctx, eglGetError()); goto done; }
        if (load_gl()) OUT(@"some GL entry points are missing (see above)\n");
        OUT(@"GL_VENDOR   %s\nGL_RENDERER %s\nGL_VERSION  %s\nGLSL        %s\n", glGetString(0x1F00), glGetString(0x1F01), glGetString(0x1F02), glGetString(0x8B8C));
        GLint v = 0;
        glGetIntegerv(0x8C2B, &v); OUT(@"MAX_TEXTURE_BUFFER_SIZE %d\n", v);
        glGetIntegerv(0x90EB, &v); OUT(@"MAX_COMPUTE_WORK_GROUP_INVOCATIONS %d\n", v);
        glGetIntegerv(0x8E7D, &v); OUT(@"MAX_PATCH_VERTICES %d\n", v);
        OUT(@"footprint after context: %.0f MB\n", footprint_mb());
        glGetError();

        // 1. compute: SSBO + image store (direct state access)
        t0 = now_ms();
        { const char *cs = "#version 450\nlayout(local_size_x=64) in;\nlayout(std430,binding=0) buffer B{uint d[];};\nlayout(rgba8,binding=0) writeonly uniform image2D img;\n"
              "void main(){uint i=gl_GlobalInvocationID.x;d[i]=i*3u+1u;imageStore(img,ivec2(i%8u,i/8u),vec4(1.0,0.5,0.25,1.0));}\n";
          GLuint s = compile(0x91B9, cs, "compute"), p = s ? link_prog("compute", s, 0, 0, 0) : 0; int ok = 0;
          GLuint b = 0, t = 0;
          if (p) { glCreateBuffers(1, &b); glNamedBufferStorage(b, 1024, NULL, 0x101); glCreateTextures(0x0DE1, 1, &t); glTextureStorage2D(t, 1, 0x8058, 8, 8);
              glUseProgram(p); glBindBufferBase(0x90D2, 0, b); glBindImageTexture(0, t, 0, 0, 0, 0x88B9, 0x8058); glDispatchCompute(4, 1, 1); glMemoryBarrier(0xFFFFFFFF);
              unsigned out[256]; glGetNamedBufferSubData(b, 0, sizeof out, out); ok = 1; for (int i = 0; i < 256; i++) if (out[i] != i * 3u + 1u) ok = 0;
              unsigned char px[256]; glGetTextureImage(t, 0, 0x1908, 0x1401, sizeof px, px); ok = ok && px[0] == 255 && px[1] == 128 && px[2] == 64; }
          result("compute shader + SSBO + image store + DSA", ok, t0);
          // 5. texture view + copy image
          t0 = now_ms(); ok = 0;
          if (t) { GLuint view = 0, dst = 0; glGenTextures(1, &view); glTextureView(view, 0x0DE1, t, 0x8058, 0, 1, 0, 1);
              glCreateTextures(0x0DE1, 1, &dst); glTextureStorage2D(dst, 1, 0x8058, 8, 8); glCopyImageSubData(view, 0x0DE1, 0, 0, 0, 0, dst, 0x0DE1, 0, 0, 0, 0, 8, 8, 1);
              unsigned char px[256]; glGetTextureImage(dst, 0, 0x1908, 0x1401, sizeof px, px); ok = px[0] == 255 && px[1] == 128 && px[2] == 64; }
          result("glTextureView + glCopyImageSubData", ok, t0); }

        // 2. graphics: attrib binding + multi-draw indirect into an FBO
        t0 = now_ms();
        GLuint fbo = 0, ft = 0, vao = 0, vb = 0, ib = 0;
        const char *vs = "#version 450\nlayout(location=0) in vec2 pos;\nvoid main(){gl_Position=vec4(pos,0.0,1.0);}\n";
        const char *fs = "#version 450\nlayout(location=0) out vec4 c;\nvoid main(){c=vec4(0.0,1.0,0.0,1.0);}\n";
        float verts[] = {-1, -1, 0, -1, -1, 1, 0, -1, 1, -1, 1, 1};
        unsigned cmds[] = {3, 1, 0, 0,  3, 1, 3, 0};      // count, instanceCount, first, baseInstance
        glCreateTextures(0x0DE1, 1, &ft); glTextureStorage2D(ft, 1, 0x8058, 64, 64);
        glCreateFramebuffers(1, &fbo); glNamedFramebufferTexture(fbo, 0x8CE0, ft, 0);
        { GLenum st = glCheckNamedFramebufferStatus(fbo, 0x8D40); if (st != 0x8CD5) OUT(@"  framebuffer incomplete 0x%x\n", st); }
        glCreateBuffers(1, &vb); glNamedBufferStorage(vb, sizeof verts, verts, 0); glCreateBuffers(1, &ib); glNamedBufferStorage(ib, sizeof cmds, cmds, 0);
        glCreateVertexArrays(1, &vao); glVertexArrayVertexBuffer(vao, 0, vb, 0, 8); glVertexArrayAttribFormat(vao, 0, 2, 0x1406, 0, 0);
        glVertexArrayAttribBinding(vao, 0, 0); glEnableVertexArrayAttrib(vao, 0);
        { GLuint a = compile(0x8B31, vs, "vertex"), b = compile(0x8B30, fs, "fragment"), p = (a && b) ? link_prog("draw", a, b, 0, 0) : 0; int ok = 0;
          if (p) { glBindFramebuffer(0x8D40, fbo); glViewport(0, 0, 64, 64); glClearColor(0, 0, 0, 1); glClear(0x4000); glUseProgram(p); glBindVertexArray(vao);
              glBindBuffer(0x8F3F, ib); glMultiDrawArraysIndirect(0x4, NULL, 2, 0); glFinish();
              unsigned char l[4], r[4], mid[4]; glReadPixels(6, 10, 1, 1, 0x1908, 0x1401, l); glReadPixels(58, 10, 1, 1, 0x1908, 0x1401, r); glReadPixels(6, 58, 1, 1, 0x1908, 0x1401, mid);
              ok = l[1] == 255 && r[1] == 255 && mid[1] == 0; OUT(@"  pixels left=%d,%d,%d right=%d,%d,%d empty=%d,%d,%d\n", l[0], l[1], l[2], r[0], r[1], r[2], mid[0], mid[1], mid[2]); }
          result("vertex attrib binding + glMultiDrawArraysIndirect + FBO", ok, t0);
          // 3. tessellation
          t0 = now_ms(); ok = 0;
          const char *tcs = "#version 450\nlayout(vertices=3) out;\nvoid main(){gl_out[gl_InvocationID].gl_Position=gl_in[gl_InvocationID].gl_Position;\n"
              "if(gl_InvocationID==0){gl_TessLevelInner[0]=1.0;gl_TessLevelOuter[0]=1.0;gl_TessLevelOuter[1]=1.0;gl_TessLevelOuter[2]=1.0;}}\n";
          const char *tes = "#version 450\nlayout(triangles,equal_spacing,ccw) in;\nvoid main(){gl_Position=gl_TessCoord.x*gl_in[0].gl_Position+gl_TessCoord.y*gl_in[1].gl_Position+gl_TessCoord.z*gl_in[2].gl_Position;}\n";
          GLuint tc = compile(0x8E88, tcs, "tess control"), te = compile(0x8E87, tes, "tess eval"), tp = (a && b && tc && te) ? link_prog("tess", a, tc, te, b) : 0;
          if (tp) { glBindFramebuffer(0x8D40, fbo); glClear(0x4000); glUseProgram(tp); glPatchParameteri(0x8E72, 3); glBindVertexArray(vao); glDrawArrays(0xE, 0, 3); glFinish();
              unsigned char px[4]; glReadPixels(6, 10, 1, 1, 0x1908, 0x1401, px); ok = px[1] == 255; OUT(@"  tess pixel=%d,%d,%d\n", px[0], px[1], px[2]); }
          result("tessellation (TCS+TES, GL_PATCHES)", ok, t0); (void)p; }

        // 4. persistent coherent mapped buffer
        t0 = now_ms();
        { GLuint b = 0; glCreateBuffers(1, &b); glNamedBufferStorage(b, 4096, NULL, 0x2 | 0x40 | 0x80 | 0x100); volatile unsigned *mp = glMapNamedBufferRange(b, 0, 4096, 0x2 | 0x40 | 0x80);
          int ok = 0; if (mp) { mp[7] = 1234; glUnmapNamedBuffer(b); ok = 1; }
          result("persistent coherent mapped buffer (glBufferStorage)", ok, t0); }

        // 6. big buffer texture (Viewpoint's mesh arena asks for ~1 GiB of texels)
        t0 = now_ms();
        { double f0 = footprint_mb(); GLuint b = 0, t = 0; glCreateBuffers(1, &b); glNamedBufferStorage(b, 1u << 30, NULL, 0x100); glCreateTextures(0x8C2A, 1, &t); glTextureBuffer(t, 0x822E, b);
          int ok = glGetError() == 0; OUT(@"  footprint %.0f -> %.0f MB (1 GiB buffer, untouched)\n", f0, footprint_mb());
          result("1 GiB buffer texture (R32F)", ok, t0); }

        // 7. geometry shader (MoltenVK has none; expected to fail)
        t0 = now_ms();
        { const char *gs = "#version 450\nlayout(triangles) in;layout(triangle_strip,max_vertices=3) out;\nvoid main(){for(int i=0;i<3;i++){gl_Position=gl_in[i].gl_Position;EmitVertex();}EndPrimitive();}\n";
          GLuint g = compile(0x8DD9, gs, "geometry"); OUT(@"INFO geometry shader compile %s (expected: unsupported)\n", g ? "ok" : "failed"); glGetError(); }

        // 8. samplers + queries
        t0 = now_ms();
        { GLuint s = 0, q = 0; glCreateSamplers(1, &s); glCreateQueries(0x88BF, 1, &q); result("sampler objects + timer query objects", s && q, t0); }

        OUT(@"footprint at end: %.0f MB\n", footprint_mb());
    done:;
        fflush(stderr); dup2(savedErr, 2); close(savedErr);
        NSString *mesaErr = [NSString stringWithContentsOfFile:errPath encoding:NSUTF8StringEncoding error:nil];
        if (mesaErr.length) OUT(@"\n--- Mesa / MoltenVK messages ---\n%@", mesaErr.length > 3000 ? [mesaErr substringToIndex:3000] : mesaErr);
        strlcpy(outBuf, g_out.UTF8String, cap);
        return 0;
    }
}
