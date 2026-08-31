import Foundation

public enum OriginError: Error, Equatable { case invalidOrigin }
public enum SafeOrigin {
    public static func validate(_ string: String) -> URL? {
        guard let url = URL(string: string), url.path == "" || url.path == "/", url.query == nil, url.fragment == nil, let host = url.host?.lowercased() else { return nil }
        if url.scheme == "http", host == "localhost" || host == "127.0.0.1" || host == "::1" { return url }
        if url.scheme == "https", host.hasSuffix(".ts.net") || (!host.contains(".") && !host.isEmpty) { return url }
        return nil
    }
}

public struct TychoClient: Sendable {
    public let origin: URL; private let token: String; private let session: URLSession
    public init(origin: URL, token: String, session: URLSession = .shared) throws { guard SafeOrigin.validate(origin.absoluteString) != nil else { throw OriginError.invalidOrigin }; self.origin = origin; self.token = token; self.session = session }
    public func activity() async throws -> ActivityCatalog { try await get("/servers/activity") }
    public func resources() async throws -> Data { try await rawGet("/servers/resources") }
    private func get<T: Decodable>(_ path: String) async throws -> T { let data = try await rawGet(path); let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return try decoder.decode(T.self, from: data) }
    private func rawGet(_ path: String) async throws -> Data { var request = URLRequest(url: origin.appending(path: path)); request.httpMethod = "GET"; request.timeoutInterval = 10; if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }; let (data, response) = try await session.data(for: request); guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }; return data }
}
