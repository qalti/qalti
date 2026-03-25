//
//  FileNameTextField.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 15.07.2025.
//

import SwiftUI
import AppKit

struct FileNameTextField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onCancel: () -> Void
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.textFieldAction(_:))
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.focusRingType = .default
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.stringValue = text
        
        // Focus and select filename without extension on initial setup
        DispatchQueue.main.async {
            textField.becomeFirstResponder()
            selectFilenameWithoutExtension(in: textField)
        }
        
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Only update if the text actually changed from external source
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func selectFilenameWithoutExtension(in textField: NSTextField) {
        let fullText = textField.stringValue
        
        // Find the last dot to identify the extension
        if let lastDotIndex = fullText.lastIndex(of: ".") {
            let filenameWithoutExtension = String(fullText[..<lastDotIndex])
            let selectionRange = NSRange(location: 0, length: filenameWithoutExtension.count)
            
            if let textEditor = textField.currentEditor() {
                textEditor.selectedRange = selectionRange
            }
        } else {
            // No extension found, select all text
            textField.selectText(nil)
        }
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FileNameTextField
        
        init(_ parent: FileNameTextField) {
            self.parent = parent
        }
        
        @objc func textFieldAction(_ sender: NSTextField) {
            parent.text = sender.stringValue
            parent.onSubmit()
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
        
        func controlTextDidEndEditing(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
                
                // Check if editing ended due to pressing Enter/Return
                if let userInfo = obj.userInfo,
                   let movement = userInfo["NSTextMovement"] as? Int,
                   movement == NSTextMovement.return.rawValue {
                    parent.onSubmit()
                }
            }
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}
