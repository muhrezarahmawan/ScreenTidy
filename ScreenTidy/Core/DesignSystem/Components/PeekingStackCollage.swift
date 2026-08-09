import SwiftUI

/// Thematic mock screenshot kinds — replaced by Photos thumbnails in Sprint 4.
enum MockShotKind: String, CaseIterable, Sendable {
    case hotel
    case map
    case boarding
    case chat
    case receipt
    case furniture
    case document
    case restaurant
    case shopping
    case music
    case delivery
    case photo
}

/// Mini screenshot surface — white border, soft shadow, rounded corners.
/// Set `showsDeviceChrome` to `false` for full-bleed content (peek containers / Detail).
/// When `showsDeviceChrome` is true, also applies the classic 0.70 aspect ratio for standalone use.
struct ScreenshotPreview: View {
    let kind: MockShotKind
    var seed: Int = 0
    var showsDeviceChrome: Bool = true

    var body: some View {
        let preview = GeometryReader { geo in
            if showsDeviceChrome {
                chromePreview(size: geo.size)
            } else {
                fullBleedPreview(size: geo.size)
            }
        }

        if showsDeviceChrome {
            preview.aspectRatio(0.70, contentMode: .fit)
        } else {
            // Parent (`ScreenshotPeekContainer`) owns framing.
            preview
        }
    }

