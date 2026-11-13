import UIKit
import WebKit
import Photos

/// Full-screen web view showing the live site, plus a native "Save to Photos" bridge.
/// To turn another site into an app, change `homeURL` (and the name/icon in project.yml + Resources).
final class WebViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandlerWithReply {
    private let homeURL = URL(string: "https://squish-video.vercel.app/")!

    private var webView: WKWebView!
    private let offlineView = OfflineView()
    private var saveHandle: FileHandle?
    private var saveURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "LaunchBackground") ?? .systemBackground

        let contents = WKUserContentController()
        if let scriptURL = Bundle.main.url(forResource: "inject", withExtension: "js"),
           let source = try? String(contentsOf: scriptURL, encoding: .utf8) {
            contents.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        contents.addScriptMessageHandler(self, contentWorld: .page, name: "squishSave")

        let config = WKWebViewConfiguration()
        config.userContentController = contents
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.allowsLinkPreview = false
        webView.navigationDelegate = self
        view.addSubview(webView)

        offlineView.frame = view.bounds
        offlineView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        offlineView.isHidden = true
        offlineView.retryButton.addTarget(self, action: #selector(retry), for: .touchUpInside)
        view.addSubview(offlineView)

        loadHome()
    }

    private func loadHome() {
        webView.load(URLRequest(url: homeURL))
    }

    @objc private func retry() {
        offlineView.isHidden = true
        loadHome()
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        offlineView.isHidden = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        offlineView.isHidden = true
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loadHome()
    }

    // MARK: Save bridge (inject.js streams the finished video here in base64 chunks)

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else {
            replyHandler(nil, "Bad message")
            return
        }
        do {
            switch op {
            case "begin":
                try closeSaveFile()
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("save", isDirectory: true)
                try? FileManager.default.removeItem(at: dir)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let url = dir.appendingPathComponent(Self.safeName(body["name"] as? String))
                FileManager.default.createFile(atPath: url.path, contents: nil)
                saveHandle = try FileHandle(forWritingTo: url)
                saveURL = url
                replyHandler(true, nil)

            case "chunk":
                guard let handle = saveHandle else { throw SaveError.notStarted }
                guard let text = body["data"] as? String, let data = Data(base64Encoded: text) else { throw SaveError.badChunk }
                try handle.write(contentsOf: data)
                replyHandler(true, nil)

            case "end":
                guard let url = saveURL else { throw SaveError.notStarted }
                try closeSaveFile()
                saveToPhotos(url) { result in replyHandler(result, nil) }

            default:
                replyHandler(nil, "Unknown op")
            }
        } catch {
            try? closeSaveFile()
            replyHandler(nil, error.localizedDescription)
        }
    }

    private func closeSaveFile() throws {
        let handle = saveHandle
        saveHandle = nil
        try handle?.close()
    }

    private func saveToPhotos(_ url: URL, done: @escaping (String) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    self.share(url)
                    done("denied")
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .video, fileURL: url, options: nil)
                }, completionHandler: { ok, _ in
                    DispatchQueue.main.async {
                        if ok {
                            done("saved")
                        } else {
                            // Photos refuses some formats (e.g. WebM): offer Files / AirDrop instead.
                            self.share(url)
                            done("shared")
                        }
                    }
                })
            }
        }
    }

    private func share(_ url: URL) {
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(sheet, animated: true)
    }

    private static func safeName(_ raw: String?) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = (raw ?? "").components(separatedBy: bad).joined(separator: "_")
        return cleaned.isEmpty ? "squished.mp4" : String(cleaned.prefix(150))
    }

    private enum SaveError: LocalizedError {
        case notStarted, badChunk
        var errorDescription: String? {
            switch self {
            case .notStarted: return "Save wasn't started."
            case .badChunk: return "Got a broken piece of the video."
            }
        }
    }
}

/// Shown when the site can't load (no internet).
final class OfflineView: UIView {
    let retryButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Try again"
        config.baseBackgroundColor = .label
        config.baseForegroundColor = .systemBackground
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
        return UIButton(configuration: config)
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "LaunchBackground") ?? .systemBackground

        let title = UILabel()
        title.text = "No connection"
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let body = UILabel()
        body.text = "Squish needs the internet to start up. Your videos are never uploaded."
        body.font = .systemFont(ofSize: 15)
        body.textColor = .secondaryLabel
        body.numberOfLines = 0
        body.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [title, body, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(24, after: body)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
