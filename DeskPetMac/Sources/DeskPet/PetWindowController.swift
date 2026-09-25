import AppKit

/// 제목 표시줄 없는 창도 키보드 포커스를 받을 수 있게
final class BorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 기본 모드: 레트로 다마고치 창 (윈도우판 PetWindow)
/// 창 크기(소/중/대)는 웹뷰 pageZoom으로 처리 → HTML은 항상 360x300 CSS px 기준
final class PetWindowController: NSObject, HostWindow, NSWindowDelegate {
    static let baseW: CGFloat = 360, baseH: CGFloat = 300

    let mode = "window"
    let page: WebPage
    let window: BorderlessWindow
    var onReady: (() -> Void)?
    private let drag = NativeDrag()
    private var scale: CGFloat

    override init() {
        let s = Shell.shared.settings
        scale = CGFloat(s.scale)
        window = BorderlessWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.baseW * scale, height: Self.baseH * scale),
            styleMask: [.borderless], backing: .buffered, defer: false)
        page = WebPage(query: "mode=window&top=" + (s.topmost ? "1" : "0"), transparent: false)
        super.init()

        window.isReleasedWhenClosed = false
        window.hasShadow = true
        window.backgroundColor = NSColor(red: 0.81, green: 0.78, blue: 0.71, alpha: 1)
        window.level = s.topmost ? .floating : .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = page.webView
        window.delegate = self
        page.webView.pageZoom = scale

        if let o = s.winOrigin, NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -40, dy: -40).contains(o) }) {
            window.setFrameOrigin(o)
        } else if let vf = NSScreen.main?.visibleFrame {
            // 처음 실행: 화면 오른쪽 아래 (Dock 위)
            window.setFrameOrigin(NSPoint(x: vf.maxX - window.frame.width - 24, y: vf.minY + 24))
        }

        page.onLoaded = { [weak self] in self?.onReady?() }
        page.onMessage = { [weak self] m in self?.handle(m) }
    }

    func show() {
        // 모니터를 뺐거나 해상도가 바뀌어 창이 화면 밖에 있으면 오른쪽 아래로 되돌림
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }),
           let vf = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: vf.maxX - window.frame.width - 24, y: vf.minY + 24))
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()   // 메뉴바 앱이 아직 활성화 전이어도 무조건 앞에
        NSApp.activate(ignoringOtherApps: true)
        page.post(["type": "hostHidden", "on": false])
    }

    func close() {
        page.teardown()
        window.close()
    }

    private func handle(_ msg: [String: Any]) {
        if Shell.shared.handleCommon(msg, from: page) { return }
        switch msg["type"] as? String {
        case "dragStart":   // 타이틀바를 잡았을 때 → 창 이동
            let start = window.frame.origin
            drag.start(onMove: { [weak self] _, d in
                self?.window.setFrameOrigin(NSPoint(x: start.x + d.dx, y: start.y + d.dy))
            }, onEnd: { [weak self] moved in
                if moved { self?.savePosition() }
            })

        case "minimize":    // 맥에선 메뉴바로 숨김 → 🐾 메뉴의 [창 모드]로 다시 열기
            window.orderOut(nil)
            page.post(["type": "hostHidden", "on": true])

        case "topmost":
            let on = msg["on"] as? Bool ?? true
            window.level = on ? .floating : .normal
            Shell.shared.settings.topmost = on

        case "scale":       // 설정의 창 크기(소/중/대)
            let v = CGFloat(max(0.75, min(2, num(msg["value"]))))
            guard abs(v - scale) > 0.001 || abs(page.webView.pageZoom - v) > 0.001 else { return }
            scale = v
            page.webView.pageZoom = v
            // 오른쪽 아래 모서리 기준으로 크기 변경
            let f = window.frame
            let w = Self.baseW * v, h = Self.baseH * v
            window.setFrame(NSRect(x: f.maxX - w, y: f.minY, width: w, height: h), display: true)
            Shell.shared.settings.scale = Double(v)
            savePosition()

        case "capture":
            Shell.shared.capture(page: page, msg: msg)

        default:
            break
        }
    }

    private func savePosition() {
        Shell.shared.settings.winOrigin = window.frame.origin
    }

    func windowDidMove(_ notification: Notification) { savePosition() }
}
