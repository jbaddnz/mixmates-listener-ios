//
//  ListenerAPITests.swift
//  ListenerTests
//
//  Created by jamie baddeley on 10/04/2026.
//

import Testing
import Foundation
@testable import Listener

@Suite("ListenerAPI", .serialized)
struct ListenerAPITests {

    private let baseURL = URL(string: "https://test.example/api/v1/listener")!

    init() {
        StubURLProtocol.reset()
    }

    // MARK: - Helpers

    private func makeAPI(
        token: String? = "test_token",
        onUnauthorized: @escaping @Sendable () async -> Void = {}
    ) -> ListenerAPI {
        ListenerAPI(
            baseURL: baseURL,
            session: StubURLProtocol.session(),
            tokenProvider: { token },
            onUnauthorized: onUnauthorized
        )
    }

    private func ok(_ json: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: baseURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (response, Data(json.utf8))
    }

    private func http(_ status: Int, body: String = "", headers: [String: String] = [:]) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: baseURL,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return (response, Data(body.utf8))
    }

    // MARK: - Successful requests

    @Test func healthSucceeds() async throws {
        StubURLProtocol.handler = { _ in self.ok(Fixtures.health) }
        let api = makeAPI()
        let health = try await api.health()
        #expect(health.status == "ok")
        #expect(health.version == "1")
    }

    @Test func healthDoesNotIncludeAuthHeader() async throws {
        let captured = RequestCapture()
        StubURLProtocol.handler = { req in
            captured.set(req)
            return self.ok(Fixtures.health)
        }
        let api = makeAPI()
        _ = try await api.health()
        #expect(captured.value?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func authenticatedRequestsIncludeBearerHeader() async throws {
        let captured = RequestCapture()
        StubURLProtocol.handler = { req in
            captured.set(req)
            return self.ok(Fixtures.authMe)
        }
        let api = makeAPI(token: "key_xyz")
        _ = try await api.me()
        #expect(captured.value?.value(forHTTPHeaderField: "Authorization") == "Bearer key_xyz")
    }

    @Test func meReturnsParsedProfile() async throws {
        StubURLProtocol.handler = { _ in self.ok(Fixtures.authMe) }
        let api = makeAPI()
        let profile = try await api.me()
        #expect(profile.displayName == "Jamie")
        #expect(profile.role == .paid)
        #expect(profile.rateLimit?.remaining == 17)
    }

    @Test func historySendsCursorAndLimitQueryItems() async throws {
        let captured = RequestCapture()
        StubURLProtocol.handler = { req in
            captured.set(req)
            return self.ok(Fixtures.history)
        }
        let api = makeAPI()
        _ = try await api.history(cursor: "abc", limit: 10)

        let url = try #require(captured.value?.url)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "cursor", value: "abc")))
        #expect(items.contains(URLQueryItem(name: "limit", value: "10")))
    }

    @Test func historyOmitsQueryItemsWhenNotProvided() async throws {
        let captured = RequestCapture()
        StubURLProtocol.handler = { req in
            captured.set(req)
            return self.ok(Fixtures.history)
        }
        let api = makeAPI()
        _ = try await api.history()

        let url = try #require(captured.value?.url)
        #expect(url.query == nil)
    }

    @Test func historyDetailHitsExpectedPath() async throws {
        let captured = RequestCapture()
        StubURLProtocol.handler = { req in
            captured.set(req)
            return self.ok(Fixtures.historyDetail)
        }
        let api = makeAPI()
        _ = try await api.historyDetail(id: "h_1")

        #expect(captured.value?.url?.path.hasSuffix("/history/h_1") == true)
        #expect(captured.value?.httpMethod == "GET")
    }

    @Test func deleteHistoryUsesDeleteMethod() async throws {
        let captured = RequestCapture()
        StubURLProtocol.handler = { req in
            captured.set(req)
            return self.ok(Fixtures.historyDelete)
        }
        let api = makeAPI()
        try await api.deleteHistory(id: "h_1")

        #expect(captured.value?.httpMethod == "DELETE")
        #expect(captured.value?.url?.path.hasSuffix("/history/h_1") == true)
    }

    @Test func shareHistoryPostsJSONBody() async throws {
        let captured = RequestCapture()
        StubURLProtocol.handler = { req in
            captured.set(req)
            return self.ok(Fixtures.share)
        }
        let api = makeAPI()
        let outcome = try await api.shareHistory(id: "h_1", groupIds: ["g1", "g2"])

        #expect(captured.value?.httpMethod == "POST")
        #expect(captured.value?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(outcome.results.count == 2)
    }

    @Test func recognizeUsesMultipartContentType() async throws {
        let captured = RequestCapture()
        StubURLProtocol.handler = { req in
            captured.set(req)
            return self.ok(Fixtures.recognizeSaved)
        }
        let api = makeAPI()
        let result = try await api.recognize(audio: Data([0x00, 0x01, 0x02]), mimeType: "audio/mp4")

        let contentType = captured.value?.value(forHTTPHeaderField: "Content-Type") ?? ""
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
        #expect(result.status == .saved)
    }

    // MARK: - Error handling

    @Test func unauthorized401TriggersCallbackAndThrows() async throws {
        let signal = UnauthorizedSignal()
        StubURLProtocol.handler = { _ in
            self.http(401, body: Fixtures.errorEnvelope)
        }
        let api = makeAPI(onUnauthorized: { await signal.fire() })

        do {
            _ = try await api.me()
            Issue.record("Expected unauthorized error")
        } catch let APIError.unauthorized(payload) {
            #expect(payload?.code == "auth_required")
        } catch {
            Issue.record("Got wrong error: \(error)")
        }

        #expect(await signal.fired)
    }

    @Test func rateLimited429ParsesHeaders() async throws {
        StubURLProtocol.handler = { _ in
            self.http(429, headers: ["Retry-After": "30", "X-RateLimit-Remaining": "0"])
        }
        let api = makeAPI()

        do {
            _ = try await api.me()
            Issue.record("Expected rate limit error")
        } catch let APIError.rateLimited(retryAfter, remaining) {
            #expect(retryAfter == 30)
            #expect(remaining == 0)
        } catch {
            Issue.record("Got wrong error: \(error)")
        }
    }

    @Test func rateLimited429FallsBackWhenHeadersMissing() async throws {
        StubURLProtocol.handler = { _ in self.http(429) }
        let api = makeAPI()

        do {
            _ = try await api.me()
            Issue.record("Expected rate limit error")
        } catch let APIError.rateLimited(retryAfter, remaining) {
            #expect(retryAfter == 60)
            #expect(remaining == nil)
        } catch {
            Issue.record("Got wrong error: \(error)")
        }
    }

    @Test func badGateway502BecomesRecognitionUnavailable() async throws {
        StubURLProtocol.handler = { _ in self.http(502) }
        let api = makeAPI()

        do {
            _ = try await api.recognize(audio: Data(), mimeType: "audio/mp4")
            Issue.record("Expected recognition unavailable error")
        } catch APIError.recognitionUnavailable {
            // success
        } catch {
            Issue.record("Got wrong error: \(error)")
        }
    }

    @Test func http400PreservesParsedPayload() async throws {
        StubURLProtocol.handler = { _ in
            self.http(400, body: #"{"error":{"code":"audio_too_large","message":"Audio file exceeds 5MB limit"}}"#)
        }
        let api = makeAPI()

        do {
            _ = try await api.recognize(audio: Data(), mimeType: "audio/mp4")
            Issue.record("Expected http error")
        } catch let APIError.http(status, payload) {
            #expect(status == 400)
            #expect(payload?.code == "audio_too_large")
            #expect(payload?.message == "Audio file exceeds 5MB limit")
        } catch {
            Issue.record("Got wrong error: \(error)")
        }
    }

    @Test func networkFailureBecomesNetworkError() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let api = makeAPI()

        do {
            _ = try await api.me()
            Issue.record("Expected network error")
        } catch APIError.network {
            // success
        } catch {
            Issue.record("Got wrong error: \(error)")
        }
    }

    @Test func malformedJSONBecomesDecodingError() async throws {
        StubURLProtocol.handler = { _ in self.ok("{not valid json}") }
        let api = makeAPI()

        do {
            _ = try await api.me()
            Issue.record("Expected decoding error")
        } catch APIError.decoding {
            // success
        } catch {
            Issue.record("Got wrong error: \(error)")
        }
    }
}

// MARK: - Test helpers

/// Captures a single URLRequest from inside a stub handler so the test
/// can inspect what the API client actually sent. Reference type so the
/// closure mutation is visible to the test scope.
private final class RequestCapture: @unchecked Sendable {
    private(set) var value: URLRequest?
    func set(_ request: URLRequest) { value = request }
}

/// Async signal so a `@Sendable () async -> Void` callback can flip a flag
/// the test can later assert on.
private actor UnauthorizedSignal {
    private(set) var fired = false
    func fire() { fired = true }
}
