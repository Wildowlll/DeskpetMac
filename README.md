# 🐾 데스크펫 (윈도우 · 맥)

바탕화면에서 키우는 다마고치. 게임 화면은 `DeskPetShell/web/index.html` 하나를 두 플랫폼이 같이 씀.

| 폴더 | 내용 |
|---|---|
| `DeskPetShell/` | 윈도우판 (C# WPF + WebView2) — `publish.bat`으로 배포 파일 생성 |
| `DeskPetShell/web/` | 게임 화면·로직 (공용) |
| `DeskPetMac/` | 맥판 (Swift + WKWebView) — `build_app.sh`로 빌드 |
| `.github/workflows/mac.yml` | 맥판 자동 빌드 (GitHub Actions) |
