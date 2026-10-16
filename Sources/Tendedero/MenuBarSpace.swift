import AppKit
import ApplicationServices

/// The empty stretch of the menu bar: from where the front app's menus end
/// to where the menu bar icons begin. Resting the pointer there brings the
/// line down, so reaching for a menu or an icon never does.
///
/// Neither edge can be seen from outside: the menu bar is one window drawn
/// by the system. Both come from the accessibility interface, which apps use
/// to describe their menus and icons, so this needs Accessibility access.
/// Without it, `empty` stays nil and the line falls back to a fixed zone
/// around the notch.
///
/// Asking every app takes a moment and can stall on one that hangs, so it
/// happens off the main thread, with a short timeout, every couple of
/// seconds and whenever another app comes to the front.
final class MenuBarSpace: @unchecked Sendable {
    static let shared = MenuBarSpace()

    /// How far in from each side of a screen the empty stretch runs: past the
    /// menus from the left edge, and short of the icons from the right edge.
    /// Measured on the menu bar the menus are on, used on every screen.
    struct Insets {
        var left: CGFloat
        var right: CGFloat
    }

    private let lock = NSLock()
    private var latest: Insets?
    private let queue = DispatchQueue(label: "app.tendedero.menu-bar-space", qos: .utility)
    private var timer: DispatchSourceTimer?

    /// The last measurement, or nil without Accessibility access.
    var empty: Insets? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    /// Starts measuring. The first time, macOS is asked to show its
    /// Accessibility prompt, once ever.
    func start() {
        let askedKey = "askedAccessibilityForMenuBar"
        if !AXIsProcessTrusted() && !UserDefaults.standard.bool(forKey: askedKey) {
            UserDefaults.standard.set(true, forKey: askedKey)
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 2)
        timer.setEventHandler { [weak self] in self?.measure() }
        timer.resume()
        self.timer = timer
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil
        ) { [weak self] _ in
            // The new app's menus need a moment to be in place.
            self?.queue.asyncAfter(deadline: .now() + 0.3) { self?.measure() }
        }
    }

    // MARK: Measuring

    private func measure() {
        guard AXIsProcessTrusted(),
              let (screen, notchEnd) = DispatchQueue.main.sync(execute: { () -> (NSScreen, CGFloat?)? in
                  guard let screen = NSScreen.screens.first else { return nil }
                  return (screen, screen.auxiliaryTopRightArea?.minX)
              }) else {
            store(nil)
            return
        }
        let frame = screen.frame
        // An app with no menus of its own reports nothing useful.
        let menusEnd = frontMenusEnd().flatMap { $0 > frame.minX + 30 ? $0 : nil }
        // Icons that do not fit hide behind the notch and report a place
        // under it; the ones that show are all past it.
        let iconsStart = menuBarIconsStart(after: max(menusEnd ?? frame.minX, notchEnd ?? frame.minX), within: frame)
        guard menusEnd != nil || iconsStart != nil else {
            store(nil)
            return
        }
        // Positions come in global coordinates; as insets they carry over to
        // every screen's menu bar.
        store(Insets(left: (menusEnd ?? frame.midX) - frame.minX,
                     right: frame.maxX - (iconsStart ?? frame.maxX)))
    }

    private func store(_ insets: Insets?) {
        lock.lock()
        let changed = latest?.left != insets?.left || latest?.right != insets?.right
        latest = insets
        lock.unlock()
        if changed {
            if let insets {
                log.notice("Menu bar empty from \(Int(insets.left), privacy: .public) pt after the left edge to \(Int(insets.right), privacy: .public) pt before the right edge")
            } else {
                log.notice("Menu bar not measured: no Accessibility access")
            }
        }
    }

    /// The right edge of the front app's last menu title.
    private func frontMenusEnd() -> CGFloat? {
        guard let app = DispatchQueue.main.sync(execute: { NSWorkspace.shared.frontmostApplication }) else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.15)
        guard let bar = attribute(element, kAXMenuBarAttribute) else { return nil }
        return frames(of: bar).map(\.maxX).max()
    }

    /// The left edge of the leftmost menu bar icon that shows, from every app
    /// that has one, Control Center's clock and Wi-Fi included.
    ///
    /// Hidden icons still report a place. A menu bar manager puts them off
    /// the left edge of the screen; icons that do not fit go behind the notch;
    /// and icons tucked behind the system's « button lie stacked on top of
    /// one another just under it. Icons that show sit side by side, so the
    /// row is followed from the rightmost icon leftwards, one neighbour at a
    /// time, and stops at the first that overlaps the one before it.
    private func menuBarIconsStart(after menusEnd: CGFloat, within screen: CGRect) -> CGFloat? {
        let apps = DispatchQueue.main.sync { NSWorkspace.shared.runningApplications }
        var icons: [CGRect] = []
        for app in apps where app.activationPolicy != .prohibited || app.bundleIdentifier == "com.apple.controlcenter" {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.1)
            guard let extras = attribute(element, "AXExtrasMenuBar") else { continue }
            // Accessibility measures from the top left of the main screen.
            icons += frames(of: extras).filter {
                $0.width > 0 && $0.minX >= menusEnd && $0.maxX <= screen.maxX + 1 && $0.minY < 40
            }
        }
        var start: CGFloat?
        for icon in icons.sorted(by: { $0.minX > $1.minX }) {
            if let start, icon.maxX > start + 2 { break }
            start = icon.minX
        }
        return start
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// The frames of a menu bar's items.
    private func frames(of bar: AXUIElement) -> [CGRect] {
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement] else { return [] }
        return items.compactMap { item in
            var position: CFTypeRef?, size: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &position) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size) == .success,
                  let position, let size else { return nil }
            var point = CGPoint.zero, extent = CGSize.zero
            AXValueGetValue(position as! AXValue, .cgPoint, &point)
            AXValueGetValue(size as! AXValue, .cgSize, &extent)
            return CGRect(origin: point, size: extent)
        }
    }
}
