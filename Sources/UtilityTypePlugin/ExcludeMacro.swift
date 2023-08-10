import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxBuilder

public struct ExcludeMacro: MemberMacro {
    public static func expansion<Declaration, Context>(
        of node: AttributeSyntax,
        providingMembersOf declaration: Declaration,
        in context: Context
    ) throws -> [DeclSyntax] where Declaration : DeclGroupSyntax, Context : MacroExpansionContext {
        guard
            case .argumentList(let arguments) = node.arguments,
            arguments.count >= 2,
            let string = arguments.first?.expression.as(StringLiteralExprSyntax.self),
            string.segments.count == 1,
            let name = string.segments.first 
        else {
            throw CustomError.message(#"@Exclude requires the raw type and property names, in the form @Exclude("ExcludedType", "one", "two")"#)
        }

        let _cases = arguments.dropFirst()
        guard _cases
            .map(\.expression)
            .allSatisfy({ $0.is(StringLiteralExprSyntax.self) }) else {
            throw CustomError.message("@Exclude requires the exclude case names to string literal. got: \(_cases)")
        }
        let cases = _cases
            .map(\.expression)
            .compactMap { $0.as(StringLiteralExprSyntax.self) }
            .flatMap { $0.segments.children(viewMode: .all) }
            .compactMap { $0.as(StringSegmentSyntax.self) }
            .flatMap { $0.tokens(viewMode: .all) }
            .map(\.text)

        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            throw CustomError.message(#"@Exclude should attach to Enum)"#)
        }

        let typeName = enumDecl.name.with(\.trailingTrivia, [])
        let access = enumDecl.modifiers?.first(where: \.isNeededAccessLevelModifier)
        let excludedCases = enumDecl.cases.filter { enumCase in
            !cases.contains { c in enumCase.name.text == c }
        }

        let syntax = try EnumDeclSyntax(
            "\(access)enum \(name)",
            membersBuilder: {
                // case .one(Int)
                MemberBlockItemListSyntax(
                    excludedCases.map { excludedCase in
                        MemberBlockItemSyntax(
                            decl: EnumCaseDeclSyntax(
                                elements: EnumCaseElementListSyntax(
                                    [excludedCase]
                                )
                            )
                        )
                    }
                )
                try InitializerDeclSyntax("\(access)init?(_ \(raw: "enumType"): \(typeName))") {
                    try CodeBlockItemListSyntax {
                        try SwitchExprSyntax("switch \(raw: "enumType")") {
                            SwitchCaseListSyntax(try excludedCases.map {
                                excludedCase in
                                let identifier = excludedCase.name
                                let parameters = excludedCase.parameterClause?.parameters

                                return .switchCase(
                                    SwitchCaseSyntax(
                                        label: .case(
                                            SwitchCaseLabelSyntax(
                                                caseItems: SwitchCaseItemListSyntax(itemsBuilder: {
                                                    if let parameters {
                                                        // case .one(let param1):
                                                        SwitchCaseItemSyntax(
                                                            pattern: ExpressionPatternSyntax(
                                                                expression: FunctionCallExprSyntax(
                                                                    calledExpression: MemberAccessExprSyntax(
                                                                        name: identifier
                                                                    ),
                                                                    leftParen: "(",
                                                                    arguments: LabeledExprListSyntax(
                                                                        parameters.enumerated().map { (index, _) in
                                                                            LabeledExprSyntax(
                                                                                expression: PatternExprSyntax(
                                                                                    pattern: ValueBindingPatternSyntax(
                                                                                        bindingSpecifier: TokenSyntax(
                                                                                            stringLiteral: "let"
                                                                                        ),
                                                                                        pattern: IdentifierPatternSyntax(
                                                                                            identifier: TokenSyntax(
                                                                                                stringLiteral: "param\(index)"
                                                                                            )
                                                                                        )
                                                                                    )
                                                                                ),
                                                                                trailingComma: index + 1 == parameters.count ? nil : .commaToken()
                                                                            )
                                                                        }
                                                                    ),
                                                                    rightParen: ")"
                                                                )
                                                            )
                                                        )
                                                    } else {
                                                        // case .one:
                                                        SwitchCaseItemSyntax(
                                                            pattern: ExpressionPatternSyntax(
                                                                expression: MemberAccessExprSyntax(
                                                                    name: identifier
                                                                )
                                                            )
                                                        )
                                                    }
                                                })
                                            )
                                        ),
                                        statements: try CodeBlockItemListSyntax(itemsBuilder: {
                                            if let parameters {
                                                // self = .one(param1)
                                                try CodeBlockItemSyntax(
                                                    item: .expr(
                                                        SequenceExprSyntax(
                                                            elements: ExprListSyntax(
                                                                [
                                                                    DeclReferenceExprSyntax(baseName: .init(stringLiteral: "self")),
                                                                    AssignmentExprSyntax(equal: .equalToken()),
                                                                    FunctionCallExprSyntax(
                                                                        calledExpression: MemberAccessExprSyntax(
                                                                            leadingTrivia: [],
                                                                            name: identifier,
                                                                            trailingTrivia: []
                                                                        ),
                                                                        leftParen: "(",
                                                                        arguments: LabeledExprListSyntax(
                                                                            parameters.enumerated().map { (index, parameter: EnumCaseParameterListSyntax.Element) in
                                                                                LabeledExprSyntax(
                                                                                    label: parameter.firstName,
                                                                                    colon: parameter.firstName != nil ? .colonToken() : nil,
                                                                                    expression: DeclReferenceExprSyntax(baseName: TokenSyntax(stringLiteral: "param\(index)")),
                                                                                    trailingComma: index + 1 == parameters.count ? nil : .commaToken()
                                                                                )
                                                                            }
                                                                        ),
                                                                        rightParen: ")"
                                                                    )
                                                                ]
                                                            )
                                                        ).tryCast(ExprSyntax.self)
                                                    )
                                                )
                                            } else {
                                                // self = .one
                                                CodeBlockItemSyntax(
                                                    item: .expr(
                                                        try SequenceExprSyntax(
                                                            elements: ExprListSyntax(
                                                                [
                                                                    DeclReferenceExprSyntax(baseName: .init(stringLiteral: "self")),
                                                                    AssignmentExprSyntax(),
                                                                    MemberAccessExprSyntax(
                                                                        name: identifier
                                                                    )
                                                                ]
                                                            )
                                                        ).tryCast(ExprSyntax.self)
                                                    )
                                                )
                                            }
                                        })
                                    )
                                )
                            } + [
                                .switchCase(
                                    try SwitchCaseSyntax(
                                        label: .default(.init()),
                                        statements: CodeBlockItemListSyntax([
                                            CodeBlockItemSyntax(
                                                item: .stmt(ReturnStmtSyntax(
                                                    expression: NilLiteralExprSyntax()
                                                ).tryCast(StmtSyntax.self))
                                            )
                                        ])
                                    )
                                )
                            ])
                        }
                    }
                }
            })

        return [syntax.cast(DeclSyntax.self)]
    }
}
