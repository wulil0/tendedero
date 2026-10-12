import AppKit
import AVFoundation
import Combine
import os
import SwiftUI

let log = Logger(subsystem: "app.tendedero.Tendedero", category: "line")

/// One screenshot hanging on the line, or a recording, copied text or a
/// copied file.
struct Pegged: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var thumb: NSImage
    /// Every photo hangs a little crooked, like on a real line.
    let tilt = Double.random(in: -2.5...2.5)
    var falling = false
    /// Still flying in from where it was captured; the card waits hidden.
    var flying = false
    /// Pushed off the end of a full line into the history. It still hangs,
    /// left of the rest, and is reached by scrolling.
    var archived = false
    /// Pinned to the line: a full line never pushes it into the history,
    /// and Take everything down leaves it.
    var pinned = false
    /// When the file was last changed, to notice it was edited, like text
    /// changed in its editor, and draw the card again.
    var modified: Date?
    /// What history search looks in: the name, and the words of copied text.
    var searchText = ""
    /// Copied text that kept its formatting, as an .rtf or .html beside it.
    var isRich = false
    /// The clothespin it hangs from, which tells its kind at a glance.
    var clip: ClipFinish = .aluminium
    /// A screen recording rather than a screenshot.
    var isRecording: Bool { Tendedero.isRecording(url) }
    /// Text copied to the clipboard, kept as a .txt in Tendedero's folder.
    var isText: Bool { Tendedero.isClippedText(url) }
    /// A document or folder copied in Finder, hung where it is.
    var isFile: Bool { Tendedero.isOtherFile(url) }
    /// A picture, which copies as one and opens in Markup.
    var isPicture: Bool { !isRecording && !isText && !isFile }

    static func == (a: Pegged, b: Pegged) -> Bool {
        a.id == b.id && a.falling == b.falling && a.flying == b.flying && a.archived == b.archived
            && a.pinned == b.pinned && a.clip == b.clip && a.thumb === b.thumb
    }
}

/// The line itself: what hangs on it and what you can do with each item.
/// The files never move. The line is only a view onto them.
@MainActor
final class Line: ObservableObject {
    /// Oldest first. The history, if any, comes first: it hangs at the left.
    @Published private(set) var items: [Pegged] = [] {
        didSet { if historyExpanded && !hasHistory { historyExpanded = false } }
    }
    /// The history waits piled up in the space kept at the left end of the
    /// line. A click on the pile hangs all of it along the line.
    @Published private(set) var historyExpanded = false
    /// Typed in the search tag under an expanded history: only history cards
    /// that match hang along the line.
    @Published var query = "" {
        didSet { if query != oldValue && historyExpanded { showNewestHistory() } }
    }
    /// The search tag's entry in `hitRects`.
    static let searchID = UUID()
    /// Resting the pointer on the pile spreads the history out once. After
    /// that, until the line tucks away, only a click does, or piling it up
    /// again would spread it right back out under the pointer.
    private(set) var hoverExpandSpent = false
    /// When the history last spread out, so the click someone was already
    /// making to open it does not close it again.
    private(set) var expandedAt = Date.distantPast
    /// The history pile's entry in `hitRects`.
    static let historyID = UUID()
    /// Past this, the oldest entries leave the history for good: to the Trash
    /// from Tendedero's folder, or the folder would only ever grow.
    nonisolated static let historyLimit = 100
    @Published private(set) var gust = 0
    @Published var copiedID: UUID?
    @Published var draggingID: UUID?
    @Published var pressedID: UUID?
    /// The card chosen with the arrow keys, while the line has the keyboard.
    @Published var selectedID: UUID?
    /// Whether the line has slid down into view.
    @Published var revealed = false {
        // Once the line tucks away, the history goes back on its pile.
        didSet {
            guard !revealed else { return }
            if historyExpanded { collapseHistory() }
            hoverExpandSpent = false
        }
    }

