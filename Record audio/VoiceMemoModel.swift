//
//  VoiceMemoModel.swift
//  Record audio
//
//  Created by Steven Hertz on 9/5/25.
//


import SwiftUI
import AVFoundation

@MainActor
@Observable
final class VoiceMemoModel: NSObject {
    // UI state
    var isRecording = false
    var elapsed: TimeInterval = 0
    var currentFileURL: URL?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private let maxDuration: TimeInterval = 7

    // MARK: - Public API

    func toggleRecord() {
        if isRecording {
            stopRecording()
        } else {
            Task { try? await startRecording() }
        }
    }

    func startRecording() async throws {
        // 1) Ask permission
        let granted = try await requestMicPermission()
        guard granted else { throw RecorderError.micPermissionDenied }

        // 2) Configure audio session
        try configureSession()

        // 3) Prepare file + settings
        let url = makeNewFileURL()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        // 4) Create recorder
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.delegate = self
        recorder?.isMeteringEnabled = false

        // 5) Record
        guard recorder?.record(forDuration: maxDuration) == true else { throw RecorderError.failedToStart }
        currentFileURL = url
        elapsed = 0
        isRecording = true
        startTimer()
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        stopTimer()
        // Keep currentFileURL set so UI can show/share it
        // Optionally deactivate session here:
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Helpers

    private func requestMicPermission() async throws -> Bool {
        try await withCheckedThrowingContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
    }

    private func makeNewFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "memo_\(formatter.string(from: Date())).m4a"
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = .scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let rec = self.recorder, rec.isRecording else { return }
            
            // Wrap the main actor property mutation in a Task
            Task { @MainActor in
                self.elapsed = rec.currentTime
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    private func stopTimer() { timer?.invalidate(); timer = nil }

    enum RecorderError: LocalizedError {
        case micPermissionDenied, failedToStart
        var errorDescription: String? {
            switch self {
            case .micPermissionDenied: return "Microphone permission was denied."
            case .failedToStart: return "Could not start recording."
            }
        }
    }
}

// MARK: - AVAudioRecorderDelegate
extension VoiceMemoModel: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            self.isRecording = false
            // Handle successful recording
        }
    }
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.isRecording = false
            // Handle error
            print("Recording error: \(error?.localizedDescription ?? "Unknown error")")
        }
    }
}
