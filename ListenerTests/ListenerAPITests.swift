//
//  ListenerAPITests.swift
//  ListenerTests
//
//  Created by jamie baddeley on 10/04/2026.
//

import Testing
import Foundation
@testable import Listener

@Suite("ListenerAPI")
struct ListenerAPITests {

    // MARK: - Helpers

    private func makeAPI(
        token: String? = "test_token",
        onUnauthorized: @Sendable @escaping () async -> Void = {},
        handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
    ) -> ListenerAPI {
        ListenerAPI(
            baseURL: StubResponses.url,
            client: StubHTTPClient(handler: handler),
            tokenProvider: { token },
            onUnauthorized: onUnauthorized
        )
    }

    // MARK: - Successful requests

    @Test func healthSucceeds() async throws {
        let api = makeAPI(handler: { _ in StubResponses.ok(Fixtures.health) })
        let health = try await api.health()
        #expect(health.status == "ok")
        #expect(health.version == "1")
    }

    @Test func healthDoesNotIncludeAuthHeader() async throws {
        let captured = RequestCapture()
        let api = makeAPI(handler: { req in
            captured.set(req)
            return StubResponses.ok(Fixtures.health)
        })
        _ = try await api.health()
        #expect(captured.value?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func authenticatedRequestsIncludeBearerHeader() async throws {
        let captured = RequestCapture()
        let api = makeAPI(token: "key_xyz", handler: { req in
            captured.set(req)
            return StubResponses.ok(Fixtures.authMe)
        })
        _ = try await api.me()
        #expect(captured.value?.value(forHTTPHeaderField: "Authorization") == "Bearer key_xyz")
    }

    @Test func meReturnsParsedProfile() async throws {
        let api = makeAPI(handler: { _ in StubResponses.ok(Fixtures.authMe) })
        let profile = try await api.me()
        #expect(profile.displayName == "Jamie")
        #expect(profile.role == .paid)
        #expect(profile.rateLimit?.remaining == 17)
    }

    @Test func historySendsCursorAndLimitQueryItems() async throws {
        let captured = RequestCapture()
        let api = makeAPI(handler: { req in
            captured.set(req)
            return StubResponses.ok(Fixtures.history)
        })
        _ = try await api.history(cursor: "abc", limit: 10)

        let url = try #require(captured.value?.url)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "cursor", value: "abc")))
        #expect(items.contains(URLQueryItem(name: "limit", value: "10")))
    }

    @Test func historyOmitsQueryItemsWhenNotProvided() async throws {
        let captured = RequestCapture()
        let api = makeAPI(handler: { req in
            captured.set(req)
            return StubResponses.ok(Fixtures.history)
        })
        _ = try await api.history()

        let url = try #require(captured.value?.url)
        #expect(url.query == nil)
    }

    @Test func historyDetailHitsExpectedPath() async throws {
        let captured = RequestCapture()
        let api = makeAPI(handler: { req in
            captured.set(req)
            return StubResponses.ok(Fixtures.historyDetail)
        })
        _ = try await api.historyDetail(id: "h_1")

        #expect(captured.value?.url?.path.hasSuffix("/history/h_1") == true)
        #expect(captured.value?.httpMethod == "GET")
    }

    @Test func deleteHistoryUsesDeleteMethod() async throws {
        let captured = RequestCapture()
        let api = makeAPI(handler: { req in
            captured.set(req)
            return StubResponses.ok(Fixtures.historyDelete)
        })
        try await api.deleteHistory(id: "h_1")

        #expect(captured.value?.httpMethod == "DELETE")
        #expect(captured.value?.url?.path.hasSuffix("/history/h_1") == true)
    }

    @Test func shareHistoryPostsJSONBody() async throws {
        let captured = RequestCapture()
        let api = makeAPI(handler: { req in
            captured.set(req)
            return StubResponses.ok(Fixtures.share)
        })
        let outcome = try await api.shareHistory(id: "h_1", groupIds: ["g1", "g2"])

        #expect(captured.value?.httpMethod == "POST")
        #expect(captured.value?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(outcome.results.count == 2)
    }

    @Test func recognizeUsesMultipartContentType() async throws {
        let captured = RequestCapture()
        let api = makeAPI(handler: { req in
            captured.set(req)
            return StubResponses.ok(Fixtures.recognizeSaved)
        })
        let result = try await api.recognize(audio: Data([0x00, 0x01, 0x02]), mimeType: "audio/mp4")

        let contentType = captured.value?.value(forHTTPHeaderField: "Content-Type") ?? ""
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
        #expect(result.status == .saved)
    }

    // MARK: - Error handling

    @Test func unauthorized401TriggersCallbackAndThrows() async throws {
        let signal = UnauthorizedSignal()
        let api = makeAPI(
            onUnauthorized: { await signal.fire() },
            handler: { _ in StubResponses.http(401, body: Fixtures.errorEnvelope) }
        )

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
        let api = makeAPI(handler: { _ in
            StubResponses.http(429, headers: ["Retry-After": "30", "X-RateLimit-Remaining": "0"])
        })

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
        let api = makeAPI(handler: { _ in StubResponses.http(429) })

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
        let api = makeAPI(handler: { _ in StubResponses.http(502) })

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
        let api = makeAPI(handler: { _ in
            StubResponses.http(400, body: #"{"error":{"code":"audio_too_large","message":"Audio file exceeds 5MB limit"}}"#)
        })

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
        let api = makeAPI(handler: { _ in throw URLError(.notConnectedToInternet) })

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
        let api = makeAPI(handler: { _ in StubResponses.ok("{not valid json}") })

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

/// Captures a single URLRequest from inside a stub handler so the test can
/// inspect what the API client actually sent. Reference type so the closure
/// mutation is visible from the test scope.
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
