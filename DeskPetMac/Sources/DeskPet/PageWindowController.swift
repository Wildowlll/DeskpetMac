import AppKit

/// 설정 / 대사 풀 창 — 일반 창에 index.html?mode=settings|pool 을 띄움 (윈도우판 SettingsWindow)
final class PageWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    let page: WebPage
    var onClose: (() -> Void)?

    private let kind: String

    init(kind: String) {
        self.kind = kind
        let size = kind == "pool" ? NSSize(width: 640, height: 660) : NSSize(width: 500, height: 740)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        page = WebPage(query: "mode=" + kind, transparent: false)
        super.init()

        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 400)
        window.contentView = page.webView
        window.delegate = self
        window.center()
        applyLang()
        page.onMessage = { [weak self] m in
            guard let self = self else { return }
            Shell.shared.handleCommon(m, from: self.page)
        }
    }

    func applyLang() {
        window.title = kind == "pool"
            ? Shell.L("💬 대사 풀 — 데스크펫", "💬 Dialogue Pool — DeskPet")
            : Shell.L("⚙ 설정 — 데스크펫", "⚙ Settings — DeskPet")
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        page.teardown()
        onClose?()
    }
}
