// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "JBar",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "11.0.0")
    ],
    targets: [
        .executableTarget(
            name: "JBar",
            dependencies: [
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk")
            ],
            path: "Sources/JBar"
        )
    ]
)
