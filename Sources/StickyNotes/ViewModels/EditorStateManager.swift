import Foundation
import SwiftUI
import WebKit

class EditorStateManager: ObservableObject {
    @Published var isBold = false
    @Published var isItalic = false
    @Published var isUnderline = false
    @Published var isStrike = false
    @Published var currentHeading = 0
    @Published var isBulletList = false
    @Published var isOrderedList = false
    @Published var currentAlignment = "left"
    
    weak var webView: WKWebView?
    
    func updateState(from status: [String: Any]) {
        if let bold = status["bold"] as? Bool { isBold = bold }
        if let italic = status["italic"] as? Bool { isItalic = italic }
        if let underline = status["underline"] as? Bool { isUnderline = underline }
        if let strike = status["strike"] as? Bool { isStrike = strike }
    }
    
    func applyBold() {
        executeJS("window.commands.bold()")
    }
    
    func applyItalic() {
        executeJS("window.commands.italic()")
    }
    
    func applyUnderline() {
        executeJS("window.commands.underline()")
    }
    
    func applyStrikethrough() {
        executeJS("window.commands.strike()")
    }
    
    func toggleHeading(_ level: Int) {
        executeJS("window.commands.header(\(level))")
    }
    
    func toggleList(type: String) {
        if type == "bullet" {
            executeJS("window.commands.bulletList()")
        } else if type == "ordered" {
            executeJS("window.commands.orderedList()")
        }
    }
    
    func applyAlignment(_ align: String) {
        let value = align == "" ? "''" : "'\(align)'"
        executeJS("window.commands.align(\(value))")
    }
    
    func applyHighlight(color: String = "#FFF200") {
        executeJS("window.commands.background('\(color)')")
    }
    
    func undo() {
        executeJS("window.commands.undo()")
    }
    
    func redo() {
        executeJS("window.commands.redo()")
    }
    
    private func executeJS(_ js: String) {
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
}
