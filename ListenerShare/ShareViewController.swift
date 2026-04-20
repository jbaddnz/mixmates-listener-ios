//
//  ShareViewController.swift
//  ListenerShare
//
//  Created by jamie baddeley on 20/04/2026.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Entry point for the Share Extension. Extracts the shared URL from the
/// extension context, creates a `ShareViewModel` wired to the real API,
/// and hosts the SwiftUI `ShareView` in a presentation sheet.
@objc(ShareViewController)
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let keychain = KeychainManager(accessGroup: KeychainManager.sharedAccessGroup)
        let token = try? keychain.get()

        let viewModel = ShareViewModel(
            token: token,
            dismiss: { [weak self] in
                self?.extensionContext?.completeRequest(
                    returningItems: nil, completionHandler: nil
                )
            }
        )

        let shareView = ShareView(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: shareView)

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hostingController.didMove(toParent: self)

        Task {
            let url = await extractURL()
            await viewModel.resolve(url: url)
        }
    }

    /// Extract a music service URL from the shared content. Checks for a
    /// URL attachment first, then falls back to extracting a URL from shared
    /// text (Spotify shares text like "Track Name https://open.spotify.com/...").
    private func extractURL() async -> URL? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return nil
        }

        for item in items {
            guard let attachments = item.attachments else { continue }

            // Try URL type first
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await provider.loadItem(
                        forTypeIdentifier: UTType.url.identifier
                    ) as? URL {
                        return url
                    }
                }
            }

            // Fall back to text — extract first music URL via pattern matching
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await provider.loadItem(
                        forTypeIdentifier: UTType.plainText.identifier
                    ) as? String {
                        return extractMusicURL(from: text)
                    }
                }
            }
        }

        return nil
    }

    /// Finds the first Spotify, Tidal, or Apple Music URL in a text string.
    private func extractMusicURL(from text: String) -> URL? {
        let pattern = #"https?://(?:open\.spotify\.com|music\.apple\.com|tidal\.com|listen\.tidal\.com)/\S+"#
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return URL(string: String(text[range]))
    }
}
