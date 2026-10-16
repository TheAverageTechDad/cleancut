import AVFoundation
import Clear
import Observation
import Voz

/// One dropped file: clean it, transcribe the clean audio, write the outputs next to it.
@MainActor @Observable
final class Job {
    enum Stage: Equatable {
        case idle
        case working(String, Double)
        case done
        case failed(String)
    }

    var stage: Stage = .idle
    var source: URL?
    var cleaned: URL?
    var lines: [Segment] = []

    private let clear = Clear(variant: .clearStudio)
    private var voz: Voz?
    private var step = UUID()

    var isWorking: Bool {
        if case .working = stage { true } else { false }
    }

    /// Callers don't start a new run while one is working.
    func run(_ url: URL) {
        source = url
        cleaned = nil
        lines = []
        Task { await process(url) }
    }

    private func process(_ source: URL) async {
        let base = source.deletingPathExtension()
        let cleaned = base.appendingPathExtension("clean.wav")
        do {
            let cleaning = begin("Cleaning audio")
            try await clear.enhance(path: source.path, to: cleaned.path,
                                    options: .init(mastering: .youtube)) { cleaning($0.phase == .enhancing ? $0.fraction : 0) }
            self.cleaned = cleaned

            if !Voz.isDownloaded() {
                let downloading = begin("Downloading speech model (first run only, ~470 MB)")
                try await Voz.download { downloading($0.fraction) }
            }
            if voz == nil {
                _ = begin("Loading speech model")
                voz = try await Voz()
            }
            let transcribing = begin("Transcribing")
            let result = try await voz!.transcribe(cleaned) { transcribing($0.fractionCompleted) }

            lines = Transcript.lines(from: result.words.map { Segment(start: $0.start, end: $0.end, text: $0.text) })
            try Transcript.text(lines).write(to: base.appendingPathExtension("transcript.txt"), atomically: true, encoding: .utf8)
            try Transcript.srt(lines).write(to: base.appendingPathExtension("transcript.srt"), atomically: true, encoding: .utf8)
            stage = .done
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    /// Starts a new progress step. Late callbacks from an earlier step are dropped.
    private func begin(_ label: String) -> @Sendable (Double) -> Void {
        let id = UUID()
        step = id
        stage = .working(label, 0)
        return { fraction in
            Task { @MainActor in
                if self.step == id { self.stage = .working(label, fraction) }
            }
        }
    }
}

/// Plays the original or the clean file, keeping the position when you switch.
@MainActor @Observable
final class ABPlayer {
    var useClean = true { didSet { swap() } }
    var isPlaying = false
    var time: Double = 0
    var duration: Double = 1

    private let player = AVPlayer()
    private var original: URL?
    private var clean: URL?
    private var observer: Any?

    init() {
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.time = t.seconds
                self.isPlaying = self.player.timeControlStatus != .paused
                if let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 { self.duration = d }
            }
        }
    }

    func load(original: URL, clean: URL) {
        player.pause()
        self.original = original
        self.clean = clean
        time = 0
        player.replaceCurrentItem(with: AVPlayerItem(url: useClean ? clean : original))
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlay() {
        if isPlaying { return pause() }
        if time >= duration - 0.2 { seek(to: 0) }
        player.play()
        isPlaying = true
    }

    func seek(to seconds: Double) {
        time = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func swap() {
        guard let url = useClean ? clean : original else { return }
        let at = player.currentTime()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.seek(to: at, toleranceBefore: .zero, toleranceAfter: .zero)
        if isPlaying { player.play() }
    }
}
