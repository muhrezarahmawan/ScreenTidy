import SwiftUI

/// Home grid “add” tile — same folder envelope as Collections, visually secondary.
/// No peeks, emoji, or counts.
struct STNewCollectionTile: View {
    var body: some View {
        // Same locked envelope as Collection folders — equal LazyVGrid cell size.
        Color.clear
            .aspectRatio(FolderLayout.aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { geo in
                    let layout = FolderLayout(width: geo.size.width)
                    tile(layout: layout)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
            }
            .contentShape(Rectangle())
            .accessibilityLabel("New Collection")
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func tile(layout: FolderLayout) -> some View {
        ZStack(alignment: .top) {
            FolderBackShape(layout: layout)
                .fill(NewCollectionChrome.back)
                .frame(width: layout.width, height: layout.totalHeight)

            RoundedRectangle(cornerRadius: layout.frontRadius, style: .continuous)
                .fill(NewCollectionChrome.front)
                .overlay {
                    RoundedRectangle(cornerRadius: layout.frontRadius, style: .continuous)
                        .strokeBorder(
                            NewCollectionChrome.stroke,
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                }
                .overlay {
                    VStack(spacing: STSpacing.sm) {
                        Image(systemName: "plus")
                            .font(.system(size: layout.iconFontSize * 1.15, weight: .medium))
                            .foregroundStyle(STColor.secondaryLabel)

                        Text("New Collection")
                            .font(STTypography.pocketMeta)
                            .foregroundStyle(STColor.secondaryLabel)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: layout.width, height: layout.frontHeight)
                .padding(.top, layout.frontTop)
        }
        // Match Collection soft depth so grid cells read the same size.
        .background {
            FolderBackShape(layout: layout)
                .fill(Color.black.opacity(0.001))
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 5)
                .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
        }
    }
}

private enum NewCollectionChrome {
    static let back = Color(red: 0.93, green: 0.933, blue: 0.94)
    static let front = Color.white.opacity(0.78)
    static let stroke = STColor.hairline.opacity(1.4)
}

#Preview("New Collection vs Folder") {
    LazyVGrid(
        columns: [
            GridItem(.flexible(), spacing: STSpacing.collectionGridGutter),
            GridItem(.flexible(), spacing: STSpacing.collectionGridGutter)
        ],
        spacing: STSpacing.collectionGridRow
    ) {
        ContextCollectionPocketView(
            collection: ContextCollection(
                id: ContextCollectionID(),
                kind: .userContext,
                title: "Testing Ajah Boskuh",
                isPinned: false,
                isArchived: false,
                memberCount: 5,
                memberPreviewSymbols: ["hotel", "map", "boarding"],
                badgeEmoji: "✈️",
                insight: nil
            )
        )
        STNewCollectionTile()
    }
    .padding(STSpacing.page)
    .background(STColor.background)
}
