// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DeskPet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DeskPet", targets: ["DeskPet"])
    ],
    targets: [
        // Pure pet logic + persistence. No UI imports, fully unit-testable.
        .target(name: "DeskPetCore"),
        // The macOS app: windows, rendering, menu bar, settings.
        .executableTarget(
            name: "DeskPet",
            dependencies: ["DeskPetCore"]
        ),
        .testTarget(
            name: "DeskPetCoreTests",
            dependencies: ["DeskPetCore"]
        )
    ]
)
