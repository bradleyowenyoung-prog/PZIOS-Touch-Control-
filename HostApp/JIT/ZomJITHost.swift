// Host side of built-in JIT: starts the helper extension and asks it to attach to this process. ObjC calls startIfSelected() before the
// JVM requests its code region; the existing wait-for-debugger loop then proceeds as it does with an external StikDebug.
import Foundation
import UIKit

/// The private NSExtension API (ExtensionFoundation) used to start an app extension that belongs to this app.
@objc private protocol NSExtensionClassShim {
    @objc(extensionWithIdentifier:error:) func `extension`(withIdentifier identifier: String) throws -> AnyObject
}
@objc private protocol NSExtensionShim {
    @objc(beginExtensionRequestWithInputItems:completion:) func beginExtensionRequest(withInputItems items: [Any], completion: @escaping (NSUUID?) -> Void)
    @objc(pidForRequestIdentifier:) func pid(forRequestIdentifier identifier: NSUUID) -> Int32
    @objc(setRequestCompletionBlock:) func setRequestCompletionBlock(_ block: @escaping (NSUUID?, [Any]?) -> Void)
    @objc(setRequestCancellationBlock:) func setRequestCancellationBlock(_ block: @escaping (NSUUID?, NSError?) -> Void)
    @objc(setRequestInterruptionBlock:) func setRequestInterruptionBlock(_ block: @escaping (NSUUID?) -> Void)
}