    private func chromePreview(size: CGSize) -> some View {
        let r = min(11, size.width * 0.15)
        let border = max(2.2, size.width * 0.04)

        return ZStack {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(Color.white)

            RoundedRectangle(cornerRadius: max(r - border * 0.5, 5), style: .continuous)
                .fill(sceneBackground)
                .padding(border)
                .overlay {
                    sceneContent(size: size)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: max(r - border * 0.5, 5),
                                style: .continuous
                            )
                        )
                        .padding(border)
                }
        }
        .stPeekShadow()
    }

    private func fullBleedPreview(size: CGSize) -> some View {
        ZStack(alignment: .top) {
            sceneBackground
            sceneContent(size: size, scaleAxis: .width)
                .frame(width: size.width, height: size.height, alignment: .top)
        }
        .frame(width: size.width, height: size.height)
    }

    private var sceneBackground: Color {
        switch kind {
        case .hotel: return Color(red: 0.90, green: 0.93, blue: 0.96)
        case .map: return Color(red: 0.86, green: 0.92, blue: 0.86)
        case .boarding: return Color(red: 0.93, green: 0.95, blue: 0.98)
        case .chat: return Color(red: 0.94, green: 0.95, blue: 0.97)
        case .receipt: return Color(red: 0.97, green: 0.97, blue: 0.96)
        case .furniture: return Color(red: 0.95, green: 0.92, blue: 0.88)
        case .document: return Color(red: 0.96, green: 0.96, blue: 0.97)
        case .restaurant: return Color(red: 0.96, green: 0.90, blue: 0.86)
        case .shopping: return Color(red: 0.95, green: 0.94, blue: 0.97)
        case .music: return Color(red: 0.20, green: 0.18, blue: 0.24)
        case .delivery: return Color(red: 0.93, green: 0.95, blue: 0.92)
        case .photo: return Color(red: 0.88, green: 0.90, blue: 0.93)
        }
    }

    private enum ScaleAxis {
        case minSide
        case width
    }

    @ViewBuilder
    private func sceneContent(size: CGSize, scaleAxis: ScaleAxis = .minSide) -> some View {
        let s = scaleAxis == .width ? size.width : min(size.width, size.height)

        VStack(spacing: 0) {
            switch kind {
            case .hotel: hotelScene(s: s)
            case .map: mapScene(s: s)
            case .boarding: boardingScene(s: s)
            case .chat: chatScene(s: s)
            case .receipt: receiptScene(s: s)
            case .furniture: furnitureScene(s: s)
            case .document: documentScene(s: s)
            case .restaurant: restaurantScene(s: s)
            case .shopping: shoppingScene(s: s)
            case .music: musicScene(s: s)
            case .delivery: deliveryScene(s: s)
            case .photo: photoScene(s: s)
            }

            Spacer(minLength: 0)
        }
    }

    private func hotelScene(s: CGFloat) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.68, blue: 0.82),
                            Color(red: 0.72, green: 0.80, blue: 0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: s * 0.28)
                .overlay {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: s * 0.12, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 4)
            mockLines(count: 3, s: s, widths: [0.72, 0.55, 0.4])
            Spacer(minLength: 0)
        }
    }

    private func mapScene(s: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.78, green: 0.88, blue: 0.78))
                .frame(width: s * 0.55)
                .offset(x: -s * 0.15, y: s * 0.05)
            Circle()
                .fill(Color(red: 0.82, green: 0.86, blue: 0.80))
                .frame(width: s * 0.4)
                .offset(x: s * 0.2, y: -s * 0.05)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.55))
                .frame(width: s * 0.08, height: s * 0.7)
                .rotationEffect(.degrees(25))
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: s * 0.18))
                .foregroundStyle(Color(red: 0.85, green: 0.25, blue: 0.25))
                .stBadgeShadow()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func boardingScene(s: CGFloat) -> some View {
        VStack(spacing: 3) {
            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 0.45, green: 0.55, blue: 0.75))
                    .frame(width: s * 0.35, height: s * 0.08)
                Spacer()
            }
            .padding(.horizontal, 5)

            HStack(spacing: 4) {
                Text("DOH")
                    .font(.system(size: s * 0.11, weight: .bold, design: .rounded))
                Image(systemName: "airplane")
                    .font(.system(size: s * 0.08))
                Text("NRT")
                    .font(.system(size: s * 0.11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Color(red: 0.25, green: 0.32, blue: 0.45))

            HStack(spacing: 1) {
                ForEach(0..<12, id: \.self) { i in
                    Rectangle()
                        .fill(STColor.textPrimary.opacity(i % 3 == 0 ? 0.55 : 0.25))
                        .frame(width: i % 2 == 0 ? 1.5 : 1)
                }
            }
            .frame(height: s * 0.16)
            .padding(.horizontal, 8)

            Spacer(minLength: 0)
        }
    }

    private func chatScene(s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            chatBubble(width: s * 0.55, align: .leading, color: Color.white)
            chatBubble(width: s * 0.48, align: .trailing, color: Color(red: 0.35, green: 0.55, blue: 0.95))
            chatBubble(width: s * 0.42, align: .leading, color: Color.white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private func chatBubble(width: CGFloat, align: HorizontalAlignment, color: Color) -> some View {
        HStack {
            if align == .trailing { Spacer(minLength: 0) }
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color)
                .frame(width: width, height: 10)
                .stBadgeShadow()
            if align == .leading { Spacer(minLength: 0) }
        }
    }

    private func receiptScene(s: CGFloat) -> some View {
        VStack(spacing: 2.5) {
            RoundedRectangle(cornerRadius: 1)
                .fill(STColor.textPrimary.opacity(0.2))
                .frame(width: s * 0.4, height: 3)
            mockLines(count: 5, s: s, widths: [0.8, 0.75, 0.7, 0.65, 0.45])
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private func furnitureScene(s: CGFloat) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.85, green: 0.78, blue: 0.68),
                            Color(red: 0.92, green: 0.88, blue: 0.80)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: s * 0.35)
                .overlay {
                    Image(systemName: "sofa.fill")
                        .font(.system(size: s * 0.16, weight: .ultraLight))
                        .foregroundStyle(Color(red: 0.55, green: 0.45, blue: 0.35).opacity(0.5))
                }
                .padding(.horizontal, 5)
            mockLines(count: 2, s: s, widths: [0.6, 0.35])
            Spacer(minLength: 0)
        }
    }

    private func documentScene(s: CGFloat) -> some View {
        VStack(spacing: 3) {
            HStack {
                Image(systemName: "globe")
                    .font(.system(size: s * 0.1))
                    .foregroundStyle(Color(red: 0.3, green: 0.4, blue: 0.6).opacity(0.6))
                Spacer()
            }
            .padding(.horizontal, 5)
            mockLines(count: 4, s: s, widths: [0.85, 0.8, 0.75, 0.5])
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(STColor.textPrimary.opacity(0.15), lineWidth: 0.5)
                .frame(height: s * 0.12)
                .padding(.horizontal, 6)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func restaurantScene(s: CGFloat) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.90, green: 0.55, blue: 0.40),
                            Color(red: 0.95, green: 0.75, blue: 0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: s * 0.32)
                .overlay {
                    Image(systemName: "fork.knife")
                        .font(.system(size: s * 0.12, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.horizontal, 5)
            mockLines(count: 2, s: s, widths: [0.65, 0.4])
            Spacer(minLength: 0)
        }
    }

    private func shoppingScene(s: CGFloat) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(red: 0.88, green: 0.86, blue: 0.92))
                .frame(height: s * 0.3)
                .overlay {
                    Image(systemName: "bag.fill")
                        .font(.system(size: s * 0.14, weight: .ultraLight))
                        .foregroundStyle(Color(red: 0.45, green: 0.4, blue: 0.55).opacity(0.45))
                }
                .padding(.horizontal, 5)
            mockLines(count: 3, s: s, widths: [0.7, 0.5, 0.35])
            Spacer(minLength: 0)
        }
    }

    private func musicScene(s: CGFloat) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.35, blue: 0.75),
                            Color(red: 0.35, green: 0.25, blue: 0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: s * 0.32)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: s * 0.14, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 6)
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 3)
                    .padding(.horizontal, 8)
            }
            Spacer(minLength: 0)
        }
    }

    private func deliveryScene(s: CGFloat) -> some View {
        VStack(spacing: 3) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: s * 0.18, weight: .ultraLight))
                .foregroundStyle(Color(red: 0.4, green: 0.55, blue: 0.4).opacity(0.55))
                .padding(.top, 6)
            mockLines(count: 3, s: s, widths: [0.7, 0.55, 0.4])
            Spacer(minLength: 0)
        }
    }

    private func photoScene(s: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.70, green: 0.78, blue: 0.88),
                    Color(red: 0.85, green: 0.88, blue: 0.90)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(systemName: "photo")
                .font(.system(size: s * 0.2, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func mockLines(count: Int, s: CGFloat, widths: [CGFloat]) -> some View {
        VStack(spacing: 2.5) {
            ForEach(0..<count, id: \.self) { i in
                let w = widths.indices.contains(i) ? widths[i] : 0.6
                RoundedRectangle(cornerRadius: 1)
                    .fill(STColor.textPrimary.opacity(0.12 + Double(i % 3) * 0.03))
                    .frame(width: s * w, height: max(2.5, s * 0.035))
            }
        }
    }
}

/// Exactly up to 3 peeks — fixed geometry owned by `ScreenshotPeekContainer`.
/// Real PhotoKit thumbnails and placeholders share the same fan layout.
struct PeekingStackCollage: View {
    let kinds: [MockShotKind]
    var photoLocalIdentifiers: [String] = []
    var shotWidth: CGFloat
    var shotHeight: CGFloat

    private struct PeekLayout {
        let rotation: Double
        let xFactor: CGFloat
        let yDrop: CGFloat
        let heightScale: CGFloat
        let z: Double
    }

    /// Reference fan — compact, centered in the mouth; leaves left tab visible.
    private let layouts: [PeekLayout] = [
        PeekLayout(rotation: -4.5, xFactor: -0.22, yDrop: 4, heightScale: 0.94, z: 1),
        PeekLayout(rotation: 0.0, xFactor: 0.02, yDrop: 0, heightScale: 1.0, z: 3),
        PeekLayout(rotation: 4.5, xFactor: 0.26, yDrop: 4, heightScale: 0.95, z: 2)
    ]

    var body: some View {
        let count = min(3, max(kinds.count, photoLocalIdentifiers.count))
        let shots = Array(kinds.prefix(count))
        let ids = Array(photoLocalIdentifiers.prefix(count))
        let usedLayouts: [PeekLayout] = {
            switch count {
            case 0: return []
            case 1: return [layouts[1]] // center only
            case 2: return [layouts[0], layouts[2]] // left + right
            default: return Array(layouts.prefix(3))
            }
        }()

        ZStack(alignment: .top) {
            ForEach(Array(shots.enumerated()), id: \.offset) { index, kind in
                let layout = usedLayouts[index]
                let h = shotHeight * layout.heightScale
                let w = shotWidth * (0.96 + layout.heightScale * 0.04)
                let photoID = ids.indices.contains(index) ? ids[index] : nil

                ScreenshotPeekContainer(width: w, height: h) {
                    PhotosThumbnailImage(
                        localIdentifier: photoID,
                        targetSize: CGSize(
                            width: max(1, w * 2),
                            height: max(1, h * 2)
                        ),
                        contentMode: .aspectFill
                    ) {
                        ScreenshotPreview(kind: kind, seed: index, showsDeviceChrome: false)
                    }
                }
                .rotationEffect(.degrees(layout.rotation), anchor: .bottom)
                .offset(x: shotWidth * layout.xFactor, y: layout.yDrop)
                .zIndex(layout.z)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }
}

/// Fixed peek chrome — geometry owner for both placeholders and PhotoKit thumbnails.
/// Outer size never depends on source image aspect ratio.
struct ScreenshotPeekContainer<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        let corner = min(STRadius.screenshotPeek, width * 0.15)
        let border = max(2.2, width * 0.04)
        let innerCorner = max(corner - border * 0.5, 5)

        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.white)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(1.01) // avoid hairline gaps after clip
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: innerCorner, style: .continuous))
                .padding(border)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .stPeekShadow()
    }
}
