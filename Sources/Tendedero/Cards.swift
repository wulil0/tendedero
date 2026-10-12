import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// What hangs on the line besides screenshots and recordings: text copied to
/// the clipboard, and files copied in Finder. Neither has a picture of its
/// own, so each is drawn as a small card the line can hang like a photo.

/// Text copied to the clipboard. ClipboardWatcher saves it as a .txt file in
/// Tendedero's own folder, so on the line it behaves like any screenshot.
func isClippedText(_ url: URL) -> Bool {
    url.pathExtension.lowercased() == "txt"
        && url.standardizedFileURL.path.hasPrefix(Inbox.folder.standardizedFileURL.path + "/")
}

/// A file that is not a picture, a recording or copied text: a document or a
/// folder copied in Finder.
func isOtherFile(_ url: URL) -> Bool {
    guard !isRecording(url), !isClippedText(url) else { return false }
    let type = UTType(filenameExtension: url.pathExtension)
    return !(type?.conforms(to: .image) ?? false)
}

/// Cards are drawn at the same pixel width as a photo's thumbnail, three
/// quarters as tall, so they fit the card area the way a landscape shot does.
private func cardCanvas(width: Int) -> (w: CGFloat, h: CGFloat) {
    let w = CGFloat(max(width, 120))
    return (w, (w * 0.75).rounded())
}

private func drawCard(width: Int, draw: (CGRect) -> Void) -> NSImage? {
    let (w, h) = cardCanvas(width: width)
    // In sRGB from the start, so a colour card shows exactly the colour copied.
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let cg = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0,
                             space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
    draw(CGRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    guard let image = cg.makeImage() else { return nil }
    return NSImage(cgImage: image, size: NSSize(width: w, height: h))
}

// MARK: Light and dark

/// Whether cards are drawn for a dark appearance. The app sets it as the
/// system switches between light and dark, then draws every card again.
nonisolated(unsafe) var cardsAreDark = false

/// The colours cards are drawn in, as paper by day and as dark paper at
/// night, so a sheet of text does not glare on a dark screen.
private struct Palette {
    let paper: NSColor, ink: NSColor, faint: NSColor, accent: NSColor
    let codePaper: NSColor, codeInk: NSColor, filePaper: NSColor, fileInk: NSColor
    let checkerLight: CGFloat, checkerDark: CGFloat

    static var current: Palette { cardsAreDark ? dark : light }

    static let light = Palette(
        paper: NSColor(white: 0.985, alpha: 1), ink: NSColor(white: 0.13, alpha: 1),
        faint: NSColor(white: 0.45, alpha: 1), accent: NSColor(srgbRed: 0.18, green: 0.47, blue: 0.95, alpha: 1),
        codePaper: NSColor(srgbRed: 0.955, green: 0.962, blue: 0.972, alpha: 1),
        codeInk: NSColor(srgbRed: 0.16, green: 0.2, blue: 0.27, alpha: 1),
        filePaper: NSColor(white: 0.95, alpha: 1), fileInk: NSColor(white: 0.2, alpha: 1),
        checkerLight: 0.96, checkerDark: 0.86)

    static let dark = Palette(
        paper: NSColor(white: 0.17, alpha: 1), ink: NSColor(white: 0.9, alpha: 1),
        faint: NSColor(white: 0.6, alpha: 1), accent: NSColor(srgbRed: 0.42, green: 0.64, blue: 1, alpha: 1),
        codePaper: NSColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 1),
        codeInk: NSColor(srgbRed: 0.8, green: 0.85, blue: 0.92, alpha: 1),
        filePaper: NSColor(white: 0.2, alpha: 1), fileInk: NSColor(white: 0.86, alpha: 1),
        checkerLight: 0.32, checkerDark: 0.24)
}

// MARK: Copied text

/// What a piece of copied text is, for how its card shows it.
enum ClipKind {
    case plain
    /// One web address and nothing else.
    case link(URL)
    /// A colour written as #RGB, #RRGGBB, #RRGGBBAA or rgb()/rgba().
    case color(NSColor, String)
    /// Several lines that read as program code.
    case code
}

func classifyClip(_ raw: String) -> ClipKind {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.count <= 2048, !text.contains(where: \.isWhitespace),
       let url = URL(string: text), let scheme = url.scheme?.lowercased(),
       ["http", "https"].contains(scheme), url.host?.isEmpty == false {
        return .link(url)
    }
    if let color = parseColor(text) { return .color(color, text) }
    if looksLikeCode(text) { return .code }
    return .plain
}

