import UIKit
import UniformTypeIdentifiers

/// Share Extension entry point (issue #343). It appears in the Safari / browser
/// share sheet; when the user shares a web page (e.g. a ContraDB program page),
/// this stashes the shared URL string in the shared App Group and wakes the
/// host app so it can import it through the existing hardened pipeline.
///
/// **Write-then-signal (issue #428):** the payload is appended to the App Group
/// queue *first* (durable), *then* the host is woken best-effort. The host also
/// drains the queue on its next activation, so delivery survives a failed wake —
/// nothing is orphaned even if the app was suspended/closed when it was shared.
///
/// This extension deliberately does **no** validation and **no** import: it
/// only forwards the raw shared string verbatim. The host app treats it as
/// untrusted input and OWASP-validates it (`validateSharedContraDbProgramUrl`:
/// https only, `contradb.com` host allow-list, `/programs/N` path) before it
/// touches the import pipeline. Keeping the native surface dumb keeps the trust
/// boundary in one place (Dart).
final class ShareViewController: UIViewController {
  /// App Group shared with the host app; shared URLs are handed over through
  /// its `UserDefaults` suite.
  private static let appGroupId = "group.org.callerscompendium.compendiumApp"

  /// Key under which raw shared URL strings are appended as a FIFO queue, so
  /// multiple shares while the host is suspended/closed all survive until the
  /// host drains them (issue #428).
  private static let sharedQueueKey = "SharedImportQueue"

  /// Custom URL scheme used only to wake the host app (NOT a universal link —
  /// see issue #343). Confirmed against `Runner/Info.plist` `CFBundleURLSchemes`.
  private static let hostScheme = "callerscompendium"

  /// Upper bound on queued payloads so repeatedly sharing into a suspended app
  /// can't grow the App Group unbounded; the host drains and clears it on its
  /// next activation. Oldest entries beyond the cap are dropped.
  private static let maxQueuedURLs = 16

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
  ///
  /// Write-then-signal (issue #428): the payload is made durable *before* the
  /// wake is attempted, so a failed wake never loses it.
  private func forward(_ shared: String?) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let trimmed = shared?.trimmingCharacters(in: .whitespacesAndNewlines)
      if let trimmed, !trimmed.isEmpty {
        self.enqueueSharedURL(trimmed)
      }
      self.wakeHostAndComplete()
    }
  }

  /// Appends the raw shared string to the App Group FIFO queue. The host treats
  /// every entry as untrusted input and OWASP-validates it before import.
  private func enqueueSharedURL(_ url: String) {
    guard let defaults = UserDefaults(suiteName: Self.appGroupId) else { return }
    var queue = defaults.stringArray(forKey: Self.sharedQueueKey) ?? []
    queue.append(url)
    if queue.count > Self.maxQueuedURLs {
      queue = Array(queue.suffix(Self.maxQueuedURLs))
    }
    defaults.set(queue, forKey: Self.sharedQueueKey)
  }

  /// Best-effort wake of the host via the PUBLIC extension API (issue #428),
  /// then finish the request. An extension must NOT reach `UIApplication` or the
  /// private `openURL:` selector (a no-op on scene-based iOS); `open` is the
  /// supported hand-off. Success or failure is non-fatal — the payload is
  /// already durable in the App Group and the host drains it on activation — so
  /// the request completes either way.
  private func wakeHostAndComplete() {
    guard let context = extensionContext,
      let url = URL(string: "\(Self.hostScheme)://import")
    else {
      complete()
      return
    }
    context.open(url) { [weak self] _ in
      self?.complete()
    }
  }

  private func complete() {
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }
}
