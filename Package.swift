// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Orchestrator",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OrchestratorCore", targets: ["OrchestratorCore"]),
        .executable(name: "orchestrator", targets: ["OrchestratorCLI"]),
        .executable(name: "OrchestratorApp", targets: ["OrchestratorApp"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "OrchestratorCore", path: "Sources/OrchestratorCore"),
        .executableTarget(name: "OrchestratorCLI", dependencies: ["OrchestratorCore"], path: "Sources/OrchestratorCLI"),
        .executableTarget(name: "OrchestratorApp", dependencies: ["OrchestratorCore"], path: "Sources/OrchestratorApp"),
        .testTarget(name: "OrchestratorCoreTests", dependencies: ["OrchestratorCore"], path: "Tests/OrchestratorCoreTests"),
    ]
)
