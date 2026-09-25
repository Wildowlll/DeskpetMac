// swift-tools-version:5.9
// 데스크펫 맥판 — Xcode 프로젝트 없이 Swift Package로 빌드하고, build_app.sh가 .app으로 묶음
import PackageDescription

let package = Package(
    name: "DeskPet",
    platforms: [.macOS(.v13)],   // 로그인 시 실행(SMAppService)이 macOS 13부터
    targets: [
        .executableTarget(name: "DeskPet", path: "Sources/DeskPet")
    ]
)
