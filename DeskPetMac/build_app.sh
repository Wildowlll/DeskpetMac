#!/bin/bash
# ================================================================
#  데스크펫 맥판 빌드 → dist/DeskPet.app, dist/DeskPet-mac-버전.zip
#  - 인텔 맥 + 애플 실리콘 맥 둘 다 돌아가는 유니버설 빌드
#  - web 폴더는 윈도우판과 같은 것을 씀 (기본: ../DeskPetShell/web)
#  - 맥이 없으면 GitHub Actions(.github/workflows/mac.yml)가 이 스크립트를 대신 돌림
# ================================================================
set -euo pipefail
cd "$(dirname "$0")"

WEB="${1:-../DeskPetShell/web}"
if [ ! -f "$WEB/index.html" ]; then
  echo "web 폴더를 찾을 수 없어요: $WEB" >&2
  exit 1
fi
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

echo "▶ 빌드 (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64
BIN=".build/apple/Products/Release/DeskPet"

echo "▶ .app 묶기"
APP="dist/DeskPet.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DeskPet"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R "$WEB" "$APP/Contents/Resources/web"

# 애플 실리콘은 서명 없는 실행 파일을 아예 못 돌리므로 최소한 임시(ad-hoc) 서명은 필수
echo "▶ 임시 서명"
codesign --force --deep --sign - "$APP"

echo "▶ 압축"
(cd dist && ditto -c -k --keepParent DeskPet.app "DeskPet-mac-$VERSION.zip")
echo "✅ dist/DeskPet-mac-$VERSION.zip"
