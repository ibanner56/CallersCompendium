import UIKit
import UniformTypeIdentifiers

/// Share Extension entry point (issue #343). It appears in the Safari / browser
/// share sheet; when the user shares a web page (e.g. a ContraDB program page),
/// this stashes the shared URL string in the shared App Group and opens the
/// host app via its private custom URL scheme so the app can import it through
/// the existing hardened pipeline.
///
/// This extension deliberately does **no** validation and **no** import: it
/// only forwards the raw shared string verbatim. The host app treats it as
/// untrusted input and OWASP-validates it (`validateSharedContraDbProgramUrl`:
/// https only, `contradb.com` host allow-list, `/programs/N` path) before it
/// touches the import pipeline. Keeping the native surface dumb keeps the trust
/// boundary in one place (Dart).
final class ShareViewController: UIViewController {
  /// App Group shared with the host app; the shared URL is handed over through
  /// its `UserDefaults` suite.
  private static let appGroupId = "group.org.callerscompendium.compendiumApp"

  /// Key under which the raw shared URL string is written for the host app.
  private static let sharedUrlKey = "SharedImportURL"

  /// Private custom URL scheme used only to wake the host app (NOT a universal
  /// link — see issue #343).
  private static let hostScheme = "callerscompendium"

  override func viewDidLoad() {
    super.viewDidLoad()
    handleShare()
  }

  private func handleShare() {
    guard
      let item = extensionContext?.inputItems.first as? NSExtensionItem,
      let attachments = item.attachments
    else {
      return complete()
    }

    let urlType = UTType.url.identifier
    let textType = UTType.plainText.identifier
    for provider in attachments {
      if provider.hasItemConformingToTypeIdentifier(urlType) {
        provider.loadItem(forTypeIdentifier: urlType, options: nil) {
          [weak self] data, _ in
          let shared = (data as? URL)?.absoluteString ?? (data as? String)
          self?.forward(shared)
        }
        return
      }
      if provider.hasItemConformingToTypeIdentifier(textType) {
        provider.loadItem(forTypeIdentifier: textType, options: nil) {
          [weak self] data, _ in
          self?.forward(data as? String)
        }
        return
      }
    }
    complete()
  }

  /// Writes the shared string to the App Group and wakes the host app. Runs the
  /// hand-off on the main thread because `loadItem` completes off-main.
  private func forward(_ shared: String?) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let trimmed = shared?.trimmingCharacters(in: .whitespacesAndNewlines)
      if let trimmed, !trimmed.isEmpty,
        let defaults = UserDefaults(suiteName: Self.appGroupId)
      {
        defaults.set(trimmed, forKey: Self.sharedUrlKey)
        self.openHostApp()
      }
      self.complete()
    }
  }

  /// Wakes the host app via its custom scheme. An extension has no direct handle
  /// to `UIApplication`, so walk the responder chain to the app and invoke the
  /// legacy `openURL:` selector — the standard technique for this hand-off.
  private func openHostApp() {
    guard let url = URL(string: "\(Self.hostScheme)://import") else { return }
    let selector = NSSelectorFromString("openURL:")
    var responder: UIResponder? = self
    while let current = responder {
      if current.responds(to: selector) {
        current.perform(selector, with: url)
        return
      }
      responder = current.next
    }
  }

  private func complete() {
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }
}
