//
//  ListenerAPI.swift
//  Listener
//
//  Created by jamie baddeley on 10/04/2026.
//

import Foundation

/// Actor wrapping every endpoint of the MixMates Listener API.
///
/// One method per endpoint, all `async throws`. Authentication, error envelope
/// decoding, rate-limit parsing, and 401 → sign-out are all handled centrally
/// in `request(...)` so call sites stay tiny.
///
/// The actor depends on an `HTTPClient` rather than a concrete `URLSession`
/// so tests can substitute a `StubHTTPClient` without going through
/// `URLProtocol`. Production wires `URLSession.shared` by default.
actor ListenerAPI {

    static let defaultBaseURL = URL(string: "https://mixmat.es/api/v1/listener")!

    let baseURL: URL
    let client: HTTPClient
    let tokenProvider: @Sendable () async -> String?
    let onUnauthorized: @Sendable () async -> Void

    init(
        baseURL: URL = ListenerAPI.defaultBaseURL,
        client: HTTPClient = URLSession.shared,
        tokenProvider: @Sendable @escaping () async -> String?,
        onUnauthorized: @Sendable @escaping () async -> Void = {}
    ) {
        self.baseURL = baseURL
        self.client = client
        self.tokenProvider = tokenProvider
        self.onUnauthorized = onUnauthorized
    }

    // MARK: - Endpoints

    func health() async throws -> HealthDTO {
        try await request(path: "health", method: "GET", authenticated: false)
    }

    func me() async throws -> UserProfile {
        let dto: UserDTO = try await request(path: "auth/me", method: "GET")
        return UserProfile(dto: dto)
    }

    func recognize(audio: Data, mimeType: String, filename: String = "recording.m4a") async throws -> RecognitionResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".utf8Data)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".utf8Data)
        body.append("Content-Type: \(mimeType)\r\n\r\n".utf8Data)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".utf8Data)

        let dto: RecognizeDTO = try await request(
            path: "recognize",
            method: "POST",
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        return RecognitionResult(dto: dto)
    }

    func history(cursor: String? = nil, limit: Int? = nil) async throws -> HistoryList {
        var query: [URLQueryItem] = []
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        let dto: HistoryListDTO = try await request(path: "history", method: "GET", query: query)
        return HistoryList(dto: dto)
    }

    func historyDetail(id: String) async throws -> HistoryDetail {
        let dto: HistoryDetailDTO = try await request(path: "history/\(id)", method: "GET")
        return HistoryDetail(dto: dto)
    }

    func deleteHistory(id: String) async throws {
        let _: DeletedDTO = try await request(path: "history/\(id)", method: "DELETE")
    }

    func reportHistory(id: String, reason: String? = nil) async throws {
        struct ReportBody: Encodable { let reason: String? }
        let body = try JSONEncoder().encode(ReportBody(reason: reason))
        let _: ReportedDTO = try await request(
            path: "history/\(id)/report",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
    }

    func shareHistory(id: String, groupIds: [String]) async throws -> ShareOutcome {
        let body = try JSONEncoder().encode(ShareRequestDTO(groupIds: groupIds))
        let dto: ShareDataDTO = try await request(
            path: "history/\(id)/share",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        return ShareOutcome(dto: dto)
    }

    func resolve(url: URL) async throws -> RecognitionResult {
        struct ResolveBody: Encodable { let url: String }
        let body = try JSONEncoder().encode(ResolveBody(url: url.absoluteString))
        let dto: RecognizeDTO = try await request(
            path: "resolve",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        return RecognitionResult(dto: dto)
    }

    func groups() async throws -> [HumanGroup] {
        let dto: HumanGroupListDTO = try await request(path: "groups", method: "GET")
        return dto.items.map(HumanGroup.init(dto:))
    }

    func recordings() async throws -> [Recording] {
        let dto: RecordingListDTO = try await request(path: "recordings", method: "GET")
        return dto.items.map(Recording.init(dto:))
    }

    func deleteRecordings() async throws -> Int {
        let dto: DeletedCountDTO = try await request(path: "recordings", method: "DELETE")
        return dto.deleted
    }

    // MARK: - Request plumbing

    /// Build the request, send it, and turn the response into either a decoded
    /// `T` or an `APIError`. This is the only place that touches `HTTPClient`,
    /// so retries, logging, or interceptors can be added in one spot.
    private func request<T: Decodable>(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        let urlRequest = try await buildRequest(
            path: path,
            method: method,
            query: query,
            body: body,
            contentType: contentType,
            authenticated: authenticated
        )

        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await client.send(urlRequest)
        } catch let error as URLError {
            throw APIError.network(error)
        }

        switch http.statusCode {
        case 200..<300:
            do {
                let envelope = try JSONDecoder().decode(APIResponse<T>.self, from: data)
                return envelope.data
            } catch let error as DecodingError {
                throw APIError.decoding(String(describing: error))
            }

        case 401:
            let payload = decodeErrorPayload(data)
            await onUnauthorized()
            throw APIError.unauthorized(payload: payload)

        case 429:
            let retryAfter = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
            let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init)
            throw APIError.rateLimited(retryAfter: retryAfter, remaining: remaining)

        case 502:
            throw APIError.recognitionUnavailable

        default:
            throw APIError.http(status: http.statusCode, payload: decodeErrorPayload(data))
        }
    }

    private func buildRequest(
        path: String,
        method: String,
        query: [URLQueryItem],
        body: Data?,
        contentType: String?,
        authenticated: Bool
    ) async throws -> URLRequest {
        var url = baseURL.appendingPathComponent(path)
        if !query.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw APIError.unexpected("Could not build URL components for \(url)")
            }
            components.queryItems = query
            guard let composed = components.url else {
                throw APIError.unexpected("Could not assemble URL with query items")
            }
            url = composed
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.httpBody = body
        }
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if authenticated, let token = await tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func decodeErrorPayload(_ data: Data) -> APIErrorPayload? {
        try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error
    }
}

private extension String {
    var utf8Data: Data { Data(utf8) }
}
