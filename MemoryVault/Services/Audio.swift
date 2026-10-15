import AVFoundation
import Foundation
import Observation

/// Where saved voice recordings live (Documents/Audio).
enum AudioStorage {
    static var directory: URL {
        let dir = URL.documentsDirectory.appendingPathComponent("Audio", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// Moves a temporary recording into permanent storage and returns its file name.
    static func persist(_ tempURL: URL) -> String? {
        let name = "\(UUID().uuidString).m4a"
        do {
            try FileManager.default.moveItem(at: tempURL, to: url(for: name))
            return name
        } catch {
            return nil
        }
    }

    static func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}

enum RecorderError: LocalizedError {
    case couldNotStart

    var errorDescription: String? { "Couldn't start recording." }
}

/// Records voice memos as small AAC files suitable for upload to the transcription API.
@Observable
final class AudioRecorder {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// Normalized input level, 0...1, for the pulsing mic animation.
    private(set) var level: Double = 0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTask: Task<Void, Never>?

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    @MainActor
    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw RecorderError.couldNotStart }

        self.recorder = recorder
        isRecording = true
        elapsed = 0
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                self?.tick()
            }
        }
    }

    /// Stops recording and returns the temporary file URL.
    @MainActor
    func stop() -> URL? {
        guard let recorder else { return nil }
        recorder.stop()
        meterTask?.cancel()
        meterTask = nil
        isRecording = false
        level = 0
        self.recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return recorder.url
    }

    @MainActor
    private func tick() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        elapsed = recorder.currentTime
        let power = Double(recorder.averagePower(forChannel: 0)) // -160...0 dB
        level = max(0, min(1, (power + 50) / 50))
    }
}

/// Plays back a saved recording.
@Observable
final class ClipPlayer {
    private(set) var playingURL: URL?
    private(set) var progress: Double = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    @MainActor
    func toggle(_ url: URL) {
        if playingURL == url {
            stop()
            return
        }
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.play()
            self.player = player
            playingURL = url
            progressTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    self?.update()
                }
            }
        } catch {
            stop()
        }
    }

    @MainActor
    func stop() {
        player?.stop()
        player = nil
        progressTask?.cancel()
        progressTask = nil
        playingURL = nil
        progress = 0
    }

    @MainActor
    private func update() {
        guard let player else { return }
        if !player.isPlaying {
            stop()
            return
        }
        progress = player.duration > 0 ? player.currentTime / player.duration : 0
    }

    static func duration(of url: URL) -> TimeInterval {
        (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
    }
}
