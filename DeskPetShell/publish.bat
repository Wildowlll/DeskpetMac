@echo off
chcp 65001 >nul
rem ================================================================
rem  데스크펫 배포용 빌드
rem  - .NET 런타임이 없는 PC에서도 돌아가게 런타임을 exe에 포함 (self-contained)
rem  - 결과: dist\DeskPet\ 폴더 (DeskPet.exe + web 폴더) 와 dist\DeskPet-버전.zip
rem ================================================================
setlocal
cd /d "%~dp0"

set OUT=dist\DeskPet
if exist dist rmdir /s /q dist

dotnet publish DeskPetShell.csproj -c Release -r win-x64 --self-contained true ^
  -p:PublishSingleFile=true ^
  -p:IncludeNativeLibrariesForSelfExtract=true ^
  -p:EnableCompressionInSingleFile=true ^
  -p:DebugType=none ^
  -o "%OUT%"
if errorlevel 1 (
  echo.
  echo [실패] 빌드 중 오류가 났어요. 위 메시지를 확인해 주세요.
  pause
  exit /b 1
)

rem 버전 번호를 csproj에서 읽어서 zip 이름에 붙임
for /f "tokens=3 delims=<>" %%v in ('findstr /c:"<Version>" DeskPetShell.csproj') do set VER=%%v

powershell -NoProfile -Command "Compress-Archive -Path '%OUT%' -DestinationPath 'dist\DeskPet-%VER%.zip' -Force"

echo.
echo [완료] dist\DeskPet-%VER%.zip 을 배포하면 돼요.
explorer dist
pause
