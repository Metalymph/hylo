import Utils

/// Val's mangling algorithm.
struct Mangler {

  /// The type of the stream to which data is written.
  typealias Output = String

  /// The identity of a mangled symbol.
  private enum Symbol: Hashable {

    /// A declaration or lexical scope.
    case node(AnyNodeID)

    /// A canonical type.
    case type(AnyType)

  }

  /// The program defining the symbols being defined.
  private let program: TypedProgram

  /// A table mapping mangled symbols to their position in the symbol lookup table.
  private var symbolID: [Symbol: Int] = [:]

  /// The ID of the next symbol inserted in the symbol lookup table.
  private var nextSymbolID = 0

  /// A table mapping known symbols to their reserved mangled identifier.
  private var reserved: [Symbol: ReservedSymbol] = [
    .type(.void): .void,
    .type(.never): .never,
  ]

  /// Creates an instance mangling symbols defined in `programs`.
  init(_ program: TypedProgram) {
    self.program = program

    if program.ast.isCoreModuleLoaded {
      self.reserved[.node(AnyNodeID(program.ast.coreLibrary!))] = .val
      register(coreType: "Bool", as: .bool)
      register(coreType: "Int", as: .int)
      register(coreType: "Float64", as: .float64)
      register(coreType: "String", as: .string)
    }
  }

  /// Associates `coreType` to `r`.
  private mutating func register(coreType: String, as r: ReservedSymbol) {
    let d = AnyNodeID(program.ast.coreType(coreType)!.decl)
    reserved[.node(d)] = r
  }

  /// Writes the mangled representation of `d` to `output`.
  mutating func mangle(_ d: AnyDeclID, to output: inout Output) {
    if writeLookup(.node(AnyNodeID(d)), to: &output) {
      return
    }

    if d.kind != ModuleDecl.self {
      writeQualification(of: d, to: &output)
    }

    if let s = AnyScopeID(d) {
      write(scope: s, to: &output)
      return
    }

    switch d.kind {
    case AssociatedTypeDecl.self:
      write(entity: AssociatedTypeDecl.ID(d)!, to: &output)
    case AssociatedValueDecl.self:
      write(entity: AssociatedValueDecl.ID(d)!, to: &output)
    case ImportDecl.self:
      write(entity: ImportDecl.ID(d)!, to: &output)
    case GenericParameterDecl.self:
      write(entity: GenericParameterDecl.ID(d)!, to: &output)
    case ParameterDecl.self:
      write(entity: ParameterDecl.ID(d)!, to: &output)
    case VarDecl.self:
      write(entity: VarDecl.ID(d)!, to: &output)
    default:
      unexpected(d, in: program.ast)
    }

    symbolID[.node(AnyNodeID(d))] = nextSymbolID
    nextSymbolID += 1
  }

  /// Writes the mangled the qualification of `d`, defined in program, to `output`.
  private mutating func writeQualification(of d: AnyDeclID, to output: inout Output) {
    // Anonymous scopes corresponding to the body of a function aren't mangled.
    var parent = program.nodeToScope[d]!
    if parent.kind == BraceStmt.self {
      let grandParant = program.nodeToScope[parent]!
      switch grandParant.kind {
      case FunctionDecl.self, InitializerDecl.self, MethodImpl.self, SubscriptImpl.self:
        parent = grandParant
      default:
        break
      }
    }

    for p in program.scopes(from: parent).reversed() {
      write(scope: p, to: &output)
    }
  }

  /// Writes the mangled the representation of `symbol` to `output`.
  private mutating func write(scope symbol: AnyScopeID, to output: inout Output) {
    if writeLookup(.node(AnyNodeID(symbol)), to: &output) {
      return
    }

    switch symbol.kind {
    case FunctionDecl.self:
      write(function: FunctionDecl.ID(symbol)!, to: &output)
    case InitializerDecl.self:
      write(initializer: InitializerDecl.ID(symbol)!, to: &output)
    case ModuleDecl.self:
      write(entity: ModuleDecl.ID(symbol)!, to: &output)
    case NamespaceDecl.self:
      write(entity: NamespaceDecl.ID(symbol)!, to: &output)
    case ProductTypeDecl.self:
      write(entity: ProductTypeDecl.ID(symbol)!, to: &output)
    case SubscriptDecl.self:
      write(subscriptDecl: SubscriptDecl.ID(symbol)!, to: &output)
    case SubscriptImpl.self:
      write(subscriptImpl: SubscriptImpl.ID(symbol)!, to: &output)
    case TraitDecl.self:
      write(entity: TraitDecl.ID(symbol)!, to: &output)
    case TranslationUnit.self:
      write(translationUnit: TranslationUnit.ID(symbol)!, to: &output)
    case TypeAliasDecl.self:
      write(entity: TypeAliasDecl.ID(symbol)!, to: &output)
    default:
      unexpected(symbol, in: program.ast)
    }

    symbolID[.node(AnyNodeID(symbol))] = nextSymbolID
    nextSymbolID += 1
  }

