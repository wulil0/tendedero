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
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw(CGRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: NSSize(width: w, height: h))
    image.addRepresentation(rep)
    return image
}

/// Copied text shows its first lines on a sheet of paper. Only the start of
/// the file is read: the card has room for a few lines at most.
func textCard(_ url: URL, maxPixels: Int) -> NSImage? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    let head = (try? handle.read(upToCount: 4096)) ?? Data()
    var text = String(decoding: head, as: UTF8.self)
    // A character cut in half at the end of what was read.
    if text.hasSuffix("\u{FFFD}") { text.removeLast() }
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)

    return drawCard(width: maxPixels) { rect in
        NSColor(white: 0.985, alpha: 1).setFill()
        rect.fill()
        let pad = rect.width * 0.07
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: rect.width * 0.068),
            .foregroundColor: NSColor(white: 0.13, alpha: 1),
            .paragraphStyle: style,
        ]
        NSAttributedString(string: text, attributes: attributes).draw(
            with: rect.insetBy(dx: pad, dy: pad),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

/// A file shows its icon, or a preview once Quick Look has made one, above
/// its name.
func fileCard(_ url: URL, preview: NSImage? = nil, maxPixels: Int) -> NSImage? {
    let icon = preview ?? NSWorkspace.shared.icon(forFile: url.path)
    let name = FileManager.default.displayName(atPath: url.path)
    return drawCard(width: maxPixels) { rect in
        NSColor(white: 0.95, alpha: 1).setFill()
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
            .foregroundColor: NSColor(white: 0.2, alpha: 1),
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
