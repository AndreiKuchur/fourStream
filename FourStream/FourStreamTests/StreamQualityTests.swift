import CoreGraphics
import Testing
@testable import FourStream

struct StreamQualityTests {
    private let quality = StreamQuality.preset720p30

    @Test
    func presetIs720p30WithRequiredBitratesAndCodecs() {
        #expect(quality.width == 1280)
        #expect(quality.height == 720)
        #expect(quality.encodedVideoSize == CGSize(width: 720, height: 1280))
        #expect(quality.frameRate == 30)
        #expect(quality.videoBitrate == 2_500_000)
        #expect(quality.audioBitrate == 128_000)
        #expect(quality.videoCodec == .h264)
        #expect(quality.audioCodec == .aac)
    }

    @Test
    func capableFormatIsSupported() {
        #expect(quality.validated(against: [Self.capableFormat]) == .supported)
    }

    @Test
    func unsupportedPictureSizeNamesTheResolution() {
        var format = Self.capableFormat
        format.width = 640
        format.height = 480

        let result = quality.validated(against: [format])

        guard case .unsupported(let reason) = result else {
            Issue.record("expected unsupported, got \(result)")
            return
        }
        #expect(reason.contains("1280"))
        #expect(reason.contains("720"))
    }

    @Test
    func unsupportedFrameRateNamesTheRate() {
        var format = Self.capableFormat
        format.frameRates = [24]

        let result = quality.validated(against: [format])

        guard case .unsupported(let reason) = result else {
            Issue.record("expected unsupported, got \(result)")
            return
        }
        #expect(reason.contains("30"))
    }

    @Test
    func unsupportedVideoBitrateNamesTheValue() {
        var format = Self.capableFormat
        format.maxVideoBitrate = 1_000_000

        let result = quality.validated(against: [format])

        guard case .unsupported(let reason) = result else {
            Issue.record("expected unsupported, got \(result)")
            return
        }
        #expect(reason.contains("2500000") || reason.contains("2_500_000"))
    }

    @Test
    func unsupportedAudioBitrateNamesTheValue() {
        var format = Self.capableFormat
        format.maxAudioBitrate = 64_000

        let result = quality.validated(against: [format])

        guard case .unsupported(let reason) = result else {
            Issue.record("expected unsupported, got \(result)")
            return
        }
        #expect(reason.contains("128000") || reason.contains("128_000"))
    }

    @Test
    func unsupportedVideoCodecNamesTheCodec() {
        var format = Self.capableFormat
        format.videoCodecs = []

        let result = quality.validated(against: [format])

        guard case .unsupported(let reason) = result else {
            Issue.record("expected unsupported, got \(result)")
            return
        }
        #expect(reason.lowercased().contains("h.264") || reason.lowercased().contains("codec"))
    }

    @Test
    func unsupportedOrientationNamesPortrait() {
        var format = Self.capableFormat
        format.supportsPortrait = false

        let result = quality.validated(against: [format])

        guard case .unsupported(let reason) = result else {
            Issue.record("expected unsupported, got \(result)")
            return
        }
        #expect(reason.lowercased().contains("portrait"))
    }

    private static let capableFormat = SupportedCaptureFormat(
        width: 1280,
        height: 720,
        frameRates: [30],
        maxVideoBitrate: 2_500_000,
        maxAudioBitrate: 128_000,
        videoCodecs: [.h264],
        audioCodecs: [.aac],
        supportsPortrait: true
    )
}
