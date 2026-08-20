import Foundation
import Testing

@testable import RationKit

@Suite("Motion curves")
struct MotionCurveTests {

    @Test("progress runs from nothing to one and stops there")
    func progressBounds() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(MotionCurve.progress(since: start, duration: 1, now: start) == 0)
        #expect(
            MotionCurve.progress(
                since: start, duration: 1, now: start.addingTimeInterval(0.5)) == 0.5)
        #expect(
            MotionCurve.progress(since: start, duration: 1, now: start.addingTimeInterval(9)) == 1)
    }

    /// An animation with no duration is already over, rather than dividing by
    /// zero and leaving the ring at nothing forever.
    @Test("a zero-length animation is finished")
    func zeroDuration() {
        #expect(MotionCurve.progress(since: Date(), duration: 0) == 1)
    }

    @Test("ease-out starts fast and lands exactly on the value")
    func easeOutShape() {
        #expect(MotionCurve.easeOut(0) == 0)
        #expect(MotionCurve.easeOut(1) == 1)
        #expect(MotionCurve.easeOut(0.5) > 0.5)
    }

    /// The overshoot is the point — a card that eases in has not been caught,
    /// it has been placed.
    @Test("the spring overshoots and then settles")
    func springOvershoots() {
        #expect(MotionCurve.spring(0) == 0)
        #expect(MotionCurve.spring(1) == 1)
        let peak = stride(from: 0.0, through: 1.0, by: 0.01).map(MotionCurve.spring).max() ?? 0
        #expect(peak > 1)
    }
}
