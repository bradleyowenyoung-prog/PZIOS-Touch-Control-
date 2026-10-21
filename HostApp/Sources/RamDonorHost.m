// Extra Memory (the "RAM donor"), app side (experimental).
//
// iOS limits the memory of each process separately. A helper process (an app extension, here the same one that carries the built-in JIT) can hold memory
// that iOS then charges to the helper and not to the app. The helper allocates purgeable memory and shares it; the app maps it. zom_donor_prepare() and
// zom_donor_map() below put the Java heap into such memory: the JVM asks for the mapping through PZ_DONOR_MAP_FN once it has reserved its heap range.
// The app and the helper talk over the extension's own auxiliary XPC channel (the two context classes declared here and in RamDonor/ZomRamDonor.m).
#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <os/proc.h>
#import <dlfcn.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <signal.h>
#import <sys/sysctl.h>
#import <mach/mach_host.h>
#import <xpc/xpc.h>
#import "../RamDonor/ZomRamDonorProtocol.h"

extern kern_return_t mach_vm_allocate(vm_map_t target, mach_vm_address_t *address, mach_vm_size_t size, int flags);
extern kern_return_t mach_vm_deallocate(vm_map_t target, mach_vm_address_t address, mach_vm_size_t size);
extern kern_return_t mach_vm_remap(vm_map_t target, mach_vm_address_t *address, mach_vm_size_t size, mach_vm_offset_t mask, int flags,
                                   vm_map_t source, mach_vm_address_t sourceAddress, boolean_t copy, vm_prot_t *cur, vm_prot_t *max, vm_inherit_t inherit);
#ifndef VM_FLAGS_OVERWRITE
#define VM_FLAGS_OVERWRITE 0x4000
#endif

// The private NSExtension API, declared on NSObject so nothing has to link against it (resolved by name at run time).
@interface NSObject (ZomRamDonorExtension)
+ (instancetype)extensionWithIdentifier:(NSString *)identifier error:(NSError **)error;
- (void)beginExtensionRequestWithInputItems:(NSArray *)items completion:(void (^)(NSUUID *))completion;
- (int)pidForRequestIdentifier:(NSUUID *)identifier;
- (void)setRequestCompletionBlock:(void (^)(NSUUID *, NSArray *))block;
- (void)setRequestCancellationBlock:(void (^)(NSUUID *, NSError *))block;
- (void)setRequestInterruptionBlock:(void (^)(NSUUID *))block;
- (void)_kill:(int)signal;
@end

// The app-side context class (Info.plist NSExtensionContextHostClass of the JIT helper). Same auxiliary protocols as the extension's context.
@interface ZomDonorHostContext : NSExtensionContext <ZomDonorHostProtocol>
@end
@implementation ZomDonorHostContext
+ (id)_extensionAuxiliaryVendorProtocol { return [NSXPCInterface interfaceWithProtocol:@protocol(ZomDonorVendorProtocol)]; }
+ (id)_extensionAuxiliaryHostProtocol { return [NSXPCInterface interfaceWithProtocol:@protocol(ZomDonorHostProtocol)]; }
- (void)zomHello:(NSString *)text {}
@end

static double now_s(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e9; }
static double footprint_mb(void) {
    task_vm_info_data_t v; mach_msg_type_number_t c = TASK_VM_INFO_COUNT;
    return task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&v, &c) == KERN_SUCCESS ? v.phys_footprint / 1048576.0 : -1;
}
static double avail_mb(void) { return os_proc_available_memory() / 1048576.0; }

// The donor code lives in the JIT helper extension (a new extension would need its own App ID and profile).
static NSString *donor_identifier(void) {
    NSURL *u = [NSBundle.mainBundle.builtInPlugInsURL URLByAppendingPathComponent:@"ZomJITHelper.appex"];
    return [NSBundle bundleWithURL:u].bundleIdentifier;
}

