//
//  DecodingTests.swift
//  ListenerTests
//
//  Created by jamie baddeley on 10/04/2026.
//

import Testing
import Foundation
@testable import Listener

@Suite("Decoding")
struct DecodingTests {

    private let decoder = JSONDecoder()

    // MARK: - Envelope

    @Test func decodesHealthEnvelope() throws {
        let envelope = try decoder.decode(APIResponse<HealthDTO>.self, from: Data(Fixtures.health.utf8))
        #expect(envelope.data.status == "ok")
        #expect(envelope.data.version == "1")
    }

    @Test func decodesErrorEnvelope() throws {
        let envelope = try decoder.decode(APIErrorEnvelope.self, from: Data(Fixtures.errorEnvelope.utf8))
        #expect(envelope.error.code == "auth_required")
        #expect(envelope.error.message == "Authentication required")
        #expect(envelope.meta?.requestId == "req_abc")
        #expect(envelope.meta?.timestamp == "2026-04-10T10:00:00Z")
    }

    // MARK: - Auth / user profile

    @Test func decodesAuthMeAndMapsToProfile() throws {
        let envelope = try decoder.decode(APIResponse<UserDTO>.self, from: Data(Fixtures.authMe.utf8))
        let profile = UserProfile(dto: envelope.data)

        #expect(profile.id == "u_abc123")
        #expect(profile.displayName == "Jamie")
        #expect(profile.role == "paid")
        #expect(profile.listenEnabled == true)
        #expect(profile.preferredPlatform == "tidal")

        let rate = try #require(profile.rateLimit)
        #expect(rate.limit == 20)
        #expect(rate.remaining == 17)
        #expect(rate.resetAt == Date(timeIntervalSince1970: 1709654400))
    }

    // MARK: - Recognition

    @Test func decodesRecognizeSaved() throws {
        let envelope = try decoder.decode(APIResponse<RecognizeDTO>.self, from: Data(Fixtures.recognizeSaved.utf8))
        let result = RecognitionResult(dto: envelope.data)

        #expect(result.status == .saved)
        #expect(result.source == "recognition")

        let track = try #require(result.track)
        #expect(track.title == "Midnight City")
        #expect(track.artist == "M83")
        #expect(track.thumbnail == URL(string: "https://img.example.com/m83.jpg"))
        #expect(track.shortcode == "aBcDeF12")
        #expect(track.shareURL == URL(string: "https://mixmat.es/aBcDeF12"))
        #expect(track.platforms.spotify == URL(string: "https://open.spotify.com/track/abc"))
        #expect(track.platforms.tidal == URL(string: "https://tidal.com/browse/track/abc"))
        #expect(track.platforms.appleMusic == URL(string: "https://music.apple.com/us/album/abc"))
    }

    @Test func decodesRecognizeNoMatch() throws {
        let envelope = try decoder.decode(APIResponse<RecognizeDTO>.self, from: Data(Fixtures.recognizeNoMatch.utf8))
        let result = RecognitionResult(dto: envelope.data)

        #expect(result.status == .noMatch)
        #expect(result.source == nil)
        #expect(result.track == nil)
    }

    // MARK: - History

    @Test func decodesHistoryList() throws {
        let envelope = try decoder.decode(APIResponse<HistoryListDTO>.self, from: Data(Fixtures.history.utf8))
        let list = HistoryList(dto: envelope.data)

        #expect(list.items.count == 2)
        #expect(list.cursor == "next_cursor_token")
        #expect(list.hasMore == true)

        let first = list.items[0]
        #expect(first.id == "h_1")
        #expect(first.title == "Midnight City")
        #expect(first.platforms.spotify == URL(string: "https://open.spotify.com/track/abc"))
        #expect(first.platforms.tidal == nil)
        #expect(first.platforms.appleMusic == nil)
        // Wire format is ISO-8601 UTC; the domain promotes it to a `Date`.
        // Timestamp is 2026-04-10T10:00:00Z verified with `date -ujf`.
        #expect(first.createdAt == Date(timeIntervalSince1970: 1775815200))

        let second = list.items[1]
        #expect(second.thumbnail == nil)
        #expect(second.platforms == .empty)
    }

    @Test func decodesHistoryDetail() throws {
        let envelope = try decoder.decode(APIResponse<HistoryDetailDTO>.self, from: Data(Fixtures.historyDetail.utf8))
        let detail = HistoryDetail(dto: envelope.data)

        #expect(detail.id == "h_1")
        #expect(detail.sharedTo.count == 1)
        #expect(detail.sharedTo[0].groupId == "g1")
        #expect(detail.sharedTo[0].groupName == "Wellington Batucada")
    }

    @Test func decodesHistoryDelete() throws {
        let envelope = try decoder.decode(APIResponse<DeletedDTO>.self, from: Data(Fixtures.historyDelete.utf8))
        #expect(envelope.data.deleted == true)
    }

    // MARK: - Groups

    @Test func decodesGroups() throws {
        let envelope = try decoder.decode(APIResponse<HumanGroupListDTO>.self, from: Data(Fixtures.groups.utf8))
        let groups = envelope.data.items.map(HumanGroup.init(dto:))

        #expect(groups.count == 2)
        #expect(groups[0].id == "g1")
        #expect(groups[0].name == "Wellington Batucada")
        #expect(groups[0].description == "Fortnightly drum sessions")
        #expect(groups[1].description == nil)
    }

    // MARK: - Share

    @Test func decodesShareResponse() throws {
        let envelope = try decoder.decode(APIResponse<ShareDataDTO>.self, from: Data(Fixtures.share.utf8))
        let outcome = ShareOutcome(dto: envelope.data)

        #expect(outcome.results.count == 2)
        #expect(outcome.results[0].groupId == "g1")
        #expect(outcome.results[0].status == .shared)
        #expect(outcome.results[1].groupId == "g2")
        #expect(outcome.results[1].status == .duplicate)
    }

    // MARK: - Recordings

    @Test func decodesRecordings() throws {
        let envelope = try decoder.decode(APIResponse<RecordingListDTO>.self, from: Data(Fixtures.recordings.utf8))
        let recordings = envelope.data.items.map(Recording.init(dto:))

        #expect(recordings.count == 1)
        #expect(recordings[0].id == "r_1")
        #expect(recordings[0].outcome == .matched)
        #expect(recordings[0].mimeType == "audio/mp4")
        #expect(recordings[0].title == "Midnight City")
    }

    @Test func decodesRecordingsDelete() throws {
        let envelope = try decoder.decode(APIResponse<DeletedCountDTO>.self, from: Data(Fixtures.recordingsDelete.utf8))
        #expect(envelope.data.deleted == 3)
    }

    // MARK: - Forward-compatibility for unknown enum values

    @Test func unknownRecognitionStatusBecomesOther() {
        #expect(RecognitionStatus(rawValue: "totally_new") == .other("totally_new"))
    }

    @Test func unknownShareStatusBecomesOther() {
        #expect(ShareStatus(rawValue: "queued") == .other("queued"))
    }

    @Test func unknownRecordingOutcomeBecomesOther() {
        #expect(RecordingOutcome(rawValue: "pending") == .other("pending"))
    }
}
