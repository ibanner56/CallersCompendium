import UIKit
import UniformTypeIdentifiers

/// Share Extension entry point (issue #343). It appears in the Safari / browser
/// share sheet; when the user shares a web page, this stashes the shared URL
/// string in the shared App Group for the host app to import.
///
/// **Write-then-confirm:** the payload is appended to the App Group queue
/// *before* the extension presents a confirmation. A Share Extension cannot
/// foreground its containing app, so the user explicitly dismisses this surface
/// and opens Caller's Compendium to review and import the queued link.
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

  /// Upper bound on queued payloads so repeatedly sharing into a suspended app
  /// can't grow the App Group unbounded; the host drains and clears it on its
  /// next activation. Oldest entries beyond the cap are dropped.
  private static let maxQueuedURLs = 16
  private let titleLabel = UILabel()
  private let messageLabel = UILabel()
  private let activityIndicator = UIActivityIndicatorView(style: .large)
  private let doneButton = UIButton(type: .system)

  override func viewDidLoad() {
    super.viewDidLoad()
    configureView()
    showLoading()
    handleShare()
  }

  private func configureView() {
    view.backgroundColor = .systemBackground
    let content = UIStackView(arrangedSubviews: [
      titleLabel,
      activityIndicator,
      messageLabel,
      doneButton,
    ])
    content.axis = .vertical
    content.spacing = 16
    content.alignment = .fill
    content.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(content)

    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.textAlignment = .center
    titleLabel.adjustsFontForContentSizeCategory = true

    messageLabel.font = .preferredFont(forTextStyle: .body)
    messageLabel.numberOfLines = 0
    messageLabel.textAlignment = .center
    messageLabel.adjustsFontForContentSizeCategory = true

    doneButton.configuration = .filled()
    doneButton.setTitle("Done", for: .normal)
    doneButton.addTarget(self, action: #selector(dismissExtension), for: .touchUpInside)

    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
      content.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }

  private func handleShare() {
    guard
      let item = extensionContext?.inputItems.first as? NSExtensionItem,
      let attachments = item.attachments
    else {
      return showFailure(
        title: "No link to import",
        message: "This share did not include a link that Caller's Compendium can import.")
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
    showFailure(
      title: "No link to import",
      message: "This share did not include a link that Caller's Compendium can import.")
  }

  /// Writes the shared string to the App Group. Runs the hand-off on the main
  /// thread because `loadItem` completes off-main.
  private func forward(_ shared: String?) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let trimmed = shared?.trimmingCharacters(in: .whitespacesAndNewlines)
      if let trimmed, !trimmed.isEmpty {
        if self.enqueueSharedURL(trimmed) {
          self.showConfirmation()
        } else {
          self.showFailure(
            title: "Couldn't save link",
            message: "Caller's Compendium could not save this link for import. Please try again.")
        }
      } else {
        self.showFailure(
          title: "No link to import",
          message: "This share did not include a link that Caller's Compendium can import.")
      }
    }
  }

  /// Writes the raw shared string to the App Group queue as its own uniquely
  /// named file, published atomically so the host — a separate process draining
  /// concurrently — only ever observes a fully-written payload (issue #428, PR
  /// #484 review). The host treats every entry as untrusted input and
  /// OWASP-validates it before import.
  private func enqueueSharedURL(_ url: String) -> Bool {
    guard let data = url.data(using: .utf8),
      let directory = Self.queueDirectory()
    else { return false }
    let fileManager = FileManager.default
    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      let destination = directory.appendingPathComponent(
        "\(UUID().uuidString).\(Self.payloadExtension)")
      // `.atomic` writes to a temp file then renames into place; the rename is
      // atomic within the directory, so the host never reads a half-written file.
      try data.write(to: destination, options: .atomic)
      pruneQueue(in: directory)
      return true
    } catch {
      return false
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

  private func showLoading() {
    titleLabel.text = "Preparing import"
    messageLabel.text = "Saving this link for Caller's Compendium."
    activityIndicator.startAnimating()
    doneButton.isHidden = true
  }

  private func showConfirmation() {
    titleLabel.text = "Ready to import"
    messageLabel.text =
      "This link has been saved. Open Caller's Compendium to review and import it."
    activityIndicator.stopAnimating()
    doneButton.isHidden = false
  }

  private func showFailure(title: String, message: String) {
    titleLabel.text = title
    messageLabel.text = message
    activityIndicator.stopAnimating()
    doneButton.isHidden = false
  }

  @objc private func dismissExtension() {
    complete()
  }

  private func complete() {
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }
}
