import AppKit
import FotoTagCore
import SwiftUI

/// Campo «Aggiungi un tag» con i suggerimenti: a campo vuoto le proposte dalle foto vicine e dai tag che
/// aggiungi più spesso; mentre scrivi i tag dell'archivio che iniziano (poi contengono) il testo.
/// ↑ ↓ scelgono, ↩ aggiunge la voce evidenziata, ⌥↩ il testo così com'è, Esc chiude.
struct CampoTag: View {
    @EnvironmentObject var stato: Stato
    let suggerimento: String
    let presenti: Set<String>
    let vicini: [String]
    let fuoco: FocusState<Bool>.Binding
    let aggiungi: (String) -> Void
    @State private var testo = ""
    @State private var scelta = 0
    @State private var chiuso = false

    var body: some View {
        let voci = chiuso ? [] : Suggerimenti.completa(testo, conteggi: stato.tagArchivio, esclusi: presenti)
        VStack(alignment: .leading, spacing: 6) {
            TextField(suggerimento, text: $testo)
                .textFieldStyle(.roundedBorder)
                .focused(fuoco)
                .onChange(of: testo) { _, _ in scelta = 0; chiuso = false }
                .onKeyPress(.downArrow) { guard !voci.isEmpty else { return .ignored }; scelta = min(scelta + 1, voci.count); return .handled }
                .onKeyPress(.upArrow) { guard !voci.isEmpty else { return .ignored }; scelta = max(scelta - 1, 0); return .handled }
                .onKeyPress(.escape) { guard !testo.isEmpty else { return .ignored }; chiuso = true; return .handled }
                .onSubmit {
                    // ⌥↩ o l'ultima riga («come nuovo tag»): il testo com'è; altrimenti la voce evidenziata
                    let comE = NSEvent.modifierFlags.contains(.option) || scelta >= voci.count
                    metti(comE ? testo : voci[scelta].tag)
                }
            if !voci.isEmpty {
                elenco(voci)
                Text("↑ ↓ scegli, ↩ aggiungi, Esc chiudi").font(.caption).foregroundStyle(.secondary)
            } else if testo.isEmpty {
                proposte("Usati nelle foto vicine di questo rullino", vicini)
                proposte("Usati spesso da te", Suggerimenti.frequenti(stato.tagManuali, esclusi: presenti.union(vicini), massimo: 5))
            }
        }
    }

    func metti(_ t: String) {
        let t = t.trimmingCharacters(in: .whitespaces).lowercased()
        if !t.isEmpty && !presenti.contains(t) { aggiungi(t) }
        testo = ""
    }

    func elenco(_ voci: [(tag: String, foto: Int)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(voci.enumerated()), id: \.offset) { i, v in
                riga(i) {
                    evidenzia(v.tag)
                    Spacer()
                    Text("\(v.foto) foto").foregroundStyle(.secondary).monospacedDigit()
                }
                .onTapGesture { metti(v.tag) }
            }
            Divider().padding(.vertical, 2)
            riga(voci.count) {
                Text("Aggiungi «\(testo.trimmingCharacters(in: .whitespaces))» come nuovo tag")
                Spacer()
                Text("⌥↩").foregroundStyle(.secondary)
            }
            .onTapGesture { metti(testo) }
        }
        .font(.callout)
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 6).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
    }

    func riga<C: View>(_ i: Int, @ViewBuilder _ contenuto: () -> C) -> some View {
        HStack { contenuto() }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 4).fill(i == scelta ? Color.accentColor.opacity(0.2) : .clear))
            .contentShape(Rectangle())
    }

    /// La parte già scritta in grassetto.
    func evidenzia(_ tag: String) -> Text {
        let q = testo.trimmingCharacters(in: .whitespaces).lowercased()
        guard let r = tag.range(of: q) else { return Text(tag) }
        return Text(tag[..<r.lowerBound]) + Text(tag[r]).bold() + Text(tag[r.upperBound...])
    }

    @ViewBuilder
    func proposte(_ titolo: LocalizedStringKey, _ tag: [String]) -> some View {
        if !tag.isEmpty {
            Text(titolo).font(.caption).foregroundStyle(.secondary)
            Fila(spaziatura: 6) {
                ForEach(tag, id: \.self) { t in
                    Button { metti(t) } label: { Text("+ \(t)").padding(.horizontal, 9).padding(.vertical, 3) }
                        .buttonStyle(.plain)
                        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        .help("Aggiungi «\(t)»")
                }
            }
        }
    }
}

extension Stato {
    /// Tag più frequenti nelle altre foto della stessa cartella (lo stesso rullino), che la foto non ha.
    func tagVicini(a f: FotoRecord, presenti: Set<String>) -> [String] {
        let dir = (f.percorso as NSString).deletingLastPathComponent
        let altre = foto.filter { $0.id != f.id && ($0.stato == .proposta || $0.stato == .rivista)
            && ($0.percorso as NSString).deletingLastPathComponent == dir }
        return Suggerimenti.frequenti(Suggerimenti.conta(altre.map(\.parole)), esclusi: presenti, massimo: 5)
    }

    /// Ricalcola i conteggi dei tag dell'archivio poco dopo l'ultima modifica, fuori dal thread principale.
    func aggiornaSuggerimenti() {
        guard let archivio else { return }
        lavoroSuggerimenti?.cancel()
        lavoroSuggerimenti = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled,
                  let t = try? await Task.detached(priority: .utility, operation: { try archivio.tagPerSuggerimenti() }).value
            else { return }
            tagArchivio = t.archivio
            tagManuali = t.manuali
        }
    }
}
