#if canImport(SwiftUI)
import SwiftUI
import OrchestratorCore

// Maps DSL Node -> SwiftUI. This target only builds with Xcode.
struct TileView: View {
    let node: Node
    let onAction: (String, [String: String]?) -> Void
    @State private var formValues: [String: String] = [:]

    var body: some View {
        render(node)
    }
    @ViewBuilder
    func render(_ node: Node) -> some View {
        switch node {
        case .vstack(let gap, let children):
            VStack(alignment: .leading, spacing: gap == "sm" ? 4 : 8) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, c in TileView(node: c, onAction: onAction) }
            }
        case .hstack(let gap, let children):
            HStack(alignment: .top, spacing: gap == "sm" ? 4 : 8) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, c in TileView(node: c, onAction: onAction) }
            }
        case .card(let title, let children):
            VStack(alignment: .leading, spacing: 8) {
                if let title { Text(title).font(.headline) }
                ForEach(Array(children.enumerated()), id: \.offset) { _, c in TileView(node: c, onAction: onAction) }
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
                    .contentShape(Rectangle())
                    .onTapGesture { if let a = item.onClick { onAction(a.id, a.payload) } }
                }
            }
        case .progress(let v):
            ProgressView(value: v)
        case .sparkline(let data):
            SparklineView(data: data)
        case .icon(let name, _):
            Image(systemName: name).foregroundColor(.secondary)
        case .button(let label, _, let onClick):
            Button(label) { onAction(onClick.id, onClick.payload) }
                .buttonStyle(.bordered)
        case .form(let fields, let onSubmit):
            ForEach(fields, id: \.name) { f in
                TextField(f.placeholder, text: Binding(
                    get: { formValues[f.name] ?? "" },
                    set: { formValues[f.name] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    onAction(onSubmit.id, formValues.merging(onSubmit.payload ?? [:]) { a, _ in a })
                    formValues = [:]
                }
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
