import AppKit
import ServiceManagement
import UserNotifications

/// 로그인 시 실행 — 시스템 설정 > 일반 > 로그인 항목에 등록됨
enum Autostart {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
            // 서명 안 된 앱은 사용자가 시스템 설정에서 한 번 허용해야 할 수 있음
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// 맥 알림 센터 알림 (윈도우판 트레이 풍선 알림 대신)
enum Notifier {
    static func setup() {
        UNUserNotificationCenter.current().delegate = NotifierDelegate.shared
    }

    static func show(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

/// 앱이 앞에 있을 때도 알림 배너를 보여줌
final class NotifierDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifierDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}


/// 간단한 파일 로그: ~/Library/Logs/DeskPet.log (콘솔 앱에서도 "DeskPet"으로 검색 가능)
enum Log {
    static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("DeskPet.log")
    }()

    /// 실행할 때마다: 로그가 너무 커졌으면 비우고 시작
    static func start() {
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 512_000 {
            try? FileManager.default.removeItem(at: url)
        }
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        write("===== DeskPet \(v) / macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    }

    static func write(_ text: String) {
        NSLog("DeskPet: %@", text)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let data = "[\(f.string(from: Date()))] \(text)\n".data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}
