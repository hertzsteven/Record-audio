//
//  ContentView.swift
//  Record audio
//
//  Created by Steven Hertz on 9/5/25.
//

import SwiftUI

struct VoiceMemoView: View {
    @State private var model = VoiceMemoModel()
    @State private var showShare = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Model State: isRecording=\(model.isRecording)")
                .font(.caption)
                .foregroundColor(.secondary)
            CustomProgressBar(
                progress: model.elapsed / model.maxDuration,
                color: progressColor(model.elapsed / model.maxDuration)
            )
            .frame(height: 28) // Make it wider and more noticeable
            .padding(.horizontal)

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
        .confirmationDialog("Save recording?", isPresented: $model.isPromptPresented, titleVisibility: .visible) {
            Button("Save") { 
                print("LOG: Save button pressed in dialog")
                model.confirmSave() 
            }
            Button("Discard", role: .destructive) { 
                print("LOG: Discard button pressed in dialog")
                model.discardRecording() 
            }
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
