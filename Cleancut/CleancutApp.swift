import DesertAnt
import SwiftUI
import UniformTypeIdentifiers

@main
struct CleancutApp: App {
    init() { DesertAnt.usageDisabled = true }

    var body: some Scene {
        Window("Cleancut", id: "main") { ContentView() }
            .defaultSize(width: 760, height: 580)
    }
}

struct ContentView: View {
    @State private var job = Job()
    @State private var player = ABPlayer()
    @State private var choosing = false
    @State private var copied = false
    @State private var targeted = false
    @AppStorage("engine") private var engine = Job.Engine.voz
    @AppStorage("voice") private var voice = Job.Voice.studio
    @State private var deleteError: String?

    var body: some View {
        Group {
            switch job.stage {
            case .idle: dropZone
            case .working(let label, let fraction): working(label, fraction)
            case .failed(let message): failed(message)
            case .done: results
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .dropDestination(for: URL.self) { urls, _ in
            guard !job.isWorking, let url = urls.first(where: isMedia) else { return false }
            start(url)
            return true
        } isTargeted: { targeted = $0 }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.audiovisualContent]) { result in
            if case .success(let url) = result { start(url) }
        }
        .alert("Couldn't delete outputs", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
        } message: { Text(deleteError ?? "") }
        .onChange(of: job.stage) { _, stage in
            if stage == .done, let source = job.source, let cleaned = job.cleaned {
                player.load(original: source, clean: cleaned)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Drop an audio or video file").font(.title2)
            Text("Cleans the voice, then writes a timestamped transcript next to the file.")
                .foregroundStyle(.secondary)
            Button("Choose File…") { choosing = true }.keyboardShortcut("o")
            settings.padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.4))
        )
        .padding()
    }

    private func working(_ label: String, _ fraction: Double) -> some View {
        VStack(spacing: 16) {
            Text(job.source?.lastPathComponent ?? "").font(.headline)
            if fraction > 0 {
                ProgressView(value: fraction) { Text(label) } currentValueLabel: {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                }
                .frame(maxWidth: 380)
            } else {
                ProgressView(label)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text(message).multilineTextAlignment(.center).textSelection(.enabled)
            HStack {
                if let source = job.source { Button("Try Again") { start(source) } }
                Button("Choose File…") { choosing = true }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(job.source?.lastPathComponent ?? "").font(.headline)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("New File…") { choosing = true }.keyboardShortcut("o")
            }
            HStack {
                settings
                Spacer()
                Button("Reprocess", systemImage: "arrow.clockwise") {
                    if let source = job.source { start(source) }
                }
                .keyboardShortcut("r")
                .help("Run this file again with the voice and transcriber selected on the left")
                Button("Delete Outputs", systemImage: "trash", role: .destructive) {
                    player.pause()
                    do { try job.deleteOutputs() } catch { deleteError = error.localizedDescription }
                }
                .help("Move the .clean.wav, .transcript.txt and .transcript.srt to the Trash")
            }
            playerBar
            ScrollView {
                Text(Transcript.text(job.lines))
                    .font(.body.monospacedDigit())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button(copied ? "Copied" : "Copy for AI", systemImage: copied ? "checkmark" : "doc.on.doc", action: copy)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Reveal in Finder", systemImage: "folder") {
                    if let cleaned = job.cleaned { NSWorkspace.shared.activateFileViewerSelecting([cleaned]) }
                }
                Spacer()
                Text("Saved .clean.wav, .transcript.txt, .transcript.srt")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var settings: some View {
        HStack(spacing: 16) {
            Picker("Voice", selection: $voice) {
                ForEach(Job.Voice.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).fixedSize()
            .help("Studio: quiet, polished, near-silent gaps. Natural: keeps room tone and breaths.")
            Picker("Transcriber", selection: $engine) {
                ForEach(Job.Engine.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).fixedSize()
            .help("Voz: Desert Ant, ~470 MB. Parakeet: NVIDIA via FluidAudio, ~600 MB, English.")
        }
    }

    private var playerBar: some View {
        HStack(spacing: 12) {
            Button(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill") {
                player.togglePlay()
            }
            .labelStyle(.iconOnly)
            .keyboardShortcut(.space, modifiers: [])
            Slider(value: Binding(get: { player.time }, set: { player.seek(to: $0) }),
                   in: 0...max(player.duration, 1)) { Text("Position") }
                .labelsHidden()
            Text(Transcript.clock(player.time)).monospacedDigit().foregroundStyle(.secondary)
            Picker("Listen to", selection: $player.useClean) {
                Text("Original").tag(false)
                Text("Clean").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }

    private func isMedia(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .audiovisualContent) ?? false
    }

    private func start(_ url: URL) {
        player.pause()
        job.run(url, engine: engine, voice: voice)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Transcript.chapterPrompt(job.lines), forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}
