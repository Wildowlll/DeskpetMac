import AppKit
import WebKit

/// 창 모드 / 자유 모드 창이 공통으로 갖는 것
protocol HostWindow: AnyObject {
    var mode: String { get }
    var page: WebPage { get }
    var onReady: (() -> Void)? { get set }
    func show()
    func close()
}

/// 모든 창이 공유하는 것: 모드 전환, 설정·대사 풀 창, 공통 메시지 처리 (윈도우판 Shell.cs와 같은 역할)
final class Shell {
    static let shared = Shell()
    let settings = ShellSettings()

    private(set) var current: HostWindow?
    private var pages: [String: PageWindowController] = [:]   // "settings", "pool"

    /// "window" = 다마고치 창, "free" = 바탕화면 자유 모드
    func open(_ mode: String) {
        let m = mode == "free" ? "free" : "window"
        if let c = current, c.mode == m { c.show(); return }
        settings.mode = m

        let old = current
        let next: HostWindow = m == "free" ? OverlayWindowController() : PetWindowController()
        current = next
        if let old = old {
            // 새 창의 페이지가 다 뜬 다음에 옛 창을 닫음 (윈도우판과 같은 순서)
            var closed = false
            let closeOld = { if closed { return }; closed = true; old.close() }
            next.onReady = closeOld
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: closeOld)
        }
        next.show()
    }

    func showWindowMode() {
        if let c = current, c.mode == "window" { c.show() } else { open("window") }
    }

    func openPage(_ kind: String) {
        if let w = pages[kind] { w.show(); return }
        let w = PageWindowController(kind: kind)
        w.onClose = { [weak self] in self?.pages[kind] = nil }
        pages[kind] = w
        w.show()
    }

    /// 종료 전 저장
    func saveAll(_ done: @escaping () -> Void) {
        guard let wv = current?.page.webView else { done(); return }
        var finished = false
        let finish = { if finished { return }; finished = true; done() }
        wv.evaluateJavaScript("window.DeskPet && window.DeskPet.save(); true") { _, _ in finish() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: finish)
    }

    /// 모든 창 공통 메시지. 처리했으면 true.
    @discardableResult
    func handleCommon(_ msg: [String: Any], from page: WebPage) -> Bool {
        switch msg["type"] as? String {
        case "quit":
            DispatchQueue.main.async { NSApp.terminate(nil) }
        case "switchMode":
            let mode = msg["mode"] as? String ?? "window"
            DispatchQueue.main.async { self.open(mode) }
        case "openSettings":
            DispatchQueue.main.async { self.openPage("settings") }
        case "openPool":
            DispatchQueue.main.async { self.openPage("pool") }
        case "closeSettings":
            DispatchQueue.main.async { self.pages["settings"]?.window.performClose(nil) }
        case "notify":
            Notifier.show(title: msg["title"] as? String ?? "", body: msg["body"] as? String ?? "")
        case "setAutostart":
            do { try Autostart.set(msg["on"] as? Bool ?? false) }
            catch { Shell.alert("로그인 항목을 바꾸지 못했어요.\n\n\(error.localizedDescription)") }
            page.post(["type": "autostart", "on": Autostart.isOn])
        case "getAutostart":
            page.post(["type": "autostart", "on": Autostart.isOn])
        default:
            return false
        }
        return true
    }

    /// 📷 저장 / 📋 복사 — 웹뷰가 실제로 그린 화면을 찍어서 요청 영역만 사용
    func capture(page: WebPage, msg: [String: Any]) {
        let wv = page.webView
        let vw = num(msg["vw"])
        guard vw > 0 else { return }
        let k = wv.bounds.width / vw   // CSS px → 뷰 좌표(pt). 창 크기 배율(pageZoom) 반영
        let cfg = WKSnapshotConfiguration()
        cfg.rect = CGRect(x: num(msg["x"]) * k, y: num(msg["y"]) * k,
                          width: num(msg["w"]) * k, height: num(msg["h"]) * k)
        wv.takeSnapshot(with: cfg) { image, error in
            guard let image = image else {
                page.post(["type": "captured", "ok": false, "msg": error?.localizedDescription ?? "캡처 실패"])
                return
            }
            if (msg["action"] as? String) == "save" {
                guard let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    page.post(["type": "captured", "ok": false, "msg": "이미지 변환 실패"])
                    return
                }
                let dir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("DeskPet")
                let name = (msg["name"] as? String ?? "deskpet.png")
                    .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try png.write(to: dir.appendingPathComponent(name))
                    page.post(["type": "captured", "ok": true, "msg": "📷 사진/DeskPet 폴더에 저장했어요"])
                } catch {
                    page.post(["type": "captured", "ok": false, "msg": error.localizedDescription])
                }
            } else {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([image])
                page.post(["type": "captured", "ok": true, "msg": "📋 클립보드에 복사했어요"])
            }
        }
    }

    static func alert(_ text: String) {
        let a = NSAlert()
        a.messageText = "데스크펫"
        a.informativeText = text
        a.runModal()
    }
}

/// JSON 숫자(NSNumber) → Double
func num(_ v: Any?) -> Double {
    if let n = v as? NSNumber { return n.doubleValue }
    if let d = v as? Double { return d }
    return 0
}

/// 창 위치 등 앱 껍데기 설정 (게임 데이터는 웹뷰 localStorage)
final class ShellSettings {
    private let d = UserDefaults.standard

    var mode: String {
        get { d.string(forKey: "mode") ?? "window" }
        set { d.set(newValue, forKey: "mode") }
    }
    var topmost: Bool {
        get { d.object(forKey: "topmost") as? Bool ?? true }
        set { d.set(newValue, forKey: "topmost") }
    }
    var scale: Double {
        get { let v = d.double(forKey: "scale"); return v > 0 ? v : 1 }
        set { d.set(newValue, forKey: "scale") }
    }
    /// 창 좌하단 좌표 (맥 화면 좌표계)
    var winOrigin: NSPoint? {
        get {
            guard d.object(forKey: "winX") != nil else { return nil }
            return NSPoint(x: d.double(forKey: "winX"), y: d.double(forKey: "winY"))
        }
        set {
            guard let p = newValue else { return }
            d.set(p.x, forKey: "winX"); d.set(p.y, forKey: "winY")
        }
    }
}
