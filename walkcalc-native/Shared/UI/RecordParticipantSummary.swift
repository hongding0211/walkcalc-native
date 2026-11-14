import Foundation

enum RecordParticipantSummary {
    static func text(payerID: String, recipientIDs: [String], names: [String: String], currentParticipantID: String?, isSettlement: Bool, compact: Bool = true, nameLimit: Int? = nil, eligibleParticipantIDs: [String] = []) -> String {
        func name(_ id: String) -> String {
            let fullName = names[id] ?? L("Unknown")
            guard let nameLimit, nameLimit >= 3, fullName.count > nameLimit else { return fullName }
            let prefixCount = nameLimit / 2
            return "\(fullName.prefix(prefixCount))…\(fullName.suffix(nameLimit - prefixCount - 1))"
        }
        let payer = payerID == currentParticipantID ? L("You") : name(payerID)
        var seen = Set<String>()
        var recipients = recipientIDs.filter { seen.insert($0).inserted }
        // Keep everyone else's original order while giving the viewer priority.
        if let currentParticipantID, let index = recipients.firstIndex(of: currentParticipantID) {
            recipients.insert(recipients.remove(at: index), at: 0)
        }
        if compact && !isSettlement && !eligibleParticipantIDs.isEmpty
            && Set(recipients) == Set(eligibleParticipantIDs) {
            return String(format: L("Record.paid for"), payer, L("Record.everyone"))
        }
        let recipientNames = recipients.map { id in
            if id == payerID {
                return L(id == currentParticipantID ? "Record.yourself" : "Record.themselves")
            }
            return id == currentParticipantID ? L("Record.you") : name(id)
        }
        guard !recipientNames.isEmpty else {
            return String(format: L("Record.paid"), payer)
        }
        let separator = L("Record.name separator")
        let summary: String
        if compact && recipientNames.count >= 3 {
            summary = String(format: L("Record.recipient group"), recipientNames.prefix(2).joined(separator: separator), String(recipientNames.count))
        } else if recipientNames.count == 2 {
            summary = recipientNames.joined(separator: L("Record.pair separator"))
        } else if recipientNames.count > 2 {
            summary = recipientNames.dropLast().joined(separator: separator)
                + L("Record.final separator") + recipientNames.last!
        } else {
            summary = recipientNames.joined(separator: separator)
        }
        // A settlement transfers money to someone; it is not an expense on their behalf.
        return String(format: L(isSettlement ? "Record.paid to" : "Record.paid for"), payer, summary)
    }
}
