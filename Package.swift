// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PPTXLinkEditor",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PptxKit", targets: ["PptxKit"]),
        .executable(name: "pptxcli", targets: ["pptxcli"]),
        .executable(name: "PPTXLinkEditor", targets: ["PPTXLinkEditor"]),
    ],
    targets: [
        .target(name: "PptxKit"),
        .executableTarget(name: "pptxcli", dependencies: ["PptxKit"]),
        .executableTarget(name: "PPTXLinkEditor", dependencies: ["PptxKit"]),
    ]
)
