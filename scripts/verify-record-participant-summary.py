#!/usr/bin/env python3
"""Run production participant copy against both localization tables."""
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'walkcalc-native/Shared/UI/RecordParticipantSummary.swift').read_text()
with tempfile.TemporaryDirectory(prefix='walkcalc-participant-copy-') as directory:
    temp = Path(directory)
    for language in ['en', 'zh-Hans']:
        strings = root / f'walkcalc-native/Resources/{language}.lproj/Localizable.strings'
        result = subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(strings)])
        (temp / f'{language}.json').write_bytes(result)
    harness = r'''
var translations: [String: String] = [:]
func L(_ key: String) -> String { translations[key] ?? key }
let names = ["me": "Hong", "a": "Alex", "b": "Blair", "c": "Chris"]
func summary(_ payer: String, _ recipients: [String], settlement: Bool = false, compact: Bool = true, viewer: String? = "me") -> String {
    RecordParticipantSummary.text(payerID: payer, recipientIDs: recipients, names: names,
                                  currentParticipantID: viewer, isSettlement: settlement, compact: compact)
}
func check(_ actual: String, _ expected: String) {
    precondition(actual == expected, "Expected \(expected), got \(actual)")
}
for language in ["en", "zh-Hans"] {
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("\(language).json"))
    translations = try JSONSerialization.jsonObject(with: data) as! [String: String]
    let longNames = ["a": "Alexandra Catherine Montgomery-Wellington", "b": "Christopher Benjamin Alexander-Richardson", "c": "李小明这是一位拥有非常长显示名称的成员"]
    let shortened = RecordParticipantSummary.text(payerID: "a", recipientIDs: ["b", "me", "c"], names: longNames,
                                                  currentParticipantID: "me", isSettlement: false, nameLimit: 8)
    precondition(shortened.contains("Alex…ton") && shortened.contains("Chri…son"))
    precondition(shortened.contains(language == "zh-Hans" ? "等3人支付" : "(3 people)"))
    let full = RecordParticipantSummary.text(payerID: "a", recipientIDs: ["b", "me", "c"], names: longNames,
                                             currentParticipantID: "me", isSettlement: false, compact: false)
    precondition(longNames.values.allSatisfy { full.contains($0) })
    let unicode = RecordParticipantSummary.text(payerID: "c", recipientIDs: ["me"], names: longNames,
                                                currentParticipantID: "me", isSettlement: false, nameLimit: 5)
    precondition(unicode.contains("李小…成员"))
    let allIDs = ["a", "b", "me", "c"]
    func allSummary(_ recipients: [String], candidates: [String] = allIDs, settlement: Bool = false, compact: Bool = true) -> String {
        RecordParticipantSummary.text(payerID: "a", recipientIDs: recipients, names: names, currentParticipantID: "me",
                                      isSettlement: settlement, compact: compact, eligibleParticipantIDs: candidates)
    }
    let everyone = language == "zh-Hans" ? "Alex替所有人支付" : "Alex paid for everyone"
    check(allSummary(["c", "me", "a", "b"]), everyone)
    check(allSummary(["c", "me", "a", "b", "b"]), everyone)
    precondition(allSummary(["b", "me", "c"]) != everyone)
    precondition(allSummary(["a", "b", "me", "c", "old-member"]) != everyone)
    precondition(allSummary([], candidates: []) != everyone)
    precondition(allSummary(allIDs, candidates: [], settlement: false) != everyone)
    precondition(allSummary(allIDs, settlement: true) != everyone)
    precondition(allSummary(allIDs, compact: false) != everyone)
    if language == "zh-Hans" {
        check(summary("a", ["b", "me"]), "Alex替你和Blair支付")
        check(summary("a", ["b", "me", "c"]), "Alex替你、Blair等3人支付")
        check(summary("a", ["b", "me", "c", "a"]), "Alex替你、Blair等4人支付")
        check(summary("me", ["me"]), "你替自己支付")
        check(summary("a", ["a", "me"]), "Alex替你和TA支付")
        check(summary("me", ["b", "me"]), "你替自己和Blair支付")
        check(summary("me", ["a", "b"]), "你替Alex和Blair支付")
        check(summary("a", ["me"], settlement: true), "Alex支付给你")
        check(summary("a", ["me", "me"]), "Alex替你支付")
        check(summary("missing", []), "未知支付")
        check(summary("a", ["b", "me", "c"], compact: false), "Alex替你、Blair、Chris支付")
    } else {
        check(summary("a", ["b", "me"]), "Alex paid for you and Blair")
        check(summary("a", ["b", "me", "c"]), "Alex paid for you, Blair and others (3 people)")
        check(summary("me", ["me"]), "You paid for yourself")
        check(summary("a", ["a"]), "Alex paid for themselves")
        check(summary("a", ["a", "me"]), "Alex paid for you and themselves")
        check(summary("a", ["b", "me", "c"], compact: false), "Alex paid for you, Blair, and Chris")
        check(summary("a", ["me"], settlement: true), "Alex paid you")
        check(summary("a", ["me"], viewer: nil), "Alex paid for Hong")
    }
}
print("PASS: both languages, viewer first, 2/3/4 recipients, self, settlement, duplicates, missing member, full accessibility copy")
'''
    (temp / 'main.swift').write_text(source + '\n' + harness)
    subprocess.run(['xcrun', 'swiftc', str(temp / 'main.swift'), '-o', str(temp / 'verify')], check=True)
    subprocess.run([str(temp / 'verify'), str(temp)], check=True)
