import AppKit
import SwiftUI

/// The history: what a full line pushed past its length. Its cards hang at
/// the left of the line, a swipe away; this menu lists them in the menu bar.
@MainActor
enum HistoryMenu {
    /// One entry per item, newest first, each with its own small menu, and a
    /// way to empty the whole history at the end.
    static func make(for line: Line) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for url in line.history {
            let item = NSMenuItem(title: title(for: url), action: nil, keyEquivalent: "")
            item.image = icon(for: url)
            item.submenu = actions(for: url, line: line)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = ClosureMenuItem(L("Clear history")) { line.clearHistory() }
        clear.isEnabled = !line.history.isEmpty
        menu.addItem(clear)
        return menu
    }

    private static func actions(for url: URL, line: Line) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ClosureMenuItem(L("Copy")) { line.copy(url) })
        menu.addItem(ClosureMenuItem(L("Hang on the line again")) { line.hangAgain(url) })
        menu.addItem(ClosureMenuItem(L("Open")) { NSWorkspace.shared.open(url) })
        menu.addItem(ClosureMenuItem(L("Show in Finder")) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L("Remove from history")) { line.removeFromHistory(url) })
        return menu
    }

    /// Copied text shows its first line; anything else its name.
    private static func title(for url: URL) -> String {
        if isClippedText(url), let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            let head = String(decoding: (try? handle.read(upToCount: 512)) ?? Data(), as: UTF8.self)
            let first = head.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty } ?? ""
            if !first.isEmpty { return first.count > 48 ? String(first.prefix(48)) + "…" : first }
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    private static func icon(for url: URL) -> NSImage? {
        guard let thumb = makeThumbnail(url, maxPixels: 96) else { return nil }
        let size = thumb.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(40 / size.width, 28 / size.height)
        thumb.size = NSSize(width: size.width * scale, height: size.height * scale)
        return thumb
    }
}

/// The history in the space kept at the left end of the line. Collapsed, it
/// is the newest history cards piled under one clothespin, a little askew,
/// with a count; resting the pointer on it, or a click, hangs them all along
/// the line. Expanded, it is a small card that piles them up again, as does
/// the line tucking away. A right click lists the history.
struct HistoryPile: View {
    @ObservedObject var line: Line
    @State private var hovering = false

    /// How each card under the top one sits: turned and nudged aside.
    private static let fan: [(angle: Double, x: CGFloat, y: CGFloat)] = [(0, 0, 0), (-5, -5, 4), (6, 6, 7)]

    var body: some View {
        VStack(spacing: -12) {
            Clothespin()
                .zIndex(1)
            Group {
                if line.historyExpanded { collapse } else { pile }
            }
            .scaleEffect(hovering ? 1.035 : 1, anchor: .top)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hovering)
            .overlay(PileButton(line: line, onClick: click, onRest: rest))
            .onHover { hovering = $0 }
            .help(line.historyExpanded ? L("Pile up the history") : L("Hang the history on the line"))
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: HitRectsKey.self, value: [Line.historyID: g.frame(in: .global)])
                }
            )
        }
    }

    /// The pointer resting in the middle of the pile spreads the history
    /// out, once per time the line comes down (see hoverExpandSpent).
    private func rest() {
        guard !line.historyExpanded, !line.hoverExpandSpent else { return }
        line.expandHistory()
    }

    private func click() {
        if !line.historyExpanded {
            line.expandHistory()
        } else if Date().timeIntervalSince(line.expandedAt) > 0.5 {
            line.collapseHistory()
        }
    }

    private var pile: some View {
        let thumbs = line.pileThumbs
        // The top card sets the pile's size; the ones under it fit inside.
        let size = PeggedView.cardSize(for: thumbs.first?.size ?? CGSize(width: 4, height: 3))
        return ZStack {
            ForEach(Array(thumbs.enumerated().reversed()), id: \.offset) { index, thumb in
                let fan = Self.fan[min(index, Self.fan.count - 1)]
                card(thumb, in: size)
                    .rotationEffect(.degrees(fan.angle * (hovering ? 1.6 : 1)), anchor: .top)
                    .offset(x: fan.x * (hovering ? 1.6 : 1), y: fan.y)
                    .brightness(-0.04 * Double(index))
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .bottomTrailing) { badge(systemImage: "clock.arrow.circlepath").offset(x: 8, y: 8) }
    }

    /// While the history hangs along the line, its place keeps a small card
    /// that piles it up again.
    private var collapse: some View {
        VStack(spacing: 4) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 18, weight: .medium))
            Text("\(line.history.count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.primary)
        .frame(width: 62, height: 62)
        .glassFrame(cornerRadius: Frame.radius)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }

    private func badge(systemImage: String) -> some View {
        Label("\(line.history.count)", systemImage: systemImage)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .glassFrame(capsule: true)
    }

    /// One card in the pile, framed like a photo on the line, its picture
    /// filling the card so every card in the pile is the same size.
    private func card(_ thumb: NSImage, in size: CGSize) -> some View {
        Image(nsImage: thumb)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width - Frame.inset * 2, height: size.height - Frame.inset * 2)
            .clipShape(RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous))
            .padding(Frame.inset)
            .glassFrame(cornerRadius: Frame.radius)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }
}

/// Catches the clicks on the history pile: a click expands or collapses it,
/// a right click lists the history.
private struct PileButton: NSViewRepresentable {
    let line: Line
    let onClick: () -> Void
    let onRest: () -> Void

    func makeNSView(context: Context) -> PileButtonView {
        let view = PileButtonView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: PileButtonView, context: Context) {
        view.line = line
        view.onClick = onClick
        view.onRest = onRest
    }
}

final class PileButtonView: NSView {
    var line: Line?
    var onClick: () -> Void = {}
    /// The pointer has rested in the middle of the pile.
    var onRest: () -> Void = {}

    private var restTimer: Timer?

    /// Only the middle of the pile counts for resting, and only after a
    /// moment: passing its edge on the way to the first card, or sweeping
    /// over it towards the menu bar, must not spread the history out.
    private static let restInset: CGFloat = 0.15
    private static let restDelay: TimeInterval = 0.2

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let middle = bounds.insetBy(dx: bounds.width * Self.restInset, dy: bounds.height * Self.restInset)
        addTrackingArea(NSTrackingArea(rect: middle, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { startResting() }

    /// The line's window only takes the mouse once the pointer is over the
    /// pile, which can be after it entered the middle: moving there counts.
    override func mouseMoved(with event: NSEvent) {
        if restTimer == nil { startResting() }
    }

    private func startResting() {
        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: Self.restDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.onRest() }
        }
    }

    override func mouseExited(with event: NSEvent) {
        restTimer?.invalidate()
        restTimer = nil
    }

    override func mouseDown(with event: NSEvent) {
        // Clicking settles it; resting no longer needs to.
        restTimer?.invalidate()
        restTimer = nil
    }

    override func mouseUp(with event: NSEvent) { onClick() }

    override func rightMouseDown(with event: NSEvent) {
        guard let line else { return }
        // The menu reaches past the line, so the line waits while it is open.
        GrabView.isShowingMenu = true
        NSMenu.popUpContextMenu(HistoryMenu.make(for: line), with: event, for: self)
        GrabView.isShowingMenu = false
    }
}
