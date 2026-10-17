import AVFoundation
import Clear
import FluidAudio
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

    enum Engine: String, CaseIterable, Identifiable {
        case voz = "Voz"
        case parakeet = "Parakeet"
        var id: Self { self }
    }

    enum Voice: String, CaseIterable, Identifiable {
        case studio = "Studio"
        case natural = "Natural"
        var id: Self { self }
        var variant: ModelVariant { self == .studio ? .clearStudio : .clearNatural }
    }

    var stage: Stage = .idle
    var source: URL?
    var cleaned: URL?
    var lines: [Segment] = []

    private var clears: [Voice: Clear] = [:]
    private var voz: Voz?
    private var parakeet: AsrManager?
    private var step = UUID()

    var isWorking: Bool {
        if case .working = stage { true } else { false }
    }

    /// Callers don't start a new run while one is working.
    func run(_ url: URL, engine: Engine, voice: Voice) {
        source = url
        cleaned = nil
        lines = []
        Task { await process(url, engine: engine, voice: voice) }
    }

    /// Moves this file's outputs to the Trash and goes back to the drop zone.
    func deleteOutputs() throws {
        guard let source else { return }
        for url in Self.outputs(for: source) where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        self.source = nil
        cleaned = nil
        lines = []
        stage = .idle
    }

    /// The clean WAV, the .txt and the .srt written next to `source`.
    nonisolated static func outputs(for source: URL) -> [URL] {
        let base = source.deletingPathExtension()
        return ["clean.wav", "transcript.txt", "transcript.srt"].map { base.appendingPathExtension($0) }
    }

    private func process(_ source: URL, engine: Engine, voice: Voice) async {
        let base = source.deletingPathExtension()
        let cleaned = base.appendingPathExtension("clean.wav")
        do {
            let cleaning = begin("Cleaning audio (\(voice.rawValue))")
            let clear = clears[voice] ?? Clear(variant: voice.variant)
            clears[voice] = clear
            try await clear.enhance(path: source.path, to: cleaned.path,
                                    options: .init(mastering: .youtube)) { cleaning($0.phase == .enhancing ? $0.fraction : 0) }
            self.cleaned = cleaned

            let words = switch engine {
            case .voz: try await transcribeWithVoz(cleaned)
            case .parakeet: try await transcribeWithParakeet(cleaned)
            }
            lines = Transcript.lines(from: words)
            try Transcript.text(lines).write(to: base.appendingPathExtension("transcript.txt"), atomically: true, encoding: .utf8)
            try Transcript.srt(lines).write(to: base.appendingPathExtension("transcript.srt"), atomically: true, encoding: .utf8)
            stage = .done
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    private func transcribeWithVoz(_ url: URL) async throws -> [Segment] {
        if !Voz.isDownloaded() {
            let downloading = begin("Downloading Voz (first run only, ~470 MB)")
            try await Voz.download { downloading($0.fraction) }
        }
        if voz == nil {
            _ = begin("Loading Voz")
            voz = try await Voz()
        }
        let transcribing = begin("Transcribing")
        let result = try await voz!.transcribe(url) { transcribing($0.fractionCompleted) }
        return result.words.map { Segment(start: $0.start, end: $0.end, text: $0.text) }
    }

    private func transcribeWithParakeet(_ url: URL) async throws -> [Segment] {
        if parakeet == nil {
            let loading = begin("Loading Parakeet (first run downloads ~600 MB)")
            // v2 is the English-only model, better recall than multilingual v3
            let models = try await AsrModels.downloadAndLoad(version: .v2) { loading($0.fractionCompleted) }
            let manager = AsrManager()
            try await manager.loadModels(models)
            parakeet = manager
        }
        _ = begin("Transcribing")
        var state = TdtDecoderState.make(decoderLayers: await parakeet!.decoderLayerCount)
        let result = try await parakeet!.transcribe(url, decoderState: &state)
        return buildWordTimings(from: result.tokenTimings ?? [])
            .map { Segment(start: $0.startTime, end: $0.endTime, text: $0.word) }
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
