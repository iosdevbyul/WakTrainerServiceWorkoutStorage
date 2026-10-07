// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "WakTrainerServiceWorkoutStorage",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "WakTrainerServiceWorkoutStorage",
            targets: ["WakTrainerServiceWorkoutStorage"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/iosdevbyul/WakTrainerCoreModels",
            branch: "main"
        ),
        .package(
            url: "https://github.com/iosdevbyul/WakTrainerDomainWorkout",
            branch: "main"
        )
    ],
    targets: [
        .target(
            name: "WakTrainerServiceWorkoutStorage",
            dependencies: [
                "WakTrainerCoreModels",
                "WakTrainerDomainWorkout"
            ]
        ),
        .testTarget(
            name: "WakTrainerServiceWorkoutStorageTests",
            dependencies: [
                "WakTrainerServiceWorkoutStorage",
                "WakTrainerCoreModels",
                "WakTrainerDomainWorkout"
            ]
        )
    ]
)