private func parseColor(_ text: String) -> NSColor? {
    let lower = text.lowercased()
    if lower.hasPrefix("#") {
        var hex = String(lower.dropFirst())
        guard [3, 4, 6, 8].contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return nil }
        if hex.count <= 4 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard let value = UInt64(hex, radix: 16) else { return nil }
        let hasAlpha = hex.count == 8
        let v = hasAlpha ? value : value << 8 | 0xFF
        return NSColor(srgbRed: CGFloat(v >> 24 & 0xFF) / 255, green: CGFloat(v >> 16 & 0xFF) / 255,
                       blue: CGFloat(v >> 8 & 0xFF) / 255, alpha: CGFloat(v & 0xFF) / 255)
    }
    guard let open = lower.firstIndex(of: "("), lower.hasSuffix(")"),
          ["rgb", "rgba"].contains(String(lower[..<open])) else { return nil }
    let parts = lower[lower.index(after: open)..<lower.index(before: lower.endIndex)]
        .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
        .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard parts.count == 3 || parts.count == 4, parts.prefix(3).allSatisfy({ (0...255).contains($0) }) else { return nil }
    let alpha = parts.count == 4 ? (parts[3] > 1 ? parts[3] / 100 : parts[3]) : 1
    return NSColor(srgbRed: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, alpha: alpha)
}

/// Code has its own shape: lines ending in ; { or }, indented blocks, and
/// words like func, def, return or import.
private func looksLikeCode(_ text: String) -> Bool {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
    guard lines.count >= 2 else { return false }
    let keywords = try! NSRegularExpression(
        pattern: #"\b(func|def|class|struct|import|return|const|let|var|function|public|private|static|if|else|for|while|SELECT|FROM|WHERE)\b|#include|=>|->|::"#)
    var shaped = 0, keywordHits = 0
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let last = trimmed.last, ";{}".contains(last) { shaped += 1 }
        else if line.hasPrefix("    ") || line.hasPrefix("\t") { shaped += 1 }
        let ns = String(line)
        keywordHits += keywords.numberOfMatches(in: ns, range: NSRange(ns.startIndex..., in: ns))
    }
    return Double(shaped) / Double(lines.count) >= 0.4 || (keywordHits >= 2 && shaped >= 1)
}

/// Copied text on a sheet of paper. Plain text shows its first lines; a
/// link its site, large, and the rest of the address; a colour fills the
/// card with its code on it; code is set in a monospaced face on a cooler
/// sheet, keeping its indentation. Only the start of the file is read: the
/// card has room for a few lines at most.
func textCard(_ url: URL, maxPixels: Int) -> NSImage? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    let head = (try? handle.read(upToCount: 4096)) ?? Data()
    var text = String(decoding: head, as: UTF8.self)
    // A character cut in half at the end of what was read.
    if text.hasSuffix("\u{FFFD}") { text.removeLast() }
    let kind = classifyClip(text)
    if case .code = kind {
        // Indentation matters in code; only blank lines around it go.
        text = text.trimmingCharacters(in: .newlines)
    } else {
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return drawCard(width: maxPixels) { rect in
        let pad = rect.width * 0.07
        switch kind {
        case .link(let link):
            drawLink(link, in: rect, pad: pad)
        case .color(let color, let code):
            drawColor(color, code: code, in: rect, pad: pad)
        case .code:
            drawCode(text, in: rect, pad: pad)
        case .plain:
            Palette.current.paper.setFill()
            rect.fill()
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: rect.width * 0.068),
                .foregroundColor: Palette.current.ink,
                .paragraphStyle: style,
            ]).draw(with: rect.insetBy(dx: pad, dy: pad),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }
}

