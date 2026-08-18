import UIKit

final class StatusPanelView: UIControl {
    private let stateLabel = UILabel()
    private let durationLabel = UILabel()
    private let chevronView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        backgroundColor = UIColor.black.withAlphaComponent(0.55)
        layer.cornerRadius = 12
        clipsToBounds = true

        stateLabel.font = .preferredFont(forTextStyle: .headline)
        stateLabel.textColor = .white
        stateLabel.textAlignment = .center
        stateLabel.numberOfLines = 0
        stateLabel.isUserInteractionEnabled = false

        durationLabel.font = .monospacedDigitSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .title2).pointSize,
            weight: .semibold
        )
        durationLabel.textColor = .white
        durationLabel.textAlignment = .center
        durationLabel.isHidden = true
        durationLabel.isUserInteractionEnabled = false

        chevronView.image = UIImage(systemName: "chevron.up")
        chevronView.tintColor = .white
        chevronView.contentMode = .scaleAspectFit
        chevronView.isHidden = true
        chevronView.isUserInteractionEnabled = false
        chevronView.setContentHuggingPriority(.required, for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [stateLabel, durationLabel])
        textStack.axis = .vertical
        textStack.alignment = .center
        textStack.spacing = 2
        textStack.isUserInteractionEnabled = false

        let content = UIStackView(arrangedSubviews: [textStack, chevronView])
        content.axis = .horizontal
        content.alignment = .center
        content.spacing = 8
        content.isUserInteractionEnabled = false
        content.translatesAutoresizingMaskIntoConstraints = false

        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            chevronView.widthAnchor.constraint(equalToConstant: 14),
            chevronView.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(stateText: String, durationText: String, isTappable: Bool) {
        stateLabel.text = stateText
        durationLabel.text = durationText
        durationLabel.isHidden = durationText.isEmpty
        chevronView.isHidden = !isTappable
        isUserInteractionEnabled = isTappable
        accessibilityTraits = isTappable ? .button : .staticText
        accessibilityHint = isTappable ? "Shows stream details" : nil
        if durationText.isEmpty {
            accessibilityLabel = stateText
        } else {
            accessibilityLabel = "\(stateText), \(durationText)"
        }
    }
}
