import Foundation
import Network

public enum WizError: LocalizedError, Equatable {
    case invalidAddress(String)
    case timeout(ip: String, detail: String?)
    case network(String)
    case rejected(String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .invalidAddress(let ip): return "\"\(ip)\" is not an IP address."
        case .timeout(_, let detail): return detail.map { "No answer from the bulb (\($0))." } ?? "No answer from the bulb."
        case .network(let message): return message
        case .rejected(let message): return "The bulb rejected the command: \(message)"
        case .badResponse: return "The bulb sent a reply WizBar could not read."
        }
    }

    /// macOS blocks LAN traffic for apps without Local Network permission, which
    /// surfaces as "no route to host" rather than a permission error.
    public var mayBeLocalNetworkPermission: Bool {
        switch self {
        case .timeout(_, let detail?), .network(let detail):
            let d = detail.lowercased()
            return d.contains("no route") || d.contains("policy") || d.contains("unreachable") || d.contains("not permitted")
        default:
            return false
        }
    }
}

public struct SystemInfo: Equatable, Sendable {
    public var module: String?
    public var firmware: String?
    public var mac: String?
}

/// Stateless WiZ UDP client (port 38899). Each request opens a connected UDP
/// socket, sends up to three copies 150 ms apart, and takes the first reply
/// whose `method` matches.
public final class WizClient: Sendable {
    public static let port: UInt16 = 38899
    public let timeout: TimeInterval

    public init(timeout: TimeInterval = 2.0) {
        self.timeout = timeout
    }

    public func getPilot(ip: String) async throws -> BulbState {
        let reply = try await request(ip: ip, method: "getPilot", params: [:])
        guard let result = reply["result"] as? [String: Any], let state = BulbState(pilot: result) else {
            throw WizError.badResponse
        }
        return state
    }

    public func setPilot(ip: String, change: PilotChange) async throws {
        let reply = try await request(ip: ip, method: "setPilot", params: change.params)
        if let result = reply["result"] as? [String: Any], result["success"] as? Bool == false {
            throw WizError.rejected("success: false")
        }
    }

    public func systemInfo(ip: String) async throws -> SystemInfo {
        let reply = try await request(ip: ip, method: "getSystemConfig", params: [:])
        let result = reply["result"] as? [String: Any] ?? [:]
        return SystemInfo(
            module: result["moduleName"] as? String,
            firmware: result["fwVersion"] as? String,
            mac: result["mac"] as? String
        )
    }

    func request(ip: String, method: String, params: [String: Any]) async throws -> [String: Any] {
        let trimmed = ip.trimmingCharacters(in: .whitespaces)
        guard IPv4Address(trimmed) != nil else { throw WizError.invalidAddress(trimmed) }
        let payload = try JSONSerialization.data(withJSONObject: ["method": method, "params": params])
        let exchange = UDPExchange(ip: trimmed, method: method, payload: payload, timeout: timeout)
        return try await exchange.run()
    }

    /// Firmware 1.35 puts a few bytes of uninitialized memory in the `src`
    /// field of every reply. Those bytes are often invalid UTF-8, so a strict
    /// JSON parse rejects many replies. The value is cut out before parsing;
    /// WizBar never reads `src`.
    public static func parseReply(_ data: Data) -> [String: Any]? {
        var bytes = [UInt8](data)
        let open = Array(#""src":""#.utf8)
        if let start = bytes.firstRange(of: open)?.upperBound {
            let rest = bytes[start...]
            // The value ends where the next field or the object begins.
            if let end = rest.firstRange(of: Array(#"",""#.utf8))?.lowerBound ?? rest.firstRange(of: Array(#""}"#.utf8))?.lowerBound {
                bytes.removeSubrange(start..<end)
            }
        }
        return try? JSONSerialization.jsonObject(with: Data(bytes)) as? [String: Any]
    }
}

/// One request/response round trip. All mutable state lives on `queue`.
private final class UDPExchange: @unchecked Sendable {
    private let ip: String
    private let method: String
    private let payload: Data
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "wizbar.udp")
    private let connection: NWConnection

    private var continuation: CheckedContinuation<[String: Any], Error>?
    private var sends = 0
    private var lastIssue: String?

    init(ip: String, method: String, payload: Data, timeout: TimeInterval) {
        self.ip = ip
        self.method = method
        self.payload = payload
        self.timeout = timeout
        connection = NWConnection(
            host: NWEndpoint.Host(ip),
            port: NWEndpoint.Port(rawValue: WizClient.port)!,
            using: .udp
        )
    }

    func run() async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                self.connection.stateUpdateHandler = { [self] state in
                    switch state {
                    case .ready:
                        send()
                        receive()
                    case .waiting(let error):
                        lastIssue = Self.describe(error)
                    case .failed(let error):
                        finish(.failure(WizError.network(Self.describe(error))))
                    default:
                        break
                    }
                }
                self.queue.asyncAfter(deadline: .now() + self.timeout) { [self] in
                    finish(.failure(WizError.timeout(ip: ip, detail: lastIssue)))
                }
                self.connection.start(queue: self.queue)
            }
        }
    }

    private func send() {
        guard continuation != nil, sends < 3 else { return }
        sends += 1
        connection.send(content: payload, completion: .contentProcessed { [self] error in
            if let error { lastIssue = Self.describe(error) }
        })
        queue.asyncAfter(deadline: .now() + 0.15) { [self] in send() }
    }

    private func receive() {
        connection.receiveMessage { [self] data, _, _, error in
            guard continuation != nil else { return }
            if let data,
               let reply = WizClient.parseReply(data),
               reply["method"] as? String == method {
                if let error = reply["error"] {
                    finish(.failure(WizError.rejected(String(describing: error))))
                } else {
                    finish(.success(reply))
                }
                return
            }
            if let error {
                // ICMP errors land here; keep listening until the deadline.
                lastIssue = Self.describe(error)
                queue.asyncAfter(deadline: .now() + 0.05) { [self] in receive() }
                return
            }
            receive()
        }
    }

    private func finish(_ result: Result<[String: Any], Error>) {
        guard let continuation else { return }
        self.continuation = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation.resume(with: result)
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code): return String(cString: strerror(code.rawValue))
        default: return error.localizedDescription
        }
    }
}
