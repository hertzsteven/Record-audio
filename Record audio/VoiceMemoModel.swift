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
    var isRecording = false {
        didSet {
            print("LOG: isRecording changed to \(isRecording)")
        }
    }
    var elapsed: TimeInterval = 0 {
        didSet {
            // Uncomment for verbose timer logging
            // print("LOG: elapsed updated to \(String(format: "%.2f", elapsed))")
        }
    }
    var currentFileURL: URL? {
        didSet {
            if let url = currentFileURL {
                print("LOG: currentFileURL set to \(url.lastPathComponent)")
            } else {
                print("LOG: currentFileURL cleared")
            }
        }
    }

    private let minSaveDuration: TimeInterval = 0.7
    var isPromptPresented = false
    // The button should only be disabled when the save/discard prompt is shown.
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
    private var durationTimer: Timer? // New timer for 7-second limit
    let maxDuration: TimeInterval = 7

    // MARK: - Public API

    func toggleRecord() {
        print("LOG: ---  toggleRecord() called. isRecording=\(isRecording)")
        if isRecording {
            print("LOG: --- Calling stopRecording() from toggleRecord()")
            stopRecording()
        } else {
            print("LOG: --- Calling startRecording() from toggleRecord()")
            Task { 
                do {
                    print("LOG: About to call startRecording()")
                    try await startRecording()
                    print("LOG: startRecording() completed successfully")
                } catch {
                    print("LOG: startRecording() failed with error: \(error)")
                    // Reset state on failure
                    isRecording = false
                    stopTimers()
                }
            }
        }
    }

    func startRecording() async throws {
        print("LOG: startRecording() called")
        // 1) Ask permission
        let granted = try await requestMicPermission()
        guard granted else { 
            print("LOG: Microphone permission denied")
            throw RecorderError.micPermissionDenied 
        }

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

        // 5) Record (without duration limit)
        print("LOG: Attempting to start recording")
        guard recorder?.record() == true else { 
            print("LOG: recorder.record() returned false")
            throw RecorderError.failedToStart 
        }
        currentFileURL = url
        elapsed = 0
        isRecording = true
        isPromptPresented = false // Reset prompt state on new recording
        startTimers() // Start both the UI timer and the duration timer
        print("LOG: Recording started successfully")
    }

    func stopRecording() {
        print("LOG: stopRecording() called. isRecording=\(isRecording), recorderExists=\(recorder != nil)")
        
        // This handles cases where recorder was deallocated but isRecording was not reset
        isRecording = false
        stopTimers()
        
        guard let rec = recorder else {
            print("LOG: Recorder is nil in stopRecording(), calling cleanup with current elapsed")
            // Recorder is nil, but we still need to ensure state is clean
            // This can happen if delegate already fired or recorder was deallocated elsewhere
            cleanupRecordingState(successfully: false, finalTime: elapsed) // Use current elapsed time
            return
        }

        let finalTime = rec.currentTime
        print("LOG: Captured finalTime before stopping: \(String(format: "%.2f", finalTime))")

        // IMPORTANT: Set delegate to nil *before* stopping for manual stops
        // This prevents the delegate method from firing and double-handling state.
        print("LOG: Stopping recorder instance")
        rec.delegate = nil
        rec.stop()
        
        // Use the captured finalTime
        cleanupRecordingState(successfully: true, finalTime: finalTime)
    }

    // MARK: - Helpers

    private func requestMicPermission() async throws -> Bool {
        print("LOG: Requesting microphone permission")
        return try await withCheckedThrowingContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                print("LOG: Microphone permission granted: \(granted)")
                cont.resume(returning: granted)
            }
        }
    }

    private func configureSession() throws {
        print("LOG: Configuring audio session")
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        print("LOG: Audio session configured and activated")
    }

    private func makeNewFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "memo_\(formatter.string(from: Date())).m4a"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
        print("LOG: New file URL created: \(url.lastPathComponent)")
        return url
    }

    private func startTimers() {
        print("LOG: Starting timers")
        stopTimers() // Ensure any existing timers are stopped
        
        // UI Timer (every 0.1 seconds)
        timer = .scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let rec = self.recorder, rec.isRecording else { 
                print("LOG: UI Timer tick - recorder not available or not recording, returning")
                return 
            }
            
            Task { @MainActor in
                let currentTime = rec.currentTime
                print("LOG: UI Timer updating elapsed to \(String(format: "%.2f", currentTime))")
                self.elapsed = min(currentTime, self.maxDuration)
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
        
        // Duration Timer (fires once after maxDuration)
        durationTimer = .scheduledTimer(withTimeInterval: maxDuration, repeats: false) { [weak self] _ in
            print("LOG: Duration timer fired after \(self?.maxDuration ?? 0) seconds")
            self?.stopRecording() // Automatically stop after maxDuration
        }
        RunLoop.main.add(durationTimer!, forMode: .common)
    }
    
    private func stopTimers() {
        print("LOG: Stopping timers")
        timer?.invalidate(); timer = nil
        durationTimer?.invalidate(); durationTimer = nil
    }

    private func cleanupRecordingState(successfully flag: Bool, finalTime: TimeInterval) {
        print("LOG: cleanupRecordingState() called. successfully=\(flag), finalTime=\(String(format: "%.2f", finalTime))")
        // Ensure timer is stopped and recorder reference is cleared
        self.stopTimers()
        self.recorder = nil
        self.elapsed = min(finalTime, self.maxDuration) // Ensure elapsed is capped at maxDuration
        print("LOG: elapsed after capping: \(String(format: "%.2f", self.elapsed))")

        // Deactivate audio session
        print("LOG: Deactivating audio session")
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if flag && self.elapsed >= self.minSaveDuration {
            print("LOG: Recording >= \(self.minSaveDuration)s, presenting save prompt")
            self.isPromptPresented = true
        } else {
            // Discard recording if not successful or below minimum duration
            print("LOG: Recording < \(self.minSaveDuration)s or unsuccessful, discarding")
            if let url = self.currentFileURL {
                print("LOG: Deleting file \(url.lastPathComponent)")
                try? FileManager.default.removeItem(at: url)
            }
            self.currentFileURL = nil
            self.elapsed = 0 // Reset elapsed if discarded
            self.isPromptPresented = false // Ensure prompt is not shown
        }
        print("LOG: cleanupRecordingState() completed")
    }

    func confirmSave() {
        print("LOG: confirmSave() called")
        isPromptPresented = false
        // currentFileURL already holds the path, nothing else needed here for "save"
    }

    func discardRecording() {
        print("LOG: discardRecording() called")
        if let url = currentFileURL {
            print("LOG: Deleting file \(url.lastPathComponent)")
            try? FileManager.default.removeItem(at: url)
        }
        currentFileURL = nil
        elapsed = 0
        isPromptPresented = false
    }

    func appDidEnterBackground() {
        print("LOG: appDidEnterBackground() called. isRecording=\(isRecording)")
        guard isRecording else { return }
        discardCurrentRecordingImmediately()
    }

    private func discardCurrentRecordingImmediately() {
        print("LOG: discardCurrentRecordingImmediately() called")
        if let rec = recorder {
            print("LOG: Stopping and discarding active recording")
            rec.delegate = nil
            rec.stop()
        }
        cleanupRecordingState(successfully: false, finalTime: 0) // Force discard and clean up
        isRecording = false // Ensure isRecording is false
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
        print("LOG: audioRecorderDidFinishRecording() delegate called. successfully=\(flag), currentTime=\(String(format: "%.2f", currentTime))")
        Task { @MainActor in
            // Guard against delegate firing for a recorder that's already been manually stopped and reset
            guard self.recorder === recorder else {
                print("LOG: Delegate fired for old recorder instance, ignoring")
                return
            }
            print("LOG: Delegate processing for current recorder instance")
            self.isRecording = false // Ensure isRecording is false
            self.cleanupRecordingState(successfully: flag, finalTime: currentTime)
        }
    }
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let currentTime = recorder.currentTime
        print("LOG: audioRecorderEncodeErrorDidOccur() delegate called. error=\(error?.localizedDescription ?? "Unknown"), currentTime=\(String(format: "%.2f", currentTime))")
        Task { @MainActor in
            // Guard against delegate firing for a recorder that's already been manually stopped and reset
            guard self.recorder === recorder else {
                print("LOG: Error delegate fired for old recorder instance, ignoring")
                return
            }
            print("LOG: Error delegate processing for current recorder instance")
            print("Recording error: \(error?.localizedDescription ?? "Unknown error")")
            self.isRecording = false // Ensure isRecording is false
            self.cleanupRecordingState(successfully: false, finalTime: currentTime) // Treat error as unsuccessful
        }
    }
}