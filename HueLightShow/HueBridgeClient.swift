import Foundation

enum HueBridgeError: LocalizedError {
    case invalidBridgeAddress
    case bridgeButtonRequired
    case bridgeNotPaired
    case badResponse(Int)
    case hueError(String)
    case noLightsFound
    case couldNotReadResponse

    var errorDescription: String? {
        switch self {
        case .invalidBridgeAddress:
            return "Enter a valid Hue Bridge address."
        case .bridgeButtonRequired:
            return "Press the Hue Bridge button, then tap Pair again."
        case .bridgeNotPaired:
            return "Pair with the Hue Bridge first."
        case .badResponse(let statusCode):
            return "Hue Bridge returned HTTP \(statusCode)."
        case .hueError(let message):
            return message
        case .noLightsFound:
            return "No Hue lights were returned by the bridge."
        case .couldNotReadResponse:
            return "The Hue Bridge response could not be read."
        }
    }
}

final class HueBridgeClient: NSObject, URLSessionDelegate {
    static let shared = HueBridgeClient()

    private let trustedHostLock = NSLock()
    private var trustedBridgeHosts: Set<String> = []

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 18
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func discoverBridges() async throws -> [HueBridge] {
        guard let url = URL(string: "https://discovery.meethue.com/") else {
            throw HueBridgeError.invalidBridgeAddress
        }
        let data = try await send(URLRequest(url: url))
        return try JSONDecoder().decode([HueBridge].self, from: data)
    }

    func createUser(bridgeAddress: String) async throws -> String {
        let body = ["devicetype": "HueLightShow#iPhone"]
        let data = try await sendBridgeRequest(
            bridgeAddress: bridgeAddress,
            path: "/api",
            method: "POST",
            jsonObject: body
        )
        let response = try JSONDecoder().decode([HueCreateUserEnvelope].self, from: data)

        if let username = response.compactMap({ $0.success?.username }).first {
            return username
        }

        if let error = response.compactMap({ $0.error }).first {
            if error.type == 101 {
                throw HueBridgeError.bridgeButtonRequired
            }
            throw HueBridgeError.hueError(error.description)
        }

        throw HueBridgeError.couldNotReadResponse
    }

    func fetchLights(bridgeAddress: String, username: String) async throws -> [HueLight] {
        let data = try await sendBridgeRequest(
            bridgeAddress: bridgeAddress,
            path: "/api/\(username)/lights",
            method: "GET",
            jsonObject: nil
        )

        do {
            let payload = try JSONDecoder().decode([String: HueLightPayload].self, from: data)
            let lights = payload.map { id, light in
                HueLight(id: id, name: light.name, type: light.type, state: light.state)
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

            if lights.isEmpty {
                throw HueBridgeError.noLightsFound
            }
            return lights
        } catch let bridgeError as HueBridgeError {
            throw bridgeError
        } catch {
            if let hueError = try? decodeFirstHueError(from: data) {
                throw hueError
            }
            throw HueBridgeError.couldNotReadResponse
        }
    }

    func setLight(
        bridgeAddress: String,
        username: String,
        lightID: String,
        color: HueBridgeColor,
        transitionSeconds: Double
    ) async throws {
        let transitionTime = max(1, min(600, Int((transitionSeconds * 10.0).rounded())))
        let body: [String: Any] = [
            "on": true,
            "hue": color.hue,
            "sat": color.saturation,
            "bri": color.brightness,
            "transitiontime": transitionTime
        ]
        let data = try await sendBridgeRequest(
            bridgeAddress: bridgeAddress,
            path: "/api/\(username)/lights/\(lightID)/state",
            method: "PUT",
            jsonObject: body
        )
        try validateHueCommandResponse(data)
    }

    private func sendBridgeRequest(
        bridgeAddress: String,
        path: String,
        method: String,
        jsonObject: Any?
    ) async throws -> Data {
        let url = try bridgeURL(for: bridgeAddress, path: path)
        rememberTrustedHost(from: url)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let jsonObject = jsonObject {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonObject)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HueBridgeError.couldNotReadResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HueBridgeError.badResponse(httpResponse.statusCode)
        }
        return data
    }

    private func bridgeURL(for bridgeAddress: String, path: String) throws -> URL {
        let trimmed = bridgeAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HueBridgeError.invalidBridgeAddress
        }

        let addressWithScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: addressWithScheme), components.host != nil else {
            throw HueBridgeError.invalidBridgeAddress
        }
        components.path = path
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw HueBridgeError.invalidBridgeAddress
        }
        return url
    }

    private func validateHueCommandResponse(_ data: Data) throws {
        let response = try JSONDecoder().decode([HueCommandEnvelope].self, from: data)
        if let error = response.compactMap({ $0.error }).first {
            throw HueBridgeError.hueError(error.description)
        }
    }

    private func decodeFirstHueError(from data: Data) throws -> HueBridgeError {
        let response = try JSONDecoder().decode([HueCommandEnvelope].self, from: data)
        if let error = response.compactMap({ $0.error }).first {
            if error.type == 1 {
                return .bridgeNotPaired
            }
            return .hueError(error.description)
        }
        return .couldNotReadResponse
    }

    private func rememberTrustedHost(from url: URL) {
        guard let host = url.host else {
            return
        }
        trustedHostLock.lock()
        trustedBridgeHosts.insert(host.lowercased())
        trustedHostLock.unlock()
    }

    private func shouldTrustBridgeHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        trustedHostLock.lock()
        let hasRememberedHost = trustedBridgeHosts.contains(normalized)
        trustedHostLock.unlock()

        return hasRememberedHost || normalized.hasSuffix(".local") || isPrivateIPv4Host(normalized)
    }

    private func isPrivateIPv4Host(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else {
            return false
        }

        if parts[0] == 10 {
            return true
        }
        if parts[0] == 172 && (16...31).contains(parts[1]) {
            return true
        }
        if parts[0] == 192 && parts[1] == 168 {
            return true
        }
        if parts[0] == 169 && parts[1] == 254 {
            return true
        }
        return false
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust,
            shouldTrustBridgeHost(challenge.protectionSpace.host)
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

private struct HueCreateUserEnvelope: Decodable {
    let success: HueCreateUserSuccess?
    let error: HueAPIError?
}

private struct HueCreateUserSuccess: Decodable {
    let username: String
}

private struct HueCommandEnvelope: Decodable {
    let error: HueAPIError?
}

private struct HueAPIError: Decodable {
    let type: Int?
    let address: String?
    let description: String
}

private struct HueLightPayload: Decodable {
    let name: String
    let type: String
    let state: HueLightState
}
