//
//  ContentView.swift
//  Record audio
//
//  Created by Steven Hertz on 9/5/25.
//

import SwiftUI

struct VoiceMemoView: View {
    @StateObject private var model = VoiceMemoModel()
    @State private var showShare = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Model State: isRecording=\(model.isRecording)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {                
                HStack {
                    Text("0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    CustomProgressBar(
                        progress: model.elapsed / model.maxDuration,
                        color: progressColor(model.elapsed / model.maxDuration)
                    )
                    .frame(height: 28)
                    .padding(.horizontal,4)
                    Text("\(Int(model.maxRecordingDuration))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal,8)
            }

            // Timer
            Text(formatTime(model.elapsed))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()

            // Record / Stop button
            Button(action: { 
                print("LOG: Record/Stop button pressed. Model isRecording=\(model.isRecording)")
                model.toggleRecord() 
            }) {
                Circle()
                    .frame(width: 88, height: 88)
                    .overlay(
                        Image(systemName: model.isRecording ? "stop.fill" : "record.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(model.isRecording
                                             ? AnyShapeStyle(.primary)
                                             : AnyShapeStyle(Color.red))
                    )
                    .accessibilityLabel(model.isRecording ? "Stop recording" : "Start recording")
            }
            .disabled(!model.isRecordButtonEnabled)

            // Last file & share
            if let url = model.currentFileURL {
                VStack(spacing: 8) {
                    Text(url.lastPathComponent)
                        .font(.footnote)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button("Share last recording") { 
                        print("LOG: Share button pressed")
                        showShare = true 
                    }
                    .sheet(isPresented: $showShare) {
                        ShareSheet(items: [url])
                    }
                }
                .padding(.top, 8)
            }

            // Optional: list all recordings in Documents
            RecordingsList()
                .frame(maxHeight: 220)
        }
        .padding()
        // .confirmationDialog(...)

        .sheet(isPresented: $model.isPromptPresented) {
            // Ensure the model is passed correctly to the sheet view
            SaveRecordingView(model: model)
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let s = Int(t)
        let ms = Int((t - Double(s)) * 100)
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d.%02d", m, r, ms)
    }

    private func progressColor(_ p: Double) -> Color {
        let clamped = max(0, min(1, p))
        let hue = max(0.0, 0.33 - 0.33 * clamped)
        return Color(hue: hue, saturation: 0.95, brightness: 0.95)
    }
}

struct SaveRecordingView: View {
    @ObservedObject var model: VoiceMemoModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Text("Recording Complete")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    if let url = model.currentFileURL {
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    Text("Duration: \(formatTime(model.elapsed))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 16) {
                    // Playback progress bar - only show when playback duration is available
                    if model.playbackDuration > 0 && (model.isPlaying || model.playbackProgress > 0) {
                        VStack(spacing: 8) {
                            HStack {
                                Text("0:00")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                                
                                CustomProgressBar(
                                    progress: model.playbackProgress,
                                    color: .blue
                                )
                                .frame(height: 4)
                                
                                Text(formatTime(model.playbackDuration))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    
                    // Play/Pause button
                    Button(action: {
                        print("LOG: Play/Pause button pressed")
                        model.togglePlayback()
                    }) {
                        HStack {
                            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            Text(model.isPlaying ? "Pause" : "Play Recording")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(25)
                    }
                }
                
                Spacer()
                
                // Save and Discard buttons
                HStack(spacing: 16) {
                    Button("Discard", role: .destructive) {
                        print("LOG: Discard button pressed in sheet")
                        model.discardRecording()
                    }
                    .font(.headline)
                    .foregroundColor(.red)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(Color.red, lineWidth: 2)
                    )
                    
                    Button("Save Recording") {
                        print("LOG: Save button pressed in sheet")
                        model.saveRecording()
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.green)
                    .cornerRadius(25)
                }
            }
            .padding()
            .navigationTitle("Review Recording")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear {
            // Stop playback when sheet is dismissed
            model.stopPlayback()
        }
    }
    
    private func formatTime(_ t: TimeInterval) -> String {
        let s = Int(t)
        let ms = Int((t - Double(s)) * 100)
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d.%02d", m, r, ms)
    }
}

private struct CustomProgressBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background of the progress bar
                Capsule()
                    .fill(Color.gray.opacity(0.25))
                
                // Foreground (the actual progress)
                Capsule()
                    .fill(color)
                    // Animate the width change for a smooth progress update
                    .frame(width: geometry.size.width * progress)
                    .animation(.linear(duration: 0.1), value: progress)
            }
        }
    }
}

// Simple share sheet wrapper
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    VoiceMemoView()
}