// RAM donor (Extra Memory), extension side (experimental): the helper that owns memory on behalf of the app. It is the same extension as the built-in JIT
// helper (JITHelper/ZomJITHelper.swift hands donor requests to zom_ramdonor_serve). The app starts it through the private NSExtension API; the extension's
// own auxiliary XPC channel (ZomDonorVendorContext below) carries the app's endpoint, the helper connects back and answers a few requests: allocate
// purgeable memory and hand it over as shared memory, report its own footprint, free everything.
@import Foundation;
#import <mach/mach.h>
#import <os/proc.h>
#import <objc/runtime.h>
#import <xpc/xpc.h>
#import "ZomRamDonorProtocol.h"

extern kern_return_t mach_vm_allocate(vm_map_t target, mach_vm_address_t *address, mach_vm_size_t size, int flags);
extern kern_return_t mach_vm_deallocate(vm_map_t target, mach_vm_address_t address, mach_vm_size_t size);
#ifndef VM_FLAGS_PURGABLE
#define VM_FLAGS_PURGABLE 0x2
#endif

static NSMutableArray<NSValue *> *gRegions;       // pairs: base, size


static void release_regions(void) {
    for (NSUInteger i = 0; i + 1 < gRegions.count; i += 2)
        mach_vm_deallocate(mach_task_self(), (mach_vm_address_t)(uintptr_t)gRegions[i].pointerValue, (mach_vm_size_t)(uintptr_t)gRegions[i + 1].pointerValue);
    [gRegions removeAllObjects];
}

static uint64_t own_footprint(void) {
    task_vm_info_data_t v; mach_msg_type_number_t c = TASK_VM_INFO_COUNT;
    return task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&v, &c) == KERN_SUCCESS ? v.phys_footprint : 0;
}

static xpc_object_t create_region(uint64_t size, NSString **error) {
    if (!size) { *error = @"zero-sized request"; return nil; }
    mach_vm_address_t addr = 0;
    kern_return_t kr = mach_vm_allocate(mach_task_self(), &addr, size, VM_FLAGS_ANYWHERE | VM_FLAGS_PURGABLE);
    if (kr != KERN_SUCCESS) { *error = [NSString stringWithFormat:@"mach_vm_allocate failed: %s", mach_error_string(kr)]; return nil; }
    xpc_object_t shmem = xpc_shmem_create((void *)addr, (size_t)size);
    if (!shmem) { mach_vm_deallocate(mach_task_self(), addr, size); *error = @"xpc_shmem_create failed"; return nil; }
    gRegions = gRegions ?: [NSMutableArray array];
    [gRegions addObject:[NSValue valueWithPointer:(void *)(uintptr_t)addr]];
    [gRegions addObject:[NSValue valueWithPointer:(void *)(uintptr_t)size]];
    return shmem;
}

static void handle(xpc_connection_t channel, xpc_object_t msg) {
    if (xpc_get_type(msg) != XPC_TYPE_DICTIONARY) return;
    const char *op = xpc_dictionary_get_string(msg, ZomDonorKeyOp);
    xpc_object_t reply = op ? xpc_dictionary_create_reply(msg) : NULL;
    if (!reply) return;
    if (!strcmp(op, ZomDonorOpCreate)) {
        NSString *err = nil;
        xpc_object_t shmem = create_region(xpc_dictionary_get_uint64(msg, ZomDonorKeySize), &err);
        if (shmem) xpc_dictionary_set_value(reply, ZomDonorKeyShmem, shmem);
        else xpc_dictionary_set_string(reply, ZomDonorKeyError, err.UTF8String);
    } else if (!strcmp(op, ZomDonorOpRelease)) release_regions();
    else if (!strcmp(op, ZomDonorOpAvailable)) xpc_dictionary_set_uint64(reply, ZomDonorKeyAvail, (uint64_t)os_proc_available_memory());
    else if (!strcmp(op, ZomDonorOpFootprint)) xpc_dictionary_set_uint64(reply, ZomDonorKeyFootprint, own_footprint());
    else xpc_dictionary_set_string(reply, ZomDonorKeyError, "unknown operation");
    xpc_connection_send_message(channel, reply);
}

// Ends the request with a plain status string (this form always survives the trip back to the app).
static void finish_with_status(NSExtensionContext *context, NSString *status) {
    NSExtensionItem *item = [NSExtensionItem new];
    item.userInfo = @{ ZomDonorStatusKey: status };
    [context completeRequestReturningItems:@[item] completionHandler:nil];
}

static NSExtensionContext *gOpenContext;     // keeps an unanswered request's context alive


static xpc_connection_t gChannel;     // one donor request per process; the connection stays up until the app goes away

static NSString *start_channel(xpc_endpoint_t endpoint) {
    if (!endpoint) return @"the endpoint object was empty";
    gChannel = xpc_connection_create_from_endpoint(endpoint);
    xpc_connection_set_event_handler(gChannel, ^(xpc_object_t event) {
        if (xpc_get_type(event) == XPC_TYPE_ERROR) { exit(0); }      // the app went away
        handle(gChannel, event);
    });
    xpc_connection_resume(gChannel);
    xpc_object_t hello = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(hello, ZomDonorKeyOp, "hello");
    xpc_connection_send_message(gChannel, hello);
    return @"connected";
}

// The context class of the extension (Info.plist NSExtensionContextClass): the auxiliary protocols make iOS create a real XPC channel to the app.
@interface ZomDonorVendorContext : NSExtensionContext <ZomDonorVendorProtocol>
@end
@implementation ZomDonorVendorContext
+ (id)_extensionAuxiliaryVendorProtocol { return [NSXPCInterface interfaceWithProtocol:@protocol(ZomDonorVendorProtocol)]; }
+ (id)_extensionAuxiliaryHostProtocol { return [NSXPCInterface interfaceWithProtocol:@protocol(ZomDonorHostProtocol)]; }
- (void)zomPing:(void (^)(NSString *))reply { reply([NSString stringWithFormat:@"pong from pid %d", getpid()]); }
- (void)zomConnect:(NSXPCListenerEndpoint *)endpoint reply:(void (^)(NSString *))reply { reply(start_channel(ZomUnwrapEndpoint(endpoint))); }
@end

// Called by the JIT helper extension (JITHelper/ZomJITHelper.swift) for requests that carry the donor marker.
void zom_ramdonor_serve(NSExtensionContext *context) {
    NSExtensionItem *item = (NSExtensionItem *)context.inputItems.firstObject;
    if ([item.userInfo[@"probe"] isEqual:@"open"]) { gOpenContext = context; return; }      // stay alive without answering, so the app can look at its side of the context
    finish_with_status(context, @"unexpected donor request");
}
