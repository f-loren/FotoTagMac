import AppKit
import FotoTagCore

extension Stato {
    /// Testo per FotoTag ▸ Esporta diagnostica…: niente foto né percorsi delle cartelle, solo dati utili a capire un problema.
    func testoDiagnostica() -> String {
        let info = Bundle.main.infoDictionary
        var chip = [CChar](repeating: 0, count: 256)
        var n = chip.count
        sysctlbyname("machdep.cpu.brand_string", &chip, &n, nil, 0)
        let m = modelloAnalisi
        let casa = FileManager.default.homeDirectoryForCurrentUser
        let liberi = (try? casa.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
        var righe = [
            "FotoTag \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Chip: \(String(cString: chip))",
            String(format: "Memoria: %.0f GB", Modelli.ramGB),
            "Modello per l'analisi: \(m.nome) (scelta: \(sceltaModello)) in \(Modelli.posizione(m)?.path ?? "non scaricato")",
            "Modello per la ricerca: \(SigLIP.cartellaPredefinita().path)",
            String(format: "Spazio libero sul disco di sistema: %.1f GB", Double(liberi) / 1e9),
            "Database: \(archivio?.url.path ?? "non disponibile")",
        ]
        for (nome, valore) in (try? archivio?.riepilogo()) ?? [] { righe.append("  \(nome): \(valore)") }
        righe += ["", "Ultime righe del registro (\(Diario.file.path)):"] + Diario.ultimeRighe(200)
        return righe.joined(separator: "\n").replacingOccurrences(of: casa.path, with: "~") + "\n"
    }

    func esportaDiagnostica() {
        let pannello = NSSavePanel()
        pannello.nameFieldStringValue = "FotoTag diagnostica \(Date().formatted(.iso8601.year().month().day())).txt"
        pannello.allowedContentTypes = [.plainText]
        guard pannello.runModal() == .OK, let u = pannello.url else { return }
        do { try testoDiagnostica().write(to: u, atomically: true, encoding: .utf8) } catch {
            messaggio = String(localized: "Diagnostica non salvata: \(error.localizedDescription)")
        }
    }
}
