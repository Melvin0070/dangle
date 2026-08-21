import Testing
import CoreGraphics
@testable import DangleKit

@Suite struct ConfettiTests {

    @Test func burstActivatesAndExpires() {
        let confetti = ConfettiSystem()
        confetti.container.bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(!confetti.isActive)

        confetti.burst(at: CGPoint(x: 400, y: 300), count: 40)
        #expect(confetti.isActive)
        #expect(confetti.container.sublayers?.count == 40)

        // canvas-confetti particles live 200 ticks at 60fps; step well past.
        for _ in 0..<300 { confetti.step(frameDt: 1.0 / 60.0) }
        #expect(!confetti.isActive)
        #expect(confetti.container.sublayers?.isEmpty ?? true)
    }

    @Test func removeAllClearsImmediately() {
        let confetti = ConfettiSystem()
        confetti.burst(at: .zero, count: 10)
        confetti.removeAll()
        #expect(!confetti.isActive)
        #expect(confetti.container.sublayers?.isEmpty ?? true)
    }
}
