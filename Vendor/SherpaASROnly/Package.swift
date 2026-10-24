// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SherpaASROnly",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "sherpa-onnx", targets: ["SherpaOnnx"])],
    dependencies: [
        .package(url: "https://github.com/csukuangfj/onnxruntime-libs", exact: "1.28.2")
    ],
    targets: [
        .binaryTarget(name: "SherpaOnnxC", path: "Artifacts/SherpaOnnxC.xcframework"),
        .target(name: "SherpaOnnx", dependencies: [
            "SherpaOnnxC",
            .product(name: "onnxruntime-ios", package: "onnxruntime-libs", condition: .when(platforms: [.iOS])),
            .product(name: "onnxruntime-macos", package: "onnxruntime-libs", condition: .when(platforms: [.macOS]))
        ], linkerSettings: [.linkedLibrary("c++")])
    ]
)
