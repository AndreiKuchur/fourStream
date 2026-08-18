import UIKit

final class StreamDetailsViewController: UIViewController {
    private let stateRow = DetailRowView(title: "State")
    private let reasonRow = DetailRowView(title: "Reason")
    private let videoBitrateRow = DetailRowView(title: "Video bitrate")
    private let audioBitrateRow = DetailRowView(title: "Audio bitrate")
    private let videoCodecRow = DetailRowView(title: "Video codec")
    private let audioCodecRow = DetailRowView(title: "Audio codec")
    private let pictureSizeRow = DetailRowView(title: "Picture size")
    private let frameRateRow = DetailRowView(title: "Frame rate")

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stream details"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemBackground

        reasonRow.isHidden = true
        [videoBitrateRow, audioBitrateRow, videoCodecRow, audioCodecRow, pictureSizeRow, frameRateRow]
            .forEach { $0.value = "—" }

        let stack = UIStackView(arrangedSubviews: [
            stateRow,
            reasonRow,
            videoBitrateRow,
            audioBitrateRow,
            videoCodecRow,
            audioCodecRow,
            pictureSizeRow,
            frameRateRow,
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
    }

    func render(stateTitle: String, reason: String?, statistics: StreamStatistics?) {
        loadViewIfNeeded()
        stateRow.value = stateTitle
        reasonRow.value = reason
        reasonRow.isHidden = reason == nil || reason?.isEmpty == true

        guard let statistics else { return }
        videoBitrateRow.value = Self.bitrateText(statistics.videoBitrate)
        audioBitrateRow.value = Self.bitrateText(statistics.audioBitrate)
        videoCodecRow.value = statistics.videoCodec.displayName
        audioCodecRow.value = statistics.audioCodec.displayName
        pictureSizeRow.value = "\(Int(statistics.resolution.width)) × \(Int(statistics.resolution.height))"
        frameRateRow.value = "\(statistics.frameRate) fps"
    }

    private static func bitrateText(_ bitsPerSecond: Int) -> String {
        "\(bitsPerSecond / 1_000) kbit/s"
    }
}

private final class DetailRowView: UIView {
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()

    var value: String? {
        get { valueLabel.text }
        set { valueLabel.text = newValue }
    }

    init(title: String) {
        super.init(frame: .zero)
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.textColor = .secondaryLabel
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        valueLabel.font = .preferredFont(forTextStyle: .body)
        valueLabel.textAlignment = .right
        valueLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
