import Foundation

/// Minimal `.env` support for development keys: `KEY=value`, `export KEY=value`, `# comments`, quoted values.
public enum DotEnv {
    public static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if let quote = value.first, quote == "\"" || quote == "'", value.count >= 2, value.last == quote {
                value = String(value.dropFirst().dropLast())
            } else if let comment = value.range(of: " #") {
                value = String(value[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            if !key.isEmpty, !value.isEmpty { result[key] = value }
        }
        return result
    }

    /// Looks for a `.env` file in `directory` and each parent, up to `maxLevels` levels.
    public static func find(from directory: URL, maxLevels: Int = 6) -> URL? {
        var current = directory.standardizedFileURL
        for _ in 0..<maxLevels {
            let candidate = current.appendingPathComponent(".env")
            if FileManager.default.isReadableFile(atPath: candidate.path) { return candidate }
            let parent = current.deletingLastPathComponent()
            if parent == current { break }
            current = parent
        }
        return nil
    }

    /// Values from the nearest `.env` above `directory`, or empty.
    public static func load(from directory: URL) -> [String: String] {
        guard let url = find(from: directory), let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return parse(text)
    }
}
