// libfmodhal: replaces the macOS-only audio APIs that the macOS libfmod.dylib imports.
//  - CoreAudio HAL "AudioObject*" device queries: answered with one fake stereo output device.
//  - AudioUnit: forwarded to AudioToolbox, with the HAL output unit ('auou'/'ahal') mapped to iOS RemoteIO ('rioc')
//    and macOS-only unit properties (CurrentDevice, EnableIO, ChannelLayout) tolerated.
// Query set derived from running the original FMOD on macOS with a logging interposer.
#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <string.h>
#include <stdio.h>

#define EXPORT __attribute__((visibility("default"), used))
typedef UInt32 AudioObjectID;
typedef struct { UInt32 mSelector, mScope, mElement; } AudioObjectPropertyAddress;
typedef OSStatus (*AudioObjectPropertyListenerProc)(AudioObjectID, UInt32, const AudioObjectPropertyAddress *, void *);

#define SYSTEM_OBJECT 1
#define DEVICE 100
#define STREAM 101
static const char UID[] = "ios-default-output";

#define FCC(a, b, c, d) (((UInt32)(a) << 24) | ((UInt32)(b) << 16) | ((UInt32)(c) << 8) | (UInt32)(d))

static int dbg(void) { static int v = -1; if (v < 0) v = getenv("ZOMIOS_FMODHAL_LOG") != NULL; return v; }
#define LOG(...) do { if (dbg()) { fprintf(stderr, "[fmodhal] " __VA_ARGS__); fputc('\n', stderr); } } while (0)

// ---------------------------------------------------------------- CoreAudio HAL ---
EXPORT OSStatus AudioObjectAddPropertyListener(AudioObjectID o, const AudioObjectPropertyAddress *a, AudioObjectPropertyListenerProc l, void *c) { return 0; }
EXPORT OSStatus AudioObjectRemovePropertyListener(AudioObjectID o, const AudioObjectPropertyAddress *a, AudioObjectPropertyListenerProc l, void *c) { return 0; }

static OSStatus prop_size(AudioObjectID o, const AudioObjectPropertyAddress *a, UInt32 *sz) {
    switch (a->mSelector) {
        case FCC('d','O','u','t'): case FCC('d','I','n',' '): *sz = 4; return 0;                 // default devices
        case FCC('d','e','v','#'): *sz = 4; return 0;                                              // device list (1 device)
        case FCC('s','t','m','#'): *sz = (o == DEVICE && a->mScope == FCC('o','u','t','p')) ? 4 : 0; return 0;
        case FCC('u','i','d',' '): *sz = 8; return 0;                                              // CFStringRef
        case FCC('l','n','a','m'): *sz = 8; return 0;
        case FCC('n','s','r','t'): *sz = 8; return 0;                                              // Float64
        case FCC('s','r','n','d'): *sz = 52; return 0;                                             // AudioChannelLayout, 2 descs
        case FCC('d','c','h','2'): *sz = 8; return 0;                                              // UInt32[2]
        case FCC('l','t','n','c'): case FCC('t','r','a','n'): *sz = 4; return 0;
        case FCC('d','u','i','d'): *sz = 32; return 0;                                             // AudioValueTranslation
    }
    return FCC('w','h','o','?');
}

EXPORT OSStatus AudioObjectGetPropertyDataSize(AudioObjectID o, const AudioObjectPropertyAddress *a, UInt32 qs, const void *q, UInt32 *sz) {
    OSStatus r = prop_size(o, a, sz);
    LOG("size obj=%u sel=%.4s -> %d (%u)", o, (char[]){a->mSelector>>24,a->mSelector>>16,a->mSelector>>8,a->mSelector,0}, (int)r, r ? 0 : *sz);
    return r;
}

EXPORT OSStatus AudioObjectGetPropertyData(AudioObjectID o, const AudioObjectPropertyAddress *a, UInt32 qs, const void *q, UInt32 *sz, void *d) {
    UInt32 need = 0;
    OSStatus r = prop_size(o, a, &need);
    if (r) { LOG("data obj=%u sel=%.4s -> unknown", o, (char[]){a->mSelector>>24,a->mSelector>>16,a->mSelector>>8,a->mSelector,0}); return r; }
    if (*sz < need) need = *sz;
    memset(d, 0, need);
    switch (a->mSelector) {
        case FCC('d','O','u','t'): case FCC('d','I','n',' '): *(AudioObjectID *)d = DEVICE; break;
        case FCC('d','e','v','#'): *(AudioObjectID *)d = DEVICE; break;
        case FCC('s','t','m','#'): if (need >= 4) *(AudioObjectID *)d = STREAM; break;
        case FCC('u','i','d',' '): *(CFStringRef *)d = CFStringCreateWithCString(NULL, UID, kCFStringEncodingUTF8); break;
        case FCC('l','n','a','m'): *(CFStringRef *)d = CFStringCreateWithCString(NULL, "iOS Output", kCFStringEncodingUTF8); break;
        case FCC('n','s','r','t'): *(Float64 *)d = 48000.0; break;
        case FCC('s','r','n','d'): {
            // AudioChannelLayout { tag=UseChannelDescriptions(0), bitmap=0, numDescs=2, {label,flags,coords[3]} x2 }
            UInt32 *w = (UInt32 *)d; w[0] = 0; w[1] = 0; w[2] = 2;
            w[3] = 1; /* kAudioChannelLabel_Left */  w[8] = 2; /* Right */
            break;
        }
        case FCC('d','c','h','2'): ((UInt32 *)d)[0] = 1; ((UInt32 *)d)[1] = 2; break;
        case FCC('l','t','n','c'): *(UInt32 *)d = 0; break;
        case FCC('t','r','a','n'): *(UInt32 *)d = FCC('b','l','t','n'); break;               // built-in
        case FCC('d','u','i','d'): {
            // AudioValueTranslation: input = CFStringRef uid, output = AudioObjectID
            struct { void *in; UInt32 inSize; void *out; UInt32 outSize; } *t = d;
            if (t->out && t->outSize >= 4) *(AudioObjectID *)t->out = DEVICE;
            break;
        }
    }
    *sz = need;
    LOG("data obj=%u sel=%.4s -> ok (%u)", o, (char[]){a->mSelector>>24,a->mSelector>>16,a->mSelector>>8,a->mSelector,0}, need);
    return 0;
}

