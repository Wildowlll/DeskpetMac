using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using Microsoft.Web.WebView2.Core;

namespace DeskPetShell;

/// <summary>
/// 모든 창이 공유하는 것들: WebView2 환경, 설정 파일, 모드 전환, 설정 창, 공통 메시지 처리.
/// </summary>
static class Shell
{
    public static readonly string AppDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeskPet");
    public static readonly string WebDataDir = Path.Combine(AppDir, "WebView2");   // localStorage 등 세이브 데이터

    public static CoreWebView2Environment Env = null!;

    /// <summary>앱 껍데기 문구 (트레이 메뉴·안내창). 언어는 페이지가 알려준 값을 따름</summary>
    public static string L(string ko, string en) => Settings.Lang == "en" ? en : ko;
    public static ShellSettings Settings = new();
    static Window? _current;
    static SettingsWindow? _settings;

    /// <summary>"window" = 다마고치 창, "free" = 바탕화면 자유 모드</summary>
    public static void Open(string mode)
    {
        mode = mode == "free" ? "free" : "window";
        if (_current != null && (_current is OverlayWindow) == (mode == "free")) { Activate(_current); return; }

        Settings.Mode = mode;
        Settings.Save();

        var old = _current;
        var next = mode == "free" ? (Window)new OverlayWindow() : new PetWindow();
        _current = next;
        if (old != null)
        {
            // 새 창의 WebView2가 완전히 뜬 다음에 옛 창을 닫는다.
            // 먼저 닫으면 잠깐 WebView가 0개가 되면서 브라우저 프로세스가 종료 절차에 들어가고,
            // 그 사이 새 창 초기화가 0x8007139F(잘못된 상태)로 실패함.
            bool closed = false;
            void CloseOld() { if (closed) return; closed = true; old.Close(); }
            ((IWebHost)next).WebReady += CloseOld;
            var fallback = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(8) };
            fallback.Tick += (_, _) => { fallback.Stop(); CloseOld(); };
            fallback.Start();
        }
        next.Show();
    }

    /// <summary>
    /// WebView2 초기화. 환경이 이미 종료 중이라 실패(0x8007139F)하면 환경을 새로 만들어 한 번 더 시도.
    /// 그래도 실패하면 오류를 보여주고 false.
    /// </summary>
    public static async Task<bool> EnsureWebAsync(Func<CoreWebView2Environment, Task> ensure)
    {
        try { await ensure(Env); return true; }
        catch (COMException ex) when ((uint)ex.HResult == 0x8007139F)
        {
            try
            {
                await Task.Delay(300);
                Env = await CoreWebView2Environment.CreateAsync(null, WebDataDir);
                await ensure(Env);
                return true;
            }
            catch (Exception ex2) { ShowError(ex2); return false; }
        }
        catch (Exception ex) { ShowError(ex); return false; }
    }

    static void ShowError(Exception ex) =>
        MessageBox.Show(L("화면을 띄우는 중 오류가 났어요. 트레이 아이콘에서 다시 열어 주세요.",
                          "Something went wrong while opening the window. Please reopen it from the tray icon.") + "\n\n" + ex.Message, "DeskPet");

    /// <summary>창이 닫히는 중이면 메시지 전송이 예외를 던지므로 조용히 무시</summary>
    public static void SafePost(CoreWebView2? core, string json)
    {
        if (core == null) return;
        try { core.PostWebMessageAsJson(json); }
        catch (COMException) { }
        catch (InvalidOperationException) { }   // ObjectDisposedException도 여기 포함됨
    }

    public static void ShowWindowMode()
    {
        if (_current is PetWindow w) Activate(w);
        else Open("window");
    }

    static void Activate(Window w)
    {
        if (w.WindowState == WindowState.Minimized) w.WindowState = WindowState.Normal;
        w.Show();
        w.Activate();
    }

    public static void OpenSettings()
    {
        if (_settings == null)
        {
            _settings = new SettingsWindow();
            _settings.Closed += (_, _) => _settings = null;
            _settings.Show();
        }
        Activate(_settings);
    }

    public static void CloseSettings() => _settings?.Close();

    static SettingsWindow? _pool;
    public static void OpenPool()
    {
        if (_pool == null)
        {
            _pool = new SettingsWindow("pool");
            _pool.Closed += (_, _) => _pool = null;
            _pool.Show();
        }
        Activate(_pool);
    }

    public static void Quit()
    {
        _settings?.Close();
        _pool?.Close();
        _current?.Close();
        Application.Current.Shutdown();
    }

    /// <summary>WebView2 초기화 이후 공통 설정 + 페이지 로드</summary>
    public static void ConfigureCore(CoreWebView2 core, string query,
        EventHandler<CoreWebView2WebMessageReceivedEventArgs> onMessage)
    {
        // file:// 대신 가상 호스트 → origin이 고정되어 모든 창이 같은 localStorage를 씀
        var webRoot = Path.Combine(AppContext.BaseDirectory, "web");
        core.SetVirtualHostNameToFolderMapping(
            "deskpet.local", webRoot, CoreWebView2HostResourceAccessKind.Allow);

        core.Settings.AreDefaultContextMenusEnabled = false;
        core.Settings.IsZoomControlEnabled = false;          // 사용자가 줌을 바꾸면 좌표 계산이 어긋남
        core.Settings.IsStatusBarEnabled = false;
        core.WebMessageReceived += onMessage;
        core.Navigate("https://deskpet.local/index.html?" + query);
    }

    /// <summary>모든 창 공통 메시지. 처리했으면 true.</summary>
    public static bool HandleCommon(JsonElement msg)
    {
        // 메시지 핸들러 안에서 자기 WebView를 바로 닫지 않도록 한 박자 늦춰 실행
        var d = Application.Current.Dispatcher;
        switch (msg.GetProperty("type").GetString())
        {
            case "quit":
                d.InvokeAsync(Quit);
                return true;
            case "switchMode":
                var mode = msg.GetProperty("mode").GetString() ?? "window";
                d.InvokeAsync(() => Open(mode));
                return true;
            case "openSettings":
                d.InvokeAsync(OpenSettings);
                return true;
            case "openPool":
                d.InvokeAsync(OpenPool);
                return true;
            case "closeSettings":
                d.InvokeAsync(CloseSettings);
                return true;
            case "lang":   // 페이지가 현재 언어를 알려줌 → 트레이 메뉴·창 제목 맞춤
                var lang = msg.GetProperty("value").GetString() == "en" ? "en" : "ko";
                if (lang != Settings.Lang) { Settings.Lang = lang; Settings.Save(); }
                d.InvokeAsync(() => { Tray.ApplyLang(); _settings?.ApplyLang(); _pool?.ApplyLang(); });
                return true;
            case "notify":
                Tray.Balloon(msg.GetProperty("title").GetString() ?? "", msg.GetProperty("body").GetString() ?? "");
                return true;
        }
        return false;
    }
}

