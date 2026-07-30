import SwiftUI
import AppKit

// Скриншоты для README. Утилита, а не разовый рендер: снимки должны
// пересниматься одной командой, иначе они устареют на первой же правке
// вёрстки и README начнёт врать.
//
//   swiftc -swift-version 6 -target arm64-apple-macos14.0 \
//       Shared/*.swift Widget/{Provider,Components,SmallView,MediumView,LargeView,ForecastChart}.swift \
//       Tools/ccwidget-screenshots/main.swift -o .build/ccwidget-screenshots
//   ./.build/ccwidget-screenshots Docs/screenshots -AppleLocale en_US -AppleLanguages "(en)"
//
// Локаль задаётся явно: подписи в README английские, а числа и даты идут
// через системный регион (раздел 10). Без -AppleLocale снимки выйдут
// с русскими «4 ч 16 мин» под английскими подписями.

let outDir = URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Docs/screenshots")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let store = SnapshotStore.default()
let snapshot = try? store.load()
let history = HistoryStore(store: store).load()
let now = Date()
let week = snapshot?.limits.sevenDay
let forecast = week.map { Forecast.make(history: history, window: $0, now: now) }
let entry = CCWidgetEntry(date: now, snapshot: snapshot, failure: nil, forecast: forecast)

guard snapshot != nil else {
    FileHandle.standardError.write(Data("нет снимка — сначала запустите Claude Code\n".utf8))
    exit(1)
}

/// Радиус углов виджетов на рабочем столе macOS.
let cornerRadius: CGFloat = 20

@MainActor
func shoot(_ name: String, _ size: CGSize, _ scheme: ColorScheme, @ViewBuilder _ content: () -> some View) {
    let body = content()
        .padding(14)
        .frame(width: size.width, height: size.height)
        .background(scheme == .dark ? Color(white: 0.14) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .environment(\.colorScheme, scheme)
        // Поля вокруг: скруглённый угол не должен упираться в край картинки.
        .padding(12)

    let renderer = ImageRenderer(content: body)
    renderer.scale = 2
    renderer.isOpaque = false
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("не удалось отрисовать \(name)\n".utf8))
        return
    }
    let url = outDir.appending(path: "\(name).png")
    try! png.write(to: url)
    print("\(url.lastPathComponent)  \(Int(size.width))×\(Int(size.height))")
}

let small = CGSize(width: 158, height: 158)
let medium = CGSize(width: 338, height: 158)
let large = CGSize(width: 338, height: 354)

for (suffix, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
    shoot("small-\(suffix)", small, scheme) { SmallView(entry: entry) }
    shoot("medium-\(suffix)", medium, scheme) { MediumView(entry: entry) }
    shoot("large-\(suffix)", large, scheme) { LargeView(entry: entry) }
}
