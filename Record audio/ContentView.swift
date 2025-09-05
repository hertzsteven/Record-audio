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
            // Timer
            Text(formatTime(model.elapsed))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()

            // Record / Stop button
            Button(action: { model.toggleRecord() }) {
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

            // Last file & share
            if let url = model.currentFileURL {
                VStack(spacing: 8) {
                    Text(url.lastPathComponent)
                        .font(.footnote)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button("Share last recording") { showShare = true }
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
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let s = Int(t)
        let ms = Int((t - Double(s)) * 100)
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d.%02d", m, r, ms)
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
