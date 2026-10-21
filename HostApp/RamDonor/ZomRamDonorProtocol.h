// Messages between the app and its RAM donor extension (Extra Memory, experimental).
//
// The idea under test: the memory limit iOS enforces is per process. A second process (the donor, an app extension) allocates purgeable memory
// and shares it with the app over XPC; the app maps it into its own address space. If iOS charges those pages to the donor instead of the app,
// the app's footprint stays lower. This header is the wire format; the code is in Sources/RamDonorHost.m and RamDonor/ZomRamDonor.m.
#ifndef ZOM_RAM_DONOR_PROTOCOL_H
#define ZOM_RAM_DONOR_PROTOCOL_H

@import Foundation;
#import <xpc/xpc.h>

#define ZOM_DONOR_CHUNK (256ull * 1024ull * 1024ull)

// request keys / reply keys
#define ZomDonorKeyOp        "op"
#define ZomDonorKeySize      "size"
#define ZomDonorKeyShmem     "shmem"
#define ZomDonorKeyError     "error"
#define ZomDonorKeyAvail     "available"      // os_proc_available_memory() inside the donor
#define ZomDonorKeyFootprint "footprint"      // phys_footprint of the donor

// operations
#define ZomDonorOpCreate     "create"         // allocate `size` bytes of purgeable memory, reply with it as xpc shared memory
#define ZomDonorOpRelease    "release"        // free everything the donor allocated
#define ZomDonorOpAvailable  "available"
#define ZomDonorOpFootprint  "footprint"

// userInfo key of the extension request that carries the XPC endpoint
#define ZomDonorEndpointKey  @"endpoint"
// userInfo key of the extension's answer when it could not connect (a plain status string for diagnosis)
#define ZomDonorStatusKey    @"status"

// Auxiliary NSXPC protocols (the extension's own channel to the app, created by iOS for custom NSExtensionContext subclasses; see Info.plist keys
// NSExtensionContextClass / NSExtensionContextHostClass of the JIT helper and the two context classes in ZomRamDonor.m and RamDonorHost.m).
NS_ASSUME_NONNULL_BEGIN
@protocol ZomDonorVendorProtocol <NSObject>       // implemented by the context inside the extension, called by the app
- (void)zomPing:(void (^)(NSString *))reply;
- (void)zomConnect:(NSXPCListenerEndpoint *)endpoint reply:(void (^)(NSString *))reply;
@end
@protocol ZomDonorHostProtocol <NSObject>         // implemented by the context inside the app, called by the extension
- (void)zomHello:(NSString *)text;
@end
NS_ASSUME_NONNULL_END

NS_ASSUME_NONNULL_BEGIN
// An XPC endpoint travels inside an NSXPCListenerEndpoint; the xpc object sits in a private property.
@interface NSXPCListenerEndpoint (ZomPrivate)
@property (nonatomic, setter=_setEndpoint:) xpc_object_t _endpoint;
@end
static inline NSXPCListenerEndpoint *ZomWrapEndpoint(xpc_endpoint_t endpoint) {
    NSXPCListenerEndpoint *w = [NSXPCListenerEndpoint new];
    w._endpoint = endpoint;
    return w;
}
static inline xpc_endpoint_t _Nullable ZomUnwrapEndpoint(NSXPCListenerEndpoint *_Nullable w) {
    xpc_object_t inner = w._endpoint;
    return (inner && xpc_get_type(inner) == XPC_TYPE_ENDPOINT) ? (xpc_endpoint_t)inner : nil;
}
NS_ASSUME_NONNULL_END

#endif