// ---------------------------------------------------------------- AudioUnit forwarding ---
static void *at(void) {
    static void *h;
    if (!h) h = dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox", RTLD_NOW);
    return h;
}
#define REAL(name) static typeof(&name) real; if (!real) real = dlsym(at(), #name)

EXPORT AudioComponent AudioComponentFindNext(AudioComponent c, const AudioComponentDescription *d) {
    static AudioComponent (*real)(AudioComponent, const AudioComponentDescription *);
    if (!real) real = dlsym(at(), "AudioComponentFindNext");
    AudioComponentDescription m = *d;
    if (d->componentType == FCC('a','u','o','u') && d->componentSubType == FCC('a','h','a','l')) {
        m.componentSubType = FCC('r','i','o','c');   // HAL output -> RemoteIO
        LOG("FindNext: mapped HAL output to RemoteIO");
    }
    return real(c, &m);
}
EXPORT OSStatus AudioComponentInstanceNew(AudioComponent c, AudioComponentInstance *i) {
    static OSStatus (*real)(AudioComponent, AudioComponentInstance *); if (!real) real = dlsym(at(), "AudioComponentInstanceNew");
    return real(c, i);
}
EXPORT OSStatus AudioComponentInstanceDispose(AudioComponentInstance i) {
    static OSStatus (*real)(AudioComponentInstance); if (!real) real = dlsym(at(), "AudioComponentInstanceDispose");
    return real(i);
}
EXPORT OSStatus AudioOutputUnitStart(AudioUnit u) { static OSStatus (*real)(AudioUnit); if (!real) real = dlsym(at(), "AudioOutputUnitStart"); OSStatus r = real(u); LOG("Start -> %d", (int)r); return r; }
EXPORT OSStatus AudioOutputUnitStop(AudioUnit u) { static OSStatus (*real)(AudioUnit); if (!real) real = dlsym(at(), "AudioOutputUnitStop"); return real(u); }
EXPORT OSStatus AudioUnitInitialize(AudioUnit u) { static OSStatus (*real)(AudioUnit); if (!real) real = dlsym(at(), "AudioUnitInitialize"); OSStatus r = real(u); LOG("Initialize -> %d", (int)r); return r; }
EXPORT OSStatus AudioUnitUninitialize(AudioUnit u) { static OSStatus (*real)(AudioUnit); if (!real) real = dlsym(at(), "AudioUnitUninitialize"); return real(u); }
EXPORT OSStatus AudioUnitRender(AudioUnit u, AudioUnitRenderActionFlags *f, const AudioTimeStamp *t, UInt32 b, UInt32 n, AudioBufferList *l) {
    static OSStatus (*real)(AudioUnit, AudioUnitRenderActionFlags *, const AudioTimeStamp *, UInt32, UInt32, AudioBufferList *);
    if (!real) real = dlsym(at(), "AudioUnitRender");
    return real(u, f, t, b, n, l);
}
EXPORT OSStatus AudioUnitGetProperty(AudioUnit u, AudioUnitPropertyID id, AudioUnitScope s, AudioUnitElement e, void *d, UInt32 *sz) {
    static OSStatus (*real)(AudioUnit, AudioUnitPropertyID, AudioUnitScope, AudioUnitElement, void *, UInt32 *);
    if (!real) real = dlsym(at(), "AudioUnitGetProperty");
    OSStatus r = real(u, id, s, e, d, sz);
    LOG("GetProperty id=%u scope=%u elem=%u -> %d", id, s, e, (int)r);
    return r;
}
EXPORT OSStatus AudioUnitSetProperty(AudioUnit u, AudioUnitPropertyID id, AudioUnitScope s, AudioUnitElement e, const void *d, UInt32 sz) {
    static OSStatus (*real)(AudioUnit, AudioUnitPropertyID, AudioUnitScope, AudioUnitElement, const void *, UInt32);
    if (!real) real = dlsym(at(), "AudioUnitSetProperty");
    // macOS-only properties on the HAL unit: CurrentDevice (2000), EnableIO (2003), AudioChannelLayout (19)
    if (id == 2000) { LOG("SetProperty CurrentDevice ignored"); return 0; }
    OSStatus r = real(u, id, s, e, d, sz);
    LOG("SetProperty id=%u scope=%u elem=%u size=%u -> %d", id, s, e, sz, (int)r);
    if (r && (id == 2003 || id == 19)) return 0;
    return r;
}
