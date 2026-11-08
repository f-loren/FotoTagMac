import AppKit
import FotoTagCore
import SwiftUI

/// Indice delle cartelle: l'utente dà accesso a un disco o a una cartella, e FotoTag elenca da solo tutte le
/// cartelle con foto. Gira su una coda propria con una connessione propria al database, mai sul thread principale
/// né sul pool di Swift (i dischi in cloud possono non rispondere). Nessuna analisi parte da sola.
extension Stato {
    static let codaIndice = DispatchQueue(label: "fototag.indice", qos: .utility)

    var cartelleNascoste: [String] { UserDefaults.standard.stringArray(forKey: "cartelleNascoste") ?? [] }

    /// RAW senza JPG: per ora solo da vedere. Predisposto per attivarli con un'opzione più avanti.
    static var analizzaRAW: Bool { UserDefaults.standard.bool(forKey: "analizzaRAW") }
    func analizzabile(_ f: FotoRecord) -> Bool { !f.eRAW || Stato.analizzaRAW }

    /// Prima volta con cartelle già aggiunte: l'accesso c'è già, le radici si ricavano da loro.
    func preparaAccessi() {
        guard let archivio, ((try? archivio.accessi()) ?? []).isEmpty else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for r in Set(cartelle.map { Indicizzatore.radiceAccesso(di: $0.percorso, home: home) }) {
            try? archivio.aggiungiAccesso(r, segnalibro: Stato.segnalibro(URL(fileURLWithPath: r)), profilo: profiloPredefinito)
        }
    }

