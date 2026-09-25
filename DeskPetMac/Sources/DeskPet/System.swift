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
