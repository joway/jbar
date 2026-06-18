import Foundation

private let logURL = URL(fileURLWithPath: "/tmp/jbar_app.log")
private let logQueue = DispatchQueue(label: "com.joway.jbar.log")

/// 追加写入固定日志文件，线程/fd 无关，保证从任何上下文都能记录。
func jlog(_ message: String) {
    let line = "[\(Date())] [JBar] \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    logQueue.async {
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: logURL)
        }
    }
    FileHandle.standardError.write(data)
}
