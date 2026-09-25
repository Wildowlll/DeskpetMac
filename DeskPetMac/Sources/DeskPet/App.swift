import AppKit

@main
enum DeskPetMain {
    // ⚠ NSApp.delegate는 약한(weak) 참조라, 지역 변수에만 두면 릴리즈 빌드 최적화로 곧바로 해제됨
    //   → applicationDidFinishLaunching이 안 불려서 "실행은 되는데 아무것도 안 뜨는" 상태가 됨.
    //   static으로 붙잡아 둠.
    static let delegate = AppDelegate()

    static func main() {
        Log.start()
        let app = NSApplication.shared
        // Dock 아이콘 있는 일반 앱으로 실행 — 메뉴바 🐾가 노치에 가려져도 Dock에서 찾고 끌 수 있게
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }
}

/// Dock 아이콘 + 메뉴바(🐾) 둘 다 있는 앱.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let autoItem = NSMenuItem()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("launched \(Bundle.main.bundlePath)")
        // 두 개 실행되면 같은 세이브를 서로 덮어쓰므로 하나만 허용
        if let id = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
                .filter { $0 != NSRunningApplication.current }
            if let other = others.first {
                Log.write("another instance running (pid \(other.processIdentifier)) at \(other.bundleURL?.path ?? "?")")
                NSApp.activate(ignoringOtherApps: true)
                let a = NSAlert()
                a.messageText = Shell.L("데스크펫이 이미 실행 중이에요", "DeskPet is already running")
                a.informativeText = Shell.L("화면에 안 보인다면 이전 실행이 멈춘 상태일 수 있어요.\n기존 것을 끄고 새로 시작할까요?",
                                            "If you can't see it, the previous one may be stuck.\nQuit it and start fresh?")
                a.addButton(withTitle: Shell.L("기존 것 끄고 시작", "Quit it and start"))
                a.addButton(withTitle: Shell.L("그만두기", "Cancel"))
                if a.runModal() == .alertFirstButtonReturn {
                    other.forceTerminate()
                    var n = 0
                    while !other.isTerminated && n < 30 { RunLoop.current.run(until: Date().addingTimeInterval(0.1)); n += 1 }
                } else {
                    other.activate(options: [])
                    NSApp.terminate(nil)
                    return
                }
            }
        }
        setupMainMenu()
        setupStatusItem()
        Notifier.setup()
        Shell.shared.open(Shell.shared.settings.mode)
        NSApp.activate(ignoringOtherApps: true)
        Log.write("startup done")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // Dock 아이콘 우클릭 메뉴
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let m = NSMenu()
        m.addItem(item(Shell.L("🐾 창 모드", "🐾 Window mode"), #selector(showWindowMode)))
        m.addItem(item(Shell.L("🏃 자유 모드", "🏃 Free mode"), #selector(showFreeMode)))
        m.addItem(item(Shell.L("⚙ 설정", "⚙ Settings"), #selector(openSettings)))
        m.addItem(item(Shell.L("💬 대사 풀", "💬 Dialogue pool"), #selector(openPool)))
        return m
    }

    // Dock 아이콘 클릭, 또는 이미 실행 중일 때 응용 프로그램 폴더에서 또 더블클릭하면 → 숨어 있던 펫 창을 다시 보여줌
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Shell.shared.reveal()
        return false
    }

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
    // 앱이 앞에 있을 때 화면 맨 위 메뉴. 편집 메뉴가 있어야 입력칸에서 Cmd+C/V/A가 동작함
    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(item(Shell.L("🐾 창 모드", "🐾 Window mode"), #selector(showWindowMode)))
        appMenu.addItem(item(Shell.L("🏃 자유 모드", "🏃 Free mode"), #selector(showFreeMode)))
        let st = item(Shell.L("⚙ 설정…", "⚙ Settings…"), #selector(openSettings))
        st.keyEquivalent = ","
        appMenu.addItem(st)
        appMenu.addItem(item(Shell.L("💬 대사 풀", "💬 Dialogue pool"), #selector(openPool)))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: Shell.L("데스크펫 가리기", "Hide DeskPet"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: Shell.L("데스크펫 종료", "Quit DeskPet"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
