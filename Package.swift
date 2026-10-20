// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AmplifierMac", platforms: [.macOS(.v13)],
    products: [.executable(name: "Amplifier", targets: ["AmplifierApp"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "ClientCore"),
        .executableTarget(name: "AmplifierApp", dependencies: ["ClientCore", .product(name: "Sparkle", package: "Sparkle", condition: .when(platforms: [.macOS]))],
                          resources: [.copy("Resources")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"], .when(platforms: [.macOS]))]),
        .testTarget(name: "ClientCoreTests", dependencies: ["ClientCore"])
    ])