// Sends one request to the donor and waits for the reply (nil on timeout).
static NSString *gAskError;      // why the last ask() returned nothing
static xpc_object_t ask(xpc_connection_t donor, const char *op, uint64_t size, double timeout) {
    gAskError = @"no reply within the timeout";
    xpc_object_t req = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(req, ZomDonorKeyOp, op);
    if (size) xpc_dictionary_set_uint64(req, ZomDonorKeySize, size);
    __block xpc_object_t answer = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    xpc_connection_send_message_with_reply(donor, req, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(xpc_object_t reply) {
        if (xpc_get_type(reply) == XPC_TYPE_DICTIONARY) answer = reply;
        else if (xpc_get_type(reply) == XPC_TYPE_ERROR) gAskError = [NSString stringWithUTF8String:xpc_dictionary_get_string(reply, XPC_ERROR_KEY_DESCRIPTION) ?: "xpc error"];
        dispatch_semaphore_signal(done);
    });
    return dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) == 0 ? answer : nil;
}

#define LINE(...) [report appendFormat:__VA_ARGS__]

// Starts the extension with a request it does not answer, then reaches it through the auxiliary XPC channel iOS creates for our context classes:
// ping first, then hand over the endpoint of our own listener. On success `donor` is the connection the extension opened back to us.
static NSMutableArray *gListeners;       // must stay alive as long as the donors' connections are used (releasing an anonymous listener drops what it accepted)

static BOOL connect_donor(Class extClass, NSString *identifier, NSMutableString *report, id *extOut, xpc_connection_t *donorOut) {
    NSError *error = nil;
    id ext = [extClass extensionWithIdentifier:identifier error:&error];
    if (!ext) { LINE(@"Could not load %@: %@\n", identifier, error.localizedDescription); return NO; }
    *extOut = ext;

    // Our listener, which the extension will connect to.
    __block xpc_connection_t donor = nil;
    dispatch_semaphore_t connected = dispatch_semaphore_create(0);
    xpc_connection_t listener = xpc_connection_create(NULL, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
    xpc_connection_set_event_handler(listener, ^(xpc_object_t event) {
        if (xpc_get_type(event) != XPC_TYPE_CONNECTION) return;
        donor = (xpc_connection_t)event;
        xpc_connection_set_event_handler(donor, ^(xpc_object_t e) {});
        xpc_connection_resume(donor);
        dispatch_semaphore_signal(connected);
    });
    xpc_connection_resume(listener);
    if (!gListeners) gListeners = [NSMutableArray array];
    [gListeners addObject:listener];


    NSExtensionItem *open = [NSExtensionItem new];
    open.userInfo = @{ @"donor": @"1", @"probe": @"open" };
    __block NSUUID *request = nil; __block BOOL started = NO;
    dispatch_semaphore_t spawned = dispatch_semaphore_create(0);
    double t0 = now_s();
    [ext beginExtensionRequestWithInputItems:@[open] completion:^(NSUUID *uuid) { request = uuid; started = uuid != nil; dispatch_semaphore_signal(spawned); }];
    dispatch_semaphore_wait(spawned, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC));
    if (!started) { LINE(@"iOS would not start the extension.\n"); return NO; }
    LINE(@"Extension started: pid %d (%.2f s)\n", [ext pidForRequestIdentifier:request], now_s() - t0);

    id ctx = nil;
    for (int i = 0; i < 20 && !ctx; i++) { ctx = ((id (*)(id, SEL, id))objc_msgSend)(ext, NSSelectorFromString(@"_extensionContextForUUID:"), request); if (!ctx) usleep(100000); }
    if (!ctx) { LINE(@"No app-side context for the request.\n"); return NO; }
    NSXPCConnection *conn = nil; @try { conn = [ctx valueForKey:@"_auxiliaryConnection"]; } @catch (NSException *e) {}
    LINE(@"App-side context %@, auxiliary connection %@, interface %@\n", NSStringFromClass([ctx class]), conn ? @"present" : @"nil", conn.remoteObjectInterface ? NSStringFromProtocol(conn.remoteObjectInterface.protocol) : @"none");
    if (!conn) return NO;
    if (!conn.remoteObjectInterface) conn.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(ZomDonorVendorProtocol)];

    dispatch_semaphore_t replied = dispatch_semaphore_create(0); __block NSString *answer = nil;
    id<ZomDonorVendorProtocol> proxy = [conn remoteObjectProxyWithErrorHandler:^(NSError *e) { answer = [NSString stringWithFormat:@"connection error: %@", e.localizedDescription]; dispatch_semaphore_signal(replied); }];
    @try { [proxy zomPing:^(NSString *s) { answer = s; dispatch_semaphore_signal(replied); }]; } @catch (NSException *e) { answer = [@"exception " stringByAppendingString:e.name]; dispatch_semaphore_signal(replied); }
    dispatch_semaphore_wait(replied, dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC));
    LINE(@"Ping through the auxiliary channel: %@\n", answer ?: @"no answer within 8 s");
    if (![answer hasPrefix:@"pong"]) return NO;

    answer = nil;
    replied = dispatch_semaphore_create(0);
    proxy = [conn remoteObjectProxyWithErrorHandler:^(NSError *e) { answer = [NSString stringWithFormat:@"connection error: %@", e.localizedDescription]; dispatch_semaphore_signal(replied); }];
    @try { [proxy zomConnect:ZomWrapEndpoint(xpc_endpoint_create(listener)) reply:^(NSString *s) { answer = s; dispatch_semaphore_signal(replied); }]; } @catch (NSException *e) { answer = [@"exception " stringByAppendingString:e.name]; dispatch_semaphore_signal(replied); }
    dispatch_semaphore_wait(replied, dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC));
    LINE(@"Endpoint handed over: %@\n", answer ?: @"no answer within 8 s");
    if (![answer isEqual:@"connected"]) return NO;
    if (dispatch_semaphore_wait(connected, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) != 0 || !donor) { LINE(@"The extension did not connect back.\n"); return NO; }
    *donorOut = donor;
    LINE(@"Donor connected (%.2f s after start)\n", now_s() - t0);
    return YES;
}


