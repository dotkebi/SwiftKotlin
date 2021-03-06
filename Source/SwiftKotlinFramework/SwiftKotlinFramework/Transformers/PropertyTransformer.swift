//
//  PropertyTransformer.swift
//  SwiftKotlinFramework
//
//  Created by Angel Garcia on 03/11/16.
//  Copyright © 2016 Angel G. Olloqui. All rights reserved.
//

import Foundation

class PropertyTransformer: Transformer {
    
    func transform(formatter: Formatter) throws {
        transformComputedProperties(formatter)
        transformPrivateSetters(formatter)
        transformLateInitProperties(formatter)
    }
    
    func transformComputedProperties(_ formatter: Formatter) {
        var previousIndex = 0
        while let index = findFirstPropertyBodyIndex(formatter, fromIndex: previousIndex) {
            //Find a get or set keyword
            let getIndex = formatter.indexOfNextToken(fromIndex: index, matching: { $0 == .identifier("get")})
            let setIndex = formatter.indexOfNextToken(fromIndex: index, matching: { $0 == .identifier("set")})
            
            //Convert the getter if a getter is defined or there is no setter
            if getIndex != nil || setIndex == nil {
                transformGetterProperty(formatter, index: getIndex ?? index)
            }
            
            //Convert the setter if defined
            if let setIndex = formatter.indexOfNextToken(fromIndex: index, matching: { $0 == .identifier("set")}) {
                transformSetterProperty(formatter, index: setIndex)
            }
            
            //Replace var by val if no setter
            if  setIndex == nil,
                let varIndex = formatter.indexOfPreviousToken(fromIndex: index, matching: { $0.string == "var" }) {
                formatter.replaceTokenAtIndex(varIndex, with: .keyword("val"))
            }
            
            //If there is a "get" or "set" then remove the {} from the property
            if  getIndex != nil || setIndex != nil,
                let closeIndex = formatter.indexOfNextToken(fromIndex: index, matching: { $0 == .endOfScope("}") }) {
                formatter.removeTokenAtIndex(closeIndex)
                formatter.removeTokenAtIndex(index)
            }
            
            previousIndex = index + 1
        }
    }
    
    func transformGetterProperty(_ formatter: Formatter, index: Int) {
        let isExplicitGet = formatter.tokenAtIndex(index) == .identifier("get")
        var position = index
        var tokens:[Token] = [
            .startOfScope("("),
            .endOfScope(")"),
        ]
        
        //Add "get" keyword if no explicit getter
        if isExplicitGet {
            position += 1
        }
        else {
            tokens.insert(.keyword("get"), at: 0)
            tokens.append(.whitespace(" "))
        }
        
        formatter.insertTokens(tokens, atIndex: position)
       
        //Add extra space if none
        if !(formatter.tokenAtIndex(index - 1)?.isWhitespace ?? false) {
            formatter.insertToken(.whitespace(" "), atIndex: index)
        }
    }
    
    func transformSetterProperty(_ formatter: Formatter, index: Int) {
        //Consume spaces
        var position = index + 1
        while formatter.tokenAtIndex(position)?.isWhitespaceOrCommentOrLinebreak ?? false {
            position += 1
        }
        
        //Check if the setter has a variable name, otherwise create it with "newValue" as name (default for swift)
        if formatter.tokenAtIndex(position) == .startOfScope("{") {
            formatter.insertTokens([
                .startOfScope("("),
                .identifier("newValue"),
                .endOfScope(")")
            ], atIndex: index + 1)
        }
    }
    
