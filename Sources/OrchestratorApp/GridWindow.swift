#if canImport(SwiftUI)
import SwiftUI
import OrchestratorCore

// Xcode-only: NSWindow hosting the tile grid + Detail sheet.
// CLI target (swift build) does not compile this file (canImport check).

struct GridWindowView: View {
    @State var renders: [String: RenderPayload] = [:]
    let columns = [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(renders.keys.sorted()), id: \.self) { appId in
                    if let payload = renders[appId], let tile = payload.tile {
                        TileView(node: tile)
                            .frame(minHeight: 90)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)).shadow(radius: 2))
                            .onTapGesture {
                                // Host sends detail.opened -> App can lazy-load heavy data
                                // Presentation of DetailWindow sheet
                            }
                    }
                }
            }.padding(16)
        }.frame(minWidth: 600, minHeight: 400)
    }
}
#endif
