import AppKit

/// 네이티브 드래그 추적기 (윈도우판 NativeDrag와 같은 역할).
/// 드래그 중엔 웹뷰의 마우스 이벤트 대신 커서 위치·버튼 상태를 직접 읽어서 끊김 없이 따라가게 함.
final class NativeDrag {
    private var timer: Timer?
    private var origin = NSPoint.zero
    private var moved = false
    private let threshold: CGFloat = 4   // 이보다 적게 움직이고 떼면 클릭

    var active: Bool { timer != nil }

    /// onMove(현재 커서 화면 좌표, 시작점 대비 이동량) — 맥 화면 좌표계(좌하단 원점, y 위로 증가)
    /// onEnd(실제로 드래그했는지)
    func start(onMove: @escaping (NSPoint, CGVector) -> Void, onEnd: @escaping (Bool) -> Void) {
        guard timer == nil else { return }
        origin = NSEvent.mouseLocation
        moved = false
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            let p = NSEvent.mouseLocation
            if NSEvent.pressedMouseButtons & 1 == 0 {
                t.invalidate()
                self.timer = nil
                onEnd(self.moved)
                return
            }
            let d = CGVector(dx: p.x - self.origin.x, dy: p.y - self.origin.y)
            if !self.moved && hypot(d.dx, d.dy) > self.threshold { self.moved = true }
            if self.moved { onMove(p, d) }
        }
        // 마우스를 누르고 있는 동안에도 돌도록 common 모드에 등록
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