    static func segnalibro(_ u: URL) -> Data? {
        (try? u.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)) ?? (try? u.bookmarkData())
    }

    /// Pannello di macOS: si sceglie la cartella Inizio, un disco o una cartella; poi si indicizza tutto da solo.
    func chiediAccesso() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = true
        p.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        p.prompt = String(localized: "Consenti")
        p.message = String(localized: "Scegli la cartella che contiene tutte le tue foto, ad esempio Immagini o un disco esterno: FotoTag le trova anche nelle sottocartelle. Le foto non vengono modificate e nessuna analisi parte da sola.")
        guard p.runModal() == .OK else { return }
        p.urls.forEach(aggiungiAccesso)
        indicizza()
    }

    func aggiungiAccesso(_ u: URL) {
        if !Indicizzatore.compresa(u.path, in: radiciAccesso) {
            // un accesso che ora è compreso nel nuovo lascia a lui le sue regole; ridare lo stesso accesso non le cambia
            let compresi = radiciAccesso.filter { Indicizzatore.compresa($0, in: [u.path]) }
            let profilo = radiciAccesso.contains(u.path) ? nil : compresi.first.map(profiloAccesso) ?? profiloPredefinito
            try? archivio?.aggiungiAccesso(u.path, segnalibro: Stato.segnalibro(u), profilo: profilo)
            for a in compresi { try? archivio?.togliAccesso(a) }
            ricaricaAccessi()
        }
    }

    /// Disco appena collegato: l'avviso in fondo alla barra chiede se aggiungerlo, senza fermare il lavoro.
    func proponi(volume u: URL) {
        // shortcut: i volumi in sola lettura (DMG di installazione, SD col blocco) non si propongono, restano ⌘O
        guard (try? u.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly != true,
              Indicizzatore.daProporre(u.path, accessi: radiciAccesso, ignorati: Stato.volumiIgnorati) else { return }
        volumeNuovo = u
    }

    static var volumiIgnorati: [String] { UserDefaults.standard.stringArray(forKey: "volumiIgnorati") ?? [] }

    func aggiungiVolumeNuovo() {
        guard let u = volumeNuovo else { return }
        volumeNuovo = nil
        aggiungiAccesso(u)
        indicizza()
    }

    func ignoraVolumeNuovo() {
        guard let u = volumeNuovo else { return }
        volumeNuovo = nil
        UserDefaults.standard.set(Stato.volumiIgnorati + [u.path], forKey: "volumiIgnorati")
    }

    func ricaricaAccessi() {
        let voci = (try? archivio?.accessi()) ?? []
        radiciAccesso = voci.map(\.percorso)
        regoleAccessi = Dictionary(voci.map { ($0.percorso, $0.profilo ?? profiloPredefinito) }, uniquingKeysWith: { a, _ in a })
        costruisciAlbero()
    }

    func profiloAccesso(_ percorso: String) -> String { regoleAccessi[percorso] ?? profiloPredefinito }

    /// Le regole stanno sull'accesso, mai sulle sottocartelle: vale quello più specifico che contiene il percorso.
    func profiloID(di percorso: String) -> String {
        radiciAccesso.filter { Albero.contiene($0, percorso) }.max { $0.count < $1.count }
            .map(profiloAccesso) ?? profiloPredefinito
    }

    /// Cambia le regole di una radice e ricalcola i tag fissi delle foto aperte (non quelli corretti a mano).
    func impostaProfiloAccesso(_ percorso: String, _ profilo: String) {
        try? archivio?.impostaProfiloAccesso(percorso, profilo)
        ricaricaAccessi()
        ricalcolaFissi()
        indicizza()
    }

    func togliAccesso(_ percorso: String) {
        try? archivio?.togliAccesso(percorso)
        ricaricaAccessi()
    }

    /// Scorre le radici in sottofondo e aggiorna l'indice (all'avvio, con ⌘R, dopo un nuovo accesso).
    func indicizza() {
        guard indicizzazione == nil else { indiceDaRifare = true; return }
        guard let archivio else { return }
        let voci = (try? archivio.accessi()) ?? []
        guard !voci.isEmpty else { return }
        indicizzazione = String(localized: "Indicizzo…")
        let predefinito = profiloPredefinito, profili = profili
        let escluse = Set(cartelleNascoste + [Stato.cartellaAnteprimeImpostata.path])
        Stato.codaIndice.async { [weak self] in
            // connessione propria: la scrittura lunga non si intreccia con le transazioni del thread principale
            let db = try? Archivio()
            var totale = (foto: 0, cartelle: 0)
            for (percorso, segnalibro, profiloRadice) in voci {
                // regole della radice: cosa saltare e con che profilo nascono le cartelle nuove
                let profilo = profiloRadice ?? predefinito
                let saltate = (profili.first { $0.id == profilo } ?? profili[0]).sottocartelleSaltate
                var url = URL(fileURLWithPath: percorso)
                var vecchio = false
                if let s = segnalibro, let u = try? URL(resolvingBookmarkData: s, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &vecchio)
                    ?? URL(resolvingBookmarkData: s, options: [], relativeTo: nil, bookmarkDataIsStale: &vecchio) {
                    url = u
                }
                let aperto = url.startAccessingSecurityScopedResource()
                defer { if aperto { url.stopAccessingSecurityScopedResource() } }
                let nome = url.lastPathComponent
                let (f0, c0) = totale
                let r = Indicizzatore.percorri(url, saltate: saltate, escluse: escluse) { f, c in
                    let testo = String(localized: "Indicizzo \(nome)… \((f0 + f).formatted()) foto in \(c0 + c) cartelle")
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.indicizzazione = testo } }
                }
                if !r.letta { Diario.info("indice: \(percorso) non raggiungibile, non cambio nulla") }
                if !r.illeggibili.isEmpty { Diario.info("indice: \(r.illeggibili.count) percorsi non letti in \(percorso), es. \(r.illeggibili[0])") }
                do {
                    // l'albero cresce mentre si registra, senza aspettare la fine (che su un disco grande è lontana)
                    let annidate = voci.map(\.percorso).filter { $0 != percorso && Albero.contiene(percorso, $0) }
                    try db?.applicaIndice(r, profilo: profilo, saltate: saltate, annidate: annidate) { _ in
                        DispatchQueue.main.async { MainActor.assumeIsolated { self?.mostraAvanzamentoIndice() } }
                    }
                } catch {
                    Diario.errore("indice di \(percorso): \(error.localizedDescription)")
                }
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.mostraAvanzamentoIndice() } }
                totale = (f0 + r.foto, c0 + r.perCartella.count)
            }
            let (f, c) = totale
            Diario.info("indice aggiornato: \(f) foto in \(c) cartelle")
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.indicizzazione = nil
                    self.ricaricaCartelle()
                    self.ricaricaFoto()
                    if self.indiceDaRifare { self.indiceDaRifare = false; self.indicizza() } else { self.ricerca.avviaInSottofondo() }
                }
            }
        }
    }

    /// Clic su una cartella dell'albero. Una cartella senza foto proprie (un anno, un disco) non ha ancora una riga:
    /// la si crea come passaggio, con le regole della radice che la contiene.
    func apriCartella(_ percorso: String) {
        if let c = cartellePerPercorso[percorso] { cartellaScelta = c.id; return }
        guard let id = try? archivio?.aggiungiPassaggio(percorso, profilo: profiloID(di: percorso)) else { return }
        ricaricaCartelle()
        cartellaScelta = id
    }

    /// Durante l'indicizzazione: albero aggiornato al massimo ogni 2 s.
    func mostraAvanzamentoIndice() {
        guard Date().timeIntervalSince(ultimoAlbero) >= 2 else { return }
        ultimoAlbero = Date()
        ricaricaCartelle()
    }

    /// Con migliaia di cartelle l'albero parte chiuso: aperte solo le radici e la strada fino alla cartella scelta.
    func ramoAperto(_ nodo: NodoAlbero, livello: Int, corrente: String?) -> Bool {
        ramiScelti[nodo.percorso] ?? (livello == 0 || corrente?.hasPrefix(nodo.percorso + "/") == true)
    }

    /// Toglie una cartella (con quello che ha sotto) dall'albero, anche dalle prossime indicizzazioni. Non cancella
    /// nulla: si rimette da Impostazioni ▸ Generali ▸ Cartelle.
    func nascondi(_ percorso: String) {
        UserDefaults.standard.set(cartelleNascoste + [percorso], forKey: "cartelleNascoste")
        if let c = cartellaCorrente, c.percorso == percorso || c.percorso.hasPrefix(percorso + "/") { cartellaScelta = nil }
        ricaricaCartelle()
    }

    func mostra(_ percorso: String) {
        UserDefaults.standard.set(cartelleNascoste.filter { $0 != percorso }, forKey: "cartelleNascoste")
        ricaricaCartelle()
        indicizza()
    }

    /// Albero dall'indice: tutte le cartelle con foto (quelle mai indicizzate contano finché non si indicizza).
    func costruisciAlbero() {
        let nascoste = cartelleNascoste
        let visibili = cartelle.filter { c in
            c.nFoto != 0 && !nascoste.contains { c.percorso == $0 || c.percorso.hasPrefix($0 + "/") }
        }
        let nuovo = Albero.costruisci(visibili.map(\.percorso), radici: radiciAccesso, home: FileManager.default.homeDirectoryForCurrentUser.path)
        if nuovo != albero { albero = nuovo }
        cartellePerPercorso = Dictionary(cartelle.map { ($0.percorso, $0) }, uniquingKeysWith: { a, _ in a })
    }
}

