//
//  StickerBackdrop.swift
//  ImageDemo
//

import SwiftUI

enum StickerBackdrop: String, CaseIterable, Identifiable {
    case clear
    case peach
    case grape
    case mint
    case sky
    case butter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clear: "透明"
        case .peach: "桃汽"
        case .grape: "葡萄"
        case .mint: "薄荷"
        case .sky: "晴空"
        case .butter: "奶油"
        }
    }
}

struct StickerCard: View {
    let sticker: UIImage
    let backdrop: StickerBackdrop

    var body: some View {
        ZStack {
            BackdropFill(kind: backdrop)
            Image(uiImage: sticker)
                .resizable()
                .scaledToFit()
                .padding(56)
                .shadow(color: Color(hex: 0x3B2148).opacity(0.22), radius: 22, y: 14)
        }
    }
}

struct BackdropFill: View {
    let kind: StickerBackdrop

    var body: some View {
        switch kind {
        case .clear:
            Checkerboard()
        case .peach:
            blobBackground(
                colors: [Color(hex: 0xFFE4EC), Color(hex: 0xFF8FAB), Color(hex: 0xFFD0B5)],
                spots: [
                    Spot(color: Color(hex: 0xFF6B8A), x: -0.22, y: -0.28, size: 0.62),
                    Spot(color: Color(hex: 0xFFE7C2), x: 0.28, y: 0.32, size: 0.5)
                ]
            )
        case .grape:
            blobBackground(
                colors: [Color(hex: 0xEDE4FF), Color(hex: 0xD8B4FE), Color(hex: 0xF9A8D4)],
                spots: [
                    Spot(color: Color(hex: 0xC084FC), x: 0.26, y: -0.22, size: 0.58),
                    Spot(color: Color(hex: 0xF472B6), x: -0.24, y: 0.3, size: 0.46)
                ]
            )
        case .mint:
            blobBackground(
                colors: [Color(hex: 0xE6FFFA), Color(hex: 0x99F6E4), Color(hex: 0xBAE6FD)],
                spots: [
                    Spot(color: Color.white, x: -0.2, y: -0.24, size: 0.5),
                    Spot(color: Color(hex: 0x5EEAD4), x: 0.24, y: 0.28, size: 0.48)
                ]
            )
        case .sky:
            blobBackground(
                colors: [Color(hex: 0xE0F2FE), Color(hex: 0xC4B5FD), Color(hex: 0xFBCFE8)],
                spots: [
                    Spot(color: Color(hex: 0x7DD3FC), x: -0.26, y: -0.18, size: 0.55),
                    Spot(color: Color(hex: 0xF9A8D4), x: 0.22, y: 0.3, size: 0.42)
                ]
            )
        case .butter:
            blobBackground(
                colors: [Color(hex: 0xFFF7D6), Color(hex: 0xFDE68A), Color(hex: 0xFBCFE8)],
                spots: [
                    Spot(color: Color(hex: 0xFB7185), x: 0.3, y: -0.26, size: 0.28),
                    Spot(color: Color(hex: 0xFDBA74), x: -0.22, y: 0.28, size: 0.46),
                    Spot(color: Color.white.opacity(0.85), x: 0.12, y: 0.08, size: 0.16)
                ]
            )
        }
    }

    private func blobBackground(colors: [Color], spots: [Spot]) -> some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height)
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                ForEach(Array(spots.enumerated()), id: \.offset) { _, spot in
                    Circle()
                        .fill(spot.color)
                        .frame(width: side * spot.size, height: side * spot.size)
                        .blur(radius: side * 0.06)
                        .offset(x: geo.size.width * spot.x, y: geo.size.height * spot.y)
                }
            }
        }
    }
}

private struct Spot {
    let color: Color
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
}

struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 18
            let columns = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            for row in 0..<rows {
                for column in 0..<columns {
                    let light = (row + column).isMultiple(of: 2)
                    let rect = CGRect(
                        x: CGFloat(column) * cell,
                        y: CGFloat(row) * cell,
                        width: cell,
                        height: cell
                    )
                    context.fill(
                        Path(rect),
                        with: .color(light ? Color(hex: 0xFBF7FF) : Color(hex: 0xE7DEF5))
                    )
                }
            }
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