@objc(ZomJITHost)
public final class ZomJITHost: NSObject {
    static let helperFile = "ZomJITHelper.appex"
    /// The classic JIT path (no debugger-provided memory): iOS older than 19 unless the preference zom.classicJIT says otherwise (1 force on, 0 force off).
    static var usesClassicJIT: Bool {
        let forced = UserDefaults.standard.object(forKey: "zom.classicJIT") as? Int
        let old = !ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 19, minorVersion: 0, patchVersion: 0))
        return forced.map { $0 == 1 } ?? old
    }
    static let methodKey = "zom.jitMethod"            // 0 manual (external StikDebug script), 1 built-in StikJIT
    @objc public static var failureMessage: String?    // set when the helper fails; the launcher stops waiting for a debugger

    private static var running: [Request] = []

    static var unavailableReason: String? {
        guard #available(iOS 17.4, *) else { return "Built-in JIT needs iOS 17.4 or later." }
        if getenv("LC_HOME_PATH") != nil { return "Built-in JIT is unavailable inside LiveContainer." }
        if helperIdentifier == nil { return "The JIT helper is missing from this install." }
        return nil
    }
    /// One line for the top of jvm.log: which helper this install has and which JIT path is selected.
    @objc public static var diagnosticSummary: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let ver = "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["PZReleaseLabel"] as? String ?? "?")) build \(info["CFBundleVersion"] as? String ?? "?")"
        let method = UserDefaults.standard.integer(forKey: methodKey) == 1 ? "built-in" : "manual"
        let plugin = Bundle.main.builtInPlugInsURL?.appendingPathComponent(helperFile).path
        let present = plugin.map { FileManager.default.fileExists(atPath: $0) } ?? false
        return "app: \(Bundle.main.bundleIdentifier ?? "?"), version \(ver), JIT method \(method), helper \(helperIdentifier ?? "none") (\(present ? "present" : "missing")), pairing file \(PairingStore.exists ? "yes" : "no"), LiveContainer \(getenv("LC_HOME_PATH") != nil ? "yes" : "no")"
    }
    static var helperIdentifier: String? {
        guard let url = Bundle.main.builtInPlugInsURL?.appendingPathComponent(helperFile) else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    // MARK: launcher glue

    /// Called from launchJVM (any thread). Returns YES when a built-in JIT request was started.
    @objc public static func startIfSelected() -> Bool {
        guard UserDefaults.standard.integer(forKey: methodKey) == 1 else { return false }
        failureMessage = nil
        if let reason = unavailableReason { failureMessage = reason; return true }
        guard let pairing = PairingStore.load(), !pairing.isEmpty else {
            failureMessage = "No pairing file. Import one in Settings > JIT."; return true
        }
        guard let scriptURL = Bundle.main.url(forResource: "pzios-jvm", withExtension: "js"), var script = try? Data(contentsOf: scriptURL) else {
            failureMessage = "The bundled JIT script is missing."; return true
        }
        // iOS 17 and 18 (or zom.classicJIT forced on) run the JVM's classic JIT path, which never asks the debugger for memory. The script must then attach and
        // let go at once: left attached it would stop on every page-protection fault the JVM handles itself, which makes the game many times slower.
        if Self.usesClassicJIT, var text = String(data: script, encoding: .utf8) {
            text = text.replacingOccurrences(of: "const EXPECTED_REQUESTS = 1;", with: "const EXPECTED_REQUESTS = 0;")
            script = Data(text.utf8)
        }
        let request = ZomJITRequest(operation: .enable, targetPID: getpid(), pairingData: pairing, scriptBase64: script.base64EncodedString())
        DispatchQueue.main.async {
            send(request) { result in
                switch result {
                case .success(let r):
                    print("[jit-helper] enable: \(r.success ? "ok" : "FAILED") - \(r.message)")
                    if !r.success { failureMessage = r.message }
                case .failure(let e):
                    print("[jit-helper] enable: FAILED - \(e.localizedDescription)")
                    failureMessage = e.localizedDescription
                }
            }
        }
        return true
    }

    /// Wires the settings screen's actions.
    @objc(attachToModel:) public static func attach(to model: LauncherModel) {
        PairingStore.migrateLegacyFile()
        model.jitAvailable = unavailableReason == nil
        model.jitUnavailableReason = unavailableReason ?? ""
        func refresh(_ status: String? = nil) {
            model.hasPairing = PairingStore.exists
            model.pairingStatus = status ?? (model.hasPairing ? "Pairing file saved (in the Keychain)" : "No pairing file")
        }
        refresh()
        model.onImportPairing = { url in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard !data.isEmpty, (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil else {
                    refresh("That file isn't a valid pairing file."); return
                }
                guard PairingStore.save(data) else { refresh("Couldn't save the pairing file to the Keychain."); return }
                refresh("Pairing file imported")
            } catch { refresh("Import failed: \(error.localizedDescription)") }
        }
        model.onPrepareJIT = {
            guard let pairing = PairingStore.load() else { model.jitStatus = "No pairing file."; return }
            model.jitStatus = "Checking LocalDevVPN and the Developer Disk Image..."
            send(ZomJITRequest(operation: .prepare, targetPID: nil, pairingData: pairing, scriptBase64: nil)) { result in
                switch result {
                case .success(let r): model.jitStatus = (r.success ? "Ready. " : "Not ready: ") + r.message
                case .failure(let e): model.jitStatus = "Not ready: \(e.localizedDescription)"
                }
            }
        }
        model.onResetDDI = {
            send(ZomJITRequest(operation: .resetDDI, targetPID: nil, pairingData: nil, scriptBase64: nil)) { result in
                if case .success(let r) = result { model.jitStatus = r.message } else if case .failure(let e) = result { model.jitStatus = e.localizedDescription }
            }
        }
    }

    // MARK: extension request

    static func send(_ request: ZomJITRequest, completion: @escaping (Result<ZomJITRequest.Response, Error>) -> Void) {
        func fail(_ code: Int, _ message: String) {
            completion(.failure(NSError(domain: "ZomJITHost", code: code, userInfo: [NSLocalizedDescriptionKey: message])))
        }
        guard let identifier = helperIdentifier else { return fail(1, "The JIT helper is missing from this install (error 1). The app was probably installed without its extensions; reinstall keeping app extensions, or use StikDebug.") }
        if NSClassFromString("NSExtension") == nil { dlopen("/System/Library/Frameworks/ExtensionFoundation.framework/ExtensionFoundation", RTLD_NOW) }
        guard let cls = NSClassFromString("NSExtension") else { return fail(2, "iOS did not provide the extension API the JIT helper needs (error 2). Use StikDebug instead.") }
        let found: AnyObject
        do { found = try unsafeBitCast(cls as AnyObject, to: NSExtensionClassShim.self).extension(withIdentifier: identifier) }
        catch { return fail(3, "The JIT helper (\(identifier)) could not be found (error 3): \(error.localizedDescription). The sideloading tool may have changed the bundle ID of the app but not of the helper; reinstall, or use StikDebug.") }
        guard let data = try? JSONEncoder().encode(request) else { return fail(4, "The JIT request could not be encoded.") }
        let req = Request(extension: found, operation: request.operation.rawValue, completion: completion)
        running.append(req)
        req.begin(data: data, identifier: identifier)
    }

    fileprivate static func finished(_ r: Request) { running.removeAll { $0 === r } }

    fileprivate final class Request {
        private let shim: NSExtensionShim
        private let ext: AnyObject
        private let operation: String
        private var completion: ((Result<ZomJITRequest.Response, Error>) -> Void)?

        init(extension found: AnyObject, operation: String, completion: @escaping (Result<ZomJITRequest.Response, Error>) -> Void) {
            ext = found; shim = unsafeBitCast(found, to: NSExtensionShim.self); self.operation = operation; self.completion = completion
        }

        func begin(data: Data, identifier: String) {
            shim.setRequestCompletionBlock { [weak self] _, items in
                let payload = ((items?.first as? NSExtensionItem)?.userInfo)?[ZomJITRequest.Response.itemKey] as? Data
                DispatchQueue.main.async { self?.returned(payload) }
            }
            shim.setRequestCancellationBlock { [weak self] _, error in
                let message = error?.localizedDescription ?? "the request was cancelled"
                DispatchQueue.main.async { self?.end(.failure(Self.error(5, "The JIT helper stopped: \(message)"))) }
            }
            shim.setRequestInterruptionBlock { [weak self] _ in
                DispatchQueue.main.async { self?.end(.failure(Self.error(6, "The JIT helper stopped unexpectedly."))) }
            }
            let item = NSExtensionItem()
            item.userInfo = [ZomJITRequest.itemKey: data]
            shim.beginExtensionRequest(withInputItems: [item]) { [weak self] uuid in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard let uuid else { self.end(.failure(Self.error(7, "iOS would not start the JIT helper (error 7). The sideloading tool may have removed or not signed it, or changed the bundle ID. Reinstall keeping app extensions, or use StikDebug with the script from the README."))); return }
                    print("[jit-helper] \(self.operation): started \(identifier) as pid \(self.shim.pid(forRequestIdentifier: uuid))")
                }
            }
        }

        private func returned(_ payload: Data?) {
            guard let payload, let response = try? JSONDecoder().decode(ZomJITRequest.Response.self, from: payload) else {
                end(.failure(Self.error(8, "The JIT helper finished without an answer."))); return
            }
            end(.success(response))
        }
        private func end(_ result: Result<ZomJITRequest.Response, Error>) {
            guard let completion else { return }       // the first result counts
            self.completion = nil
            ZomJITHost.finished(self)
            completion(result)
        }
        private static func error(_ code: Int, _ message: String) -> NSError {
            NSError(domain: "ZomJITHost", code: code, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
