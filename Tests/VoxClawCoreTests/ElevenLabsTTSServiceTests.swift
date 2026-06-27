@testable import VoxClawCore
import Foundation
import Testing

struct ElevenLabsTTSServiceTests {

    /// Parse a JSON object literal the way the streaming reader does, so the
    /// alignment values arrive as `NSNumber` (not Swift `Double`/`Int`) — the
    /// exact representation that previously broke the `as? [Int]` cast.
    private func alignmentDict(_ json: String) throws -> [String: Any] {
        let data = Data(json.utf8)
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return obj
    }

    // MARK: - Current HTTP schema (seconds, start + end, "characters")

    @Test func parsesSecondsSchemaFromHTTPEndpoint() throws {
        let dict = try alignmentDict("""
        {
          "characters": ["H", "i"],
          "character_start_times_seconds": [0.0, 0.25],
          "character_end_times_seconds": [0.25, 0.5]
        }
        """)

        let alignment = try #require(ElevenLabsTTSService.parseAlignment(dict))

        #expect(alignment.chars == ["H", "i"])
        #expect(alignment.charStartTimesMs == [0, 250])
        // duration = end - start, in ms
        #expect(alignment.charDurationsMs == [250, 250])
    }

    @Test func secondsSchemaRoundsToNearestMillisecond() throws {
        let dict = try alignmentDict("""
        {
          "characters": ["a"],
          "character_start_times_seconds": [1.2345],
          "character_end_times_seconds": [1.5006]
        }
        """)

        let alignment = try #require(ElevenLabsTTSService.parseAlignment(dict))
        #expect(alignment.charStartTimesMs == [1235])      // 1234.5 -> 1235
        #expect(alignment.charDurationsMs == [266])         // 1501 - 1235 = 266
    }

    // MARK: - Legacy / WebSocket schema (milliseconds, start + duration, "chars")

    @Test func parsesLegacyMillisecondSchema() throws {
        let dict = try alignmentDict("""
        {
          "chars": ["H", "i"],
          "char_start_times_ms": [0, 250],
          "char_durations_ms": [250, 250]
        }
        """)

        let alignment = try #require(ElevenLabsTTSService.parseAlignment(dict))
        #expect(alignment.chars == ["H", "i"])
        #expect(alignment.charStartTimesMs == [0, 250])
        #expect(alignment.charDurationsMs == [250, 250])
    }

    // MARK: - Robustness

    @Test func returnsNilWhenNoRecognizedSchema() throws {
        let dict = try alignmentDict("""
        { "something_else": [1, 2, 3] }
        """)
        #expect(ElevenLabsTTSService.parseAlignment(dict) == nil)
    }

    @Test func returnsNilForEmptyCharacters() throws {
        let dict = try alignmentDict("""
        {
          "characters": [],
          "character_start_times_seconds": [],
          "character_end_times_seconds": []
        }
        """)
        #expect(ElevenLabsTTSService.parseAlignment(dict) == nil)
    }

    @Test func clampsToShortestArrayOnLengthMismatch() throws {
        let dict = try alignmentDict("""
        {
          "characters": ["a", "b", "c"],
          "character_start_times_seconds": [0.0, 0.1],
          "character_end_times_seconds": [0.1, 0.2]
        }
        """)
        let alignment = try #require(ElevenLabsTTSService.parseAlignment(dict))
        #expect(alignment.chars.count == 2)
        #expect(alignment.charStartTimesMs == [0, 100])
    }

    // MARK: - End-to-end: seconds alignment -> word timings

    @Test @MainActor func secondsAlignmentProducesAccurateWordTimings() throws {
        let dict = try alignmentDict("""
        {
          "characters": ["H","i"," ","b","o","b"],
          "character_start_times_seconds": [0.0, 0.10, 0.20, 0.30, 0.40, 0.50],
          "character_end_times_seconds":   [0.10, 0.20, 0.30, 0.40, 0.50, 0.60]
        }
        """)
        let alignment = try #require(ElevenLabsTTSService.parseAlignment(dict))

        let timings = ElevenLabsSpeechEngine.convertAlignmentsToWordTimings(
            [alignment], words: ["Hi", "bob"]
        )

        #expect(timings.count == 2)
        // "Hi" spans chars 0..1: start 0.0s, end = start(0.10)+dur(0.10)=0.20s
        #expect(timings[0].word == "Hi")
        #expect(abs(timings[0].startTime - 0.0) < 0.001)
        #expect(abs(timings[0].endTime - 0.20) < 0.001)
        // "bob" spans chars 3..5: start 0.30s, end = start(0.50)+dur(0.10)=0.60s
        #expect(timings[1].word == "bob")
        #expect(abs(timings[1].startTime - 0.30) < 0.001)
        #expect(abs(timings[1].endTime - 0.60) < 0.001)
    }
}
