import AppKit

/// 자유 모드: 화면 전체를 덮는 투명 창 (윈도우판 OverlayWindow)
/// - 메뉴바와 Dock을 뺀 영역(visibleFrame)을 덮음 → 펫이 Dock 바로 위를 걸어다님
/// - 펫/메뉴 위에 커서가 있을 때만 마우스를 받고, 나머지는 뒤 창으로 통과
final class OverlayWindowController: NSObject, HostWindow {
    let mode = "free"
    let page: WebPage
    let window: BorderlessWindow
    var onReady: (() -> Void)?

    private var hitRects: [NSRect] = []   // 창 기준 좌상단 원점 좌표 (= CSS px)
    private var hitTimer: Timer?
    private let drag = NativeDrag()
    private var lastSent = NSPoint(x: -1, y: -1)
    private var screenObserver: NSObjectProtocol?

    override init() {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        window = BorderlessWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        page = WebPage(query: "mode=free", transparent: true)
        super.init()

        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.contentView = page.webView
        window.setFrame(frame, display: false)

        page.onLoaded = { [weak self] in
            self?.startHitTest()
            self?.onReady?()
        }
        page.onMessage = { [weak self] m in self?.handle(m) }

        // 해상도·Dock 위치가 바뀌면 다시 맞춤
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            if let f = NSScreen.main?.visibleFrame { self?.window.setFrame(f, display: true) }
        }
    }

    func show() {
        window.orderFrontRegardless()
    }

    func close() {
        hitTimer?.invalidate()
        hitTimer = nil
        if let o = screenObserver { NotificationCenter.default.removeObserver(o) }
        page.teardown()
        window.close()
    }

    /// 화면 좌표(좌하단 원점) → 창 안 CSS 좌표(좌상단 원점)
    private func toLocal(_ p: NSPoint) -> NSPoint {
        let f = window.frame
        return NSPoint(x: p.x - f.minX, y: f.maxY - p.y)
    }

    private func startHitTest() {
        let t = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self = self, !self.drag.active else { return }
            let local = self.toLocal(NSEvent.mouseLocation)
            let over = self.hitRects.contains { $0.contains(local) }
            if self.window.ignoresMouseEvents == over { self.window.ignoresMouseEvents = !over }
        }
        RunLoop.main.add(t, forMode: .common)
        hitTimer = t
    }

    private func handle(_ msg: [String: Any]) {
        if Shell.shared.handleCommon(msg, from: page) { return }
        switch msg["type"] as? String {
        case "hitRects":
            let rects = msg["rects"] as? [[String: Any]] ?? []
            hitRects = rects.map { NSRect(x: num($0["x"]), y: num($0["y"]), width: num($0["w"]), height: num($0["h"])) }

        case "dragStart":   // 펫을 잡았을 때 → 좌표를 페이지로 계속 보냄
            window.ignoresMouseEvents = false
            lastSent = NSPoint(x: -1, y: -1)
            drag.start(onMove: { [weak self] p, _ in
                guard let self = self else { return }
                let l = self.toLocal(p)
                if l == self.lastSent { return }
                self.lastSent = l
                self.page.post(["type": "dragMove", "x": Double(l.x), "y": Double(l.y)])
            }, onEnd: { [weak self] moved in
                self?.page.post(["type": "dragEnd", "moved": moved])
            })

        default:
            break
        }
    }
}
