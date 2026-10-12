import AppKit
import PDFKit
import UniformTypeIdentifiers
import Vision

/// The words inside what hangs, for history search: text read from pictures
/// with the system's text recognition, the text of PDFs, documents and
/// plain-text files, and the names inside a folder.
///
/// Reading a picture takes a moment, so it all happens on a background queue,
/// one file at a time, and is remembered by path and modification date in
/// Tendedero's folder, so it is only ever done once per version of a file.
/// Everything stays on this Mac.
final class SearchIndex: @unchecked Sendable {
    static let shared = SearchIndex()

    private struct Entry: Codable {
        var modified: Date
        var text: String
    }

    /// Only touched on `queue`.
    private var entries: [String: Entry] = [:]
    private let queue = DispatchQueue(label: "app.tendedero.search-index", qos: .utility)
    private var saveScheduled = false

    /// Enough to find a file by its words, not a copy of it.
    private static let maxCharacters = 20_000

    private static let file: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Tendedero/SearchIndex.plist")
    }()

    private init() {
        queue.async {
            guard let data = try? Data(contentsOf: Self.file),
                  let saved = try? PropertyListDecoder().decode([String: Entry].self, from: data) else { return }
            self.entries = saved
        }
    }

    /// The words in `url`, from memory if this version of the file was read
    /// before. `done` runs on the main thread, and only with words found.
    func text(for url: URL, modified: Date?, done: @escaping @MainActor (String) -> Void) {
        queue.async {
            let path = url.path
            let text: String
            if let entry = self.entries[path], let modified, entry.modified == modified {
                text = entry.text
            } else {
                text = Self.extract(url)
                if let modified {
                    self.entries[path] = Entry(modified: modified, text: text)
                    self.scheduleSave()
                }
            }
            guard !text.isEmpty else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { done(text) } }
        }
    }

    /// Forgets files no longer on the line or in its history.
    func keep(only paths: Set<String>) {
        queue.async {
            let before = self.entries.count
            self.entries = self.entries.filter { paths.contains($0.key) }
            if self.entries.count != before { self.scheduleSave() }
        }
    }

    /// Written a moment after the last change, so a burst of new files is
    /// one write. Only the user can read it: it holds what their files say.
    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        queue.asyncAfter(deadline: .now() + 2) {
            self.saveScheduled = false
            guard let data = try? PropertyListEncoder().encode(self.entries) else { return }
            try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: Self.file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.file.path)
        }
    }

    // MARK: Reading

    private static func extract(_ url: URL) -> String {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return "" }
        if isFolder.boolValue {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            return names.filter { !$0.hasPrefix(".") }.prefix(300).joined(separator: " ")
        }
        guard !isRecording(url), let type = UTType(filenameExtension: url.pathExtension) else { return "" }
        let text: String
        if type.conforms(to: .image) {
            text = recognize(url)
        } else if type.conforms(to: .pdf) {
            text = PDFDocument(url: url)?.string ?? ""
        } else if [UTType.rtf, .rtfd, .init("org.openxmlformats.wordprocessingml.document"),
                   .init("com.microsoft.word.doc"), .init("org.oasis-open.opendocument.text")]
                    .compactMap({ $0 }).contains(where: { type.conforms(to: $0) }) {
            text = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string ?? ""
        } else if type.conforms(to: .text) {
            // Plain text, Markdown, source code, JSON and the like.
            let handle = try? FileHandle(forReadingFrom: url)
            defer { try? handle?.close() }
            text = String(decoding: (try? handle?.read(upToCount: 64 * 1024)) ?? Data(), as: UTF8.self)
        } else {
            text = ""
        }
        return String(text.prefix(maxCharacters))
    }

    /// The text in a picture, read on this Mac by the system's text
    /// recognition, in Chinese, English, Japanese and Korean.
    private static func recognize(_ url: URL) -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 2400,
              ] as CFDictionary) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let wanted = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        request.recognitionLanguages = wanted.filter { supported.contains($0) }
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            return ""
        }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
}
