import SwiftUI

/// ScreenTidy Collection — Folder design (locked to reference).
///
/// Hierarchy (back → front):
/// 1. `FolderBackShape` — light gray back + upper-left tab
/// 2. `FolderPeekStack` — max 3 peeks, centered, clearly peeking above the front
/// 3. Front flap — shorter white face
/// 4. Icon (upper-left) + title/count (lower-left)
struct ContextCollectionPocketView: View {
    let collection: ContextCollection

    var body: some View {
        // Envelope size is aspect-only — title line count must never change cell height.
        // Do NOT `.clipped()` here — peeks intentionally draw into the folder mouth (and slightly past the top lip).
        Color.clear
            .aspectRatio(FolderLayout.aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { geo in
                    let layout = FolderLayout(width: geo.size.width)
                    folder(layout: layout)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func folder(layout: FolderLayout) -> some View {
        ZStack(alignment: .top) {
            FolderBackShape(layout: layout)
                .fill(FolderChrome.back)
                .frame(width: layout.width, height: layout.totalHeight)
                .zIndex(0)

            if peekCount > 0 {
                FolderPeekStack(
                    kinds: peekKinds,
                    photoLocalIdentifiers: peekPhotoIDs,
                    layout: layout
                )
                .zIndex(1)
            }

            folderFront(layout: layout)
                .frame(width: layout.width, height: layout.frontHeight)
                .padding(.top, layout.frontTop)
                .zIndex(2)
        }
        .background {
            FolderBackShape(layout: layout)
                .fill(Color.black.opacity(0.001))
                .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 6)
                .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
        }
    }

    private func folderFront(layout: FolderLayout) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: layout.frontRadius, style: .continuous)
                .fill(FolderChrome.front)
                // Depth only BELOW the front — never around the upper corners.
                // SwiftUI `.shadow` blurs upward and dirtied the back-folder lip (red arrows).
                .background(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: layout.frontRadius, style: .continuous)
                        .fill(Color.black.opacity(0.055))
                        .blur(radius: 7)
                        .offset(y: 5)
                        .padding(.horizontal, 10)
                        .padding(.top, layout.frontHeight * 0.55)
                        .allowsHitTesting(false)
                }

            // Icon pinned top-left — not in a VStack with Spacer (Spacer was crushing titles to 1 line).
            folderIcon(layout: layout)
                .padding(.top, layout.folderTopInset)
                .padding(.leading, layout.folderHorizontalInset)

