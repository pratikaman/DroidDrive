import Foundation

enum DeviceState: Equatable {
    case adbMissing
    case noDevice
    case unauthorized
    case ready
}

struct Device: Identifiable, Equatable, Hashable {
    let serial: String
    let state: String   // "device", "unauthorized", "offline", ...
    var model: String = ""

    var id: String { serial }
    var displayName: String { model.isEmpty ? serial : model }
}

struct RemoteFile: Identifiable, Hashable {
    let name: String
    let path: String
    let isDirectory: Bool
    let isSymlink: Bool
    let size: Int64?
    let modified: String

    var id: String { path }

    var displaySize: String {
        guard !isDirectory, let size else { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var iconName: String {
        if isDirectory { return "folder.fill" }
        if isSymlink { return "link" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "bmp": return "photo"
        case "mp4", "mkv", "mov", "avi", "webm", "3gp": return "film"
        case "mp3", "wav", "flac", "ogg", "m4a", "opus", "aac": return "music.note"
        case "pdf": return "doc.richtext"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox"
        case "apk": return "shippingbox"
        case "txt", "md", "log", "json", "xml": return "doc.text"
        default: return "doc"
        }
    }
}

/// Parses toybox `ls -lA` output from an Android device.
enum LsParser {
    static func parse(output: String, parentPath: String) -> [RemoteFile] {
        var files: [RemoteFile] = []
        for line in output.split(separator: "\n") {
            guard let file = parseLine(String(line), parentPath: parentPath) else { continue }
            files.append(file)
        }
        return files.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // Format: perms links owner group size date time name[ -> target]
    // e.g.    -rw-rw---- 1 root everybody 123456 2024-05-05 09:30 photo 1.jpg
    private static func parseLine(_ line: String, parentPath: String) -> RemoteFile? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("total ") else { return nil }

        let type = trimmed.first!
        guard "d-lbcsp".contains(type) else { return nil }

        // Split into at most 8 fields; the 8th keeps embedded spaces (the file name).
        let fields = trimmed.split(separator: " ", maxSplits: 7, omittingEmptySubsequences: true)
        guard fields.count == 8 else { return nil }

        var name = String(fields[7])
        let isSymlink = type == "l"
        if isSymlink, let range = name.range(of: " -> ") {
            name = String(name[..<range.lowerBound])
        }
        guard !name.isEmpty else { return nil }

        let dirPath = parentPath.hasSuffix("/") ? parentPath : parentPath + "/"
        return RemoteFile(
            name: name,
            path: dirPath + name,
            // Treat symlinks as navigable; /sdcard itself is one on many devices.
            isDirectory: type == "d" || isSymlink,
            isSymlink: isSymlink,
            size: Int64(fields[4]),
            modified: "\(fields[5]) \(fields[6])"
        )
    }
}
