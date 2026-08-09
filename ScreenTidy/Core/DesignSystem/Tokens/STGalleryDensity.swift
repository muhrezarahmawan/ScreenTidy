import SwiftUI

/// Screenshot gallery column density (Collection Detail + Search) — persisted via `@AppStorage`.
enum STGalleryDensity: Int, CaseIterable, Identifiable, Sendable {
    case two = 2
    case three = 3
    case four = 4
    case five = 5

    static let `default` = Self.three
    static let storageKey = "galleryDensity"

    var id: Int { rawValue }

    var columnCount: Int { rawValue }

    var title: String {
        "\(columnCount)x\(columnCount)"
    }

    var menuTitle: String {
        title
    }

    var systemImage: String {
        switch self {
        case .two: return "square.grid.2x2"
        case .three: return "square.grid.3x3"
        case .four: return "square.grid.3x3"
        case .five: return "square.grid.3x3"
        }
    }

    /// Toolbar label — prefer distinct glyphs where SF Symbols allow.
    var toolbarSystemImage: String {
        switch self {
        case .two: return "square.grid.2x2"
        case .three, .four, .five: return "square.grid.3x3"
        }
    }

    /// Inter-cell gutter — slightly tighter for denser layouts.
    var gutter: CGFloat {
        switch self {
        case .two, .three:
            return STSpacing.galleryGridGutter
        case .four, .five:
            return max(3, STSpacing.galleryGridGutter - 2)
        }
    }

    var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: gutter),
            count: columnCount
        )
    }

    static func resolved(rawValue: Int) -> STGalleryDensity {
        Self(rawValue: rawValue) ?? .default
    }
}
