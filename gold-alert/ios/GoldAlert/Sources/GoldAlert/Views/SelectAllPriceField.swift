import SwiftUI
import UIKit

/// Decimal-pad field that selects all text when editing begins.
struct SelectAllPriceField: UIViewRepresentable {
    @Binding var text: String
    var onEditingChanged: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onEditingChanged: onEditingChanged)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = .decimalPad
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.borderStyle = .none
        field.textColor = .white
        field.font = .monospacedDigitSystemFont(ofSize: 20, weight: .regular)
        field.tintColor = UIColor(red: 0.83, green: 0.63, blue: 0.09, alpha: 1)
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onEditingChanged = onEditingChanged
        if uiView.text != text, !uiView.isFirstResponder {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        var onEditingChanged: ((Bool) -> Void)?

        init(text: Binding<String>, onEditingChanged: ((Bool) -> Void)?) {
            self.text = text
            self.onEditingChanged = onEditingChanged
        }

        @objc func editingChanged(_ field: UITextField) {
            text.wrappedValue = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            onEditingChanged?(true)
            DispatchQueue.main.async {
                textField.selectAll(nil)
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            onEditingChanged?(false)
            text.wrappedValue = textField.text ?? ""
        }
    }
}
