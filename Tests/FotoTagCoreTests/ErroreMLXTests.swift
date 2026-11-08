import Foundation
import MLX
import Testing
@testable import FotoTagCore

/// Usano MLX: si lanciano solo con FOTOTAG_PROVA_MLX=1 e con FotoTag chiusa (la GPU è condivisa).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FOTOTAG_PROVA_MLX"] != nil))
struct ErroreMLXTests {
    @Test func erroreNelTaskDiventaErroreSwift() async {
        await #expect(throws: ErroreMLX.self) {
            try await Tagger.protetto {
                let a = MLXArray(0 ..< 10, [2, 5]), b = MLXArray(0 ..< 15, [3, 5])
                _ = a + b  // dimensioni incompatibili: senza gestore MLX chiuderebbe il processo
            }
        }
    }

    @Test func erroreFuoriDalTaskArrivaAlGestoreGlobale() async {
        await #expect(throws: ErroreMLX.self) {
            try await Tagger.protetto {
                // Task.detached non eredita il gestore del Task: passa dal gestore globale
                await Task.detached {
                    let a = MLXArray(0 ..< 10, [2, 5]), b = MLXArray(0 ..< 15, [3, 5])
                    _ = a + b
                }.value
            }
        }
        // dopo l'errore MLX funziona ancora
        let r = try? await Tagger.protetto { (MLXArray([1, 2, 3]) * 2).sum().item(Int.self) }
        #expect(r == 12)
    }
}