/// <summary>WebView2 초기화가 끝났음을 알리는 창 (모드 전환 시 옛 창을 닫는 타이밍용)</summary>
interface IWebHost
{
    event Action? WebReady;
}

/// <summary>%LocalAppData%\DeskPet\settings.json — 창 위치 등 셸 전용 설정 (게임 데이터는 WebView2 localStorage)</summary>
class ShellSettings
{
    public string Mode { get; set; } = "window";
    public double? WinLeft { get; set; }
    public double? WinTop { get; set; }
    public bool Topmost { get; set; } = true;
    public double Scale { get; set; } = 1;
    /// <summary>처음엔 윈도우 표시 언어로 추정, 이후엔 페이지(설정의 언어 선택)가 알려준 값</summary>
    public string Lang { get; set; } =
        System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ko" ? "ko" : "en";

    static string FilePath => Path.Combine(Shell.AppDir, "settings.json");

    public static ShellSettings Load()
    {
        try { return JsonSerializer.Deserialize<ShellSettings>(File.ReadAllText(FilePath)) ?? new(); }
        catch { return new(); }
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Shell.AppDir);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this));
        }
        catch { /* 설정 저장 실패는 치명적이지 않음 */ }
    }
}

/// <summary>
/// 네이티브 드래그 추적기.
/// WebView2로 전달되는 마우스 이벤트는 빠르게 움직이면 뭉개지므로,
/// 드래그 중엔 커서 좌표와 버튼 상태를 Win32에서 매 프레임 직접 읽는다.
/// </summary>
sealed class NativeDrag
{
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT pt);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int nIndex);
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    const int VK_LBUTTON = 0x01, VK_RBUTTON = 0x02, SM_SWAPBUTTON = 23;
    const double Threshold = 5;   // 물리 픽셀. 이보다 적게 움직이고 떼면 클릭

    Point _origin;
    bool _moved;
    Action<Point, Vector>? _onMove;
    Action<bool>? _onEnd;

    public bool Active { get; private set; }

    /// <param name="onMove">(현재 커서 화면 좌표[물리 px], 시작점 대비 이동량[물리 px])</param>
    /// <param name="onEnd">moved: 실제로 드래그했는지(false면 클릭으로 취급)</param>
    public void Start(Action<Point, Vector> onMove, Action<bool> onEnd)
    {
        if (Active) return;
        Active = true; _moved = false;
        _origin = CursorScreen();
        _onMove = onMove; _onEnd = onEnd;
        CompositionTarget.Rendering += OnFrame;   // 모니터 주사율에 맞춰 호출
    }

    void OnFrame(object? sender, EventArgs e)
    {
        var p = CursorScreen();
        if (!PrimaryDown())
        {
            CompositionTarget.Rendering -= OnFrame;
            Active = false;
            _onEnd?.Invoke(_moved);
            return;
        }
        if (!_moved && (p - _origin).Length > Threshold) _moved = true;
        if (_moved) _onMove?.Invoke(p, p - _origin);
    }

    public static Point CursorScreen()
    {
        GetCursorPos(out var p);
        return new Point(p.X, p.Y);
    }

    static bool PrimaryDown()
    {
        int vk = GetSystemMetrics(SM_SWAPBUTTON) != 0 ? VK_RBUTTON : VK_LBUTTON;   // 좌우 버튼 바꿔 쓰는 사용자 대응
        return (GetAsyncKeyState(vk) & 0x8000) != 0;
    }
}
