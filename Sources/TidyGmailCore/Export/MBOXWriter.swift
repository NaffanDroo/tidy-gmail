import Foundation

// MARK: - MBOX writer (RFC 4155)

public enum MBOXWriter {
    /// Write a collection of raw RFC 2822 messages into MBOX format.
    ///
    /// Each message is preceded by a `From ` separator line (RFC 4155) and followed by a blank line.
    /// Any existing lines in the message body that start with "From " are escaped as ">From ".
    public static func write(messages: [MBOXEntry]) -> Data {
        var output = Data()
        for entry in messages {
            let fromLine = "From \(entry.sender) \(formatDate(entry.date))\n"
            output.append(Data(fromLine.utf8))

            let bodyString = String(data: entry.rawRFC2822, encoding: .utf8) ?? ""
            let escapedBody = escapeFromLines(bodyString)
            output.append(Data(escapedBody.utf8))

            if !escapedBody.hasSuffix("\n") {
                output.append(Data("\n".utf8))
            }
            output.append(Data("\n".utf8))
        }
        return output
    }

    // MARK: - Internal helpers

    static func escapeFromLines(_ body: String) -> String {
        body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                if line.hasPrefix("From ") {
                    return ">" + line
                }
                return String(line)
            }
            .joined(separator: "\n")
    }

    static func formatDate(_ date: Date) -> String {
        Self.mboxDateFormatter.string(from: date)
    }

    private static let mboxDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM dd HH:mm:ss yyyy"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

// MARK: - MBOX entry

public struct MBOXEntry: Sendable, Equatable {
    public let sender: String
    public let date: Date
    public let rawRFC2822: Data

    public init(sender: String, date: Date, rawRFC2822: Data) {
        self.sender = sender
        self.date = date
        self.rawRFC2822 = rawRFC2822
    }
}
