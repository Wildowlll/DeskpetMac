using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Web.WebView2.Core;

namespace DeskPetShell;

/// <summary>
/// 기본 모드: 레트로 다마고치 스타일의 작은 창.
/// 타이틀바는 HTML이 그리고, 창 이동은 NativeDrag로 C#이 처리.
/// 창 크기(소/중/대)는 WebView 줌으로 처리 → HTML 레이아웃은 항상 360x300 CSS px 기준.
/// </summary>
public partial class PetWindow : Window, IWebHost
{
    public event Action? WebReady;

    const double BaseW = 360, BaseH = 300;
    readonly NativeDrag _drag = new();

    public PetWindow()
    {
        InitializeComponent();

        var s = Shell.Settings;
        Topmost = s.Topmost;
        ApplyScale(s.Scale, keepOnScreen: false);
        WindowStartupLocation = WindowStartupLocation.Manual;
        if (s.WinLeft is double l && s.WinTop is double t && IsOnScreen(l, t))
        {
            Left = l; Top = t;
        }
        else
        {
            // 처음 실행: 작업 영역 오른쪽 아래
            var wa = SystemParameters.WorkArea;
            Left = wa.Right - Width - 24; Top = wa.Bottom - Height - 24;
        }

        Loaded += async (_, _) =>
        {
            if (!await Shell.EnsureWebAsync(env => Web.EnsureCoreWebView2Async(env))) return;
            Shell.ConfigureCore(Web.CoreWebView2,
                "mode=window&top=" + (Topmost ? "1" : "0"), OnWebMessage);
            WebReady?.Invoke();
        };
        // 최소화 여부를 페이지에 알림 → 최소화돼 있을 때만 트레이 알림 (원본의 '탭이 숨겨졌을 때' 규칙)
        StateChanged += (_, _) => Post($"{{\"type\":\"hostHidden\",\"on\":{(WindowState == WindowState.Minimized ? "true" : "false")}}}");
        Closing += (_, _) => SavePosition();
    }

    void OnWebMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        using var doc = JsonDocument.Parse(e.WebMessageAsJson);
        var msg = doc.RootElement;
        if (Shell.HandleCommon(msg)) return;

