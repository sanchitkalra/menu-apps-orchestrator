#if canImport(SwiftUI)
import SwiftUI
import OrchestratorCore

// Maps DSL Node -> SwiftUI. This target only builds with Xcode.
struct TileView: View {
    let node: Node
    var body: some View {
        render(node)
    }
    @ViewBuilder
    func render(_ node: Node) -> some View {
        switch node {
        case .vstack(let gap, let children):
            VStack(alignment: .leading, spacing: gap == "sm" ? 4 : 8) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, c in render(c) }
            }
        case .hstack(let gap, let children):
            HStack(alignment: .top, spacing: gap == "sm" ? 4 : 8) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, c in render(c) }
            }
        case .card(let title, let children):
            VStack(alignment: .leading, spacing: 8) {
                if let title { Text(title).font(.headline) }
                ForEach(Array(children.enumerated()), id: \.offset) { _, c in render(c) }
            }.padding().background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
        case .text(let text, let variant, let color):
            Text(text).font(variant == "title" ? .headline : variant == "caption" ? .caption : .body)
                .foregroundColor(color == "muted" ? .secondary : color == "red" ? .red : color == "green" ? .green : .primary)
        case .stat(let label, let value, _):
            VStack(alignment: .leading) {
                Text(value).font(.title2).bold()
                Text(label).font(.caption).foregroundColor(.secondary)
            }
        case .list(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items, id: \.id) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.title).font(.body)
                            if let sub = item.subtitle { Text(sub).font(.caption).foregroundColor(.secondary) }
                        }
                        Spacer()
                        if let r = item.right { Text(r).font(.caption).foregroundColor(.secondary) }
                    }
                }
            }
        case .progress(let v):
            ProgressView(value: v)
        case .sparkline(let data):
            SparklineView(data: data)
        case .icon(let name, _):
            Image(systemName: name).foregroundColor(.secondary)
        case .button(let label, _, _):
            Button(label) {}
                .buttonStyle(.bordered)
        case .form(let fields, _):
            ForEach(fields, id: \.name) { f in
                TextField(f.placeholder, text: .constant(""))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

struct SparklineView: View {
    let data: [Double]
    var body: some View {
        GeometryReader { geo in
            Path { p in
                guard let max = data.max(), max > 0, data.count > 1 else { return }
                let stepX = geo.size.width / CGFloat(data.count - 1)
                let scaleY = geo.size.height / CGFloat(max)
                p.move(to: CGPoint(x: 0, y: geo.size.height - CGFloat(data[0]) * scaleY))
                for i in 1..<data.count {
                    p.addLine(to: CGPoint(x: CGFloat(i) * stepX, y: geo.size.height - CGFloat(data[i]) * scaleY))
                }
            }.stroke(Color.accentColor, lineWidth: 1.5)
        }.frame(height: 24)
    }
}
#endif
