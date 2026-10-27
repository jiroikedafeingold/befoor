//
//  NarrowIsland.swift
//  BeforeWidget
//

import SwiftUI
import WidgetKit

/// Picks a Dynamic Island layout by its width: `narrow` where the island is
/// limited in width (the side island on iPhone Duo runs top to bottom), `wide`
/// everywhere else, including iOS 26, which can't tell.
struct NarrowIsland<Wide: View, Narrow: View>: View {
    @ViewBuilder var wide: Wide
    @ViewBuilder var narrow: Narrow

    var body: some View {
        if #available(iOS 27.0, *) {
            NarrowIslandReader(wide: wide, narrow: narrow)
        } else {
            wide
        }
    }
}

@available(iOS 27.0, *)
private struct NarrowIslandReader<Wide: View, Narrow: View>: View {
    let wide: Wide
    let narrow: Narrow
    @Environment(\.isDynamicIslandLimitedInWidth) private var isLimitedInWidth

    var body: some View {
        if isLimitedInWidth { narrow } else { wide }
    }
}
