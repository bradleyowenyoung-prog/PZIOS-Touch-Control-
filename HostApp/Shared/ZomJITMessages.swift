// Messages exchanged between the app and its JIT helper extension. Each travels as JSON in an extension request item's userInfo.
import Foundation

struct ZomJITRequest: Codable, Sendable {
    static let itemKey = "zomios-jit-request"

    enum Operation: String, Codable, Sendable { case prepare, enable, resetDDI }

    let operation: Operation
    let targetPID: Int32?
    let pairingData: Data?
    let scriptBase64: String?

    struct Response: Codable, Sendable {
        static let itemKey = "zomios-jit-response"
        let success: Bool
        let message: String
        let txmPresent: Bool?
    }
}
