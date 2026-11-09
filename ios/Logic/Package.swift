// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StopAndShootLogic",
    products: [
        .library(name: "StopAndShootLogic", targets: ["StopAndShootLogic"])
    ],
    targets: [
        .target(name: "StopAndShootLogic"),
        .testTarget(
            name: "StopAndShootLogicTests",
            dependencies: ["StopAndShootLogic"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
