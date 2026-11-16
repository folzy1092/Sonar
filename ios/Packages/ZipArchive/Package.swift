// swift-tools-version:6.0
// SSZipArchive (MIT, github.com/ZipArchive/ZipArchive) + minizip-ng (zlib) — распаковка и упаковка
// IPA при автообновлении. Набор файлов и флаги — как в Shadow (third-party/ZipArchive). См. README.md.
import PackageDescription

let package = Package(
    name: "ZipArchive",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "ZipArchive", targets: ["ZipArchive"]),
    ],
    targets: [
        .target(
            name: "ZipArchive",
            path: "Sources/ZipArchive",
            exclude: ["minizip/LICENSE"],
            cSettings: [
                .define("HAVE_ZLIB"),
                .define("HAVE_INTTYPES_H"),
                .define("HAVE_PKCRYPT"),
                .define("HAVE_STDINT_H"),
                .define("HAVE_WZAES"),
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("Security"),
                .linkedLibrary("z"),
                // minizip перекодирует имена файлов в zip (mz_os_posix.c)
                .linkedLibrary("iconv"),
            ]
        ),
    ]
)
