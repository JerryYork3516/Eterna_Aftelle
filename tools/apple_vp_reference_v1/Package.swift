// swift-tools-version: 6.0
import Foundation
import PackageDescription

let referenceInfoPlistPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("Info.plist").path

let package = Package(
    name: "AppleVPReferenceV1",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "apple-vp-reference", targets: ["VPReferenceAudio"])],
    targets: [
        .target(
            name: "VPRecorder",
            cSettings: [.unsafeFlags(["-Wall", "-Wextra", "-Werror"])],
            linkerSettings: [.linkedFramework("AudioToolbox")]
        ),
        .target(name: "VPReferenceCore", dependencies: ["VPRecorder"]),
        .executableTarget(
            name: "VPReferenceAudio",
            dependencies: ["VPReferenceCore", "VPRecorder"],
            linkerSettings: [
                .linkedFramework("AVFoundation"), .linkedFramework("CoreAudio"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                    "-Xlinker", referenceInfoPlistPath
                ])
            ]
        ),
        .testTarget(name: "VPReferenceCoreTests", dependencies: ["VPReferenceCore", "VPRecorder"]),
        .testTarget(name: "VPReferenceAudioTests", dependencies: ["VPReferenceAudio", "VPRecorder"])
    ],
    swiftLanguageModes: [.v5]
)
