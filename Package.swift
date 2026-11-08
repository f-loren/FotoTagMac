// swift-tools-version: 6.2
import PackageDescription

let mlx: [Target.Dependency] = [
    .product(name: "MLXVLM", package: "mlx-swift-lm"),
    .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
    .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
    .product(name: "MLXGuidedGeneration", package: "mlx-swift-lm"),
    .product(name: "HuggingFace", package: "swift-huggingface"),
    .product(name: "Tokenizers", package: "swift-transformers"),
]
// prima versione: il controllo di concorrenza stretto di Swift 6 lo attiveremo più avanti
let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "FotoTagMac",
    defaultLocalization: "it",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "3.32.3")),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        // modello, prompt, pulizia delle parole chiave, database: condivisi da app e comando
        .target(name: "FotoTagCore", dependencies: mlx, swiftSettings: swift5),
        // app SwiftUI: scegli una cartella, analizza, rivedi i tag
        // Localizable.xcstrings: testi in inglese (D68); crea_app.sh copia le cartelle .lproj nell'app, dove le cerca Bundle.main
        .executableTarget(name: "FotoTag", dependencies: ["FotoTagCore"], resources: [.process("Localizable.xcstrings")], swiftSettings: swift5),
        // comando di prova: tagga alcune foto e scrive una riga JSON per foto
        .executableTarget(name: "fototag-cli", dependencies: ["FotoTagCore"], swiftSettings: swift5),
        // prove delle funzioni pure: xcodebuild test -scheme FotoTagMac-Package -destination 'platform=macOS'
        .testTarget(name: "FotoTagCoreTests", dependencies: ["FotoTagCore"], swiftSettings: swift5),
    ]
)
