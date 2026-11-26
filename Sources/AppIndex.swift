import Foundation

/// The installed apps, scanned once when created.
struct AppIndex {
    struct Entry {
        let name: String
        let url: URL
    }

    private let entries: [Entry]

    init() {
        let roots = [
            "/Applications",
            NSHomeDirectory() + "/Applications",
            "/System/Applications",
            "/System/Cryptexes/App/System/Applications", // Safari
            "/System/Library/CoreServices/Applications",
        ]
        var found = [Entry(name: "Finder", url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))]
        for root in roots { Self.scan(URL(fileURLWithPath: root), depth: 1, into: &found) }
        var seen = Set<String>()
        entries = found.filter { seen.insert($0.url.resolvingSymlinksInPath().path).inserted }
    }

    /// `depth` is how many levels of plain subfolders (such as Utilities) to enter.
    private static func scan(_ folder: URL, depth: Int, into found: inout [Entry]) {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.localizedNameKey], options: .skipsHiddenFiles)
        for url in contents ?? [] {
            if url.pathExtension == "app" {
                var name = (try? url.resourceValues(forKeys: [.localizedNameKey]))?.localizedName ?? url.lastPathComponent
                if name.hasSuffix(".app") { name.removeLast(4) }
                found.append(Entry(name: name, url: url))
            } else if depth > 0, url.hasDirectoryPath {
                scan(url, depth: depth - 1, into: &found)
            }
        }
    }

    /// Best matches first: name starts with the text, then a word in it does, then
    /// the name contains it anywhere. The file name counts too, so an app with a
    /// translated name can also be found by its original one.
    func search(_ text: String, limit: Int) -> [Entry] {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        return entries
            .compactMap { entry -> (rank: Int, entry: Entry)? in
                let fileName = entry.url.deletingPathExtension().lastPathComponent
                guard let rank = [entry.name, fileName].compactMap({ Self.rank($0, text) }).min() else { return nil }
                return (rank, entry)
            }
            .sorted {
                $0.rank != $1.rank ? $0.rank < $1.rank
                    : $0.entry.name.localizedStandardCompare($1.entry.name) == .orderedAscending
            }
            .prefix(limit)
            .map(\.entry)
    }

    private static func rank(_ name: String, _ text: String) -> Int? {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        guard let match = name.range(of: text, options: options) else { return nil }
        if match.lowerBound == name.startIndex { return 0 }
        return name.range(of: " " + text, options: options) != nil ? 1 : 2
    }
}