// ---- Donated memory for the Java heap -------------------------------------------------------------------------------------------------------------
// zom_donor_prepare() runs before the JVM starts: it starts the donor and collects enough memory chunks (xpc shared memory, nothing mapped yet).
// zom_donor_map() is called by the JVM itself (libjvm gets its address from the PZ_DONOR_MAP_FN environment variable) once it has reserved its heap
// range: it maps the chunks over that exact range. If anything is missing it returns false and the JVM keeps ordinary memory.
static NSMutableArray *gHeldShmem;                // the chunks, in order
static NSMutableArray<NSNumber *> *gHeldLength;
static NSMutableArray *gHeldExtensions;           // the donor processes, kept alive
static NSMutableArray *gHeldDonors;               // their connections (asked for their footprint by the overlay)

// Collects `bytes` of donated memory, from as many donor processes as it takes (each one has its own memory budget, about 3.4 GB on an 8 GB iPhone).
int zom_donor_prepare(uint64_t bytes, char *msg, size_t cap) {
    @autoreleasepool {
        NSMutableString *report = [NSMutableString string];
        NSString *identifier = donor_identifier();
        if (!NSClassFromString(@"NSExtension")) dlopen("/System/Library/Frameworks/ExtensionFoundation.framework/ExtensionFoundation", RTLD_NOW);
        Class extClass = NSClassFromString(@"NSExtension");
        int ok = 0;
        if (!identifier || !extClass) { LINE(@"RAM donor: no donor extension in this build\n"); strlcpy(msg, report.UTF8String, cap); return 0; }
        gHeldShmem = [NSMutableArray array]; gHeldLength = [NSMutableArray array]; gHeldExtensions = [NSMutableArray array]; gHeldDonors = [NSMutableArray array];
        uint64_t have = 0; double t0 = now_s();
        for (int donorIndex = 0; donorIndex < 4 && have < bytes; donorIndex++) {
            id extension = nil; xpc_connection_t donor = nil;
            NSMutableString *sub = [NSMutableString string];
            if (!connect_donor(extClass, identifier, sub, &extension, &donor)) { LINE(@"RAM donor %d: %@", donorIndex + 1, sub); [extension _kill:SIGKILL]; break; }
            [gHeldExtensions addObject:extension]; [gHeldDonors addObject:donor];
            xpc_object_t r = ask(donor, ZomDonorOpAvailable, 0, 10);
            uint64_t budget = r ? xpc_dictionary_get_uint64(r, ZomDonorKeyAvail) : 0;
            uint64_t headroom = 384ull << 20;                                   // leave the donor some room of its own
            uint64_t take = budget > headroom ? MIN(bytes - have, budget - headroom) : 0;
            take &= ~((uint64_t)vm_page_size - 1);
            uint64_t got = 0;
            while (got < take) {
                uint64_t len = MIN((uint64_t)ZOM_DONOR_CHUNK, take - got);
                xpc_object_t reply = ask(donor, ZomDonorOpCreate, len, 30);
                const char *e = reply ? xpc_dictionary_get_string(reply, ZomDonorKeyError) : NULL;
                xpc_object_t shmem = reply && !e ? xpc_dictionary_get_value(reply, ZomDonorKeyShmem) : NULL;
                if (!shmem || xpc_get_type(shmem) != XPC_TYPE_SHMEM) { LINE(@"RAM donor %d stopped at %llu MB (%s)\n", donorIndex + 1, got >> 20, e ?: (reply ? "no memory object" : gAskError.UTF8String)); break; }
                [gHeldShmem addObject:shmem]; [gHeldLength addObject:@(len)]; got += len;
            }
            have += got;
            LINE(@"RAM donor %d: budget %llu MB, took %llu MB\n", donorIndex + 1, budget >> 20, got >> 20);
            if (got == 0) break;
        }
        if (have >= bytes) { ok = 1; LINE(@"RAM donor: %llu MB ready from %lu donor process(es) in %.2f s\n", have >> 20, (unsigned long)gHeldExtensions.count, now_s() - t0); }
        else {
            LINE(@"RAM donor: only %llu of %llu MB available from the donors\n", have >> 20, bytes >> 20);
            for (id e in gHeldExtensions) [e _kill:SIGKILL];
            gHeldShmem = nil; gHeldLength = nil; gHeldExtensions = nil; gHeldDonors = nil;
        }
        strlcpy(msg, report.UTF8String, cap);
        return ok;
    }
}