        switch (msg.GetProperty("type").GetString())
        {
            case "dragStart":   // 타이틀바를 잡았을 때 → 창 이동
                double startL = Left, startT = Top;
                double dpi = VisualTreeHelper.GetDpi(this).DpiScaleX;   // 물리 px → DIP
                _drag.Start(
                    (_, delta) => { Left = startL + delta.X / dpi; Top = startT + delta.Y / dpi; },
                    moved => { if (moved) SavePosition(); });
                break;

            case "minimize":
                WindowState = WindowState.Minimized;
                break;

            case "topmost":
                Topmost = msg.GetProperty("on").GetBoolean();
                Shell.Settings.Topmost = Topmost;
                Shell.Settings.Save();
                break;

            case "capture":     // 📷 저장 / 📋 복사
                _ = CaptureAsync(
                    msg.GetProperty("action").GetString() ?? "copy",
                    msg.GetProperty("name").GetString() ?? "deskpet.png",
                    msg.GetProperty("vw").GetDouble(),
                    new Rect(msg.GetProperty("x").GetDouble(), msg.GetProperty("y").GetDouble(),
                             msg.GetProperty("w").GetDouble(), msg.GetProperty("h").GetDouble()));
                break;

            case "scale":       // 설정의 창 크기(소/중/대)
                var v = msg.GetProperty("value").GetDouble();
                if (Math.Abs(v - Shell.Settings.Scale) > 0.001 || Math.Abs(Web.ZoomFactor - v) > 0.001)
                {
                    ApplyScale(v, keepOnScreen: true);
                    Shell.Settings.Scale = v;
                    Shell.Settings.Save();
                }
                break;
        }
    }

    void ApplyScale(double scale, bool keepOnScreen)
    {
        scale = Math.Clamp(scale, 0.75, 2);
        Web.ZoomFactor = scale;
        // 오른쪽 아래 모서리를 기준으로 크기를 바꿈 (보통 화면 오른쪽 아래에 두니까)
        double right = Left + Width, bottom = Top + Height;
        Width = Math.Round(BaseW * scale);
        Height = Math.Round(BaseH * scale);
        if (keepOnScreen)
        {
            var wa = SystemParameters.WorkArea;
            Left = Math.Clamp(right - Width, wa.Left, Math.Max(wa.Left, wa.Right - Width));
            Top = Math.Clamp(bottom - Height, wa.Top, Math.Max(wa.Top, wa.Bottom - Height));
            SavePosition();
        }
    }

    /// <summary>
    /// WebView2가 실제로 그린 화면을 캡처해서 요청한 영역만 잘라냄 (현재는 창 전체).
    /// cssRect는 CSS px 기준 → 캡처 이미지의 실제 픽셀 폭 / CSS 뷰포트 폭으로 배율을 구해 변환 (줌·DPI 모두 반영됨).
    /// </summary>
    async Task CaptureAsync(string action, string fileName, double cssViewportW, Rect cssRect)
    {
        try
        {
            using var ms = new MemoryStream();
            await Web.CoreWebView2.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, ms);
            ms.Position = 0;
            var full = new BitmapImage();
            full.BeginInit();
            full.CacheOption = BitmapCacheOption.OnLoad;
            full.StreamSource = ms;
            full.EndInit();
            full.Freeze();

            double k = full.PixelWidth / cssViewportW;
            int x = (int)Math.Round(cssRect.X * k), y = (int)Math.Round(cssRect.Y * k);
            int w = (int)Math.Round(cssRect.Width * k), h = (int)Math.Round(cssRect.Height * k);
            x = Math.Clamp(x, 0, full.PixelWidth - 1); y = Math.Clamp(y, 0, full.PixelHeight - 1);
            w = Math.Clamp(w, 1, full.PixelWidth - x); h = Math.Clamp(h, 1, full.PixelHeight - y);
            var crop = new CroppedBitmap(full, new Int32Rect(x, y, w, h));
            crop.Freeze();

            if (action == "save")
            {
                var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "DeskPet");
                Directory.CreateDirectory(dir);
                var path = Path.Combine(dir, string.Join("_", fileName.Split(Path.GetInvalidFileNameChars())));
                var enc = new PngBitmapEncoder();
                enc.Frames.Add(BitmapFrame.Create(crop));
                using (var fs = File.Create(path)) enc.Save(fs);
                PostCaptured(true, "📷 Pictures\\DeskPet", "capSavedApp");
            }
            else
            {
                // 다른 프로그램이 클립보드를 잡고 있으면 실패할 수 있어서 몇 번 재시도
                for (int i = 0; ; i++)
                {
                    try { Clipboard.SetImage(crop); break; }
                    catch (System.Runtime.InteropServices.COMException) when (i < 4) { await Task.Delay(60); }
                }
                PostCaptured(true, "📋", "capCopied");
            }
        }
        catch (Exception ex)
        {
            PostCaptured(false, ex.Message);
        }
    }

    // code: 페이지가 현재 언어로 문구를 고르는 키 / msg: 실패 시 오류 내용
    void PostCaptured(bool ok, string text, string code = "") =>
        Post(JsonSerializer.Serialize(new { type = "captured", ok, msg = text, code }));

    void Post(string json) => Shell.SafePost(Web.CoreWebView2, json);

    void SavePosition()
    {
        if (WindowState != WindowState.Normal || double.IsNaN(Left)) return;
        Shell.Settings.WinLeft = Left;
        Shell.Settings.WinTop = Top;
        Shell.Settings.Save();
    }

    // 모니터 구성이 바뀌어 저장된 위치가 화면 밖이면 무시
    static bool IsOnScreen(double l, double t) =>
        l > SystemParameters.VirtualScreenLeft - 100 &&
        t > SystemParameters.VirtualScreenTop - 20 &&
        l < SystemParameters.VirtualScreenLeft + SystemParameters.VirtualScreenWidth - 60 &&
        t < SystemParameters.VirtualScreenTop + SystemParameters.VirtualScreenHeight - 40;
}
