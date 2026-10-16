import Testing
@testable import Cleancut

@Test func linesBreakAtSentencesPausesAndLength() {
    let words = [
        Segment(start: 0.0, end: 0.4, text: "Hello"),
        Segment(start: 0.5, end: 0.9, text: "there."),     // sentence end
        Segment(start: 1.0, end: 1.3, text: "Next"),
        Segment(start: 1.4, end: 1.8, text: "part"),
        Segment(start: 3.0, end: 3.4, text: "after"),       // 1.2 s pause
        Segment(start: 3.5, end: 3.9, text: "pause"),
    ] + (0..<30).map { Segment(start: 4.0 + Double($0) * 0.5, end: 4.4 + Double($0) * 0.5, text: "w") }

    let lines = Transcript.lines(from: words)
    #expect(lines.prefix(3).map(\.text) == ["Hello there.", "Next part", "after pause " + Array(repeating: "w", count: 18).joined(separator: " ")])
    #expect(lines[2].start == 3.0)
    #expect(lines.allSatisfy { $0.end - $0.start <= 10 })
    #expect(lines.map(\.text).joined(separator: " ").split(separator: " ").count == words.count)
}

@Test func timestampFormats() {
    #expect(Transcript.clock(0) == "0:00")
    #expect(Transcript.clock(83.9) == "1:23")
    #expect(Transcript.clock(3723) == "1:02:03")
    #expect(Transcript.text([Segment(start: 65, end: 70, text: "Hi")]) == "[1:05] Hi\n")
    #expect(Transcript.srt([Segment(start: 1.5, end: 3723.25, text: "Hi")]) == "1\n00:00:01,500 --> 01:02:03,250\nHi\n")
}
