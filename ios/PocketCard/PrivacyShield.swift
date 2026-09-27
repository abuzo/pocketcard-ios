import SwiftUI
import UIKit

/// A window-level cover also shields presented editor/settings sheets in app-switcher snapshots.
struct WindowPrivacyShield: UIViewRepresentable {
    let active: Bool
    func makeUIView(context: Context) -> ShieldAnchor { ShieldAnchor() }
    func updateUIView(_ uiView: ShieldAnchor, context: Context) { uiView.protect(active) }
    static func dismantleUIView(_ uiView: ShieldAnchor, coordinator: ()) { uiView.protect(false) }

    final class ShieldAnchor: UIView {
        private var shield: UIView?
        private var shouldProtect = false
        override func didMoveToWindow() { super.didMoveToWindow(); synchronize() }
        func protect(_ value: Bool) { shouldProtect = value; synchronize() }
        private func synchronize() {
            guard shouldProtect, let window else { shield?.removeFromSuperview(); shield = nil; return }
            if let shield { window.bringSubviewToFront(shield); return }
            let cover = UIView(frame:window.bounds)
            cover.autoresizingMask = [.flexibleWidth,.flexibleHeight]
            cover.backgroundColor = .systemBackground
            cover.accessibilityViewIsModal = true
            let title = UILabel(); title.text = "PocketCard"; title.font = .preferredFont(forTextStyle:.largeTitle)
            title.adjustsFontForContentSizeCategory = true; title.translatesAutoresizingMaskIntoConstraints = false
            cover.addSubview(title)
            NSLayoutConstraint.activate([title.centerXAnchor.constraint(equalTo:cover.centerXAnchor),title.centerYAnchor.constraint(equalTo:cover.centerYAnchor)])
            window.addSubview(cover); shield = cover
        }
    }
}
