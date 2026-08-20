import Foundation

// MARK: - DSL Nodes (mirrors schema.ts)
public struct Action: Codable, Sendable, Equatable {
    public var id: String
    public var payload: [String: String]? // keep simple for now; real impl uses AnyCodable
    public init(id: String, payload: [String: String]? = nil) { self.id = id; self.payload = payload }
}

public indirect enum Node: Codable, Sendable, Equatable {
    case vstack(gap: String?, children: [Node])
    case hstack(gap: String?, children: [Node])
    case card(title: String?, children: [Node])
    case text(text: String, variant: String?, color: String?)
    case stat(label: String, value: String, color: String?)
    case progress(value: Double)
    case sparkline(data: [Double])
    case icon(name: String, color: String?)
    case list(items: [ListItem])
    case button(label: String, variant: String?, onClick: Action)
    case form(fields: [FormField], onSubmit: Action)

    public struct ListItem: Codable, Sendable, Equatable {
        public var id: String
        public var title: String
        public var subtitle: String?
        public var right: String?
        public var onClick: Action?
        public init(id: String, title: String, subtitle: String? = nil, right: String? = nil, onClick: Action? = nil) {
            self.id = id; self.title = title; self.subtitle = subtitle; self.right = right; self.onClick = onClick
        }
    }
    public struct FormField: Codable, Sendable, Equatable {
        public var name: String
        public var placeholder: String
        public var type: String
    }

    // Manual Codable via discriminator "type"
    enum CodingKeys: String, CodingKey { case type, gap, children, title, text, variant, color, label, value, data, name, items, onClick, fields, onSubmit, subtitle, right, id, placeholder }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let t = try c.decode(String.self, forKey: .type)
        switch t {
        case "VStack": self = .vstack(gap: try c.decodeIfPresent(String.self, forKey: .gap), children: try c.decode([Node].self, forKey: .children))
        case "HStack": self = .hstack(gap: try c.decodeIfPresent(String.self, forKey: .gap), children: try c.decode([Node].self, forKey: .children))
        case "Card": self = .card(title: try c.decodeIfPresent(String.self, forKey: .title), children: try c.decode([Node].self, forKey: .children))
        case "Text": self = .text(text: try c.decode(String.self, forKey: .text), variant: try c.decodeIfPresent(String.self, forKey: .variant), color: try c.decodeIfPresent(String.self, forKey: .color))
        case "Stat": self = .stat(label: try c.decode(String.self, forKey: .label), value: try c.decode(String.self, forKey: .value), color: try c.decodeIfPresent(String.self, forKey: .color))
        case "Progress": self = .progress(value: try c.decode(Double.self, forKey: .value))
        case "Sparkline": self = .sparkline(data: try c.decode([Double].self, forKey: .data))
        case "Icon": self = .icon(name: try c.decode(String.self, forKey: .name), color: try c.decodeIfPresent(String.self, forKey: .color))
        case "List": self = .list(items: try c.decode([ListItem].self, forKey: .items))
        case "Button": self = .button(label: try c.decode(String.self, forKey: .label), variant: try c.decodeIfPresent(String.self, forKey: .variant), onClick: try c.decode(Action.self, forKey: .onClick))
        case "Form": self = .form(fields: try c.decode([FormField].self, forKey: .fields), onSubmit: try c.decode(Action.self, forKey: .onSubmit))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown node type \(t)")
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .vstack(let gap, let children): try c.encode("VStack", forKey: .type); try c.encodeIfPresent(gap, forKey: .gap); try c.encode(children, forKey: .children)
        case .hstack(let gap, let children): try c.encode("HStack", forKey: .type); try c.encodeIfPresent(gap, forKey: .gap); try c.encode(children, forKey: .children)
        case .card(let title, let children): try c.encode("Card", forKey: .type); try c.encodeIfPresent(title, forKey: .title); try c.encode(children, forKey: .children)
        case .text(let text, let variant, let color): try c.encode("Text", forKey: .type); try c.encode(text, forKey: .text); try c.encodeIfPresent(variant, forKey: .variant); try c.encodeIfPresent(color, forKey: .color)
        case .stat(let label, let value, let color): try c.encode("Stat", forKey: .type); try c.encode(label, forKey: .label); try c.encode(value, forKey: .value); try c.encodeIfPresent(color, forKey: .color)
        case .progress(let v): try c.encode("Progress", forKey: .type); try c.encode(v, forKey: .value)
        case .sparkline(let d): try c.encode("Sparkline", forKey: .type); try c.encode(d, forKey: .data)
        case .icon(let n, let col): try c.encode("Icon", forKey: .type); try c.encode(n, forKey: .name); try c.encodeIfPresent(col, forKey: .color)
        case .list(let items): try c.encode("List", forKey: .type); try c.encode(items, forKey: .items)
        case .button(let label, let variant, let onClick): try c.encode("Button", forKey: .type); try c.encode(label, forKey: .label); try c.encodeIfPresent(variant, forKey: .variant); try c.encode(onClick, forKey: .onClick)
        case .form(let fields, let onSubmit): try c.encode("Form", forKey: .type); try c.encode(fields, forKey: .fields); try c.encode(onSubmit, forKey: .onSubmit)
        }
    }
}

public struct RenderPayload: Codable, Sendable {
    public var tile: Node?
    public var detail: Node?
    public init(tile: Node? = nil, detail: Node? = nil) { self.tile = tile; self.detail = detail }
}