__attribute__((used, visibility("default")))
bool zom_donor_map(char *base, size_t size) {
    uint64_t have = 0;
    for (NSNumber *n in gHeldLength) have += n.unsignedLongLongValue;
    if (!gHeldShmem.count || have < size) { printf("[donor] not enough donated memory for the heap (%llu MB of %zu MB)\n", have >> 20, size >> 20); return false; }
    uint64_t offset = 0; double t0 = now_s();
    for (NSUInteger i = 0; i < gHeldShmem.count && offset < size; i++) {
        uint64_t len = MIN(gHeldLength[i].unsignedLongLongValue, (uint64_t)size - offset);
        void *scratch = NULL; size_t got = xpc_shmem_map(gHeldShmem[i], &scratch);
        if (got < len || !scratch) { printf("[donor] xpc_shmem_map returned %zu of %llu bytes\n", got, len); return false; }
        vm_prot_t cur = 0, max = 0; mach_vm_address_t dest = (mach_vm_address_t)(uintptr_t)base + offset;
        kern_return_t kr = mach_vm_remap(mach_task_self(), &dest, len, 0, VM_FLAGS_FIXED | VM_FLAGS_OVERWRITE, mach_task_self(), (mach_vm_address_t)scratch, false, &cur, &max, VM_INHERIT_SHARE);
        mach_vm_deallocate(mach_task_self(), (mach_vm_address_t)scratch, got);
        if (kr != KERN_SUCCESS) { printf("[donor] mach_vm_remap failed at %llu MB: %s\n", offset >> 20, mach_error_string(kr)); return false; }
        offset += len;
    }
    printf("[donor] mapped %llu MB of donated memory over the Java heap at %p in %.2f s (app footprint %.0f MB)\n", offset >> 20, base, now_s() - t0, footprint_mb());
    return true;
}

