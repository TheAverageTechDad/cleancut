import Foundation

/// A timed piece of text: one word from Voz, or a line built from several.
struct Segment: Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

enum Transcript {
    /// Groups words into lines, breaking at sentence ends, pauses, or a length cap.
    // ponytail: punctuation + pause heuristic, not real sentence detection; good enough for chapters and captions
    static func lines(from words: [Segment], maxGap: TimeInterval = 0.8,
                      maxLength: TimeInterval = 10) -> [Segment] {
        var lines: [Segment] = []
        var current: [Segment] = []
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = current.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            lines.append(Segment(start: first.start, end: last.end, text: text))
            current = []
        }
        for word in words {
            if let first = current.first, let last = current.last,
               word.start - last.end >= maxGap
                || ".?!".contains(last.text.last ?? " ")
                || word.end - first.start > maxLength {
                flush()
            }
            current.append(word)
        }
        flush()
        return lines
    }

    /// YouTube chapter style: `1:23`, or `1:02:03` past an hour.
    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func text(_ lines: [Segment]) -> String {
        lines.map { "[\(clock($0.start))] \($0.text)" }.joined(separator: "\n") + "\n"
    }

    static func srt(_ lines: [Segment]) -> String {
        func time(_ t: TimeInterval) -> String {
            let ms = Int((t * 1000).rounded())
            return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
        }
        return lines.enumerated()
            .map { i, line in "\(i + 1)\n\(time(line.start)) --> \(time(line.end))\n\(line.text)\n" }
            .joined(separator: "\n")
    }

    static func chapterPrompt(_ lines: [Segment]) -> String {
        """
        Below is the timestamped transcript of my YouTube video. Create YouTube chapters for it.

        Rules:
        - The first chapter starts at 0:00.
        - At least 3 chapters, each at least 10 seconds long.
        - Start a chapter where the topic actually changes, using the transcript's timestamps.
        - Short, descriptive titles (under 50 characters), no clickbait.
        - Output only the chapter list, one per line, like `0:00 Intro`.

        Transcript:
        \(text(lines))
        """
    }
}
