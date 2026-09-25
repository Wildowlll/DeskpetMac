import AppKit

@main
enum DeskPetMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

/// 메뉴바(🐾) 앱. Dock 아이콘은 없음(Info.plist의 LSUIElement).
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let autoItem = NSMenuItem()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 두 개 실행되면 같은 세이브를 서로 덮어쓰므로 하나만 허용
        if let id = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
                .filter { $0 != NSRunningApplication.current }
            if let other = others.first {
                other.activate(options: [])
                NSApp.terminate(nil)
                return
            }
        }
        setupMainMenu()
        setupStatusItem()
        Notifier.setup()
        Shell.shared.open(Shell.shared.settings.mode)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // 종료 전에 페이지에 저장을 한 번 시키고 끝냄 (Cmd+Q, 메뉴 종료 모두)
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Shell.shared.saveAll { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    // MARK: 메뉴바 아이콘
    private let windowItem = NSMenuItem(), freeItem = NSMenuItem(), settingsItem = NSMenuItem(),
                poolItem = NSMenuItem(), quitItem = NSMenuItem()

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐾"

        let menu = NSMenu()
        menu.delegate = self
        for (i, sel) in [(windowItem, #selector(showWindowMode)), (freeItem, #selector(showFreeMode)),
                         (settingsItem, #selector(openSettings)), (poolItem, #selector(openPool))] {
            i.target = self; i.action = sel; menu.addItem(i)
        }
        autoItem.target = self
        autoItem.action = #selector(toggleAutostart)
        menu.addItem(autoItem)
        menu.addItem(.separator())
        quitItem.target = self; quitItem.action = #selector(quit)
        menu.addItem(quitItem)
        statusItem.menu = menu
        applyLang()
        Shell.shared.onLangChange = { [weak self] in self?.applyLang() }
    }

    /// 메뉴 글자를 현재 언어로
    private func applyLang() {
        windowItem.title = Shell.L("🐾 창 모드", "🐾 Window mode")
        freeItem.title = Shell.L("🏃 자유 모드", "🏃 Free mode")
        settingsItem.title = Shell.L("⚙ 설정", "⚙ Settings")
        poolItem.title = Shell.L("💬 대사 풀", "💬 Dialogue pool")
        autoItem.title = Shell.L("🚀 로그인 시 실행", "🚀 Launch at login")
        quitItem.title = Shell.L("종료", "Quit")
        statusItem.button?.toolTip = Shell.L("데스크펫", "DeskPet")
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    func menuWillOpen(_ menu: NSMenu) {
        autoItem.state = Autostart.isOn ? .on : .off   // 시스템 설정에서 바꿨을 수도 있으니 열 때마다 확인
    }

    @objc private func showWindowMode() { Shell.shared.showWindowMode() }
    @objc private func showFreeMode() { Shell.shared.open("free") }
    @objc private func openSettings() { Shell.shared.openPage("settings") }
    @objc private func openPool() { Shell.shared.openPage("pool") }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func toggleAutostart() {
        do { try Autostart.set(!Autostart.isOn) }
        catch { Shell.alert(Shell.L("로그인 항목을 바꾸지 못했어요.", "Couldn't change the login item.") + "\n\n\(error.localizedDescription)") }
    }

    // MARK: 메인 메뉴
    // 메뉴바 앱이라 화면에 메뉴는 안 보이지만, 이게 있어야 입력칸에서 Cmd+C/V/A가 동작함
    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "데스크펫 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "다시 실행", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사하기", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let winItem = NSMenuItem()
        let win = NSMenu(title: "윈도우")
        win.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winItem.submenu = win
        main.addItem(winItem)

        NSApp.mainMenu = main
    }
}
