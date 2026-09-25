using System.Windows;
using Microsoft.Web.WebView2.Core;

namespace DeskPetShell;

public partial class App : Application
{
    static Mutex? _single;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // 두 개 실행되면 같은 세이브를 서로 덮어쓰므로 하나만 허용
        _single = new Mutex(true, "DeskPet_SingleInstance_7f3a", out bool first);
        if (!first)
        {
            var ko = System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ko";
            MessageBox.Show(ko ? "데스크펫이 이미 실행 중이에요.\n작업표시줄 오른쪽 알림 영역의 🐾 아이콘을 확인해 주세요."
                               : "DeskPet is already running.\nLook for the 🐾 icon in the notification area of the taskbar.", "DeskPet");
            Shutdown();
            return;
        }

        try
        {
            Shell.Settings = ShellSettings.Load();
            Autostart.RefreshPath();
            // 모든 창(펫/자유/설정)이 같은 환경 = 같은 세이브 데이터를 공유해야 하므로 한 번만 만든다
            Shell.Env = await CoreWebView2Environment.CreateAsync(null, Shell.WebDataDir);
            Tray.Init();
            Shell.Open(Shell.Settings.Mode);
        }
        catch (Exception ex)
        {
            MessageBox.Show(Shell.L("시작 중 오류가 발생했어요.", "An error occurred while starting.") + "\n\n" + ex, "DeskPet");
            Shutdown();
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        Tray.Dispose();
        base.OnExit(e);
    }
}
