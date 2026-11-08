import AppKit
import FotoTagCore
import SwiftUI

/// Cartelle degli originali, indice dei RAW e collegamento JPG → originale.
extension Stato {
    func ricaricaRadici() { radiciOriginali = (try? archivio?.radiciOriginali()) ?? [] }

    func aggiungiRadiceOriginali() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = true
        p.prompt = String(localized: "Aggiungi")
        p.message = String(localized: "Scegli le cartelle dove stanno i RAW e le scansioni originali. Verranno solo lette.")
        guard p.runModal() == .OK else { return }
        for url in p.urls {
            let s = (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)) ?? (try? url.bookmarkData())
            try? archivio?.aggiungiRadiceOriginali(url.path, segnalibro: s, soloRaw: false, profilo: profiloPredefinito)
        }
        ricaricaRadici()
        aggiornaIndiceOriginali()
    }

    /// Rifà l'indice: solo nomi e date dei file, senza scaricare nulla dal disco in cloud.
    func aggiornaIndiceOriginali() {
        guard indiceInCorso == nil, let archivio else { return }
        let radici = radiciOriginali
        indiceInCorso = String(localized: "Indicizzo gli originali…")
        Task {
            for r in radici {
                indiceInCorso = String(localized: "Indicizzo \((r.percorso as NSString).lastPathComponent)…")
                var url = URL(fileURLWithPath: r.percorso)
                if let s = r.segnalibro {
                    var vecchio = false
                    if let u = try? URL(resolvingBookmarkData: s, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &vecchio) {
                        url = u; _ = u.startAccessingSecurityScopedResource()
                    }
                }
                let solo = r.soloRaw, prof = profilo(id: r.profilo), pell = prof.tabella
                let id = r.id
                let voci = await Task.detached(priority: .utility) { () -> [Originali.Voce] in
                    // impronta dello scatto dei RAW (D66): si legge solo dai file sul Mac e solo se cambiati;
                    // quelli solo nel disco in cloud entrano con «Includi…» della ricerca
                    let noti = (try? archivio.scattiNoti(radice: id)) ?? [:]
                    var v: [Originali.Voce] = []
                    Originali.elenca(url, soloRaw: solo) { u, mtime in
                        var voce = Originali.voce(u, mtime: mtime, profilo: prof, pellicole: pell)
                        if Originali.soloRAW.contains(voce.ext) {
                            if let n = noti[u.path], n.mtime == mtime { voce.scatto = n.scatto }
                            else if !Immagini.daScaricare(u) { voce.scatto = CalcoloFissi.exif(u).scatto ?? "" }  // "": letto, senza impronta
                        }
                        v.append(voce)
                    }
                    return v
                }.value
                do { try archivio.salvaIndice(radice: r.id, voci) } catch { messaggio = error.localizedDescription }
            }
            indiceInCorso = nil
            ricaricaRadici()
            ricollegaOriginali()
        }
    }

    /// Ricalcola i collegamenti (e i tag fissi) delle foto analizzate della cartella aperta.
    func ricollegaOriginali() {
        let quali = foto.filter { $0.stato != .daAnalizzare }
        lavoroFissi?.cancel()   // come ricalcolaFissi: un giro vecchio non deve scrivere con i collegamenti di prima
        lavoroFissi = Task { for f in quali { if Task.isCancelled { return }; await aggiornaFissi(f) } }
    }

    /// Originale di una foto: RAW con lo stesso nome nella stessa cartella, poi un solo RAW con la stessa impronta
    /// dello scatto (D66, regge un cambio di nome), altrimenti nome e date nell'indice (come il prototipo).
    func trovaOriginale(_ f: FotoRecord, scatto: Date?, impronta: String? = nil, profilo: Profilo) -> (String?, Originali.Livello) {
        if let r = Scrittura.rawAccanto(f.url) { return (r.path, .sicuro) }
        if let impronta, let stessi = try? archivio?.originaliPerScatto(impronta).filter({ $0 != f.percorso }), stessi.count == 1 {
            return (stessi[0], .sicuro)
        }
        let cands = (try? archivio?.candidatiOriginali(radice: Originali.radice(f.nome))) ?? []
        return Originali.trova(f.percorso, scatto: scatto, candidati: cands, profilo: profilo, pellicole: profilo.tabella)
    }

    func scegliOriginale(_ f: FotoRecord) {
        let p = NSOpenPanel()
        p.canChooseFiles = true; p.canChooseDirectories = false
        p.message = String(localized: "Scegli l'originale (RAW o scansione) di \(f.nome)")
        if let r = f.rawURL { p.directoryURL = r.deletingLastPathComponent() } else { p.directoryURL = f.url.deletingLastPathComponent() }
        guard p.runModal() == .OK, let u = p.url else { return }
        impostaOriginale(f, u.path, .sicuro)
    }

    func scollegaOriginale(_ f: FotoRecord) { impostaOriginale(f, nil, .nessuno) }

    func impostaOriginale(_ f: FotoRecord, _ raw: String?, _ livello: Originali.Livello) {
        try? archivio?.salvaOriginale(f.id, raw: raw, livello: livello, manuale: true)
        if let i = foto.firstIndex(where: { $0.id == f.id }) {
            foto[i].raw = raw; foto[i].rawLivello = livello; foto[i].rawManuale = true
            Task { await aggiornaFissi(foto[i]) }
        }
    }
}

