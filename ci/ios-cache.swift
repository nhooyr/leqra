import CryptoKit
import Darwin
import Foundation

struct CacheRecord: Codable {
    let sha256: String
    let mtime_ns: Int64
}

struct CacheError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func metadata(_ path: String) throws -> stat {
    var value = stat()
    guard fstatat(AT_FDCWD, path, &value, AT_SYMLINK_NOFOLLOW) == 0 else {
        throw CacheError(message: "stat \(path): \(String(cString: strerror(errno)))")
    }
    return value
}

func modificationTime(_ path: String) throws -> Int64 {
    let time = try metadata(path).st_mtimespec
    return Int64(time.tv_sec) * 1_000_000_000 + Int64(time.tv_nsec)
}

func setModificationTime(_ path: String, _ nanoseconds: Int64) throws {
    var seconds = nanoseconds / 1_000_000_000
    var remainder = nanoseconds % 1_000_000_000
    if remainder < 0 {
        seconds -= 1
        remainder += 1_000_000_000
    }
    let times = [
        timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT)),
        timespec(tv_sec: Int(seconds), tv_nsec: Int(remainder)),
    ]
    guard utimensat(AT_FDCWD, path, times, AT_SYMLINK_NOFOLLOW) == 0 else {
        throw CacheError(message: "utimensat \(path): \(String(cString: strerror(errno)))")
    }
}

func inputs(_ root: URL) throws -> [String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = [
        "-C", root.path, "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--",
        "ios", "scripts/ios-version.sh", "scripts/version.sh", "src/main.go",
    ]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CacheError(message: "git ls-files failed") }
    guard let names = String(data: data, encoding: .utf8) else {
        throw CacheError(message: "git ls-files returned invalid UTF-8")
    }
    return Set(names.split(separator: "\0").map(String.init)).sorted().filter {
        guard let value = try? metadata(root.appendingPathComponent($0).path) else { return false }
        return value.st_mode & S_IFMT == S_IFREG
    }
}

func digest(_ path: URL) throws -> String {
    let data = try Data(contentsOf: path, options: .mappedIfSafe)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func save(_ root: URL, _ manifest: URL) throws {
    var records = [String: CacheRecord]()
    for name in try inputs(root) {
        let path = root.appendingPathComponent(name)
        records[name] = try CacheRecord(sha256: digest(path), mtime_ns: modificationTime(path.path))
    }
    try FileManager.default.createDirectory(
        at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    var data = try encoder.encode(records)
    data.append(0x0a)
    try data.write(to: manifest, options: .atomic)
}

func restore(_ root: URL, _ manifest: URL) throws {
    guard FileManager.default.fileExists(atPath: manifest.path) else { return }
    let records = try JSONDecoder().decode([String: CacheRecord].self, from: Data(contentsOf: manifest))
    var restored = 0
    for name in try inputs(root) {
        let path = root.appendingPathComponent(name)
        guard let record = records[name], record.sha256 == (try digest(path)) else { continue }
        try setModificationTime(path.path, record.mtime_ns)
        restored += 1
    }
    print("Restored timestamps for \(restored) unchanged iOS build inputs.")
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let usage = "Usage: ios-cache.swift restore|save MANIFEST"
    if arguments.count == 1 && ["--help", "-h"].contains(arguments[0]) {
        print("\(usage)\nKeep unchanged iOS input timestamps aligned with cached Swift build records.")
    } else {
        guard arguments.count == 2 && ["restore", "save"].contains(arguments[0]) else {
            throw CacheError(message: usage)
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let manifest = URL(fileURLWithPath: arguments[1])
        if arguments[0] == "save" {
            try save(root, manifest)
        } else {
            try restore(root, manifest)
        }
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
