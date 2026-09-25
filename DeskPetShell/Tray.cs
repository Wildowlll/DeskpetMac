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
        menu.Items.Add("🐾 창 모드", null, (_, _) => Shell.ShowWindowMode());
        menu.Items.Add("🏃 자유 모드", null, (_, _) => Shell.Open("free"));
        menu.Items.Add("⚙ 설정", null, (_, _) => Shell.OpenSettings());
        menu.Items.Add("💬 대사 풀", null, (_, _) => Shell.OpenPool());
        var auto = new WinForms.ToolStripMenuItem("🚀 윈도우 시작 시 실행");
        auto.Click += (_, _) =>
        {
            try { Autostart.Set(!Autostart.IsOn); }
            catch (Exception ex) { MessageBox.Show("시작 프로그램 설정을 바꾸지 못했어요.\n\n" + ex.Message, "DeskPet"); }
        };
        menu.Items.Add(auto);
        menu.Opening += (_, _) => auto.Checked = Autostart.IsOn;   // 작업 관리자에서 바꿨을 수도 있으니 열 때마다 확인
        menu.Items.Add(new WinForms.ToolStripSeparator());
        menu.Items.Add("종료", null, (_, _) => Shell.Quit());

        _icon = new WinForms.NotifyIcon
        {
            Icon = icon,
            Text = "데스크펫",
            ContextMenuStrip = menu,
            Visible = true,
        };
        _icon.MouseClick += (_, e) => { if (e.Button == WinForms.MouseButtons.Left) Shell.ShowWindowMode(); };
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
