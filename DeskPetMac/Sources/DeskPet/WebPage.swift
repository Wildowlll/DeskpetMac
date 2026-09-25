import AppKit
import WebKit

/// 첫 클릭부터 바로 반응하는 웹뷰 (비활성 창이어도 펫 클릭이 먹히게)
final class DPWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// index.html 한 페이지를 띄운 웹뷰 + 앱 ↔ 페이지 통로.
/// 페이지 → 앱: window.webkit.messageHandlers.deskpet.postMessage(obj)
/// 앱 → 페이지: window.__deskpetHost(obj)
final class WebPage: NSObject, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate {
    let webView: DPWebView
    var onMessage: (([String: Any]) -> Void)?
    var onLoaded: (() -> Void)?
    private var loaded = false

    init(query: String, transparent: Bool) {
        Log.write("web: config")
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()          // 모든 창이 같은 localStorage(세이브)를 씀
        cfg.preferences.setValue(true, forKey: "developerExtrasEnabled")   // 문제 생기면 우클릭 → 요소 검사로 확인 가능
        Log.write("web: creating WKWebView")
        webView = DPWebView(frame: .zero, configuration: cfg)
        super.init()
        Log.write("web: WKWebView ready")

        cfg.userContentController.add(WeakHandler(self), name: "deskpet")
        // 페이지 JS 오류를 앱 로그로 (맥에서 문제 생겼을 때 원인 추적용)
        cfg.userContentController.addUserScript(WKUserScript(source: """
            (function(){
              function send(m){ try{ window.webkit.messageHandlers.deskpet.postMessage({type:'log', msg:String(m)}); }catch(_){} }
              window.addEventListener('error', function(e){ send((e.message||'error')+' @'+(e.filename||'')+':'+(e.lineno||0)); });
              window.addEventListener('unhandledrejection', function(e){ send('rejection: '+(e.reason && (e.reason.stack||e.reason))); });
            })();
            """, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        webView.uiDelegate = self
        webView.navigationDelegate = self
        if transparent {
            webView.setValue(false, forKey: "drawsBackground")   // 자유 모드: 배경 투명
            webView.underPageBackgroundColor = .clear
        }

        // ⚠ Bundle.main.resourceURL은 "Contents/Resources/ -- file:///…/DeskPet.app/" 같은 *상대* URL이라
        //   그대로 URLComponents에 넣으면 앞부분(앱 경로)이 떨어져 나가 "파일 URL이 아님" 예외로 조용히 멈춤.
        //   반드시 절대 경로 URL로 바꿔서 씀.
        guard let web = Bundle.main.resourceURL?.appendingPathComponent("web", isDirectory: true).absoluteURL.standardizedFileURL,
              FileManager.default.fileExists(atPath: web.appendingPathComponent("index.html").path) else {
            Log.write("web/index.html missing in \(Bundle.main.bundlePath)")
            DispatchQueue.main.async {
                Shell.alert(Shell.L("앱 안의 화면 파일(web/index.html)을 찾을 수 없어요. 다시 내려받아 주세요.",
                                    "The app's page files (web/index.html) are missing. Please download it again."))
            }
            return
        }
        let index = web.appendingPathComponent("index.html")
        var comps = URLComponents(url: index, resolvingAgainstBaseURL: true)
        comps?.query = query
        let url = comps?.url ?? index
        Log.write("web: load \(url.absoluteString)")
        guard url.isFileURL else { Log.write("web: not a file URL?!"); return }
        webView.loadFileURL(url, allowingReadAccessTo: web)
        Log.write("web: load requested")
    }

    func post(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__deskpetHost && window.__deskpetHost(\(json))", completionHandler: nil)
    }

    /// 창을 닫을 때 호출 — 메시지 핸들러가 페이지를 붙잡아 두지 않게
    func teardown() {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "deskpet")
        webView.stopLoading()
        onMessage = nil
    }

    // MARK: 페이지 → 앱
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any] { onMessage?(body) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Log.write("page loaded: \(webView.url?.query ?? "")")
        if !loaded { loaded = true; onLoaded?() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.write("page failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Log.write("page failed (provisional): \(error.localizedDescription)")
    }

    // 웹뷰 프로세스가 죽으면 빈 창이 되므로 다시 불러옴
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Log.write("web content process terminated → reload")
        webView.reload()
    }

    // MARK: alert / confirm / prompt — 웹뷰는 기본으로 안 띄워주므로 직접
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert()
        a.messageText = message
        a.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert()
        a.messageText = message
        a.addButton(withTitle: "확인")
        a.addButton(withTitle: "취소")
        completionHandler(a.runModal() == .alertFirstButtonReturn)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let a = NSAlert()
        a.messageText = prompt
        a.addButton(withTitle: "확인")
        a.addButton(withTitle: "취소")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = defaultText ?? ""
        a.accessoryView = field
        completionHandler(a.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
    }

    // MARK: <input type=file> (이미지 넣기, 백업 가져오기)
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        NSApp.activate(ignoringOtherApps: true)
        completionHandler(panel.runModal() == .OK ? panel.urls : nil)
    }

    // MARK: 다운로드 (백업 내보내기) → 다운로드 폴더
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var url = dir.appendingPathComponent(suggestedFilename)
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        completionHandler(url)
    }
}

/// WKUserContentController가 핸들러를 강하게 잡는 걸 끊기 위한 약한 참조 래퍼
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}
