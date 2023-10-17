import FoundationEssentials

protocol KeyPathMappingProvider {
    static var identifierByKeyPath: [AnyKeyPath: String] { get }
    static func build_Equal(from container: inout UnkeyedDecodingContainer, _ input: PredicateExpressions.Variable<Self>) throws -> any PredicateExpression<Bool>
}

struct Monster: KeyPathMappingProvider {
    let level: Int
    let name: String
    let hp: Int
    let mana: Int

    static var identifierByKeyPath: [AnyKeyPath: String] = [
        \Monster.level: "level",
        \Monster.name: "name",
        \Monster.hp: "hp",
        \Monster.mana: "mana"
    ]

    static func build_Equal<T: Decodable & Equatable>(
        from container: inout UnkeyedDecodingContainer,
        _ input: PredicateExpressions.Variable<Self>,
        _ keyPath: KeyPath<Self, T>) throws -> any PredicateExpression<Bool> {
        let lhs = PredicateExpressions.build_KeyPath(root: PredicateExpressions.build_Arg(input), keyPath: keyPath)
        let value = try container.decode(T.self)
        let rhs = PredicateExpressions.build_Arg(value)
        return PredicateExpressions.Equal(lhs: lhs, rhs: rhs)
    }

    static func build_Equal(from container: inout UnkeyedDecodingContainer, _ input: PredicateExpressions.Variable<Self>) throws -> any PredicateExpression<Bool> {
        let field = try container.decode(String.self)
        if field == "level" {
            return try build_Equal(from: &container, input, \Monster.level)
        } else if field == "name" {
            return try build_Equal(from: &container, input, \Monster.name)
        } else if field == "hp" {
            return try build_Equal(from: &container, input, \Monster.hp)
        } else if field == "mana" {
            return try build_Equal(from: &container, input, \Monster.mana)
        }
        throw CodingError.invalidField(field)
    }
}

enum CodingError: Error {
    case error
    case invalidOperation(String)
    case invalidField(String)
}

protocol CodableEx {
    func encode(to container: inout UnkeyedEncodingContainer, _ keyPathIdentifiers: [AnyKeyPath: String]) throws
}

extension PredicateExpressions.Equal: CodableEx where LHS: CodableEx, RHS: CodableEx {
    func encode(to container: inout UnkeyedEncodingContainer, _ keyPathIdentifiers: [AnyKeyPath: String]) throws {
        // print("PredicateExpressions.Equal.encode")
        try container.encode("==")
        try lhs.encode(to: &container, keyPathIdentifiers)
        try rhs.encode(to: &container, keyPathIdentifiers)
    }
}

extension PredicateExpressions.KeyPath: CodableEx {
    func encode(to container: inout UnkeyedEncodingContainer, _ keyPathIdentifiers: [AnyKeyPath: String]) throws {
        // print("PredicateExpressions.KeyPath.encode: keyPath=\(keyPath) \(type(of: keyPath))")
        if let identifier = keyPathIdentifiers[keyPath] {
            try container.encode(identifier)
        } else {
            throw CodingError.error
        }
    }
}

extension PredicateExpressions.Value: CodableEx where Output: Encodable {
    func encode(to container: inout UnkeyedEncodingContainer, _ keyPathIdentifiers: [AnyKeyPath: String]) throws {
        // print("PredicateExpressions.Value.encode")
        try container.encode(value)
    }
}

extension PredicateExpressions.Conjunction: CodableEx where LHS: CodableEx, RHS: CodableEx {
    func encode(to container: inout UnkeyedEncodingContainer, _ keyPathIdentifiers: [AnyKeyPath: String]) throws {
        // print("PredicateExpressions.Conjunction.encode")
        try container.encode("&&")
        try lhs.encode(to: &container, keyPathIdentifiers)
        try rhs.encode(to: &container, keyPathIdentifiers)
    }
}

extension PredicateExpressions.Disjunction: CodableEx where LHS: CodableEx, RHS: CodableEx {
    func encode(to container: inout UnkeyedEncodingContainer, _ keyPathIdentifiers: [AnyKeyPath: String]) throws {
        // print("PredicateExpressions.Disjunction.encode")
        try container.encode("||")
        try lhs.encode(to: &container, keyPathIdentifiers)
        try rhs.encode(to: &container, keyPathIdentifiers)
    }
}

extension Predicate: Encodable {
    public func encode(to encoder: Encoder) throws {
        // print("\(type(of: expression))")
        if let codableExpression = expression as? CodableEx {
            if let keyPathMappingProvider = (repeat each Input).self as? any KeyPathMappingProvider.Type {
                var container = encoder.unkeyedContainer()
                try codableExpression.encode(to: &container, keyPathMappingProvider.identifierByKeyPath)
            }
        } else {
            fatalError("\(type(of: expression))")
        }
    }
}

struct PredicateDecodingWrapper<T>: Decodable where T: KeyPathMappingProvider {
    let predicate: Predicate<T>

    static func builder(_ container: inout UnkeyedDecodingContainer, _ input: PredicateExpressions.Variable<T>) throws -> any PredicateExpression<Bool> {
        let op = try container.decode(String.self)
        if op == "==" {
            return try T.build_Equal(from: &container, input)
        } else if op == "&&" {
            let lhs = try builder(&container, input)
            let rhs = try builder(&container, input)

            func build<LHS: PredicateExpression<Bool>, RHS: PredicateExpression<Bool>>(_ lhs: LHS, _ rhs: RHS) -> any PredicateExpression<Bool> {
                PredicateExpressions.Conjunction(lhs: lhs, rhs: rhs)
            }

            return build(lhs, rhs)
        } else if op == "||" {
            let lhs = try builder(&container, input)
            let rhs = try builder(&container, input)

            func build<LHS: PredicateExpression<Bool>, RHS: PredicateExpression<Bool>>(_ lhs: LHS, _ rhs: RHS) -> any PredicateExpression<Bool> {
                PredicateExpressions.Disjunction(lhs: lhs, rhs: rhs)
            }

            return build(lhs, rhs)
        }
        throw CodingError.invalidOperation(op)
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decodeError: Error?
        predicate = FoundationEssentials.Predicate<T> { input in
            do {
                let expression = try Self.builder(&container, input)
                if let experssion = expression as? any StandardPredicateExpression<Bool> {
                    return experssion
                }
            } catch {
                decodeError = error
            }
            return PredicateExpressions.build_Arg(true)
        }
        if let decodeError {
            throw decodeError
        }
    }
}

@main
struct Main {
    public static func main() throws {

        let predicate = #Predicate<Monster>() { monster in
            (monster.level == 80) && (monster.name == "Orc") && (monster.hp == 100)
        }
        print("\(type(of: predicate.expression))")

        let encoder = JSONEncoder()
        let data = try encoder.encode(predicate)
        print("data=\(data)")
        print("\(String(decoding: data, as: UTF8.self))")

        let decoder = JSONDecoder()
        let pdw = try decoder.decode(PredicateDecodingWrapper<Monster>.self, from: data)
        print("\(type(of: pdw.predicate.expression))")
    }
}
