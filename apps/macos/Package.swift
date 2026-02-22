// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "VoiSER",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VoiSER", targets: ["VoiceWidget"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.3.0")
    ],
    targets: [
        .executableTarget(
            name: "VoiceWidget",
            dependencies: [
                "WhisperKit",
                "KeyboardShortcuts"
            ],
            resources: [
                .copy("Resources/Models"),
                .copy("Resources/AppIcon.icns")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "VoiceWidgetTests",
            dependencies: ["VoiceWidget"]
        )
    ]
)
