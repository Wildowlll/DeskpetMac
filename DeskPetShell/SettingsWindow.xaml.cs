using System.Text.Json;
using System.Windows;
using Microsoft.Web.WebView2.Core;

namespace DeskPetShell;

/// <summary>
/// 일반 창에 index.html의 보조 화면을 띄움.
///   "settings" = 설정 (원본 설정 팝업),  "pool" = 대사 풀 보기·편집
/// </summary>
public partial class SettingsWindow : Window
{
    public SettingsWindow() : this("settings") { }

    public SettingsWindow(string page)
    {
        InitializeComponent();
        if (page == "pool")
        {
            Title = "💬 대사 풀 — 데스크펫";
            Width = 640; Height = 660;
        }
        Loaded += async (_, _) =>
        {
            if (!await Shell.EnsureWebAsync(env => Web.EnsureCoreWebView2Async(env))) return;
            Shell.ConfigureCore(Web.CoreWebView2, "mode=" + page, OnWebMessage);
        };
    }

    void OnWebMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        using var doc = JsonDocument.Parse(e.WebMessageAsJson);
        var msg = doc.RootElement;
        switch (msg.GetProperty("type").GetString())
        {
            case "setAutostart":
                try { Autostart.Set(msg.GetProperty("on").GetBoolean()); }
                catch (Exception ex) { MessageBox.Show("시작 프로그램 설정을 바꾸지 못했어요.\n\n" + ex.Message, "DeskPet"); }
                goto case "getAutostart";   // 실제 결과를 다시 알려줌
            case "getAutostart":
                Shell.SafePost(Web.CoreWebView2, $"{{\"type\":\"autostart\",\"on\":{(Autostart.IsOn ? "true" : "false")}}}");
                return;
        }
        Shell.HandleCommon(msg);
    }
}
