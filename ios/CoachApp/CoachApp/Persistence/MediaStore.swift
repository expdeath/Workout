import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Per-exercise form photo or short clip — device-local only, never
/// synced (same as the web app's IndexedDB `media` store: far too big
/// for the database). Keyed like cue notes: the lowercased exercise name.
enum MediaStore {
    struct Item: Equatable {
        var url: URL
        var isVideo: Bool
    }

    private static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoachMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// File-safe name for a key ("Incline DB Press" → "incline%20db%20press").
    private static func base(_ key: String) -> String {
        key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? String(key.hashValue)
    }

    static func get(_ key: String) -> Item? {
        for (ext, video) in [("jpg", false), ("mov", true)] {
            let url = dir.appendingPathComponent("\(base(key)).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return Item(url: url, isVideo: video) }
        }
        return nil
    }

    /// Replaces whatever was stored for this key.
    static func put(_ key: String, imageData: Data) throws {
        remove(key)
        try imageData.write(to: dir.appendingPathComponent("\(base(key)).jpg"), options: .atomic)
    }

    static func put(_ key: String, movieAt source: URL) throws {
        remove(key)
        try FileManager.default.copyItem(at: source, to: dir.appendingPathComponent("\(base(key)).mov"))
    }

    static func remove(_ key: String) {
        for ext in ["jpg", "mov"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(base(key)).\(ext)"))
        }
    }

    /// Everything on sign-out (wipeLocal).
    static func removeAll() {
        try? FileManager.default.removeItem(at: dir)
    }
}

/// A picked video, copied out of the Photos library to a temp file.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}
