// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MedoTouchPar",
    platforms: [.macOS(.v13)],
    targets: [
        // Objective-C shim around the private Touch Bar / LaunchServices / DisplayServices APIs.
        .target(
            name: "TBPrivate",
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("CoreGraphics")]
        ),
        .executableTarget(
            name: "MedoTouchPar",
            dependencies: ["TBPrivate"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
