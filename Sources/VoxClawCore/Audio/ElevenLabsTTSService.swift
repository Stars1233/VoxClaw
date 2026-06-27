import Foundation
import os

struct ElevenLabsAlignment: Sendable {
    let charStartTimesMs: [Int]
    let charDurationsMs: [Int]
    let chars: [String]
}

struct ElevenLabsChunk: Sendable {
    let audio: Data
    let alignment: ElevenLabsAlignment?
}

actor ElevenLabsTTSService {
    private let apiKey: String
    private let voiceID: String
    private let speed: Float
    private let modelID: String

    init(apiKey: String, voiceID: String, speed: Float = 1.0, turbo: Bool = false) {
        self.apiKey = apiKey
        self.voiceID = voiceID
        self.speed = speed
        // eleven_flash_v2_5 is the current low-latency streaming model (eleven_turbo_v2_5
        // is deprecated and scheduled for removal). eleven_multilingual_v2 stays as the
        // higher-fidelity option. Both support the with-timestamps alignment stream.
        self.modelID = turbo ? "eleven_flash_v2_5" : "eleven_multilingual_v2"
    }

    struct TTSError: Error, CustomStringConvertible {
        let message: String
        let statusCode: Int?
        var description: String { message }
    }

    func streamWithTimestamps(text: String) -> AsyncThrowingStream<ElevenLabsChunk, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: ElevenLabsChunk.self)
        let task = Task {
            do {
                Log.tts.info("ElevenLabs TTS request: voiceID=\(self.voiceID, privacy: .public), model=\(self.modelID, privacy: .public), textLength=\(text.count, privacy: .public)")
                let request = try buildRequest(text: text)
                let (bytes, response) = try await URLSession.shared.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw TTSError(message: "Invalid response type", statusCode: nil)
                }

                Log.tts.info("ElevenLabs TTS response: status=\(httpResponse.statusCode, privacy: .public)")

                guard httpResponse.statusCode == 200 else {
                    var errorBody = ""
                    for try await byte in bytes {
                        errorBody.append(Character(UnicodeScalar(byte)))
                        if errorBody.count > 1000 { break }
                    }
                    Log.tts.error("ElevenLabs API error: status=\(httpResponse.statusCode, privacy: .public)")
                    throw Self.httpError(status: httpResponse.statusCode, body: errorBody)
                }

                // ElevenLabs streams JSON lines, each containing audio_base64 and optional alignment
                var lineBuffer = Data()
                var chunkCount = 0
                var totalBytes = 0

                for try await byte in bytes {
                    try Task.checkCancellation()

                    if byte == UInt8(ascii: "\n") {
                        if !lineBuffer.isEmpty {
                            if let chunk = try parseChunk(lineBuffer) {
                                continuation.yield(chunk)
                                chunkCount += 1
                                totalBytes += chunk.audio.count
                                if chunkCount % 10 == 0 {
                                    Log.tts.debug("ElevenLabs streaming: \(chunkCount, privacy: .public) chunks, \(totalBytes, privacy: .public) audio bytes")
                                }
                            }
                            lineBuffer.removeAll(keepingCapacity: true)
                        }
                    } else {
                        lineBuffer.append(byte)
                    }
                }

                // Handle final line without trailing newline
                if !lineBuffer.isEmpty {
                    if let chunk = try parseChunk(lineBuffer) {
                        continuation.yield(chunk)
                        totalBytes += chunk.audio.count
                        chunkCount += 1
                    }
                }

                Log.tts.info("ElevenLabs TTS complete: \(chunkCount, privacy: .public) chunks, \(totalBytes, privacy: .public) total audio bytes")
                continuation.finish()
            } catch {
                Log.tts.error("ElevenLabs TTS stream error: \(error)")
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private func parseChunk(_ data: Data) throws -> ElevenLabsChunk? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard let audioBase64 = json["audio_base64"] as? String,
              let audioData = Data(base64Encoded: audioBase64),
              !audioData.isEmpty else {
            return nil
        }

        var alignment: ElevenLabsAlignment?
        if let alignmentDict = json["alignment"] as? [String: Any] {
            alignment = Self.parseAlignment(alignmentDict)
        }

        return ElevenLabsChunk(audio: audioData, alignment: alignment)
    }

    /// Parse an ElevenLabs `alignment` object into the internal ms-based model.
    ///
    /// The HTTP `/stream/with-timestamps` endpoint returns seconds-based fields
    /// (`characters`, `character_start_times_seconds`, `character_end_times_seconds`).
    /// The WebSocket `stream-input` endpoint uses an ms-based schema
    /// (`chars`, `char_start_times_ms`, `char_durations_ms`). We accept both so a
    /// schema change on either path can't silently drop alignment data.
    static func parseAlignment(_ dict: [String: Any]) -> ElevenLabsAlignment? {
        // Current HTTP schema: seconds, start + end.
        if let chars = dict["characters"] as? [String],
           let startsSec = doubleArray(dict["character_start_times_seconds"]),
           let endsSec = doubleArray(dict["character_end_times_seconds"]),
           !chars.isEmpty {
            let count = min(chars.count, startsSec.count, endsSec.count)
            guard count > 0 else { return nil }
            var startsMs: [Int] = []
            var durationsMs: [Int] = []
            var outChars: [String] = []
            startsMs.reserveCapacity(count)
            durationsMs.reserveCapacity(count)
            outChars.reserveCapacity(count)
            for i in 0..<count {
                let startMs = Int((startsSec[i] * 1000).rounded())
                let endMs = Int((endsSec[i] * 1000).rounded())
                startsMs.append(startMs)
                durationsMs.append(max(0, endMs - startMs))
                outChars.append(chars[i])
            }
            return ElevenLabsAlignment(charStartTimesMs: startsMs, charDurationsMs: durationsMs, chars: outChars)
        }

        // Legacy / WebSocket schema: milliseconds, start + duration.
        if let chars = dict["chars"] as? [String],
           let starts = doubleArray(dict["char_start_times_ms"]),
           let durations = doubleArray(dict["char_durations_ms"]),
           !chars.isEmpty {
            let count = min(chars.count, starts.count, durations.count)
            guard count > 0 else { return nil }
            return ElevenLabsAlignment(
                charStartTimesMs: (0..<count).map { Int(starts[$0].rounded()) },
                charDurationsMs: (0..<count).map { Int(durations[$0].rounded()) },
                chars: Array(chars[0..<count])
            )
        }

        return nil
    }

    /// Robustly decode a JSON number array (JSONSerialization yields `NSNumber`,
    /// which won't cast to `[Int]` when the values are non-integral seconds).
    private static func doubleArray(_ value: Any?) -> [Double]? {
        if let nums = value as? [NSNumber] { return nums.map { $0.doubleValue } }
        if let doubles = value as? [Double] { return doubles }
        return nil
    }

    private func buildRequest(text: String) throws -> URLRequest {
        var components = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)/stream/with-timestamps")!
        components.queryItems = [
            URLQueryItem(name: "output_format", value: "pcm_24000"),
            URLQueryItem(name: "optimize_streaming_latency", value: "2"),
        ]
        guard let url = components.url else {
            throw TTSError(message: "Invalid API URL", statusCode: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // ElevenLabs "emotional" voice settings. Tune these to taste:
        //  • style       0–1  style exaggeration; high = dramatic / "announcer". Keep low for neutral narration.
        //  • stability    0–1  low = expressive but erratic; ~0.5 = balanced; high = flat/consistent.
        //  • similarity   0–1  fidelity to the voice's timbre (not emotional).
        //  • speakerBoost bool minor clarity/presence boost.
        let style = 0.0
        let stability = 0.5
        let similarityBoost = 0.75
        let useSpeakerBoost = true

        let body: [String: Any] = [
            "text": text,
            "model_id": modelID,
            "voice_settings": [
                "stability": stability,
                "similarity_boost": similarityBoost,
                "style": style,
                "use_speaker_boost": useSpeakerBoost,
            ] as [String: Any],
            "speed": Double(speed),
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func friendlyError(status: Int, body: String) -> String {
        switch status {
        case 401:
            return "Invalid ElevenLabs API key. Check your key in Settings."
        case 429:
            return "ElevenLabs rate limit or quota exceeded. Check your plan usage."
        case 400:
            return "ElevenLabs rejected the request. The text may be too long or contain unsupported content."
        case 500...599:
            return "ElevenLabs service is temporarily unavailable (HTTP \(status)). Try again shortly."
        default:
            return "ElevenLabs TTS error (HTTP \(status)): \(body.prefix(200))"
        }
    }

    static func httpError(status: Int, body: String) -> TTSError {
        TTSError(message: friendlyError(status: status, body: body), statusCode: status)
    }
}
