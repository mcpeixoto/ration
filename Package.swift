// swift-tools-version: 6.0
import PackageDescription

#if os(macOS)
let sparkleDependency: [Package.Dependency] = [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
]
#else
let sparkleDependency: [Package.Dependency] = []
#endif

#if os(macOS)
let macOSProducts: [Product] = [
    .executable(name: "Ration", targets: ["Ration"]),
]
let macOSTargets: [Target] = [
    .target(name: "RationUI", dependencies: ["RationKit"]),
    .executableTarget(
        name: "Ration",
        dependencies: [
            "RationKit", "RationUI",
            .product(name: "Sparkle", package: "Sparkle"),
        ]
    ),
    .executableTarget(name: "RationPreview", dependencies: ["RationKit", "RationUI"]),
    .testTarget(name: "RationUITests", dependencies: ["RationUI"]),
]
#else
let macOSProducts: [Product] = []
let macOSTargets: [Target] = []
#endif

let package = Package(
    name: "Ration",
    platforms: [.macOS(.v14)],
    products: macOSProducts + [
        .executable(name: "ration", targets: ["RationCLI"]),
        .library(name: "RationKit", targets: ["RationKit"]),
    ],
    dependencies: sparkleDependency,
    targets: [
        .systemLibrary(
            name: "CSqlite3",
            path: "Sources/CSqlite3",
            providers: [
                .apt(["libsqlite3-dev"]),
                .brew(["sqlite"]),
            ]
        ),
        .target(
            name: "RationKit",
            dependencies: ["CSqlite3"],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedLibrary("FoundationNetworking", .when(platforms: [.linux])),
            ]
        ),
        .executableTarget(
            name: "RationCLI",
            dependencies: ["RationKit"]
        ),
        .testTarget(
            name: "RationKitTests",
            dependencies: ["RationKit", "CSqlite3"],
            resources: [.copy("Fixtures")],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedLibrary("FoundationNetworking", .when(platforms: [.linux])),
            ]
        ),
    ] + macOSTargets
)
