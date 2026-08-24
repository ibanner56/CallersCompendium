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
/// untrusted input and OWASP-validates it against the supported program and
/// single-dance page URL shapes before it touches an import pipeline. Keeping
/// the native surface dumb keeps the trust boundary in one place (Dart).
final class ShareViewController: UIViewController {
  /// App Group shared with the host app; shared URLs are handed over through the
  /// `SharedImportQueue` directory in its container.
  private static let appGroupId = "group.org.callerscompendium.compendiumApp"

  /// Directory inside the App Group container holding the shared-URL queue. Each
  /// payload is its own uniquely-named `.ccurl` file written via an atomic
  /// rename, so the host draining the queue only ever sees fully-written files
  /// and a payload appended mid-drain is never partially read or silently lost
  /// (issue #428, PR #484 review). Must match `IncomingFilesPlugin`'s queue.
  private static let queueDirectoryName = "SharedImportQueue"

  /// File extension marking a queued payload; anything else in the directory
  /// (e.g. a transient atomic-write temp file) is ignored by the drain.
  private static let payloadExtension = "ccurl"

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

  /// Writes the raw shared string to the App Group queue as its own uniquely
  /// named file, published atomically so the host — a separate process draining
  /// concurrently — only ever observes a fully-written payload (issue #428, PR
  /// #484 review). The host treats every entry as untrusted input and
  /// OWASP-validates it before import.
  private func enqueueSharedURL(_ url: String) {
    guard let data = url.data(using: .utf8),
      let directory = Self.queueDirectory()
    else { return }
    let fileManager = FileManager.default
    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      let destination = directory.appendingPathComponent(
        "\(UUID().uuidString).\(Self.payloadExtension)")
      // `.atomic` writes to a temp file then renames into place; the rename is
      // atomic within the directory, so the host never reads a half-written file.
      try data.write(to: destination, options: .atomic)
      pruneQueue(in: directory)
    } catch {
      // Best-effort: if the container is briefly unavailable we skip this payload
      // rather than crash the share sheet. Delivery of prior payloads is
      // unaffected — the host drains whatever is present on its next foreground.
    }
  }

  /// Bounds the queue so repeatedly sharing into a suspended app can't grow the
  /// container unbounded. Oldest payloads beyond the cap are dropped; the host
  /// clears the rest on its next activation.
  private func pruneQueue(in directory: URL) {
    let fileManager = FileManager.default
    guard
      let files = try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.creationDateKey],
        options: [.skipsHiddenFiles])
    else { return }
    let payloads =
      files
      .filter { $0.pathExtension == Self.payloadExtension }
      .sorted { Self.creationDate(of: $0) < Self.creationDate(of: $1) }
    guard payloads.count > Self.maxQueuedURLs else { return }
    for file in payloads.prefix(payloads.count - Self.maxQueuedURLs) {
      try? fileManager.removeItem(at: file)
    }
  }

  /// URL of the App Group queue directory, or `nil` if the container is
  /// unavailable.
  private static func queueDirectory() -> URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
      .appendingPathComponent(queueDirectoryName, isDirectory: true)
  }

  private static func creationDate(of url: URL) -> Date {
    (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
      ?? .distantPast
  }

  /// Opportunistically wakes the host, then finishes the request. Delivery is
  /// NOT dependent on this: the payload is already durably queued in the App
  /// Group and the host drains it on its next foreground (issue #428).
  ///
  /// `NSExtensionContext.open` is documented for Today/iMessage extensions and
  /// is unsupported by the Share extension point — it typically reports failure
  /// without foregrounding the host (PR #484 review). We therefore treat it as a
  /// best-effort nudge only: the result flag is ignored and the extension always
  /// completes SUCCESSFULLY, because the durable queue + host foreground-drain is
  /// the authoritative, guaranteed delivery path. We must never reach
  /// `UIApplication` or the private `openURL:` selector (a no-op on scene-based
  /// iOS).
  private func wakeHostAndComplete() {
    guard let context = extensionContext,
      let url = URL(string: "\(Self.hostScheme)://import")
    else {
      complete()
      return
    }
    // Ignore the result: open() may report failure on the Share extension point;
    // that is expected and non-fatal since the payload is already enqueued.
    context.open(url) { [weak self] _ in
      self?.complete()
    }
  }

  private func complete() {
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }
}
