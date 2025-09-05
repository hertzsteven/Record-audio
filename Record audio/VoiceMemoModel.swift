//
//  VoiceMemoModel.swift
//  Record audio
//
//  Created by Steven Hertz on 9/5/25.
//


import SwiftUI
import AVFoundation

@MainActor
final class VoiceMemoModel: NSObject, ObservableObject {
    // UI state
    @Published var isRecording = false {
        didSet {
            print("LOG: isRecording changed to \(isRecording)")
        }
    }
    @Published var elapsed: TimeInterval = 0
    @Published var currentFileURL: URL? {
        didSet {
            if let url = currentFileURL {
                print("LOG: currentFileURL set to \(url.lastPathComponent)")
            } else {
                print("LOG: currentFileURL cleared")
            }
        }
    }

    @Published var isPromptPresented = false {
        didSet {
            print("LOG: isPromptPresented changed to \(isPromptPresented)")
        }
    }
    var isRecordButtonEnabled: Bool { !isPromptPresented }

    private var recorder: AVAudioRecorder? {
        didSet {
            if recorder != nil {
                print("LOG: recorder instance created")
            } else {
                print("LOG: recorder instance cleared")
            }
        }
    }
    private var timer: Timer?
    private var durationTimer: Timer?
    let maxDuration: TimeInterval = 7
    private let minSaveDuration: TimeInterval = 0.7

    // MARK: - Public API

    func toggleRecord() {
        print("LOG: toggleRecord() called. isRecording=\(isRecording)")
        if isRecording {
            stopRecording()
        } else {
            Task { try? await startRecording() }
        }
    }

    func startRecording() async throws {
        print("LOG: startRecording() called")
        let granted = try await requestMicPermission()
        guard granted else { throw RecorderError.micPermissionDenied }

        try configureSession()

        let url = makeNewFileURL()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.delegate = self

        guard recorder?.record() == true else { throw RecorderError.failedToStart }
        
        currentFileURL = url
        elapsed = 0
        isRecording = true
        isPromptPresented = false
        startTimers()
        print("LOG: Recording started successfully")
    }

    func stopRecording() {
        print("LOG: stopRecording() called. isRecording=\(isRecording), recorderExists=\(recorder != nil)")
        
        isRecording = false
        stopTimers()
        
        guard let rec = recorder else {
            cleanupRecordingState(successfully: false, finalTime: elapsed)
            return
        }

        let finalTime = rec.currentTime
        print("LOG: Captured finalTime before stopping: \(String(format: "%.2f", finalTime))")

        rec.delegate = nil
        rec.stop()
        
        cleanupRecordingState(successfully: true, finalTime: finalTime)
    }

    // MARK: - Helpers

    func confirmSave(with newName: String) {
        print("LOG: confirmSave(with: \(newName)) called")
        guard let sourceURL = currentFileURL else {
            print("LOG: Error - currentFileURL is nil, cannot save.")
            isPromptPresented = false
            return
        }

        let sanitizedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNameWithExt = sanitizedName.isEmpty
            ? sourceURL.lastPathComponent
            : (sanitizedName.hasSuffix(".m4a") ? sanitizedName : "\(sanitizedName).m4a")

        let destinationURL = sourceURL.deletingLastPathComponent().appendingPathComponent(finalNameWithExt)

        if sourceURL.lastPathComponent != destinationURL.lastPathComponent {
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                print("LOG: Renamed file to \(destinationURL.lastPathComponent)")
                self.currentFileURL = destinationURL
            } catch {
                print("LOG: Error renaming file: \(error.localizedDescription)")
            }
        }
        
        self.elapsed = 0
        self.isPromptPresented = false
    }

    func discardRecording() {
        print("LOG: discardRecording() called")
        if let url = currentFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentFileURL = nil
        elapsed = 0
        isPromptPresented = false
    }

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

    private func startTimers() {
        stopTimers()
        
        timer = .scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let rec = self.recorder, rec.isRecording else { return }
            Task { @MainActor in
                self.elapsed = min(rec.currentTime, self.maxDuration)
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
        
        durationTimer = .scheduledTimer(withTimeInterval: maxDuration, repeats: false) { [weak self] _ in
            self?.stopRecording()
        }
        RunLoop.main.add(durationTimer!, forMode: .common)
    }
    
    private func stopTimers() {
        timer?.invalidate(); timer = nil
        durationTimer?.invalidate(); durationTimer = nil
    }

    private func cleanupRecordingState(successfully flag: Bool, finalTime: TimeInterval) {
        stopTimers()
        self.recorder = nil
        self.elapsed = min(finalTime, self.maxDuration)

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if flag && self.elapsed >= self.minSaveDuration {
            self.isPromptPresented = true
        } else {
            if let url = self.currentFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            self.currentFileURL = nil
            self.elapsed = 0
            self.isPromptPresented = false
        }
    }

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
        let currentTime = recorder.currentTime
        Task { @MainActor in
            guard self.recorder === recorder else { return }
            self.isRecording = false
            self.cleanupRecordingState(successfully: flag, finalTime: currentTime)
        }
    }
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let currentTime = recorder.currentTime
        Task { @MainActor in
            guard self.recorder === recorder else { return }
            self.isRecording = false
            self.cleanupRecordingState(successfully: false, finalTime: currentTime)
        }
    }
}