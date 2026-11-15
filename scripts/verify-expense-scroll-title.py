#!/usr/bin/env python3
"""Exercise the production title state with out-of-order layout callbacks."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'walkcalc-native/Features/Groups/ExpenseScrollTitle.swift').read_text()
state = source[source.index('@Observable'):source.index('struct ExpenseScrollTracking:')]
harness = r'''
import Foundation
import Observation
STATE
@main struct Runner {
    @MainActor static func flushLayout() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @MainActor static func main() async {
        let today = Date(timeIntervalSince1970: 200_000)
        let yesterday = today.addingTimeInterval(-86_400)
        let state = ExpenseScrollTitleState()
        state.retainDates([today, yesterday])

        // Cached sections can report an intersecting frame before the scroll
        // view has reported its viewport. This must not flash a date title.
        state.setActive(true, for: today, revision: state.layoutRevision)
        await flushLayout()
        precondition(state.date == nil, "First section layout must not replace the group title")
        state.updateViewport(topInset: 100, isScrolled: false)
        await flushLayout()
        precondition(state.date == nil, "Overview keeps the group title")

        // Normal user/programmatic scrolling still publishes date boundaries.
        state.updateViewport(topInset: 44, isScrolled: true)
        await flushLayout()
        precondition(state.date == today, "Scrolling into records shows their date")
        state.setActive(true, for: yesterday, revision: state.layoutRevision)
        state.setActive(false, for: today, revision: state.layoutRevision)
        await flushLayout()
        precondition(state.date == yesterday, "Forward boundary follows the next section")
        state.setActive(false, for: yesterday, revision: state.layoutRevision)
        state.setActive(true, for: today, revision: state.layoutRevision)
        await flushLayout()
        precondition(state.date == today, "Reverse boundary restores the previous section")

        // A queued date update must not win against a newer return-to-top.
        state.setActive(true, for: yesterday, revision: state.layoutRevision)
        state.updateViewport(topInset: 100, isScrolled: false)
        precondition(state.date == nil, "Return to overview clears the date immediately")
        await flushLayout()
        precondition(state.date == nil, "Deferred section callbacks cannot restore a stale title")

        // Late data/layout from the previous record set is rejected.
        let oldRevision = state.layoutRevision
        state.reset()
        state.retainDates([yesterday])
        state.updateViewport(topInset: 44, isScrolled: true)
        state.setActive(true, for: yesterday, revision: oldRevision)
        await flushLayout()
        precondition(state.date == nil, "Old layout callbacks cannot activate new data")
        state.setActive(true, for: yesterday, revision: state.layoutRevision)
        await flushLayout()
        precondition(state.date == yesterday, "Tracking resumes after query/reset")
        state.retainDates([])
        await flushLayout()
        precondition(state.date == nil, "Removing records clears the title")

        // GroupView has per-group identity. A late update in A must never
        // supply B's initial title, regardless of B's network completion.
        let groupB = ExpenseScrollTitleState()
        state.retainDates([today])
        state.setActive(true, for: today, revision: state.layoutRevision)
        groupB.retainDates([yesterday])
        groupB.setActive(true, for: yesterday, revision: groupB.layoutRevision)
        await flushLayout()
        precondition(state.date == today && groupB.date == nil)
        print("PASS: first layout, overview, date boundaries, queued callbacks, data reset and group isolation")
    }
}
'''.replace('STATE', state)
with tempfile.TemporaryDirectory(prefix='walkcalc-scroll-title-') as directory:
    runner = Path(directory) / 'Runner.swift'
    runner.write_text(harness)
    binary = Path(directory) / 'verify'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(runner), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
