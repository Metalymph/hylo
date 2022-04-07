/// The declaration of a conformance.
public struct ConformanceDecl: Decl, ScopeOutliner, SourceRepresentable {

  var scopeID: ScopeID

  public var range: SourceRange?

  /// The expression of the conforming type.
  public var subject: TypeExpr

  /// The names of traits to which conformance is declared.
  public var conformances: [NameTypeExpr]

  /// The condition of the conformance, if any.
  public var whereClause: WhereClause?

  /// The member declarations in the lexical scope of the conformance.
  public var members: [AnyDeclIndex]

  public func accept<V: DeclVisitor>(_ visitor: inout V) -> V.Result {
    visitor.visit(conformance: self)
  }

}