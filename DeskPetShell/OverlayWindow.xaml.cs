using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;

namespace DeskPetShell;

/// <summary>
/// 자유 모드: 작업 영역 전체를 덮는 투명 오버레이 창.
/// - 펫/메뉴 위에 커서가 있을 때만 클릭을 받고, 나머지는 뒤 창으로 클릭 통과.
/// - 클릭 가능 영역(hit rect)은 HTML이 postMessage로 알려줌.
/// </summary>
public partial class OverlayWindow : Window, IWebHost
{
    public event Action? WebReady;

    const int GWL_EXSTYLE = -20;
    const int WS_EX_TRANSPARENT = 0x00000020; // 마우스 입력 통과
    const int WS_EX_TOOLWINDOW  = 0x00000080; // Alt+Tab 목록에서 숨김

    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    IntPtr _hwnd;
    bool _clickThrough;
    List<Rect> _hitRects = new();   // 창 기준 DIP 좌표 (= CSS px)
    readonly DispatcherTimer _hitTimer = new() { Interval = TimeSpan.FromMilliseconds(30) };
    readonly NativeDrag _drag = new();
    Point _lastSent;

    public OverlayWindow()
    {
        InitializeComponent();

        // 작업표시줄을 제외한 작업 영역 전체 → 펫이 작업표시줄 바로 위를 걸어다님
        var wa = SystemParameters.WorkArea;
        Left = wa.Left; Top = wa.Top; Width = wa.Width; Height = wa.Height;

        SourceInitialized += (_, _) =>
        {
            _hwnd = new WindowInteropHelper(this).Handle;
            var ex = GetWindowLong(_hwnd, GWL_EXSTYLE);
            SetWindowLong(_hwnd, GWL_EXSTYLE, ex | WS_EX_TOOLWINDOW);
            SetClickThrough(true);
        };

        Loaded += async (_, _) =>
        {
            Web.DefaultBackgroundColor = System.Drawing.Color.Transparent;   // 초기화 전에 지정해야 함
            if (!await Shell.EnsureWebAsync(env => Web.EnsureCoreWebView2Async(env))) return;
            Shell.ConfigureCore(Web.CoreWebView2, "mode=free", OnWebMessage);
            _hitTimer.Start();
            WebReady?.Invoke();
        };
        _hitTimer.Tick += (_, _) => UpdateHitTest();
        Closed += (_, _) => _hitTimer.Stop();
    }

    void OnWebMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        using var doc = JsonDocument.Parse(e.WebMessageAsJson);
        var msg = doc.RootElement;
        if (Shell.HandleCommon(msg)) return;

        switch (msg.GetProperty("type").GetString())
        {
            case "hitRects":
                _hitRects = msg.GetProperty("rects").EnumerateArray()
                    .Select(r => new Rect(
                        r.GetProperty("x").GetDouble(), r.GetProperty("y").GetDouble(),
                        r.GetProperty("w").GetDouble(), r.GetProperty("h").GetDouble()))
                    .ToList();
                break;

            case "dragStart":   // 펫을 잡았을 때 → 좌표를 HTML로 스트리밍
                SetClickThrough(false);
                _lastSent = new Point(double.NaN, double.NaN);
                _drag.Start(
                    (screen, _) =>
                    {
                        var p = PointFromScreen(screen);   // 물리 px → 창 기준 DIP
                        if (p == _lastSent) return;
                        _lastSent = p;
                        Post(FormattableString.Invariant(
                            $"{{\"type\":\"dragMove\",\"x\":{p.X:0.##},\"y\":{p.Y:0.##}}}"));
                    },
                    moved => Post($"{{\"type\":\"dragEnd\",\"moved\":{(moved ? "true" : "false")}}}"));
                break;
        }
    }

    void Post(string json) => Shell.SafePost(Web.CoreWebView2, json);

    void UpdateHitTest()
    {
        if (_drag.Active || _hwnd == IntPtr.Zero) return;   // 드래그 중엔 클릭 통과 금지 유지
        var local = PointFromScreen(NativeDrag.CursorScreen());
        SetClickThrough(!_hitRects.Any(r => r.Contains(local)));
    }

    void SetClickThrough(bool on)
    {
        if (_hwnd == IntPtr.Zero || on == _clickThrough) return;
        var ex = GetWindowLong(_hwnd, GWL_EXSTYLE);
        ex = on ? (ex | WS_EX_TRANSPARENT) : (ex & ~WS_EX_TRANSPARENT);
        SetWindowLong(_hwnd, GWL_EXSTYLE, ex);
        _clickThrough = on;
    }
}
