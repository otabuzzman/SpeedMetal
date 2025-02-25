// swift-tools-version: 5.7

// WARNING:
// This file is automatically generated.
// Do not edit it by hand because the contents will be replaced.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "SpeedMetal",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .iOSApplication(
            name: "SpeedMetal",
            targets: ["AppModule"],
            bundleIdentifier: "com.otabuzzman.speedmetal.ios",
            teamIdentifier: "28FV44657B",
            displayVersion: "1.1.3",
            bundleVersion: "23",
            appIcon: .asset("AppIcon"),
            accentColor: .presetColor(.indigo),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            appCategory: .education
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