/// Impostazioni ▸ Generali ▸ Cartelle: a cosa FotoTag ha accesso, cosa è nascosto.
struct SezioneCartelle: View {
    @EnvironmentObject var stato: Stato

    var body: some View {
        Section("Cartelle") {
            ForEach(stato.radiciAccesso, id: \.self) { p in
                HStack {
                    VStack(alignment: .leading) {
                        Text(p).lineLimit(1).truncationMode(.middle).help(p)
                        if stato.idValido(stato.profiloAccesso(p)) != stato.profiloAccesso(p) {
                            Text("Profilo «\(stato.profiloAccesso(p))» mancante: vale Generico finché non lo importi in Profili")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    Picker("Profilo", selection: Binding(get: { stato.idValido(stato.profiloAccesso(p)) }, set: { stato.impostaProfiloAccesso(p, $0) })) {
                        ForEach(stato.profili) { Text($0.nomeVisto).tag($0.id) }
                    }
                    .labelsHidden().fixedSize()
                    Button("Togli") { stato.togliAccesso(p) }
                        .help("Non si indicizza più; foto e analisi già presenti restano")
                }
            }
            Button("Aggiungi disco o cartella…") { stato.chiediAccesso() }
            Button("Aggiorna l'indice") { stato.indicizza() }.disabled(stato.indicizzazione != nil)
                .help("Formati letti: RAW, HEIC, JPG e TIFF")
            ForEach(stato.cartelleNascoste, id: \.self) { p in
                HStack {
                    Text(p).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(p)
                    Spacer()
                    Button("Mostra") { stato.mostra(p) }
                }
            }
        }
    }
}
