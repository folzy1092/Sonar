// swift-tools-version:6.0
// zsign (MIT, github.com/zhlynn/zsign) — подпись .app на устройстве для автообновления Sonar.
// Перенесено из Shadow вместе с заменой OpenSSL на Security.framework (openssl_apple.mm,
// pkcs12_apple.mm, shim/openssl/sha.h на CommonCrypto) — поэтому OpenSSL не нужен. См. README.md.
import PackageDescription

let package = Package(
    name: "Zsign",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "Zsign", targets: ["Zsign"]),
    ],
    targets: [
        .target(
            name: "Zsign",
            path: "Sources/Zsign",
            cSettings: [
                .headerSearchPath("common"),
                .headerSearchPath("shim"),
            ],
            cxxSettings: [
                .headerSearchPath("common"),
                .headerSearchPath("shim"),
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("Security"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
