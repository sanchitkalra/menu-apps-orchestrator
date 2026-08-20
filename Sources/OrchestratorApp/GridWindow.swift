#if canImport(SwiftUI)
import SwiftUI
import OrchestratorCore

// Xcode-only: hosts the tile grid + detail view.
// CLI target (swift build) does not compile this file (canImport check).

// Grid geometry: one unit cell, and tiles span whole units per manifest tile.size.
private enum G {
    static let unitW: CGFloat = 152
    static let unitH: CGFloat = 92
    static let gap: CGFloat = 12
    static let columns = 2                      // 2 units wide: apps flow vertically

    static func span(_ size: String) -> (cols: Int, rows: Int) {
        switch size {
        case "2x1": return (2, 1)
        case "2x2": return (2, 2)
        case "1x2": return (1, 2)
        default:    return (1, 1)
        }
    }
    static func width(_ cols: Int) -> CGFloat { unitW * CGFloat(cols) + gap * CGFloat(cols - 1) }
    static func height(_ rows: Int) -> CGFloat { unitH * CGFloat(rows) + gap * CGFloat(rows - 1) }
}

struct GridWindowView: View {
    @ObservedObject var model: HostModel
    // ponytail: inline swap, not a sheet — sheets inside a MenuBarExtra window blank the popover
    @State private var detailAppId: String?

    var body: some View {
        if let appId = detailAppId {
            detailView(appId)
        } else {
            grid
        }
    }

    // First-fit packing on a unit grid: each tile takes the first free cols x rows block,
    // so a 1-unit-tall tile can sit beside/under a 2x2 instead of leaving its row half empty.
    private struct Slot { let appId: String; let col: Int; let row: Int; let cols: Int; let rows: Int }

    private var layout: (slots: [Slot], rows: Int) {
        var occupied = Set<[Int]>()          // [row, col]
        var slots: [Slot] = []
        var maxRow = 0
        for appId in model.renders.keys.sorted() where model.renders[appId]?.tile != nil {
            let span = G.span(model.sizes[appId] ?? "1x1")
            var placed = false
            var row = 0
            while !placed {
                for col in 0...(G.columns - span.cols) {
                    let cells = (0..<span.rows).flatMap { r in (0..<span.cols).map { c in [row + r, col + c] } }
                    if cells.allSatisfy({ !occupied.contains($0) }) {
                        cells.forEach { occupied.insert($0) }
                        slots.append(Slot(appId: appId, col: col, row: row, cols: span.cols, rows: span.rows))
                        maxRow = max(maxRow, row + span.rows)
                        placed = true
                        break
                    }
                }
                row += 1
            }
        }
        return (slots, maxRow)
    }

    private var grid: some View {
        let l = layout
        return ZStack(alignment: .topLeading) {
            ForEach(l.slots, id: \.appId) { slot in
                tile(slot.appId)
                    .offset(x: (G.unitW + G.gap) * CGFloat(slot.col),
                            y: (G.unitH + G.gap) * CGFloat(slot.row))
            }
        }
        .frame(width: G.width(G.columns),
               height: l.rows > 0 ? G.height(l.rows) : 0,
               alignment: .topLeading)
        .padding(16)
    }

    private func tile(_ appId: String) -> some View {
        let span = G.span(model.sizes[appId] ?? "1x1")
        return VStack(alignment: .leading, spacing: 0) {
            if let node = model.renders[appId]?.tile {
                TileView(node: node) { model.send(appId: appId, actionId: $0, payload: $1) }
            }
        }
        .padding(12)
        .frame(width: G.width(span.cols), height: G.height(span.rows), alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)).shadow(radius: 2))
        .contentShape(Rectangle())
        .onTapGesture { detailAppId = appId }
    }

    private func detailView(_ appId: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                detailAppId = nil
            } label: {
                Label(appId, systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            ScrollView {
                if let detail = model.renders[appId]?.detail {
                    TileView(node: detail) { model.send(appId: appId, actionId: $0, payload: $1) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No detail view").foregroundColor(.secondary)
                }
            }
        }.padding(16).frame(height: 420)
    }
}
#endif
