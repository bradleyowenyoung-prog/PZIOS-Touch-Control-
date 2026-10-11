// App extension that runs StikJIT against the main app. A process cannot debug itself (it deadlocks), so this separate process
// attaches to the game, runs the allocator script, and answers when the script has detached.
import Foundation
#if targetEnvironment(simulator)
// StikJIT only ships a real-device slice, so simulator builds (Xcode previews, simulated devices) use this inert stand-in.
private struct DDIPaths { static func `default`(in directory: URL) -> DDIPaths { DDIPaths() } }
private enum StikJIT {
    struct State { let isTXMPresent: Bool? }
    enum Readiness { case ready(State), unreachable(reason: String), preparationFailed(reason: String) }
    enum Script { case customBase64(String) }
    static let unavailable = NSError(domain: "ZomJITHelper", code: 100, userInfo: [NSLocalizedDescriptionKey: "Built-in JIT needs a physical device."])
    static var isTXMPresent: Bool? { nil }
    static func prepareDevice(pairingFile: URL, paths: DDIPaths, progress: (Any) -> Void) -> Readiness { .unreachable(reason: "Built-in JIT needs a physical device.") }
    static func enableJIT(targetPID: Int32, pairingFile: URL, ddiPaths: DDIPaths, script: Script, forceScript: Bool,
                          preparationProgress: (Any) -> Void, progress: (String) -> Void) throws { throw unavailable }
    static func resetCachedDDI(at paths: DDIPaths) throws {}
}
#else
import StikJIT
#endif

private enum Work {
    /// StikJIT's calls are synchronous and blocking; keep them on one serial queue.
    static let queue = DispatchQueue(label: (Bundle.main.bundleIdentifier ?? "pziOS.jithelper") + ".queue")

    static func handle(_ request: ZomJITRequest) -> ZomJITRequest.Response {
        let fm = FileManager.default
        let root = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("StikJIT", isDirectory: true)
        let paths = DDIPaths.default(in: root)
        func fail(_ message: String) -> ZomJITRequest.Response { .init(success: false, message: message, txmPresent: StikJIT.isTXMPresent) }

        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            if request.operation == .resetDDI {
                try StikJIT.resetCachedDDI(at: paths)
                return .init(success: true, message: "Developer Disk Image cache reset.", txmPresent: StikJIT.isTXMPresent)
            }
            guard let pairing = request.pairingData, !pairing.isEmpty else { return fail("No pairing file was provided.") }
            let pairingURL = root.appendingPathComponent("pairing-\(UUID().uuidString).plist")
            try pairing.write(to: pairingURL, options: .atomic)
            defer { try? fm.removeItem(at: pairingURL) }          // the pairing file is secret: never keep or log it

            switch request.operation {
            case .prepare:
                switch StikJIT.prepareDevice(pairingFile: pairingURL, paths: paths, progress: { NSLog("[ZomJIT] prepare: %@", String(describing: $0)) }) {
                case .ready(let state): return .init(success: true, message: "LocalDevVPN is reachable and the Developer Disk Image is ready.", txmPresent: state.isTXMPresent)
                case .unreachable(let reason), .preparationFailed(let reason): return fail(reason)
                @unknown default: return fail("StikJIT returned an unknown preparation state.")
                }
            case .enable:
                guard let pid = request.targetPID, let script = request.scriptBase64, !script.isEmpty else { return fail("The target process or script was not provided.") }
                try StikJIT.enableJIT(targetPID: pid, pairingFile: pairingURL, ddiPaths: paths, script: .customBase64(script), forceScript: true,
                                      preparationProgress: { NSLog("[ZomJIT] prepare: %@", String(describing: $0)) },
                                      progress: { NSLog("[ZomJIT] %@", $0) })
                return .init(success: true, message: "JIT enabled; the debugger detached cleanly.", txmPresent: StikJIT.isTXMPresent)
            case .resetDDI:
                return fail("unreachable")
            }
        } catch {
            return fail(error.localizedDescription)
        }
    }
}

/// NSExtensionPrincipalClass. The request arrives as JSON in the first input item; the answer goes back the same way. An enable request
/// completes only when the script has detached, so this process lives as long as the debugger does.
@objc(ZomJITHelperHandler)
final class ZomJITHelperHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let data = (context.inputItems.first as? NSExtensionItem)?.userInfo?[ZomJITRequest.itemKey] as? Data
        Work.queue.async {
            let response: ZomJITRequest.Response
            if let data, let request = try? JSONDecoder().decode(ZomJITRequest.self, from: data) {
                response = Work.handle(request)
            } else {
                response = .init(success: false, message: "The JIT helper received no request.", txmPresent: nil)
            }
            let item = NSExtensionItem()
            item.userInfo = [ZomJITRequest.Response.itemKey: (try? JSONEncoder().encode(response)) ?? Data()]
            context.completeRequest(returningItems: [item], completionHandler: nil)
        }
    }
}
