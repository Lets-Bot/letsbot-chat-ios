// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LetsBotChat",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(name: "LetsBotChat", targets: ["LetsBotChat"]),
    ],
    targets: [
        .target(
            name: "LetsBotChat",
            path: "Sources/LetsBotChat",
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy"),
            ]
        ),
        .testTarget(
            name: "LetsBotChatTests",
            dependencies: ["LetsBotChat"],
            path: "Tests/LetsBotChatTests"
        ),
    ]
)