private func drawLink(_ link: URL, in rect: CGRect, pad: CGFloat) {
    let palette = Palette.current
    palette.paper.setFill()
    rect.fill()
    let accent = palette.accent
    // A small link mark, then the site, then the rest of the address.
    let mark = rect.width * 0.075
    if let symbol = NSImage(systemSymbolName: "link", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: mark, weight: .semibold).applying(.init(paletteColors: [accent]))) {
        symbol.draw(in: CGRect(x: rect.minX + pad, y: rect.maxY - pad - mark, width: mark * symbol.size.width / max(symbol.size.height, 1), height: mark))
    }
    var host = link.host ?? ""
    if host.hasPrefix("www.") { host.removeFirst(4) }
    let site = NSMutableParagraphStyle()
    site.lineBreakMode = .byTruncatingTail
    let siteTop = rect.maxY - pad - mark - rect.width * 0.03
    let siteHeight = rect.width * 0.11
    NSAttributedString(string: host, attributes: [
        .font: NSFont.systemFont(ofSize: rect.width * 0.085, weight: .semibold),
        .foregroundColor: palette.ink,
        .paragraphStyle: site,
    ]).draw(with: CGRect(x: rect.minX + pad, y: siteTop - siteHeight, width: rect.width - pad * 2, height: siteHeight),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    var rest = link.path
    if let query = link.query { rest += "?" + query }
    if rest == "/" { rest = "" }
    let wrap = NSMutableParagraphStyle()
    wrap.lineBreakMode = .byCharWrapping
    NSAttributedString(string: rest, attributes: [
        .font: NSFont.systemFont(ofSize: rect.width * 0.055),
        .foregroundColor: palette.faint,
        .paragraphStyle: wrap,
    ]).draw(with: CGRect(x: rect.minX + pad, y: rect.minY + pad, width: rect.width - pad * 2,
                         height: siteTop - siteHeight - rect.width * 0.02 - rect.minY - pad),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
}

private func drawColor(_ color: NSColor, code: String, in rect: CGRect, pad: CGFloat) {
    // A see-through colour shows over a light checkerboard, as in a picker.
    if color.alphaComponent < 1 {
        let square = rect.width / 16
        for row in 0..<Int(ceil(rect.height / square)) {
            for column in 0..<16 {
                let palette = Palette.current
                NSColor(white: (row + column).isMultiple(of: 2) ? palette.checkerLight : palette.checkerDark,
                        alpha: 1).setFill()
                CGRect(x: rect.minX + CGFloat(column) * square, y: rect.minY + CGFloat(row) * square,
                       width: square, height: square).fill()
            }
        }
    }
    color.setFill()
    rect.fill(using: .sourceOver)
    // The code in white on a dark colour and in black on a light one.
    let rgb = color.usingColorSpace(.sRGB) ?? color
    let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    let light = luminance * rgb.alphaComponent + (1 - rgb.alphaComponent) * 0.9 > 0.6
    // As large as fits across the card, up to a size.
    var size = rect.width * 0.07
    let font = { NSFont.monospacedSystemFont(ofSize: size, weight: .semibold) }
    let room = rect.width - pad * 2
    let width = (code as NSString).size(withAttributes: [.font: font()]).width
    if width > room { size *= room / width }
    NSAttributedString(string: code, attributes: [
        .font: font(),
        .foregroundColor: light ? NSColor(white: 0, alpha: 0.72) : NSColor(white: 1, alpha: 0.92),
    ]).draw(at: CGPoint(x: rect.minX + pad, y: rect.minY + pad))
}

private func drawCode(_ text: String, in rect: CGRect, pad: CGFloat) {
    Palette.current.codePaper.setFill()
    rect.fill()
    let style = NSMutableParagraphStyle()
    // Long lines run off the edge rather than wrap, as in an editor.
    style.lineBreakMode = .byClipping
    style.lineHeightMultiple = 1.08
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).prefix(14)
        .map { $0.replacingOccurrences(of: "\t", with: "    ") }
    NSAttributedString(string: lines.joined(separator: "\n"), attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: rect.width * 0.05, weight: .regular),
        .foregroundColor: Palette.current.codeInk,
        .paragraphStyle: style,
    ]).draw(with: rect.insetBy(dx: pad * 0.8, dy: pad * 0.8), options: [.usesLineFragmentOrigin])
}

// MARK: Formatting

/// Formatting kept from a copy, beside the text it belongs to: RTF from apps
/// like Word or Pages, HTML from a browser.
let richExtensions: Set<String> = ["rtf", "html"]

/// The formatting kept for copied text, if any, and how it pastes.
func richCompanion(of url: URL) -> (URL, NSPasteboard.PasteboardType)? {
    guard isClippedText(url) else { return nil }
    let base = url.deletingPathExtension()
    for (ext, type) in [("rtf", NSPasteboard.PasteboardType.rtf), ("html", .html)] {
        let rich = base.appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: rich.path) { return (rich, type) }
    }
    return nil
}

// MARK: Files

/// A file shows its icon, or a preview once Quick Look has made one, above
/// its name.
func fileCard(_ url: URL, preview: NSImage? = nil, maxPixels: Int) -> NSImage? {
    let icon = preview ?? NSWorkspace.shared.icon(forFile: url.path)
    let name = FileManager.default.displayName(atPath: url.path)
    return drawCard(width: maxPixels) { rect in
        Palette.current.filePaper.setFill()
        rect.fill()
        let pad = rect.width * 0.06
        let nameHeight = rect.width * 0.11
        // The picture fits the space above the name, keeping its proportions.
        let box = CGRect(x: rect.minX + pad, y: rect.minY + pad + nameHeight,
                         width: rect.width - pad * 2, height: rect.height - pad * 2 - nameHeight)
        let size = icon.size
        if size.width > 0, size.height > 0 {
            let scale = min(box.width / size.width, box.height / size.height)
            let w = size.width * scale, h = size.height * scale
            icon.draw(in: CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h))
        }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingMiddle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: rect.width * 0.062, weight: .medium),
            .foregroundColor: Palette.current.fileInk,
            .paragraphStyle: style,
        ]
        NSAttributedString(string: name, attributes: attributes).draw(
            in: CGRect(x: rect.minX + pad, y: rect.minY + pad * 0.6, width: rect.width - pad * 2, height: nameHeight))
    }
}

/// Asks Quick Look for a real preview of a file, like the first page of a
/// PDF. It arrives later, on the main thread, and only if there is one: an
/// icon is no better than the card already has.
func requestFilePreview(_ url: URL, maxPixels: Int, done: @escaping @MainActor (NSImage) -> Void) {
    let side = CGFloat(maxPixels)
    let request = QLThumbnailGenerator.Request(
        fileAt: url, size: CGSize(width: side, height: side), scale: 1, representationTypes: .thumbnail)
    QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
        guard let cg = thumbnail?.cgImage else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                done(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
            }
        }
    }
}
