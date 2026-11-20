import SwiftUI
import UIKit

enum ExpenseAmountDraft {
    struct Edit {
        let amount: String
        let display: String
        let caret: Int
    }

    static func grouped(_ amount: String) -> String {
        let sign = amount.hasPrefix("-") ? "-" : ""
        let unsigned = amount.dropFirst(sign.count)
        let integer = unsigned.prefix { $0 != "." }
        let fraction = unsigned.dropFirst(integer.count)
        let digitCount = integer.count
        var display = sign
        for (index, digit) in integer.enumerated() {
            if index > 0 && (digitCount - index).isMultiple(of: 3) {
                display.append(",")
            }
            display.append(digit)
        }
        return display + fraction
    }

    static func ungrouped(_ display: String) -> String {
        display.replacingOccurrences(of: ",", with: "")
    }

    static func applying(
        _ input: String, to display: String, range: NSRange,
        caret: Int?, decimalSeparator: String
    ) -> Edit? {
        let displayed = display as NSString
        guard range.location <= displayed.length, range.length <= displayed.length - range.location,
              let replacement = normalizedInput(input, decimalSeparator: decimalSeparator) else { return nil }

        let amount = ungrouped(display) as NSString
        let start = ungrouped(displayed.substring(to: range.location)).utf16.count
        let count = ungrouped(displayed.substring(with: range)).utf16.count
        var rawRange = NSRange(location: start, length: count)
        if input.isEmpty, range.length == 1, count == 0, let caret {
            // A deletion next to a formatting separator should delete a digit.
            let deleteIndex = caret > range.location ? start - 1 : start
            if deleteIndex >= 0 && deleteIndex < amount.length {
                rawRange = NSRange(location: deleteIndex, length: 1)
            }
        }

        var next = amount.replacingCharacters(in: rawRange, with: replacement)
        var logicalCaret = rawRange.location + replacement.utf16.count
        if next.hasPrefix(".") {
            next = "0" + next
            logicalCaret += 1
        }
        guard next.range(of: #"\A-?[0-9]*(?:\.[0-9]*)?\z"#, options: .regularExpression) != nil else { return nil }
        if let decimalPoint = next.firstIndex(of: "."),
           let end = next.index(decimalPoint, offsetBy: 3, limitedBy: next.endIndex),
           end < next.endIndex {
            next = String(next[..<end])
        }
        let formatted = grouped(next)
        for (offset, character) in formatted.enumerated() where character != "," {
            if logicalCaret == 0 { return Edit(amount: next, display: formatted, caret: offset) }
            logicalCaret -= 1
        }
        return Edit(amount: next, display: formatted, caret: formatted.utf16.count)
    }

    private static func normalizedInput(_ input: String, decimalSeparator: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.isEmpty || !trimmed.isEmpty else { return nil }
        if !trimmed.contains(",") { return trimmed }
        if trimmed.range(of: #"\A-?[0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]*)?\z"#, options: .regularExpression) != nil {
            return ungrouped(trimmed)
        }
        guard decimalSeparator == ",",
              trimmed.range(of: #"\A-?(?:[0-9]*|[0-9]{1,3}(?:\.[0-9]{3})+),[0-9]*\z"#, options: .regularExpression) != nil else { return nil }
        return trimmed.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
    }
}

struct ExpenseAmountInput: UIViewRepresentable {
    @Environment(\.softLedgerAppTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Binding var amount: String
    @Binding var isFocused: Bool

    private static let amountFont: UIFont = {
        let font = UIFont.monospacedDigitSystemFont(ofSize: 44, weight: .semibold)
        guard let rounded = font.fontDescriptor.withDesign(.rounded) else { return font }
        return UIFont(descriptor: rounded, size: font.pointSize)
    }()

    func makeCoordinator() -> Coordinator { Coordinator(input: self) }

    func makeUIView(context: Context) -> AmountField {
        let field = AmountField(font: Self.amountFont)
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: AmountField, context: Context) {
        let coordinator = context.coordinator
        coordinator.input = self
        field.isEnabled = isEnabled
        field.tintColor = theme.accentUIColor
        let display = ExpenseAmountDraft.grouped(amount)
        if field.text != display {
            field.text = display
            field.setNeedsLayout()
        }

        let wantsFocus = isEnabled && isFocused
        guard field.isFirstResponder != wantsFocus else { return }
        DispatchQueue.main.async { [weak field, weak coordinator] in
            guard let field, let coordinator, field.window != nil,
                  wantsFocus == (coordinator.input.isEnabled && coordinator.input.isFocused) else { return }
            if wantsFocus && !field.isFirstResponder {
                field.becomeFirstResponder()
            } else if !wantsFocus && field.isFirstResponder {
                field.resignFirstResponder()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AmountField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: ceil(Self.amountFont.lineHeight))
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var input: ExpenseAmountInput

        init(input: ExpenseAmountInput) {
            self.input = input
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            input.isFocused = true
            textField.setNeedsLayout()
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            input.isFocused = false
            textField.setNeedsLayout()
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            textField.setNeedsLayout()
        }

        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let display = field.text ?? ""
            let selection = field.selectedTextRange
            let caret = selection.flatMap { $0.isEmpty ? field.offset(from: field.beginningOfDocument, to: $0.start) : nil }
            guard let edit = ExpenseAmountDraft.applying(
                string, to: display, range: range, caret: caret,
                decimalSeparator: Locale.current.decimalSeparator ?? "."
            ) else { return false }

            if (display as NSString).replacingCharacters(in: range, with: string) == edit.display {
                return true
            }
            apply(edit, to: field)
            return false
        }

        @objc func editingChanged(_ field: UITextField) {
            let display = field.text ?? ""
            // Some system text replacements deliver the new value directly.
            guard let edit = ExpenseAmountDraft.applying(
                display, to: "", range: NSRange(location: 0, length: 0), caret: nil,
                decimalSeparator: Locale.current.decimalSeparator ?? "."
            ) else {
                field.text = ExpenseAmountDraft.grouped(input.amount)
                field.setNeedsLayout()
                return
            }

            if edit.display != display {
                apply(edit, to: field)
            } else {
                input.amount = edit.amount
                field.setNeedsLayout()
            }
        }

        private func apply(_ edit: ExpenseAmountDraft.Edit, to field: UITextField) {
            field.text = edit.display
            if let position = field.position(from: field.beginningOfDocument, offset: edit.caret) {
                field.selectedTextRange = field.textRange(from: position, to: position)
            }
            input.amount = edit.amount
            field.setNeedsLayout()
        }
    }

    final class AmountField: UITextField {
        private let clippedValue = UILabel()
        private let leadingFade = CAGradientLayer()
        private let ink = UIColor(SoftLedgerTheme.ink)

        init(font: UIFont) {
            super.init(frame: .zero)
            self.font = font
            textColor = ink
            placeholder = "0.00"
            keyboardType = .decimalPad
            textAlignment = .left
            semanticContentAttribute = .forceLeftToRight
            clipsToBounds = true
            adjustsFontSizeToFitWidth = false
            setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            clippedValue.font = font
            clippedValue.textColor = ink
            clippedValue.isHidden = true
            clippedValue.isAccessibilityElement = false
            addSubview(clippedValue)

            leadingFade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor]
            leadingFade.startPoint = CGPoint(x: 0, y: 0.5)
            leadingFade.endPoint = CGPoint(x: 1, y: 0.5)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width > 0, let font else { return }
            let value = text ?? ""
            let end = String(value.suffix(40))
            let textWidth = ceil((end as NSString).size(withAttributes: [.font: font]).width)
            let overflows = end != value || textWidth > bounds.width
            let showsRestingValue = overflows && !isFirstResponder
            clippedValue.isHidden = !showsRestingValue
            let activeColor = showsRestingValue ? UIColor.clear : ink
            if textColor != activeColor { textColor = activeColor }
            if showsRestingValue {
                if clippedValue.text != end { clippedValue.text = end }
                clippedValue.frame = CGRect(x: bounds.width - textWidth, y: 0, width: textWidth, height: bounds.height)
            }

            let leadingIsClipped = showsRestingValue || (overflows && hasScrolledPastFirstDigit(value, font: font))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            leadingFade.frame = bounds
            leadingFade.locations = [0, NSNumber(value: min(18 / bounds.width, 0.5))]
            layer.mask = leadingIsClipped ? leadingFade : nil
            CATransaction.commit()
        }

        private func hasScrolledPastFirstDigit(_ value: String, font: UIFont) -> Bool {
            guard isFirstResponder, let caret = selectedTextRange?.end else { return false }
            let length = offset(from: beginningOfDocument, to: caret)
            let text = value as NSString
            guard length > 0 && length <= text.length else { return false }
            if length == text.length || length > 40 { return true }
            let prefix = text.substring(to: length)
            let prefixWidth = (prefix as NSString).size(withAttributes: [.font: font]).width
            return prefixWidth - caretRect(for: caret).minX > 1
        }
    }
}
