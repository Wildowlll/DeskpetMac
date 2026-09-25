using Microsoft.Win32;

namespace DeskPetShell;

/// <summary>
/// 윈도우 시작 시 자동 실행.
/// HKCU\...\Run 에 등록 → 관리자 권한 없이 현재 사용자에게만 적용되고,
/// 작업 관리자 [시작 앱] 탭에도 그대로 보여서 거기서 꺼도 됨.
/// </summary>
static class Autostart
{
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    const string Name = "DeskPet";
    static string Command => $"\"{Environment.ProcessPath}\"";

    public static bool IsOn
    {
        get
        {
            using var k = Registry.CurrentUser.OpenSubKey(RunKey);
            return k?.GetValue(Name) is string;
        }
    }

    public static void Set(bool on)
    {
        using var k = Registry.CurrentUser.CreateSubKey(RunKey, writable: true);
        if (on) k.SetValue(Name, Command);
        else k.DeleteValue(Name, throwOnMissingValue: false);
    }

    /// <summary>켜져 있는데 exe를 다른 폴더로 옮겼으면 경로를 현재 위치로 고쳐둠</summary>
    public static void RefreshPath()
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
            if (k?.GetValue(Name) is string cur && !string.Equals(cur, Command, StringComparison.OrdinalIgnoreCase))
                k.SetValue(Name, Command);
        }
        catch { /* 레지스트리 접근 실패는 무시 */ }
    }
}