    func findFirstPropertyBodyIndex(_ formatter: Formatter, fromIndex: Int) -> Int? {
        //Find properties with the type: "var <name>:<type> {"
        for i in fromIndex..<formatter.tokens.count {
            guard formatter.tokenAtIndex(i) == .keyword("var") else { continue }
            var index = i + 1
            
            //Consume spaces
            while formatter.tokenAtIndex(index)?.isWhitespaceOrCommentOrLinebreak ?? false {
                index += 1
            }
            
            //Consume name
            index += 1
            
            //Consume possible spaces
            while formatter.tokenAtIndex(index)?.isWhitespaceOrCommentOrLinebreak ?? false {
                index += 1
            }
            
            //Check there is a : and consume
            guard formatter.tokenAtIndex(index)?.string == ":" else { continue }
            index += 1
            
            //Consume possible spaces
            while formatter.tokenAtIndex(index)?.isWhitespaceOrCommentOrLinebreak ?? false {
                index += 1
            }
            
            //Now consume identifiers, maps, optionals, unwrapping and generics
            while   let token = formatter.tokenAtIndex(index),
                    token.isIdentifier || token.string == "<" || token.string == ">" || token.string == "[" || token.string == "]" || token.string == "?" || token.string == "!" || token.string == "." {
                index += 1
            }
            
            //Consume possible spaces
            while formatter.tokenAtIndex(index)?.isWhitespaceOrCommentOrLinebreak ?? false {
                index += 1
            }
            
            //Check there is a { and add to list
            guard formatter.tokenAtIndex(index)?.string == "{" else { continue }
            return index
        }
        return nil
    }
    
    func transformPrivateSetters(_ formatter: Formatter) {
        //Look for "(set)" form
        formatter.forEachToken( { $0 == .identifier("set") }) { (i, token) in
            guard formatter.tokenAtIndex(i - 1) == .startOfScope("(") &&
                formatter.tokenAtIndex(i + 1) == .endOfScope(")") else {
                    return
            }
            guard let accessorIndex = formatter.indexOfPreviousToken(fromIndex: i - 1, matching: { !$0.isWhitespaceOrLinebreak}) else { return }
            guard let lineBreak = formatter.indexOfNextToken(fromIndex: i + 1, matching: { $0.isLinebreak} ) else { return }
            guard let nextWordIndex = formatter.indexOfNextToken(fromIndex: i + 1, matching: { !$0.isWhitespaceOrLinebreak }) else { return }
            let indentation = formatter.indentTokenForLineAtIndex(accessorIndex) ?? .whitespace("\t")
            
            //Append the "private set" to the end
            formatter.insertTokens([
                .linebreak("\n"),
                indentation,
                .whitespace("\t"),
                formatter.tokenAtIndex(accessorIndex)!,
                .whitespace(" "),
                .identifier("set")
            ], atIndex: lineBreak)
            
            //Remove the old accessor
            formatter.removeTokensInRange(Range(uncheckedBounds: (lower: accessorIndex, upper: nextWordIndex)))
        }
    }
    
    func transformLateInitProperties(_ formatter: Formatter) {
        var previousIndex = 0
        while let index = findFirstLateInitPropertyIndex(formatter, fromIndex: previousIndex) {
            if let unwrappedIndex = formatter.indexOfNextToken(fromIndex: index, matching: { $0 == .symbol("!") }) {
                formatter.removeTokenAtIndex(unwrappedIndex)
                formatter.insertTokens([
                    .keyword("lateinit"),
                    .whitespace(" ")
                    ], atIndex: index)
            }
            previousIndex = index + 2
        }
    }
    
    func findFirstLateInitPropertyIndex(_ formatter: Formatter, fromIndex: Int) -> Int? {
        //Look for "var <name>:<Type>!" form
        for i in fromIndex..<formatter.tokens.count {
            guard formatter.tokenAtIndex(i) == .keyword("var") else { continue }
            
            var index = i + 1
            
            //Consume spaces
            while formatter.tokenAtIndex(index)?.isWhitespaceOrCommentOrLinebreak ?? false {
                index += 1
            }
            
            //Check there is a name and consume
            guard formatter.tokenAtIndex(index)?.isIdentifier ?? false else { continue }
            index += 1
            
            //Consume possible spaces
            while formatter.tokenAtIndex(index)?.isWhitespaceOrCommentOrLinebreak ?? false {
                index += 1
            }
            
            //Check there is a : and consume
            guard formatter.tokenAtIndex(index)?.string == ":" else { continue }
            index += 1
            
            //Consume possible spaces
            while formatter.tokenAtIndex(index)?.isWhitespaceOrCommentOrLinebreak ?? false {
                index += 1
            }
            
            //Now consume identifiers, maps and generics
            while  let token = formatter.tokenAtIndex(index),
                token.isIdentifier || token.string == "<" || token.string == ">" || token.string == "[" || token.string == "]" || token.string == "." {
                    index += 1
            }
            
            //If there is a ! then return it
            if formatter.tokenAtIndex(index) == .symbol("!") {
                return i
            }
        }
        return nil
    }

}
