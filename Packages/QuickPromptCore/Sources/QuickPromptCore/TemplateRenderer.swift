import Foundation

/// Replaces `{{name}}` placeholders with values. Unknown placeholders are left untouched.
public enum TemplateRenderer {
    public static func render(_ template: String, values: [String: String]) -> String {
        var result = ""
        var rest = template[...]
        while let open = rest.range(of: "{{") {
            result += rest[..<open.lowerBound]
            let afterOpen = rest[open.upperBound...]
            guard let close = afterOpen.range(of: "}}") else {
                rest = rest[open.lowerBound...]
                break
            }
            let name = afterOpen[..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            if let value = values[name] {
                result += value
            } else {
                result += rest[open.lowerBound..<close.upperBound]
            }
            rest = afterOpen[close.upperBound...]
        }
        result += rest
        return result
    }

    /// Placeholder names used in `template` that have no value in `values`.
    public static func unknownPlaceholders(in template: String, values: [String: String]) -> [String] {
        var names: [String] = []
        var rest = template[...]
        while let open = rest.range(of: "{{"),
              let close = rest[open.upperBound...].range(of: "}}") {
            let name = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            if values[name] == nil { names.append(name) }
            rest = rest[close.upperBound...]
        }
        return names
    }
}
