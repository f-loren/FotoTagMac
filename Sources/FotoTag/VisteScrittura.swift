import FotoTagCore
import SwiftUI

/// Foglio di conferma e avanzamento per «Scrivi nei file».
struct FoglioScrittura: View {
    @EnvironmentObject var stato: Stato
    let lavoro: LavoroScrittura
    @State private var rimbalzo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // da conferma a esito in dissolvenza, il foglio si adatta in altezza (D67)
            if lavoro.finita { esito.transition(.opacity) } else { conferma.transition(.opacity) }
        }
        .animation(Movimento.standard, value: lavoro.finita)
        .padding(22)
        .frame(width: 560)
    }

    var conferma: some View {
        let jpg = lavoro.foto.count
        let raw = lavoro.raw.count
        return VStack(alignment: .leading, spacing: 14) {
            Text("Scrivere tag e didascalie in \(jpg) foto?").font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                Label("\(jpg) JPG: tag e didascalia dentro il file. L'immagine non viene ricompressa.", systemImage: "photo")
                if raw > 0 {
                    Label("\(raw) originali collegati: per i RAW si scrive solo il file .xmp accanto, il RAW non si tocca.", systemImage: "doc.badge.gearshape")
                }
                if lavoro.rawNonSicuri > 0 {
                    Label("\(lavoro.rawNonSicuri) originali collegati con poca certezza non ricevono nulla: controllali nella revisione.", systemImage: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
                Label("Le parole chiave già presenti nei file restano.", systemImage: "checkmark.shield")
            }
            .font(.callout)

            if lavoro.inCloud {
                Label { Text("Queste foto sono su un disco in cloud: verranno modificati gli originali, e la modifica arriverà anche lì.") } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    .font(.callout)
            }

            ScrollViewReader { scorri in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(lavoro.foto.enumerated()), id: \.element.id) { i, f in
                        HStack(alignment: .top, spacing: 10) {
                            Miniatura(url: f.url, lato: 120).frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 4))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.nome).font(.callout.weight(.medium))
                                Text(f.parole.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                                if !f.didascalia.isEmpty { Text("«\(f.didascalia)»").font(.caption).italic().foregroundStyle(.secondary) }
                                if let r = f.raw, f.rawManuale || f.rawLivello == .sicuro {
                                    Text("+ " + (FotoTagCore.Scrittura.eRAW(URL(fileURLWithPath: r)) ? String(localized: "sidecar di ") : "") + (r as NSString).lastPathComponent
                                         + (LavoroScrittura.inCloud(r) ? String(localized: " (disco in cloud)") : ""))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            // spunta file per file mentre si scrive: verde se scritta e riletta, rossa se non riuscita
                            if lavoro.inCorso || lavoro.fatte > 0 {
                                let fatta = i < lavoro.fatte, ok = lavoro.riuscite.contains(f.id)
                                Image(systemName: !fatta ? "circle" : ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(!fatta ? AnyShapeStyle(.tertiary) : ok ? AnyShapeStyle(.green) : AnyShapeStyle(.red))
                                    .contentTransition(.symbolEffect(.replace))
                                    .accessibilityLabel(!fatta ? String(localized: "da scrivere") : ok ? String(localized: "scritta") : String(localized: "non scritta"))
                            }
                        }
                        .id(f.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: lavoro.fatte) { _, n in
                // l'elenco segue la riga in corso
                guard !lavoro.foto.isEmpty else { return }
                withAnimation(Movimento.standard) { scorri.scrollTo(lavoro.foto[min(n, lavoro.foto.count - 1)].id, anchor: .center) }
            }
            }
            .frame(maxHeight: 260)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))

            Toggle("Copia di sicurezza dei file prima di modificarli", isOn: $stato.copiaDiSicurezza)
                .help("Copia gli originali in ~/Library/Application Support/FotoTag/Backups, tenuti 5 giorni")

            if lavoro.inCorso {
                ProgressView(value: Double(lavoro.fatte), total: Double(lavoro.foto.count)) {
                    Text("Scrivo… \(lavoro.fatte)/\(lavoro.foto.count)")
                }
            }

            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { stato.scrittura = nil }
                    .keyboardShortcut(.cancelAction)
                    .disabled(lavoro.inCorso)
                Button("Scrivi nei file") { stato.eseguiScrittura() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(lavoro.inCorso)
            }
        }
    }

    var esito: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(lavoro.errori.isEmpty ? String(localized: "Fatto") : String(localized: "Fatto, con qualche problema"),
                  systemImage: lavoro.errori.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title2.bold())
                .foregroundStyle(lavoro.errori.isEmpty ? .green : .orange)
                .symbolEffect(.bounce, value: rimbalzo)  // un solo piccolo rimbalzo, una volta per scrittura
                .onAppear { rimbalzo = true }
            Text("\(lavoro.scritte) foto scritte (\(lavoro.fileScritti) file), controllate rileggendole.")
            if let c = lavoro.copia {
                Button("Mostra le copie di sicurezza") { NSWorkspace.shared.activateFileViewerSelecting([c]) }
                    .buttonStyle(.link)
            }
            if !lavoro.avvisi.isEmpty {
                Text("Avvisi").font(.headline)
                ForEach(lavoro.avvisi, id: \.self) { Text($0).font(.caption) }
            }
            if !lavoro.errori.isEmpty {
                Text("Errori").font(.headline)
                ForEach(lavoro.errori, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
            }
            HStack {
                Spacer()
                Button("Chiudi") { stato.scrittura = nil }.keyboardShortcut(.defaultAction)
            }
        }
    }
}
