import AppKit
import SwiftUI

/// Resting the pointer on a card shows it larger, just below the line. The
/// line's own window is only as tall as a card, so the enlarged picture gets
/// a window of its own. It never takes the mouse: the pointer stays on the
/// card underneath, and moving off the card puts the preview away.
@MainActor
final class HoverPreview {
    static let shared = HoverPreview()

    private let panel: NSPanel
    private let host = NSHostingView(rootView: PreviewCard(image: nil, shown: false))
    private var pending: DispatchWorkItem?
    private var showing: URL?

    /// How long the pointer rests before the preview appears, so sweeping
    /// across the line does not flash one preview after another.
    private static let delay: TimeInterval = 0.35
    /// The largest the preview gets, in points.
    private static let maxSize = CGSize(width: 520, height: 380)

    private init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        host.sizingOptions = []
        panel.contentView = host
    }

    /// Shows `url` below `card`, a frame in screen coordinates, after a
    /// moment's rest.
    func show(_ url: URL, below card: CGRect, on screen: NSScreen) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.present(url, below: card, on: screen) }
        pending = work
        // Moving from one card to the next keeps the preview up, so the next
        // one follows at once.
        DispatchQueue.main.asyncAfter(deadline: .now() + (showing == nil ? Self.delay : 0.05), execute: work)
    }

    func hide() {
        pending?.cancel()
        pending = nil
        guard showing != nil else { return }
        showing = nil
        host.rootView = PreviewCard(image: host.rootView.image, shown: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, self.showing == nil else { return }
            self.panel.orderOut(nil)
        }
    }

    private func present(_ url: URL, below card: CGRect, on screen: NSScreen) {
        let pixels = Int(max(Self.maxSize.width, Self.maxSize.height) * screen.backingScaleFactor)
        guard let image = makeThumbnail(url, maxPixels: pixels) else { return }
        let size = Self.fit(image.size)
        // Room around the card for its shadow.
        let pad: CGFloat = 24
        let frameSize = CGSize(width: size.width + pad * 2, height: size.height + pad * 2)
        let visible = screen.visibleFrame
        var origin = CGPoint(x: card.midX - frameSize.width / 2, y: card.minY - 6 - frameSize.height)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - frameSize.width - 8)
        origin.y = max(origin.y, visible.minY + 8)
        panel.setFrame(CGRect(origin: origin, size: frameSize), display: false)
        host.frame = CGRect(origin: .zero, size: frameSize)

        let wasShowing = showing != nil
        showing = url
        // Appearing, it grows out of the card; moving between cards, it just
        // changes picture.
        host.rootView = PreviewCard(image: image, shown: wasShowing)
        panel.orderFrontRegardless()
        if !wasShowing {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.showing == url else { return }
                self.host.rootView = PreviewCard(image: image, shown: true)
            }
        }
    }

    private static func fit(_ size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 320, height: 240) }
        let scale = min(maxSize.width / size.width, maxSize.height / size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }
}

private struct PreviewCard: View {
    let image: NSImage?
    let shown: Bool

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Frame.radius + 2 - Frame.inset, style: .continuous))
                .padding(Frame.inset + 2)
                .glassFrame(cornerRadius: Frame.radius + 2)
                .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
                .padding(24)
                .scaleEffect(shown ? 1 : 0.6, anchor: .top)
                .opacity(shown ? 1 : 0)
                .animation(.spring(response: 0.28, dampingFraction: 0.8), value: shown)
        }
    }
}