    /// Card frames in window coordinates, reported by the views. The panel
    /// uses them to only catch clicks over photos and let the rest through.
    var hitRects: [UUID: CGRect] = [:]

    var maxItems = 8
    /// How many photos fit across the screen. With Keep on line set, the
    /// line can hold more, and the rest are reached by scrolling.
    var visibleCount = 8
    /// How far the line is scrolled towards older photos, in points; 0 shows
    /// the newest.
    @Published var scroll: CGFloat = 0

    /// Keep on line, from the menu bar: how many photos the line keeps, or
    /// nil for as many as fit across the screen.
    nonisolated static let keepChoices = [25, 50, 100]
    nonisolated static var keepOnLine: Int? {
        get {
            let n = UserDefaults.standard.integer(forKey: "keepOnLine")
            return keepChoices.contains(n) ? n : nil
        }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: "keepOnLine") }
    }


    var soundOn: Bool {
        get { !UserDefaults.standard.bool(forKey: "soundOff") }
        set { UserDefaults.standard.set(!newValue, forKey: "soundOff") }
    }

    /// Every card on the line, the history included.
    var liveCount: Int { items.filter { !$0.falling }.count }
    /// The cards that count towards a full line: everything but the history.
    var hangingCount: Int { items.filter { !$0.falling && !$0.archived }.count }

    /// What a full line pushed past its length, newest first.
    var history: [URL] { items.filter { $0.archived && !$0.falling }.reversed().map(\.url) }
    var hasHistory: Bool { items.contains { $0.archived && !$0.falling } }

    /// Whether a card sits hidden on the history pile rather than on the line:
    /// all history while it is piled up, and while searching, every card the
    /// search leaves out, so only what it found hangs.
    func isPiled(_ item: Pegged) -> Bool {
        if searching { return !matches(item) }
        return item.archived && !historyExpanded
    }

    /// Typing in the search tag, which only shows while the history is out.
    var searching: Bool { historyExpanded && !query.isEmpty }

    private func matches(_ item: Pegged) -> Bool {
        query.isEmpty || item.searchText.localizedCaseInsensitiveContains(query)
    }

    /// How many cards the search finds, on the line and in the history.
    var matchCount: Int { items.filter { !$0.falling && matches($0) }.count }

    /// The cards laid out along the line: the history only once expanded.
    private var shown: [Pegged] { items.filter { !isPiled($0) } }
    var shownCount: Int { shown.count }

    /// The newest few history cards, top of the pile first, and whether each
    /// is a picture, which sits under a veil in the dark.
    var pileThumbs: [(image: NSImage, isPicture: Bool)] {
        items.filter { $0.archived && !$0.falling }.suffix(3).reversed()
            .map { ($0.thumb, $0.isPicture || $0.isRecording) }
    }

    private let storeKey = "pegged"
    private let historyKey = "history"
    private let pinnedKey = "pinned"

    /// An expanded history makes the line longer than the screen: it keeps
    /// its spacing and is moved along by scrolling, as with Keep on line.
    var scrolls: Bool { Line.keepOnLine != nil || (historyExpanded && hasHistory) }

    /// The history pile takes the first place on the line, spaced like a
    /// card, so the whole row stays centred with even gaps.
    private var lead: Int { hasHistory ? 1 : 0 }

    /// How many history cards an expanded history shows at once, between the
    /// pile and the empty place at the other end.
    nonisolated static let historyShown = 6

    /// The line's width, from the panel, for working out how far it scrolls.
    var width: CGFloat = 1440

    /// The places along a scrolling row, and how far apart they hang. An
    /// expanded history always gets the pile, `historyShown` cards and the
    /// empty place; on a narrow screen the gaps shrink to make them fit.
    private func row(width: CGFloat) -> (slots: Int, step: CGFloat) {
        guard historyExpanded && hasHistory else { return (visibleCount, Layout.spacing) }
        let slots = Line.historyShown + 2
        return (slots, min(Layout.spacing, (width - 80) / CGFloat(slots - 1)))
    }

    /// Whether the line is longer than fits and is moved along by scrolling.
    private func scrolling(width: CGFloat) -> Bool {
        scrolls && shownCount + lead + trail > row(width: width).slots
    }

    /// Whether the line scrolls on the panel's own width.
    var isScrolling: Bool { scrolling(width: width) }

    /// While a line with history scrolls, the last place of the row stays
    /// empty, to match the pile at the other end; cards fade into it.
    private var trail: Int { hasHistory && scrolls ? 1 : 0 }

    /// Where the history pile hangs. While the line scrolls it stays put in
    /// the first place of a full row, and the cards pass under it.
    func pileX(width: CGFloat) -> CGFloat {
        if scrolling(width: width) {
            let (slots, step) = row(width: width)
            return width / 2 - CGFloat(slots - 1) * step / 2
        }
        return Layout.x(index: 0, count: shownCount + lead, width: width, visible: visibleCount,
                        scroll: 0, scrolls: false)
    }

    /// Where the card at `index` hangs. A piled card waits on the pile.
    func x(of index: Int, width: CGFloat) -> CGFloat {
        let item = items[index]
        if isPiled(item) { return pileX(width: width) }
        let shown = shown
        let i = shown.firstIndex { $0.id == item.id } ?? index
        if scrolling(width: width) {
            // The newest hangs in the last place of a full row (or the one
            // before the empty place), the rest further left, brought into
            // view by scrolling.
            let (slots, step) = row(width: width)
            let newest = width / 2 + CGFloat(slots - 1) * step / 2 - CGFloat(trail) * step
            return newest - CGFloat(shown.count - 1 - i) * step + scroll
        }
        return Layout.x(index: i + lead, count: shown.count + lead, width: width, visible: visibleCount,
                        scroll: 0, scrolls: false)
    }

    /// How see-through a card is: cards fade before they reach the screen's
    /// edge, or slide under the history pile.
    func opacity(at x: CGFloat, width: CGFloat) -> CGFloat {
        let step = row(width: width).step
        let left = hasHistory ? pileX(width: width) + step * 0.3 : 0
        // With the empty place kept on the right, cards fade into it the
        // same way they slide under the pile.
        var right = width
        if trail > 0 && scrolling(width: width) {
            right = width / 2 + CGFloat(row(width: width).slots - 1) * step / 2 - step * 0.3
        }
        return min(1, max(0, min(x - left, right - x) / 90))
    }

    /// How far the line can scroll, in points.
    private var mostScroll: CGFloat {
        guard scrolling(width: width) else { return 0 }
        let (slots, step) = row(width: width)
        return CGFloat(max(0, shownCount + lead + trail - slots)) * step
    }

    init() {
        restore()
        scheduleGust()
    }

    // MARK: Hanging and dropping

    @discardableResult
    func hang(_ url: URL, quietly: Bool = false, flying: Bool = false) -> UUID? {
        let item: Pegged
        if let i = items.firstIndex(where: { $0.url == url && !$0.falling }) {
            // Already hanging, or in the history: copied or hung again, it
            // moves to the newest end instead of hanging twice.
            var again = items.remove(at: i)
            again.archived = false
            items.append(again)
            item = again
        } else {
            guard let thumb = thumbnail(url) else { return nil }
            var new = Pegged(url: url, thumb: thumb)
            new.flying = flying
            new.modified = modifiedDate(url)
            new.searchText = searchKey(url)
            new.isRich = richCompanion(of: url) != nil
            new.clip = clipFinish(for: url)
            items.append(new)
            indexContent(url)
            item = new
        }
        scroll = 0
        // A full line moves the oldest photo into the history. Only one: a
        // line hung on a wider screen keeps its length here instead of losing
        // several photos to a single capture. Pinned photos stay.
        if hangingCount > maxItems, let oldest = oldestUnpinned {
            archive(oldest.id)
        }
        save()
        if !quietly { play("Tink", volume: 0.35) }
        return item.id
    }

    /// The capture has reached the line: the real card takes over.
    func land(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].flying = false
    }

    /// Called just before a photo starts falling, so the fall can be drawn
    /// over the whole screen.
    var onFall: ((Pegged) -> Void)?

    /// The card the pointer rests on, for the enlarged preview below it.
    private(set) var hoveredID: UUID?
    var onHover: ((Pegged?) -> Void)?

    /// Leaving one card for the next can report the new one first, so only
    /// the card that is still hovered may end the hover.
    func hover(_ id: UUID, _ on: Bool) {
        if on {
            hoveredID = id
        } else if hoveredID == id {
            hoveredID = nil
        } else {
            return
        }
        onHover?(hoveredID.flatMap { id in items.first { $0.id == id && !$0.falling } })
    }

    func drop(_ id: UUID, quietly: Bool = false) {
        guard let i = items.firstIndex(where: { $0.id == id }), !items[i].falling else { return }
        onFall?(items[i])
        let wasHanging = !items[i].archived
        items[i].falling = true
        hitRects[id] = nil
        if wasHanging { refill() }
        save()
        if !quietly { play("Pop", volume: 0.25) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.items.removeAll { $0.id == id }
        }
    }

    /// "Take everything down": every photo goes the way of its corner cross.
    /// The history stays where it is; it has its own Clear history. Pinned
    /// photos stay too.
    func clear() {
        let live = items.filter { !$0.falling && !$0.archived && !$0.pinned }
        refillPaused = true
        takeDown(live)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(live.count) + 0.1) { [weak self] in
            self?.refillPaused = false
        }
    }

    /// While everything is being taken down, the history must not come back
    /// down to take its place.
    private var refillPaused = false

    /// A card taken off a line that is no longer full makes room: the newest
    /// history card comes back to fill it. It already hangs next to the
    /// oldest card on the line, so it only stops being history.
    private func refill() {
        guard !refillPaused, hangingCount < maxItems,
              let i = items.lastIndex(where: { $0.archived && !$0.falling }) else { return }
        items[i].archived = false
    }

    /// The photos hung before (left) or after (right) this one.
    func neighbours(of id: UUID, toTheLeft: Bool) -> [Pegged] {
        let live = items.filter { !$0.falling }
        guard let i = live.firstIndex(where: { $0.id == id }) else { return [] }
        return toTheLeft ? Array(live[..<i]) : Array(live[(i + 1)...])
    }

    /// Takes down everything on one side of a photo. Each one goes the way
    /// of its own corner button: to the Trash from Tendedero's folder, and
    /// only off the line from anywhere else.
    func takeDown(_ id: UUID, toTheLeft: Bool) {
        takeDown(neighbours(of: id, toTheLeft: toTheLeft))
    }

    /// One after another, and only the first makes a sound.
    private func takeDown(_ live: [Pegged]) {
        for (n, item) in live.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(n)) { [weak self] in
                self?.discard(item.id, quietly: n > 0)
            }
        }
    }

    /// Photos whose file was deleted or moved away fall off by themselves.
    func prune() {
        for item in items where !item.falling && !FileManager.default.fileExists(atPath: item.url.path) {
            drop(item.id, quietly: true)
        }
        removeOrphanedFormatting()
    }

    /// Formatting kept beside copied text goes with it. Once the text has
    /// left Tendedero's folder, by the Trash, Save to Desktop or a drag, the
    /// formatting left behind goes to the Trash too.
    private func removeOrphanedFormatting() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: Inbox.folder.path) else { return }
        for name in names where richExtensions.contains((name as NSString).pathExtension.lowercased()) {
            let rich = Inbox.folder.appendingPathComponent(name)
            let text = rich.deletingPathExtension().appendingPathExtension("txt")
            if !fm.fileExists(atPath: text.path) { try? fm.trashItem(at: rich, resultingItemURL: nil) }
        }
    }

    // MARK: Actions on one photo

    func copy(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }), copy(item.url) else { return }
        copiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.copiedID == id { self?.copiedID = nil }
        }
    }

    /// Puts a photo, text or file on the clipboard the way its kind pastes.
    @discardableResult
    func copy(_ url: URL) -> Bool {
        let entry = NSPasteboardItem()
        if isClippedText(url) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                NSSound.beep()
                return false
            }
            entry.setString(text, forType: .string)
            // Formatting kept from the copy pastes back as it was.
            if let (rich, type) = richCompanion(of: url), let data = try? Data(contentsOf: rich) {
                entry.setData(data, forType: type)
            }
            // A link also pastes as a link.
            if case .link = classifyClip(text) { entry.setString(text.trimmingCharacters(in: .whitespacesAndNewlines), forType: .URL) }
        } else {
            // A recording or another file is copied as the file, which apps
            // paste as the video and Finder as the file itself.
            if !isRecording(url), !isOtherFile(url), let png = pngData(url) { entry.setData(png, forType: .png) }
            entry.setString(url.absoluteString, forType: .fileURL)
        }
        // So the clipboard watcher does not hang it a second time.
        entry.setData(Data(), forType: ClipboardWatcher.ownType)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([entry])
        return true
    }

    func open(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.open(item.url)
    }

    /// Moves the file to the Trash and takes the photo off the line. When a
    /// drag ends on the Dock's Trash, macOS only reports it: deleting the file
    /// is the source app's job, as Finder does.
    @discardableResult
    func trash(_ id: UUID, quietly: Bool = false) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            if let (rich, _) = richCompanion(of: item.url) { try? FileManager.default.trashItem(at: rich, resultingItemURL: nil) }
            log.notice("Trashed \(item.url.lastPathComponent, privacy: .public)")
            if soundOn && !quietly { Line.trashSound?.play() }
            drop(id, quietly: true)
            return true
        } catch {
            log.error("Could not trash \(item.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            if !quietly { NSSound.beep() }
            return false
        }
    }

    private static let trashSound = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif",
        byReference: true)

    /// Whether the file lives in Tendedero's own folder. Those are discarded
    /// to the Trash, or the folder would fill up with forgotten screenshots.
    /// Files anywhere else, like the Desktop, stay where they are.
    func isInInbox(_ id: UUID) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        return Line.isInInbox(item.url)
    }

    nonisolated static func isInInbox(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(Inbox.folder.standardizedFileURL.path + "/")
    }

    /// The corner cross and "Take down" both end up here.
    func discard(_ id: UUID, quietly: Bool = false) {
        if isInInbox(id) { trash(id, quietly: quietly) } else { drop(id, quietly: quietly) }
    }

    /// Moves along a line that holds more than fit, from a scroll gesture.
    /// Where the gesture has dragged the line, before its ends resist.
    private var dragged: CGFloat?
    private var settleWork: DispatchWorkItem?

    /// Moves along a line that holds more than fit, from a scroll gesture.
    /// Past either end the line gives a little, harder the further it goes,
    /// like a real line pulled taut, and springs back when let go. The
    /// momentum of a flick that runs into an end bounces off it.
    func scroll(by delta: CGFloat, momentum: Bool = false) {
        guard scrolling(width: width) else { return }
        let most = mostScroll
        let raw = (dragged ?? scroll) + delta
        dragged = raw
        let next = Line.resist(raw, in: 0...most)
        if next != scroll { scroll = next }
        if momentum && (next < -24 || next > most + 24) {
            endScroll()
            return
        }
        // A mouse wheel never says its gesture ended: settle once it stops.
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.endScroll() }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// The gesture is over: past an end, the line springs back to it.
    func endScroll() {
        settleWork?.cancel()
        settleWork = nil
        dragged = nil
        let bounded = min(mostScroll, max(0, scroll))
        guard bounded != scroll else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { scroll = bounded }
    }

    /// How far the line actually goes when pulled `x` past an end: less and
    /// less, up to a limit, the way a stretched line resists.
    nonisolated static func resist(_ x: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        let limit: CGFloat = 90
        func pull(_ over: CGFloat) -> CGFloat { (1 - 1 / (over * 0.5 / limit + 1)) * limit }
        if x < range.lowerBound { return range.lowerBound - pull(range.lowerBound - x) }
        if x > range.upperBound { return range.upperBound + pull(x - range.upperBound) }
        return x
    }

    /// After Keep on line is lowered, the oldest photos past it go into the
    /// history, as on a full line.
    func trim() {
        while hangingCount > maxItems, let oldest = oldestUnpinned {
            archive(oldest.id)
        }
        scroll = 0
    }

    // MARK: History

    /// The oldest photo on a full line joins the history. It keeps its place,
    /// which is already right of the older history and left of the rest.
    private func archive(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), !items[i].pinned else { return }
        items[i].archived = true
        // Past the limit, the oldest entries leave for good, the way a full
        // line used to drop them.
        var archived = items.filter { $0.archived && !$0.falling }
        while archived.count > Line.historyLimit {
            let oldest = archived.removeFirst()
            if isInInbox(oldest.id), trash(oldest.id, quietly: true) { continue }
            drop(oldest.id, quietly: true)
        }
        save()
    }

    /// Every history card goes up on the line, and the line moves along to
    /// them: the newest history comes into view where the newest cards were.
    func expandHistory() {
        guard hasHistory else { return }
        historyExpanded = true
        hoverExpandSpent = true
        expandedAt = Date()
        showNewestHistory()
    }

    /// Moves the line so the newest history hangs where the newest cards
    /// were; while searching, so the newest of what it found is in view.
    private func showNewestHistory() {
        scroll = searching ? 0 : min(mostScroll, CGFloat(hangingCount) * row(width: width).step)
    }

    func collapseHistory() {
        historyExpanded = false
        query = ""
        scroll = 0
    }

    /// Hangs an entry back on the line, at the newest end.
    func hangAgain(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            prune()
            NSSound.beep()
            return
        }
        hang(url)
    }

    /// Takes an entry out of the history, the way of its corner cross.
    func removeFromHistory(_ url: URL) {
        guard let item = items.first(where: { $0.url == url && $0.archived && !$0.falling }) else { return }
        discard(item.id)
    }

    func clearHistory() {
        takeDown(items.filter { $0.archived && !$0.falling })
    }

    /// Inbox mode: keep a screenshot by moving it to the Desktop.
    func saveToDesktop(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let target = uniqueURL(in: desktop, for: item.url.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: item.url, to: target)
            drop(id, quietly: true)
        } catch {
            log.error("Could not save to Desktop: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    private func uniqueURL(in folder: URL, for name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    /// Long press: open the photo in the system Markup editor. Markup does
    /// not edit video, so a recording opens in the trimming editor instead.
    /// Copied text opens in the text editor, and a file in Quick Look.
    func markup(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if item.isRecording {
            Trim.shared.edit(item.url, size: item.thumb.size)
        } else if item.isText {
            NSWorkspace.shared.open(item.url)
        } else if item.isFile {
            quickLook(id)
        } else {
            Markup.shared.edit(item.url)
        }
    }

    /// After editing, the photo on the line shows the new version.
    func reloadThumbnail(for url: URL) {
        guard let i = items.firstIndex(where: { $0.url == url && !$0.falling }),
              let thumb = thumbnail(url) else { return }
        items[i].thumb = thumb
        items[i].modified = modifiedDate(url)
        items[i].searchText = searchKey(url)
        items[i].clip = clipFinish(for: url)
        indexContent(url)
    }

    /// Cards whose file changed since they were drawn, like copied text
    /// edited after a long press, are drawn again. Checked as the line
    /// comes down, which is when it would be seen.
    func reloadEdited() {
        for item in items where !item.falling {
            if let date = modifiedDate(item.url), date != item.modified { reloadThumbnail(for: item.url) }
        }
    }

    // MARK: Pinning

    private var oldestUnpinned: Pegged? {
        items.first { !$0.falling && !$0.archived && !$0.pinned }
    }

    func togglePin(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].pinned.toggle()
        // A pinned history card comes back up onto the line.
        if items[i].pinned && items[i].archived { hang(items[i].url, quietly: true) }
        // Unpinning on a line over its length lets the oldest go.
        while hangingCount > maxItems, let oldest = oldestUnpinned { archive(oldest.id) }
        save()
    }

    // MARK: Text

    /// The card already holding exactly this text, on the line or in the
    /// history, so copying it again moves that card instead of adding one.
    func findText(_ text: String) -> URL? {
        let data = Data(text.utf8)
        for item in items.reversed() where !item.falling && item.isText {
            let size = (try? item.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            guard size == data.count, (try? Data(contentsOf: item.url)) == data else { continue }
            return item.url
        }
        return nil
    }

    // MARK: Keyboard

    /// The cards the arrow keys move between: those laid out on the line.
    private var selectable: [Pegged] { items.filter { !$0.falling && !isPiled($0) } }

    /// Taking the keyboard selects the newest card.
    func selectNewest() {
        selectedID = items.last { !$0.falling && !$0.archived }?.id
        reveal(selected: selectedID)
    }

    func moveSelection(by step: Int) {
        let cards = selectable
        guard !cards.isEmpty else { return }
        let i = cards.firstIndex { $0.id == selectedID } ?? cards.count - 1
        let next = cards[min(max(i + step, 0), cards.count - 1)]
        selectedID = next.id
        reveal(selected: next.id)
    }

    /// The Nth newest card on the line, for ⌘1 to ⌘9.
    func newest(_ n: Int) -> Pegged? {
        let current = items.filter { !$0.falling && !$0.archived }
        return n >= 1 && n <= current.count ? current[current.count - n] : nil
    }

    /// Scrolls just enough to bring the selected card fully into view.
    private func reveal(selected id: UUID?) {
        guard let id, let index = items.firstIndex(where: { $0.id == id }) else { return }
        let x = x(of: index, width: width)
        let margin = Layout.spacing
        if opacity(at: x, width: width) < 1 || x < margin || x > width - margin {
            // Moving the line right brings older cards in, and the other way.
            let next = min(mostScroll, max(0, scroll + width / 2 - x))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { scroll = next }
        }
    }

    /// Quick Look on this photo, with the rest of the line a key press away.
    func quickLook(_ id: UUID) {
        let live = items.filter { !$0.falling }
        guard let index = live.firstIndex(where: { $0.id == id }) else { return }
        QuickLook.shared.show(live.map(\.url), at: index)
    }

    /// After a change of size, every photo is redrawn sharp at the new one.
    func reloadThumbnails() {
        for i in items.indices where !items[i].falling {
            if let thumb = thumbnail(items[i].url) { items[i].thumb = thumb }
        }
    }

    func reveal(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: Breeze

    /// Every so often a little wind moves the line. It is the detail that
    /// makes it feel like an object and not a widget.
    private func scheduleGust() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 7...16)) { [weak self] in
            guard let self else { return }
            if !self.items.isEmpty && self.draggingID == nil { self.gust += 1 }
            self.scheduleGust()
        }
    }

    // MARK: Persistence

    private func save() {
        let paths = items.filter { !$0.falling && !$0.archived }.map(\.url.path)
        UserDefaults.standard.set(paths, forKey: storeKey)
        UserDefaults.standard.set(history.map(\.path), forKey: historyKey)
        UserDefaults.standard.set(items.filter { $0.pinned && !$0.falling }.map(\.url.path), forKey: pinnedKey)
        SearchIndex.shared.keep(only: Set(items.filter { !$0.falling }.map(\.url.path)))
    }

    /// Everything comes back as it was. This runs before the line knows its
    /// screen, so the capacity is still the default one: hanging through
    /// `hang` would let photos fall off a wide screen's line at every launch.
    private func restore() {
        // The history is kept newest first and hangs oldest first. Anything
        // also on the line proper hangs there instead.
        let paths = UserDefaults.standard.stringArray(forKey: storeKey) ?? []
        let pinned = Set(UserDefaults.standard.stringArray(forKey: pinnedKey) ?? [])
        let history = (UserDefaults.standard.stringArray(forKey: historyKey) ?? [])
            .filter { !paths.contains($0) }.reversed()
        for (path, archived) in history.map({ ($0, true) }) + paths.map({ ($0, false) })
        where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            guard !items.contains(where: { $0.url == url }), let thumb = thumbnail(url) else { continue }
            var item = Pegged(url: url, thumb: thumb)
            item.archived = archived
            item.pinned = pinned.contains(path) && !archived
            item.modified = modifiedDate(url)
            item.searchText = searchKey(url)
            item.isRich = richCompanion(of: url) != nil
            item.clip = clipFinish(for: url)
            items.append(item)
            indexContent(url)
        }
        removeOrphanedFormatting()
    }

    // MARK: Helpers

    /// Adds the words inside a picture or file to what search looks in, once
    /// they have been read in the background. Copied text has its own.
    private func indexContent(_ url: URL) {
        guard !isClippedText(url) else { return }
        SearchIndex.shared.text(for: url, modified: modifiedDate(url)) { [weak self] text in
            guard let self else { return }
            let key = self.searchKey(url) + " " + text
            for i in self.items.indices where self.items[i].url == url { self.items[i].searchText = key }
        }
    }

    /// The name, and for copied text its first words, for search.
    private func searchKey(_ url: URL) -> String {
        var key = FileManager.default.displayName(atPath: url.path)
        if isClippedText(url), let handle = try? FileHandle(forReadingFrom: url) {
            key += " " + String(decoding: (try? handle.read(upToCount: 8192)) ?? Data(), as: UTF8.self)
            try? handle.close()
        }
        return key
    }

    private func modifiedDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// A file's card first shows its icon. When Quick Look has a real preview,
    /// like the first page of a PDF, the card is drawn again with it.
    private func thumbnail(_ url: URL) -> NSImage? {
        guard let thumb = makeThumbnail(url) else { return nil }
        if isOtherFile(url) {
            let pixels = Int(320 * Layout.size.scale)
            requestFilePreview(url, maxPixels: pixels) { [weak self] preview in
                guard let self, let i = self.items.firstIndex(where: { $0.url == url && !$0.falling }),
                      let card = fileCard(url, preview: preview, maxPixels: pixels) else { return }
                self.items[i].thumb = card
            }
        }
        return thumb
    }

    private func play(_ name: String, volume: Float) {
        guard soundOn, let sound = NSSound(named: name)?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }

    private func pngData(_ url: URL) -> Data? {
        if url.pathExtension.lowercased() == "png" { return try? Data(contentsOf: url) }
        guard let tiff = NSImage(contentsOf: url)?.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// Screen recordings, as macOS saves them.
func isRecording(_ url: URL) -> Bool {
    ["mov", "mp4"].contains(url.pathExtension.lowercased())
}

/// The default size covers a card at twice its size in points, as on a
/// Retina screen, and no more: every photo on the line keeps one in memory.
func makeThumbnail(_ url: URL, maxPixels: Int = Int(320 * Layout.size.scale)) -> NSImage? {
    if isRecording(url) { return firstFrame(url, maxPixels: maxPixels) }
    if isClippedText(url) { return textCard(url, maxPixels: maxPixels) }
    if isOtherFile(url) { return fileCard(url, maxPixels: maxPixels) }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}

/// A recording shows its first frame.
private func firstFrame(_ url: URL, maxPixels: Int) -> NSImage? {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: maxPixels, height: maxPixels)
    guard let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}