            // Title + count pinned bottom-left. Title sizes to 1–2 lines, then truncates.
            VStack(alignment: .leading, spacing: layout.titleCountGap) {
                Text(collection.title)
                    .font(STTypography.pocketTitle)
                    .foregroundStyle(STColor.label)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(countLabel)
                    .font(STTypography.pocketMeta)
                    .foregroundStyle(STColor.secondaryLabel)
                    .lineLimit(1)
            }
            .padding(.horizontal, layout.folderHorizontalInset)
            .padding(.bottom, layout.folderBottomInset)
            .padding(.top, layout.folderTopInset + layout.iconSize + layout.emojiMetadataGap)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        // Hard-cap front drawing so 2-line titles can't inflate the folder envelope.
        .frame(width: layout.width, height: layout.frontHeight)
        .clipped()
    }

    @ViewBuilder
    private func folderIcon(layout: FolderLayout) -> some View {
        ZStack {
            if let emoji = collection.badgeEmoji, !emoji.isEmpty {
                Circle()
                    .fill(STCollectionBadgePalette.color(forHex: collection.badgeColor))
                    .frame(width: layout.iconSize, height: layout.iconSize)
                Text(emoji)
                    .font(.system(size: layout.badgeEmojiFontSize))
            } else {
                Image(systemName: "folder.fill")
                    .font(.system(size: layout.iconFontSize * 0.95, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.78, green: 0.80, blue: 0.84),
                                Color(red: 0.58, green: 0.61, blue: 0.67)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: layout.iconSize, height: layout.iconSize, alignment: .center)
        // Force tile refresh when badge styling changes (same collection id).
        .id("\(collection.badgeEmoji ?? "")|\(collection.badgeColor ?? "")")
        .accessibilityHidden(true)
    }

    // MARK: - Peek data

    private var peekCount: Int {
        if !collection.memberPreviewLocalIdentifiers.isEmpty {
            return min(3, collection.memberPreviewLocalIdentifiers.count)
        }
        if collection.memberCount <= 0 { return 0 }
        return min(3, max(collection.memberCount, collection.memberPreviewSymbols.count))
    }

    private var peekPhotoIDs: [String] {
        Array(collection.memberPreviewLocalIdentifiers.prefix(peekCount))
    }

    private var peekKinds: [MockShotKind] {
        let symbols = collection.memberPreviewSymbols.compactMap { MockShotKind(rawValue: $0) }
        let fallback: [MockShotKind] = [.hotel, .map, .boarding]
        return (0..<peekCount).map { index in
            symbols.indices.contains(index) ? symbols[index] : fallback[index % fallback.count]
        }
    }

    private var countLabel: String {
        let n = collection.memberCount
        return n == 1 ? "1 screenshot" : "\(n) screenshots"
    }

    private var accessibilityLabel: String {
        [collection.title, countLabel].joined(separator: ", ")
    }
}

// MARK: - Folder back silhouette

/// Shared folder-back silhouette — Collections + New Collection tile.
struct FolderBackShape: Shape {
    let layout: FolderLayout

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let tabTop = rect.minY
        let bodyTop = rect.minY + layout.tabRise
        let r = layout.backRadius
        let tr = layout.tabRadius
        let tabFlatEnd = w * 0.27
        let shoulderStart = w * 0.30
        let shoulderEnd = w * 0.50

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tr, y: tabTop))
        path.addLine(to: CGPoint(x: tabFlatEnd, y: tabTop))
        path.addCurve(
            to: CGPoint(x: shoulderEnd, y: bodyTop),
            control1: CGPoint(x: shoulderStart + w * 0.04, y: tabTop),
            control2: CGPoint(x: shoulderStart + w * 0.06, y: bodyTop)
        )
        path.addLine(to: CGPoint(x: rect.maxX - r, y: bodyTop))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: bodyTop + r),
            control: CGPoint(x: rect.maxX, y: bodyTop)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: tabTop + tr))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tr, y: tabTop),
            control: CGPoint(x: rect.minX, y: tabTop)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Folder peek stack

/// Three peeks fanned in the pocket — tops clearly above the front lip (reference).
private struct FolderPeekStack: View {
    let kinds: [MockShotKind]
    let photoLocalIdentifiers: [String]
    let layout: FolderLayout

    private struct Slot {
        let rotation: Double
        let x: CGFloat
        let y: CGFloat
        let z: Double
    }

    var body: some View {
        let count = min(3, max(kinds.count, photoLocalIdentifiers.count))
        let slots = slots(for: count)
        let w = layout.shotWidth
        let h = layout.shotHeight

        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let slot = slots[index]
                let kind = kinds.indices.contains(index) ? kinds[index] : MockShotKind.photo
                let photoID = photoLocalIdentifiers.indices.contains(index)
                    ? photoLocalIdentifiers[index]
                    : nil

                ScreenshotPeekContainer(width: w, height: h) {
                    PhotosThumbnailImage(
                        localIdentifier: photoID,
                        targetSize: CGSize(width: max(1, w * 2.5), height: max(1, h * 2.5)),
                        contentMode: .aspectFill
                    ) {
                        ScreenshotPreview(kind: kind, seed: index, showsDeviceChrome: false)
                    }
                }
                .rotationEffect(.degrees(slot.rotation), anchor: .bottom)
                .offset(x: slot.x, y: slot.y)
                .zIndex(slot.z)
            }
        }
        // Full peek height, bottom-tucked under the front. Tops sit at `mouthTop`
        // (inside the folder) so rounded corners stay visible — never clipped flat.
        .frame(width: layout.peekStageWidth, height: layout.shotHeight, alignment: .bottom)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, layout.mouthTop)
        .accessibilityHidden(true)
    }

    private func slots(for count: Int) -> [Slot] {
        let spread = layout.shotWidth * 0.40
        let all: [Slot] = [
            Slot(rotation: -10, x: -spread, y: 6, z: 1),
            Slot(rotation: -2, x: 0, y: 0, z: 3),
            Slot(rotation: 10, x: spread, y: 6, z: 2)
        ]
        switch count {
        case 0: return []
        case 1: return [all[1]]
        case 2: return [all[0], all[2]]
        default: return all
        }
    }
}