/// Riga «Originale» nella revisione.
struct RigaOriginale: View {
    @EnvironmentObject var stato: Stato
    let foto: FotoRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Originale").foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
            if let r = foto.raw {
                VStack(alignment: .leading, spacing: 2) {
                    Text(abbreviato(r)).lineLimit(1).truncationMode(.head).help(r)
                    HStack(spacing: 10) {
                        DistintivoLivello(livello: foto.rawLivello, manuale: foto.rawManuale)
                        Button("Mostra nel Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: r)]) }
                        Button("Cambia…") { stato.scegliOriginale(foto) }
                        Button("Scollega") { stato.scollegaOriginale(foto) }
                    }
                    .buttonStyle(.link).font(.caption)
                }
            } else {
                HStack {
                    Text(foto.rawManuale ? String(localized: "scollegato") : String(localized: "non trovato")).foregroundStyle(.secondary)
                    Button("Scegli…") { stato.scegliOriginale(foto) }.buttonStyle(.link)
                    if stato.radiciOriginali.isEmpty {
                        Text("· aggiungi le cartelle degli originali in Impostazioni").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    func abbreviato(_ p: String) -> String {
        let c = (p as NSString).pathComponents
        return c.count > 3 ? "…/" + c.suffix(3).joined(separator: "/") : p
    }
}

struct DistintivoLivello: View {
    let livello: Originali.Livello
    let manuale: Bool
    var descrizione: (String, Color) {
        if manuale { return (String(localized: "scelto a mano"), .blue) }
        switch livello {
        case .sicuro: return (String(localized: "sicuro"), .green)
        case .probabile: return (String(localized: "probabile"), .yellow)
        case .incerto: return (String(localized: "incerto: da verificare"), .orange)
        case .nessuno: return (String(localized: "nessuno"), .gray)
        }
    }
    var body: some View {
        let (testo, colore) = descrizione
        // colore nel pallino, testo leggibile: giallo e arancione non reggono come testo su fondo chiaro
        Label { Text(testo).foregroundStyle(.primary) } icon: { Circle().fill(colore).frame(width: 7, height: 7) }
            .font(.caption.weight(.medium))
            .help("sicuro: stessa data di scatto · probabile: cartella coerente · incerto: più candidati simili. Il sidecar si scrive solo per «sicuro» o scelto a mano.")
    }
}

/// Impostazioni ▸ Originali.
struct ImpostazioniOriginali: View {
    @EnvironmentObject var stato: Stato
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cartelle dove stanno i RAW e le scansioni originali. FotoTag le legge soltanto: guarda nomi e date dei file, senza scaricare nulla dal disco in cloud.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(stato.radiciOriginali) { r in
                    HStack {
                        VStack(alignment: .leading) {
                            Text((r.percorso as NSString).lastPathComponent).font(.body.weight(.medium))
                            Text(r.percorso).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text("\(r.voci) file").foregroundStyle(.secondary).monospacedDigit()
                        Picker("", selection: Binding(get: { stato.idValido(r.profilo) }, set: { try? stato.archivio?.impostaProfiloRadice(r.id, $0); stato.ricaricaRadici() })) {
                            ForEach(stato.profili) { Text($0.nomeVisto).tag($0.id) }
                        }
                        .labelsHidden().frame(width: 150)
                        .help("Profilo per leggere anno e mese dalle cartelle degli originali")
                        Toggle("solo RAW", isOn: Binding(get: { r.soloRaw }, set: { try? stato.archivio?.impostaSoloRaw(r.id, $0); stato.ricaricaRadici() }))
                            .help("Per le cartelle di esportazioni: considera solo i RAW, non i JPG")
                        Button { try? stato.archivio?.rimuoviRadiceOriginali(r.id); stato.ricaricaRadici() } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain)
                    }
                }
            }
            .frame(minHeight: 200)
            HStack {
                Button("Aggiungi cartella…") { stato.aggiungiRadiceOriginali() }
                Button("Aggiorna l'indice") { stato.aggiornaIndiceOriginali() }.disabled(stato.radiciOriginali.isEmpty || stato.indiceInCorso != nil)
                if let i = stato.indiceInCorso { ProgressView().controlSize(.small); Text(i).font(.caption) }
                Spacer()
            }
        }
        .padding(16)
        .onAppear { stato.ricaricaRadici() }
    }
}
