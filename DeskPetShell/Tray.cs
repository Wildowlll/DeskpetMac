using System.Windows;
using WinForms = System.Windows.Forms;

namespace DeskPetShell;

/// <summary>
/// 작업표시줄 알림 영역 아이콘: 메뉴(창 모드/자유 모드/설정/종료) + 알림 풍선.
/// 자유 모드는 작업표시줄에 버튼이 없어서, 여기가 항상 돌아올 수 있는 입구 역할.
/// </summary>
static class Tray
{
    static WinForms.NotifyIcon? _icon;

    public static void Init()
    {
        var icon = System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!)
                   ?? System.Drawing.SystemIcons.Application;

        var menu = new WinForms.ContextMenuStrip();
        _window = (WinForms.ToolStripMenuItem)menu.Items.Add("", null, (_, _) => Shell.ShowWindowMode());
        _free = (WinForms.ToolStripMenuItem)menu.Items.Add("", null, (_, _) => Shell.Open("free"));
        _settings = (WinForms.ToolStripMenuItem)menu.Items.Add("", null, (_, _) => Shell.OpenSettings());
        _pool = (WinForms.ToolStripMenuItem)menu.Items.Add("", null, (_, _) => Shell.OpenPool());
        _auto = new WinForms.ToolStripMenuItem("");
        _auto.Click += (_, _) =>
        {
            try { Autostart.Set(!Autostart.IsOn); }
            catch (Exception ex) { MessageBox.Show(Shell.L("시작 프로그램 설정을 바꾸지 못했어요.", "Couldn't change the startup setting.") + "\n\n" + ex.Message, "DeskPet"); }
        };
        menu.Items.Add(_auto);
        menu.Opening += (_, _) => _auto.Checked = Autostart.IsOn;   // 작업 관리자에서 바꿨을 수도 있으니 열 때마다 확인
        menu.Items.Add(new WinForms.ToolStripSeparator());
        _quit = (WinForms.ToolStripMenuItem)menu.Items.Add("", null, (_, _) => Shell.Quit());

        _icon = new WinForms.NotifyIcon
        {
            Icon = icon,
            Text = "DeskPet",
            ContextMenuStrip = menu,
            Visible = true,
        };
        _icon.MouseClick += (_, e) => { if (e.Button == WinForms.MouseButtons.Left) Shell.ShowWindowMode(); };
        ApplyLang();
    }

    static WinForms.ToolStripMenuItem? _window, _free, _settings, _pool, _auto, _quit;

    /// <summary>메뉴 글자를 현재 언어로</summary>
    public static void ApplyLang()
    {
        if (_icon == null) return;
        _window!.Text = Shell.L("🐾 창 모드", "🐾 Window mode");
        _free!.Text = Shell.L("🏃 자유 모드", "🏃 Free mode");
        _settings!.Text = Shell.L("⚙ 설정", "⚙ Settings");
        _pool!.Text = Shell.L("💬 대사 풀", "💬 Dialogue pool");
        _auto!.Text = Shell.L("🚀 윈도우 시작 시 실행", "🚀 Launch at startup");
        _quit!.Text = Shell.L("종료", "Quit");
        _icon.Text = Shell.L("데스크펫", "DeskPet");
    }

    public static void Balloon(string title, string body)
    {
        if (_icon == null) return;
        _icon.ShowBalloonTip(5000, title, body, WinForms.ToolTipIcon.None);   // Win10/11에선 토스트로 표시됨
    }

    public static void Dispose()
    {
        if (_icon == null) return;
        _icon.Visible = false;   // 안 끄면 종료 후에도 아이콘이 남아 있는 경우가 있음
        _icon.Dispose();
        _icon = null;
    }
}