// MARK: - Chrome + layout

private enum FolderChrome {
    /// Soft light gray — readable tab, not dark/blocky.
    static let back = Color(red: 0.93, green: 0.933, blue: 0.94)
    static let front = Color.white
}

/// Reference: front lip ≈ 29% H; peeks visible ≈ 23% H.
/// Aspect is locked for the whole grid (Collections + New Collection) — tall enough for a 2-line title.
struct FolderLayout {
    let width: CGFloat

    /// Width / height. Slightly taller than the old 1.18 so every cell matches the 2-line “max” size.
    static let aspectRatio: CGFloat = 1.08

    var totalHeight: CGFloat { width / Self.aspectRatio }

    var tabRise: CGFloat { totalHeight * 0.10 }
    var tabRadius: CGFloat { width * 0.08 }
    var backRadius: CGFloat { width * 0.12 }

    /// White front tall enough for emoji + 2-line title + count; peeks still clear above the lip.
    /// (Lower = taller front. Reference mouth ≈ 29%.)
    var frontTop: CGFloat { totalHeight * 0.28 }
    var frontHeight: CGFloat { totalHeight - frontTop }
    var frontRadius: CGFloat { width * 0.12 }

    /// Peek tops sit here — under the tab, inside the folder (rounded corners stay visible).
    var mouthTop: CGFloat { max(6, totalHeight * 0.025) }

    var peekStageWidth: CGFloat { width * 0.84 }

    /// Portrait peeks — sized so ~40%+ stays visible in the mouth above the white front.
    var shotWidth: CGFloat { width * 0.32 }
    var shotHeight: CGFloat { shotWidth / 0.58 }

    // MARK: Front content spacing (shared — empty + populated identical)

    /// Single left alignment for emoji / title / count.
    var folderHorizontalInset: CGFloat { max(STSpacing.md - 2, width * 0.05) }
    var folderTopInset: CGFloat { max(10, width * 0.038) }
    var folderBottomInset: CGFloat { max(10, totalHeight * 0.048) }
    /// Breathing room between emoji and metadata — intentional, not empty.
    var emojiMetadataGap: CGFloat { max(STSpacing.md, totalHeight * 0.035) }
    /// Tight gap — title and count read as one metadata group.
    var titleCountGap: CGFloat { 2 }

    var iconSize: CGFloat { max(28, width * 0.115) }
    var iconFontSize: CGFloat { iconSize * 0.66 }
    /// Smaller than the circle so the badge color reads as a clear ring.
    var badgeEmojiFontSize: CGFloat { iconSize * 0.48 }
}

struct PocketLayout {
    let width: CGFloat
    static let aspectRatio: CGFloat = FolderLayout.aspectRatio
    var totalHeight: CGFloat { width / Self.aspectRatio }
}

typealias ContextCollectionCard = ContextCollectionPocketView
typealias ContextCollectionPocket = ContextCollectionPocketView

#Preview("Folder — empty + filled") {
    let empty = ContextCollection(
        id: ContextCollectionID(),
        kind: .userContext,
        title: "Yoyo",
        isPinned: false,
        isArchived: false,
        memberCount: 0,
        memberPreviewSymbols: [],
        badgeEmoji: nil,
        insight: nil
    )
    let filled = ContextCollection(
        id: ContextCollectionID(),
        kind: .userContext,
        title: "Yoyo",
        isPinned: false,
        isArchived: false,
        memberCount: 5,
        memberPreviewSymbols: ["hotel", "map", "boarding"],
        badgeEmoji: "✈️",
        insight: nil
    )

    HStack(spacing: 24) {
        ContextCollectionPocketView(collection: empty)
            .frame(width: 200)
        ContextCollectionPocketView(collection: filled)
            .frame(width: 200)
    }
    .padding(32)
    .background(Color.black)
}
