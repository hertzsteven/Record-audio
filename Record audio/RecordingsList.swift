//
//  RecordingsList.swift
//  Record audio
//
//  Created by Steven Hertz on 9/5/25.
//


import SwiftUI
import AVKit

struct RecordingsList: View {
    @State private var files: [URL] = []

    var body: some View {
        List(files, id: \.self) { url in
            HStack {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    let player = AVPlayer(url: url)
                    let vc = AVPlayerViewController()
                    vc.player = player
                    UIApplication.shared.topMostViewController()?.present(vc, animated: true) {
                        player.play()
                    }
                } label: {
                    Image(systemName: "play.circle")
                }
            }
        }
        .onAppear(perform: loadFiles)
    }

    private func loadFiles() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let items = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)) ?? []
        files = items
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .sorted { (a, b) in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return da > db
            }
    }
}

// tiny helper to present AVPlayerViewController without extra plumbing
import UIKit
import AVKit
extension UIApplication {
    func topMostViewController(base: UIViewController? = UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first) -> UIViewController? {
        if let nav = base as? UINavigationController { return topMostViewController(base: nav.visibleViewController) }
        if let tab = base as? UITabBarController { return topMostViewController(base: tab.selectedViewController) }
        if let presented = base?.presentedViewController { return topMostViewController(base: presented) }
        return base
    }
}