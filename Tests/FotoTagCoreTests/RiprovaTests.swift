import Foundation
import Testing
@testable import FotoTagCore

@Suite struct RiprovaTests {
    final class Conta: @unchecked Sendable { var corpo = 0, ricariche = 0 }
    struct AltroErrore: Error {}

    @Test func erroreGPUUnaVoltaPoiRiesce() async throws {
        let c = Conta()
        let r = try await Tagger.conUnaRiprova(pausa: .zero, ricarica: { c.ricariche += 1 }) { () -> Int in
            c.corpo += 1
            if c.corpo == 1 { throw ErroreMLX(messaggio: "GPU Timeout") }
            return 42
        }
        #expect(r == 42 && c.corpo == 2 && c.ricariche == 1)
    }

    @Test func secondoErroreGPUPassaAlChiamante() async {
        let c = Conta()
        await #expect(throws: ErroreMLX.self) {
            try await Tagger.conUnaRiprova(pausa: .zero, ricarica: { c.ricariche += 1 }) { () -> Int in
                c.corpo += 1
                throw ErroreMLX(messaggio: "GPU Timeout")
            }
        }
        #expect(c.corpo == 2 && c.ricariche == 1)  // una sola riprova
    }

    @Test func altriErroriSenzaRiprova() async {
        let c = Conta()
        await #expect(throws: AltroErrore.self) {
            try await Tagger.conUnaRiprova(pausa: .zero, ricarica: { c.ricariche += 1 }) { () -> Int in
                c.corpo += 1
                throw AltroErrore()
            }
        }
        #expect(c.corpo == 1 && c.ricariche == 0)
    }
}
