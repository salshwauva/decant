import Foundation

enum ValveValue {
    case text(String)
    case object([String: ValveValue])

    var text: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    var object: [String: ValveValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}

enum ValveKeyValues {
    // explicit stacks keep nested metadata off the call stack.
    static func parse(_ source: String) -> [String: ValveValue]? {
        let bytes = Array(source.utf8)
        var index = 0
        var objects: [[String: ValveValue]] = [[:]]
        var keys: [String] = []
        var pending: String?
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 32 || byte == 9 || byte == 10 || byte == 13 { index += 1; continue }
            if byte == 47 && index + 1 < bytes.count && bytes[index + 1] == 47 {
                while index < bytes.count && bytes[index] != 10 { index += 1 }
                continue
            }
            if byte == 123 {
                guard let key = pending else { return nil }
                keys.append(key)
                objects.append([:])
                pending = nil
                index += 1
                continue
            }
            if byte == 125 {
                guard pending == nil, objects.count > 1 else { return nil }
                let value = objects.removeLast()
                objects[objects.count - 1][keys.removeLast()] = .object(value)
                index += 1
                continue
            }
            var token: [UInt8] = []
            if byte == 34 {
                index += 1
                var closed = false
                while index < bytes.count {
                    let ch = bytes[index]
                    index += 1
                    if ch == 34 { closed = true; break }
                    if ch == 92 && index < bytes.count {
                        let escaped = bytes[index]
                        if escaped == 34 || escaped == 92 {
                            token.append(escaped)
                            index += 1
                            continue
                        }
                    }
                    token.append(ch)
                }
                guard closed else { return nil }
            } else {
                while index < bytes.count && ![9, 10, 13, 32, 123, 125].contains(bytes[index]) {
                    token.append(bytes[index])
                    index += 1
                }
            }
            let value = String(decoding: token, as: UTF8.self)
            if let key = pending {
                objects[objects.count - 1][key] = .text(value)
                pending = nil
            } else {
                pending = value
            }
        }
        guard objects.count == 1, pending == nil else { return nil }
        return objects[0]
    }
}
