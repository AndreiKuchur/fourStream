import AVFoundation
import HaishinKit
import UIKit

final class PreviewContainerView: UIView {
    let previewView: UIView
    private let blurView = UIVisualEffectView(effect: nil)
    private let dimView = UIView()

    override init(frame: CGRect) {
        let metalView = MTHKView(frame: frame)
        metalView.videoGravity = .resizeAspectFill
        metalView.translatesAutoresizingMaskIntoConstraints = false
        self.previewView = metalView
        super.init(frame: frame)
        backgroundColor = .black
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        dimView.alpha = 0
        dimView.isUserInteractionEnabled = false
        blurView.isUserInteractionEnabled = false
        blurView.translatesAutoresizingMaskIntoConstraints = false
        dimView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(metalView)
        addSubview(blurView)
        addSubview(dimView)
        NSLayoutConstraint.activate([
            metalView.topAnchor.constraint(equalTo: topAnchor),
            metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            metalView.bottomAnchor.constraint(equalTo: bottomAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            dimView.topAnchor.constraint(equalTo: topAnchor),
            dimView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setObscured(_ obscured: Bool) {
        blurView.effect = obscured ? UIBlurEffect(style: .dark) : nil
        dimView.alpha = obscured ? 1 : 0
    }
}