  /// Writes the mangled the representation of `d` to `output`.
  private mutating func write<T: SingleEntityDecl>(entity d: T.ID, to output: inout Output) {
    write(operator: T.manglingOperator, to: &output)
    write(string: program.ast[d].baseName, to: &output)
  }

  /// Writes the mangled the representation of `d` to `output`.
  private mutating func write(function d: FunctionDecl.ID, to output: inout Output) {
    // If the function is anonymous, just encode a unique ID.
    guard let n = Name(of: d, in: program.ast) else {
      write(operator: .anonymousFunctionDecl, to: &output)
      write(integer: d.rawValue, to: &output)
      return
    }

    if program.ast[d].isStatic {
      write(operator: .staticFunctionDecl, to: &output)
    } else {
      write(operator: .functionDecl, to: &output)
    }

    write(name: n, to: &output)
    write(integer: program.ast[d].genericParameters.count, to: &output)
    mangle(program.declTypes[d]!, to: &output)
  }

  /// Writes the mangled the representation of `d` to `output`.
  private mutating func write(initializer d: InitializerDecl.ID, to output: inout Output) {
    // There's at most one memberwise initializer per product type declaration.
    if program.ast[d].isMemberwise {
      write(operator: .memberwiseInitializerDecl, to: &output)
      return
    }

    // Other initializers are mangled like static member functions.
    write(operator: .staticFunctionDecl, to: &output)
    write(name: Name(stem: "init"), to: &output)
    write(integer: program.ast[d].genericParameters.count, to: &output)
    mangle(program.declTypes[d]!, to: &output)
  }

  /// Writes the mangled the representation of `d` to `output`.
  private mutating func write(subscriptDecl d: SubscriptDecl.ID, to output: inout Output) {
    if program.ast[d].isProperty {
      write(operator: .propertyDecl, to: &output)
      write(string: program.ast[d].identifier?.value ?? "", to: &output)
    } else {
      write(operator: .subscriptDecl, to: &output)
      write(string: program.ast[d].identifier?.value ?? "", to: &output)
      write(integer: program.ast[d].genericParameters.count, to: &output)
    }

    mangle(program.declTypes[d]!, to: &output)
  }

  /// Writes the mangled the representation of `u` to `output`.
  private mutating func write(subscriptImpl d: SubscriptImpl.ID, to output: inout Output) {
    write(operator: .subscriptImpl, to: &output)
    write(base64Didit: program.ast[d].introducer.value, to: &output)
  }

  /// Writes the mangled the representation of `u` to `output`.
  private mutating func write(translationUnit u: TranslationUnit.ID, to output: inout Output) {
    // Note: assumes all files in a module have a different base name.
    write(operator: .translatonUnit, to: &output)
    write(string: program.ast[u].site.file.baseName, to: &output)
  }

  /// Writes the mangled the representation of `symbol` to `output`.
  private mutating func mangle(_ symbol: any CompileTimeValue, to output: inout Output) {
    if let t = symbol as? AnyType {
      mangle(t, to: &output)
    } else {
      fatalError("not implemented")
    }
  }

  /// Writes the mangled the representation of `symbol` to `output`.
  private mutating func mangle(_ symbol: AnyType, to output: inout Output) {
    if writeLookup(.type(symbol), to: &output) {
      return
    }

    assert(symbol[.isCanonical])
    switch symbol.base {
    case let t as BoundGenericType:
      write(boundGenericType: t, to: &output)

    case let t as LambdaType:
      write(lambda: t, to: &output)

    case let t as ParameterType:
      write(operator: .parameterType, to: &output)
      write(base64Didit: t.access, to: &output)
      mangle(t.bareType, to: &output)

    case let t as ProductType:
      write(operator: .productType, to: &output)
      mangle(AnyDeclID(t.decl), to: &output)
      write(operator: .endOfSequence, to: &output)

    case let t as RemoteType:
      write(operator: .remoteType, to: &output)
      write(base64Didit: t.access, to: &output)
      mangle(t.bareType, to: &output)

    case let t as SubscriptType:
      write(subscriptType: t, to: &output)

    case let t as SumType:
      write(sumType: t, to: &output)

    case let t as TupleType:
      write(tupleType: t, to: &output)

    default:
      unreachable()
    }

    symbolID[.type(symbol)] = nextSymbolID
    nextSymbolID += 1
  }

