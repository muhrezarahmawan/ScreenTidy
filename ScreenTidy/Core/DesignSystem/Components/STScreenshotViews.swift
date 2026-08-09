import SwiftUI

/// Gallery tile — compact square thumbnail.
struct STScreenshotGridItem: View {
    let memory: ScreenshotMemory
    var isSelected: Bool = false
    var showsSelectionChrome: Bool = false

    var body: some View {
        Color.clear
            .aspectRatio(STAspect.galleryTile, contentMode: .fit)
            .overlay {
                PhotosThumbnailImage(
                    localIdentifier: memory.photosLocalIdentifier,
                    targetSize: CGSize(width: 360, height: 360),
                    contentMode: .aspectFill
                ) {
                    ScreenshotPreview(
                        kind: MockShotKindResolver.kind(for: memory),
                        seed: memory.id.rawValue.hashValue,
                        showsDeviceChrome: false
                    )
                    .scaledToFill()
                }
            }
            .overlay(alignment: .topTrailing) {
                if showsSelectionChrome {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            isSelected ? Color.white : Color.white.opacity(0.95),
                            isSelected ? STColor.primary : Color.black.opacity(0.35)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .padding(6)
                }
            }
            .overlay {
                if showsSelectionChrome && isSelected {
                    RoundedRectangle(cornerRadius: STRadius.galleryTile, style: .continuous)
                        .strokeBorder(STColor.primary, lineWidth: 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: STRadius.galleryTile, style: .continuous))
            .accessibilityLabel("Screenshot")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Maps domain preview symbols / facet hints → mock shot kinds until Photos thumbs.
/// Facets remain internal classification signals — not shown in Context gallery / viewer UI.
enum MockShotKindResolver {
    static func kind(for memory: ScreenshotMemory) -> MockShotKind {
        if let fromFacet = memory.facetKeys.compactMap(fromFacetKey).first {
            return fromFacet
        }
        return fromSymbol(memory.previewSymbol)
    }

    private static func fromFacetKey(_ key: String) -> MockShotKind? {
        switch key {
        case "hotel": return .hotel
        case "flight", "boarding_pass": return .boarding
        case "receipt": return .receipt
        case "shopping": return .shopping
        case "document": return .document
        default: return nil
        }
    }

    private static func fromSymbol(_ symbol: String) -> MockShotKind {
        switch symbol {
        case "airplane", "airplane.departure": return .boarding
        case "building.2": return .hotel
        case "map": return .map
        case "shippingbox": return .delivery
        case "sofa": return .furniture
        case "globe", "doc.text": return .document
        case "fork.knife": return .restaurant
        default: return .photo
        }
    }
}

#Preview("Gallery tiles") {
    let columns = [
        GridItem(.flexible(), spacing: STSpacing.galleryGridGutter),
        GridItem(.flexible(), spacing: STSpacing.galleryGridGutter),
        GridItem(.flexible(), spacing: STSpacing.galleryGridGutter)
    ]
    ScrollView {
        LazyVGrid(columns: columns, spacing: STSpacing.galleryGridGutter) {
            ForEach(MockData.coreScreenshots.prefix(6)) { shot in
                STScreenshotGridItem(memory: shot)
            }
        }
        .padding(STSpacing.page)
    }
    .background(STColor.background)
}
