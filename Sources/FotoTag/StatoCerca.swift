import AppKit
import FotoTagCore
import SwiftUI

/// Ricerca dalla barra: i risultati prendono il posto delle foto della cartella nella griglia, così pannello,
/// tastiera, Conferma tag e Annulla funzionano come nella cartella. Esc o campo vuoto tornano indietro.
extension Stato {
    /// Mostra (o aggiorna) i risultati di `ricerca.risultati`; la selezione resta se le foto ci sono ancora.
    func mostraRisultati() {
        guard let archivio else { return }
        var r = ricerca.risultati
        if cercaSoloCartella, let c = cartellaCorrente { r = r.filter { $0.percorso.hasPrefix(c.percorso + "/") } }
        raccolta = nil
        gruppiRisultati = Ricerca.raggruppa(r)
        let ordine = gruppiRisultati.flatMap(\.ids)
        let record = Dictionary(uniqueKeysWithValues: ((try? archivio.foto(ids: ordine)) ?? []).map { ($0.id, $0) })
        if !inRisultati {
            primaDellaRicerca = (fotoScelta, selezione)
            inRisultati = true
            fotoGrande = false
            selezione = []
            fotoScelta = nil
        }
        foto = ordine.compactMap { record[$0] }
        let ids = Set(foto.map(\.id))
        selezione = selezione.intersection(ids)
        if let f = fotoScelta, !ids.contains(f) { fotoScelta = nil }
    }

    /// Torna alla cartella di prima con la stessa selezione.
    func esciDaiRisultati() {
        guard inRisultati else { return }
        inRisultati = false
        raccolta = nil
        gruppiRisultati = []
        caricaFoto()
        if let p = primaDellaRicerca {
            let ids = Set(foto.map(\.id))
            if let s = p.scelta, ids.contains(s) { fotoScelta = s }
            selezione = p.selezione.intersection(ids)
        }
        primaDellaRicerca = nil
        ricerca.dimenticaVoci()
    }

    /// Una coda «Da fare» di tutto l'archivio nella griglia, come i risultati della ricerca: stessi pannello,
    /// tastiera e Annulla. L'elenco resta fermo mentre si lavora: una foto confermata non sparisce sotto il cursore.
    func apriDaFare(_ d: Archivio.DaFare) {
        guard let archivio else { return }
        if !inRisultati { primaDellaRicerca = (fotoScelta, selezione) }
        inRisultati = true
        raccolta = d
        ricerca.frase = ""
        ricerca.mostraQuandoPronti = false
        fotoGrande = false
        schermata = .tagga
        Task {
            // con decine di migliaia di foto la lettura prende qualche secondo: fuori dal thread principale
            let (elenco, gruppi) = await Task.detached(priority: .userInitiated) { () -> ([FotoRecord], [Ricerca.Gruppo]) in
                let elenco = ((try? archivio.foto(daFare: d)) ?? []).sorted { Immagini.primaNelPercorso($0.url, $1.url) }
                var gruppi: [Ricerca.Gruppo] = []
                for f in elenco {
                    let dir = (f.percorso as NSString).deletingLastPathComponent
                    if gruppi.last?.cartella == dir { gruppi[gruppi.count - 1].ids.append(f.id) } else { gruppi.append(Ricerca.Gruppo(cartella: dir, ids: [f.id])) }
                }
                return (elenco, gruppi)
            }.value
            guard raccolta == d, inRisultati else { return }  // nel frattempo si è scelta un'altra coda o una cartella
            gruppiRisultati = gruppi
            foto = elenco
            fotoScelta = foto.first?.id
            selezione = fotoScelta.map { [$0] } ?? []
        }
    }

    /// Dopo scrittura o indice: nei risultati e nelle code si rileggono le stesse foto nello stesso ordine,
    /// invece di caricare la cartella sotto.
    func ricaricaFoto() {
        guard inRisultati, let archivio else { caricaFoto(); return }
        let record = Dictionary(uniqueKeysWithValues: ((try? archivio.foto(ids: foto.map(\.id))) ?? []).map { ($0.id, $0) })
        foto = foto.compactMap { record[$0.id] }
    }

    /// Composizione ▸ Cerca (⌘F): fuoco nel campo di ricerca della barra.
    static func fuocoNellaRicerca() {
        guard let w = NSApp.keyWindow else { return }
        for case let s as NSSearchToolbarItem in w.toolbar?.items ?? [] {
            w.makeFirstResponder(s.searchField)
            return
        }
        func cerca(_ v: NSView) -> NSSearchField? {
            if let s = v as? NSSearchField { return s }
            for f in v.subviews { if let s = cerca(f) { return s } }
            return nil
        }
        if let v = w.contentView?.superview, let s = cerca(v) { w.makeFirstResponder(s) }
    }
}

/// Campo «Cerca in tutte le foto» nella barra (osserva la ricerca, che è un oggetto a parte).
struct CampoCerca: ViewModifier {
    @EnvironmentObject var stato: Stato
    @ObservedObject var ricerca: StatoRicerca

    func body(content: Content) -> some View {
        content
            .searchable(text: $ricerca.frase, placement: .toolbar, prompt: "Cerca in tutte le foto")
            .onSubmit(of: .search) { ricerca.mostraQuandoPronti = true; ricerca.cerca() }
            .onChange(of: ricerca.frase) { vecchia, nuova in
                if nuova.isEmpty, stato.raccolta == nil { stato.esciDaiRisultati() }
                // con «Solo quando cerco» l'indice si prepara al primo uso; in sottofondo ci pensa già da solo
                if vecchia.isEmpty && !nuova.isEmpty && !ricerca.inSottofondo { ricerca.indicizza() }
            }
    }
}

/// Sotto la barra, nei risultati: dove cercare, preparazione dell'indice, come tornare.
struct StrisciaRicerca: View {
    @EnvironmentObject var stato: Stato
    @ObservedObject var ricerca: StatoRicerca

    var body: some View {
        HStack(spacing: 10) {
            Text("Cerca in:").foregroundStyle(.secondary)
            Picker("Cerca in", selection: $stato.cercaSoloCartella) {
                Text("Tutte le cartelle").tag(false)
                if let c = stato.cartellaCorrente { Text("«\(c.nome)»").tag(true) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            if ricerca.inCorso, ricerca.cercata != nil {
                // risultati fermi mentre l'indice cresce (D65): si aggiornano solo a richiesta
                Text("Cerco in \(ricerca.fotoCercate) foto. Le altre si aggiungono mentre preparo la ricerca.")
                    .foregroundStyle(.secondary).lineLimit(2)
                Button("Aggiorna") { ricerca.cerca(ricerca.cercata) }.controlSize(.small)
            } else if let p = ricerca.preparazione {
                ProgressView().controlSize(.small)
                Text(p).foregroundStyle(.secondary).lineLimit(1)
            }
            if let e = ricerca.errore {
                Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).lineLimit(2)
            } else if let a = ricerca.avviso {
                Text(a).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if let c = stato.cartellaCorrente { Text("Esc torna a \(c.nome)").foregroundStyle(.secondary) }
        }
        .font(.callout)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.bar)
    }
}