  /// Writes the mangled the representation of `symbol` to `output`.
  private mutating func write(boundGenericType t: BoundGenericType, to output: inout Output) {
    write(operator: .boundGenericType, to: &output)
    mangle(t.base, to: &output)
    write(integer: t.arguments.count, to: &output)
    for u in t.arguments.values {
      mangle(u, to: &output)
    }
  }

  /// Writes the mangled the representation of `symbol` to `output`.
  private mutating func write(lambda t: LambdaType, to output: inout Output) {
    if t.environment == .void {
      write(operator: .thinLambdaType, to: &output)
    } else {
      write(operator: .lambdaType, to: &output)
      mangle(t.environment, to: &output)
    }

    write(integer: t.inputs.count, to: &output)
    for i in t.inputs {
      write(string: i.label ?? "", to: &output)
      mangle(i.type, to: &output)
    }

    mangle(t.output, to: &output)
  }

  /// Writes the mangled the representation of `symbol` to `output`.
  private mutating func write(subscriptType t: SubscriptType, to output: inout Output) {
    write(operator: .subscriptType, to: &output)
    write(base64Didit: t.capabilities, to: &output)
    mangle(t.environment, to: &output)

    write(integer: t.inputs.count, to: &output)
    for i in t.inputs {
      write(string: i.label ?? "", to: &output)
      mangle(i.type, to: &output)
    }

    mangle(t.output, to: &output)
  }

  /// Writes the mangled the representation of `symbol` to `output`.
  private mutating func write(sumType t: SumType, to output: inout Output) {
    write(operator: .sumType, to: &output)
    write(integer: t.elements.count, to: &output)

    var elements: [String] = []
    for e in t.elements {
      // Copy `self` to share the symbol looking table built so far.
      var m = self
      var s = ""
      m.mangle(e, to: &s)
      let i = elements.partitioningIndex(where: { s < $0 })
      elements.insert(s, at: i)
    }

    elements.joined().write(to: &output)
  }

  /// Writes the mangled the representation of `symbol` to `output`.
  private mutating func write(tupleType t: TupleType, to output: inout Output) {
    write(operator: .tupleType, to: &output)

    write(integer: t.elements.count, to: &output)
    for e in t.elements {
      write(string: e.label ?? "", to: &output)
      mangle(e.type, to: &output)
    }
  }

  /// If `symbol` is reserved or has already been inserted in the symbol lookup table, writes a
  /// lookup reference to it and returns `true`. Otherwise, returns `false`.
  private func writeLookup(_ symbol: Symbol, to output: inout Output) -> Bool {
    if let r = reserved[symbol] {
      write(operator: .reserved, to: &output)
      r.write(to: &output)
      return true
    }

    if let i = symbolID[symbol] {
      write(operator: .lookup, to: &output)
      write(integer: i, to: &output)
      return true
    }

    return false
  }

  /// Writes the mangled representation of `name` to `output`.
  private func write(name: Name, to output: inout Output) {
    // Only encode notation and introducer; labels are encoded in types.
    var tag: UInt8 = 0
    if name.notation != nil { tag = 1 }
    if name.introducer != nil { tag = tag | 2 }

    write(base64Didit: tag, to: &output)
    if let n = name.notation {
      write(base64Didit: n, to: &output)
    }
    if let i = name.introducer {
      write(base64Didit: i, to: &output)
    }
    write(string: name.stem, to: &output)
  }

  /// Writes `string` to `output`, prefixed by its length encoded as a variable-length integer.
  private func write(string: String, to output: inout Output) {
    write(integer: string.count, to: &output)
    string.write(to: &output)
  }

  /// Writes `v` encoded as a variable-length integer to `output`.
  private func write(integer v: Int, to output: inout Output) {
    Base64VarUInt(v).write(to: &output)
  }

  /// Writes the raw value of `v` encoded as a base 64 digit to `output`.
  private func write<T: RawRepresentable>(
    base64Didit v: T, to output: inout Output
  ) where T.RawValue == UInt8 {
    write(base64Didit: v.rawValue, to: &output)
  }

  /// Writes `v` encoded as a base 64 digit to `output`.
  private func write(base64Didit v: UInt8, to output: inout Output) {
    Base64Digit(rawValue: v)!.description.write(to: &output)
  }

  /// Writes `o` to `output`.
  private func write(operator o: ManglingOperator, to output: inout Output) {
    o.write(to: &output)
  }

}
