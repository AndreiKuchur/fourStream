import CoreGraphics

enum VideoCodec: Equatable, Sendable {
    case h264

    var displayName: String {
        switch self {
        case .h264: "H.264"
        }
    }
}

enum AudioCodec: Equatable, Sendable {
    case aac

    var displayName: String {
        switch self {
        case .aac: "AAC"
        }
    }
}

struct StreamQuality: Equatable, Sendable {
    let width: Int
    let height: Int
    let frameRate: Int
    let videoBitrate: Int
    let audioBitrate: Int
    let videoCodec: VideoCodec
    let audioCodec: AudioCodec

    static let preset720p30 = StreamQuality(
        width: 1280,
        height: 720,
        frameRate: 30,
        videoBitrate: 2_500_000,
        audioBitrate: 128_000,
        videoCodec: .h264,
        audioCodec: .aac
    )

    /// 720p in portrait. Camera formats are reported landscape (1280×720);
    /// the encoder must emit 720×1280 so viewers get the same orientation as the preview.
    var encodedVideoSize: CGSize {
        CGSize(width: height, height: width)
    }

    func validated(against formats: [SupportedCaptureFormat]) -> StreamQualityValidation {
        guard formats.contains(where: { $0.width >= width && $0.height >= height }) else {
            return .unsupported(reason: "Unsupported resolution: \(width)×\(height).")
        }

        guard formats.contains(where: {
            $0.width >= width && $0.height >= height && $0.frameRates.contains(frameRate)
        }) else {
            return .unsupported(reason: "Frame rate not available: \(frameRate) fps.")
        }

        guard formats.contains(where: { $0.maxVideoBitrate >= videoBitrate }) else {
            return .unsupported(reason: "Unsupported video bitrate: \(videoBitrate) bit/s.")
        }

        guard formats.contains(where: { $0.maxAudioBitrate >= audioBitrate }) else {
            return .unsupported(reason: "Unsupported audio bitrate: \(audioBitrate) bit/s.")
        }

        guard formats.contains(where: { $0.videoCodecs.contains(videoCodec) }) else {
            return .unsupported(reason: "Codec not available: \(videoCodec.displayName).")
        }

        guard formats.contains(where: { $0.audioCodecs.contains(audioCodec) }) else {
            return .unsupported(reason: "Codec not available: \(audioCodec.displayName).")
        }

        guard formats.contains(where: { $0.supportsPortrait }) else {
            return .unsupported(reason: "Unsupported orientation: portrait.")
        }

        return .supported
    }
}

struct SupportedCaptureFormat: Equatable, Sendable {
    var width: Int
    var height: Int
    var frameRates: [Int]
    var maxVideoBitrate: Int
    var maxAudioBitrate: Int
    var videoCodecs: [VideoCodec]
    var audioCodecs: [AudioCodec]
    var supportsPortrait: Bool
}

enum StreamQualityValidation: Equatable, Sendable {
    case supported
    case unsupported(reason: String)
}
