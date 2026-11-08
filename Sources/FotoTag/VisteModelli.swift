import FotoTagCore
import SwiftUI

extension Modelli {
    /// Gigabyte con la virgola dei decimali della lingua del Mac («3,1»).
    static func gb(_ x: Double) -> String { x.formatted(.number.precision(.fractionLength(1))) }
}

extension Stato {
    /// Modello da usare: quello scelto in Impostazioni o, in automatico, quello consigliato per questo Mac.
    var modelloAnalisi: Modelli.Modello { Modelli.con(id: sceltaModello) ?? Modelli.consigliato }

    func scaricaModello(_ m: Modelli.Modello) {
        guard scaricamento == nil else { return }
        scaricamento = (m.id, 0, Int64(m.gigabyte * 1e9))
        // SigLIP va nella sua cartella fissa (dove lo cerca la ricerca), i modelli di analisi in Modelli/<repo>
        let dest = m.id == Modelli.siglip.id ? SigLIP.cartellaPredefinita() : nil
        Diario.info("download di \(m.repo)")
        Task {
            do {
                _ = try await Modelli.scarica(m, esattamenteIn: dest) { n, t in
                    Task { @MainActor in
                        guard let s = self.scaricamento, s.id == m.id, n / 100_000_000 != s.fatti / 100_000_000 else { return }  // come in analizza
                        self.scaricamento = (m.id, n, t)
                    }
                }
                Diario.info("download di \(m.repo) finito")
                if m.id == Modelli.siglip.id { ricerca.avviaInSottofondo() }  // D65: l'indice parte appena c'è il modello
            } catch { messaggio = String(localized: "Download non riuscito: \(error.localizedDescription)") }
            scaricamento = nil
            objectWillChange.send()
        }
    }
}

/// Impostazioni ▸ Modelli.
struct ImpostazioniModelli: View {
    @EnvironmentObject var stato: Stato

    var body: some View {
        Form {
            Section {
                Picker("Modello per l'analisi", selection: $stato.sceltaModello) {
                    Text("Automatico (\(Modelli.consigliato.nome))").tag("auto")
                    ForEach(Modelli.tutti) { Text($0.nome).tag($0.id) }
                }
                Text(String(format: String(localized: "Questo Mac ha %.0f GB di memoria: consigliato %@."), Modelli.ramGB, Modelli.consigliato.nome))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Modelli") {
                ForEach(Modelli.tutti) { m in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(m.nome).font(.body.weight(.medium))
                            if m.id == stato.modelloAnalisi.id { Text("in uso").font(.caption).foregroundStyle(.green) }
                            Spacer()
                            if let s = stato.scaricamento, s.id == m.id {
                                ProgressView(value: Double(s.fatti), total: Double(max(s.totale, 1))).frame(width: 140)
                                Text(String(format: "%.1f/%.1f GB", Double(s.fatti) / 1e9, Double(s.totale) / 1e9))
                                    .font(.caption).monospacedDigit()
                            } else if let p = Modelli.posizione(m) {
                                Label("sul Mac", systemImage: "checkmark.circle.fill").foregroundStyle(.green).help(p.path)
                                if Modelli.scaricatoDallApp(m) {
                                    Button("Elimina") { try? Modelli.elimina(m); stato.objectWillChange.send() }
                                }
                            } else {
                                Button(String(format: String(localized: "Scarica (%.1f GB)"), m.gigabyte)) { stato.scaricaModello(m) }
                                    .disabled(stato.scaricamento != nil)
                            }
                        }
                        Text(m.descrizione).font(.caption).foregroundStyle(.secondary)
                        if Modelli.ramGB < m.ramMinimaGB {
                            Label { Text("Su questo Mac potrebbe rallentare molto: serve più memoria.").foregroundStyle(.secondary) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }.font(.caption)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(Modelli.siglip.nome).font(.body.weight(.medium))
                        Spacer()
                        if let s = stato.scaricamento, s.id == Modelli.siglip.id {
                            ProgressView(value: Double(s.fatti), total: Double(max(s.totale, 1))).frame(width: 140)
                        } else if SigLIP.disponibile {
                            Label("sul Mac", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("Scarica (0,75 GB)") { stato.scaricaModello(Modelli.siglip) }.disabled(stato.scaricamento != nil)
                        }
                    }
                    Text(Modelli.siglip.descrizione + String(localized: " Occupa 1,5 GB sul disco.")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("I modelli vengono da Hugging Face e girano solo su questo Mac: le foto non escono mai dal computer.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

/// «Analizza» senza il modello sul Mac: si scarica lì dove si è e poi si analizza (D34.3).
struct FoglioScaricaModello: View {
    @EnvironmentObject var stato: Stato
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        let m = stato.modelloAnalisi
        let n = stato.attesaModello?.foto.count ?? 0
        VStack(alignment: .leading, spacing: 12) {
            Label("Serve il modello per l'analisi", systemImage: "arrow.down.circle").font(.headline)
            Text("Per riconoscere il contenuto delle foto FotoTag usa \(m.nome): \(Modelli.gb(m.gigabyte)) GB, si scarica una volta sola da Hugging Face. Le foto non escono mai dal Mac.")
                .fixedSize(horizontal: false, vertical: true)
            Text(n == 1 ? String(localized: "Finito il download parte l'analisi della foto scelta.")
                 : String(localized: "Finito il download parte l'analisi di \(n) foto. L'avanzamento si vede in fondo alla barra laterale."))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if Modelli.ramGB < m.ramMinimaGB {
                Label("Su questo Mac potrebbe rallentare molto: serve più memoria. Si cambia in Impostazioni ▸ Modelli.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
            }
            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { chiudi() }.keyboardShortcut(.cancelAction)
                Button("Scarica e analizza") {
                    guard let a = stato.attesaModello else { return }
                    chiudi()
                    stato.attesaModello = nil
                    stato.analizza(a.foto, diversa: a.diversa, scarica: true)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(stato.scaricamento != nil)
                .help(stato.scaricamento != nil ? String(localized: "C'è già un download in corso") : "")
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
