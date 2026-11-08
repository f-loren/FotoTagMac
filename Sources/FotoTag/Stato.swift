import AppKit
import FotoTagCore
import SwiftUI

/// Stato dell'app: cartelle, foto della cartella scelta, analisi in corso.
/// Le schermate dell'app.
enum Schermata: String, CaseIterable, Identifiable {
    case tagga
    var id: String { rawValue }
}

/// Bersaglio delle azioni di Annulla di una foto.
final class BersaglioAnnulla {}

/// Filtro della griglia per stato (barra degli strumenti di Tagga).
enum FiltroStato: String, CaseIterable {
    case tutte, daRivedere, riviste, errori

    func ammette(_ s: StatoFoto) -> Bool {
        switch self {
        case .tutte: return true
        case .daRivedere: return s == .proposta
        case .riviste: return s == .rivista
        case .errori: return s == .errore
        }
    }
}

@MainActor
final class Stato: ObservableObject {
    @Published var schermata: Schermata = .tagga
    @Published var conteggi: [Int64: Archivio.Conteggi] = [:]
    @Published var cartelle: [Cartella] = []
    @Published var cartellaScelta: Cartella.ID? {
        didSet {
            if cartellaScelta != oldValue {
                notizia = nil
                // la cartella scelta da altrove (ricerca, recenti) si vede anche se un suo ramo era stato chiuso a mano
                if let p = cartellaCorrente?.percorso { ramiScelti = ramiScelti.filter { !p.hasPrefix($0.key + "/") } }
                fotoGrande = false
                if inRisultati { inRisultati = false; raccolta = nil; gruppiRisultati = []; primaDellaRicerca = nil; ricerca.frase = "" }
            }
            caricaFoto()
            if let id = cartellaScelta, id != oldValue, let t = try? archivio?.segnaUsata(id),
               let i = cartelle.firstIndex(where: { $0.id == id }) { cartelle[i].usataIl = t }
        }
    }
    @Published var foto: [FotoRecord] = []
    @Published var fotoScelta: FotoRecord.ID?          // foto mostrata nella revisione (l'ultima cliccata)
    @Published var selezione: Set<FotoRecord.ID> = []  // tutte le foto selezionate nella griglia
    @Published var filtro = FiltroStato(rawValue: UserDefaults.standard.string(forKey: "filtroStato") ?? "") ?? .tutte {
        didSet { UserDefaults.standard.set(filtro.rawValue, forKey: "filtroStato") }
    }
    private var ancora: FotoRecord.ID?                 // punto di partenza per ⇧-clic
    @Published var messaggio: String? { didSet { if let messaggio { Diario.info("avviso: \(messaggio)") } } }  // ogni avviso finisce nel registro
    @Published var notizia: String? { didSet { if let notizia { Diario.info("notizia: \(notizia)") } } }  // senza scelte: in fondo alla barra laterale, non modale
    @Published var fineCoda = false                  // confermata l'ultima da rivedere: si propone di scrivere
    @Published var ispettore = UserDefaults.standard.object(forKey: "ispettore") as? Bool ?? true {  // revisione a destra (⌥⌘I)
        didSet { UserDefaults.standard.set(ispettore, forKey: "ispettore") }
    }

    // analisi
    @Published var inCorso = false
    @Published var fotoInAnalisi: FotoRecord.ID?     // la casella con la linea dello scanner (D67)
    @Published var fatte = 0
    @Published var totale = 0
    @Published var secondiMedi: Double?
    @Published var faseModello: String?
    @Published var attesaModello: (foto: [FotoRecord], diversa: Bool)?  // foglio «Scarica e analizza»: il modello manca
    @Published var cartellaInAnalisi: Cartella.ID?   // per il riquadro di avanzamento nella barra laterale
    @Published var fuocoTag = false { didSet { if fuocoTag { ispettore = true } } }  // T: fuoco nel campo «Aggiungi un tag», anche a pannello chiuso
    /// Vista ▸ Includi le sottocartelle: spento, `foto` ha solo quelle dirette, e tutto il resto segue da solo.
    @Published var includiSottocartelle = UserDefaults.standard.object(forKey: "includiSottocartelle") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(includiSottocartelle, forKey: "includiSottocartelle")
            if !inRisultati { caricaFoto() }
        }
    }
    @Published var fotoGrande = false                // colonna centrale: foto a tutta area invece della griglia
    @Published var zoom: UnitPoint?                  // foto grande al 100%, centrata su questo punto (in proporzione alla foto)
    /// La griglia scorre fino a questa foto: solo con la tastiera (frecce, ↩), non con i clic del mouse.
    @Published var scorriA: FotoRecord.ID?
    @Published var indicizzazione: String?           // avanzamento dell'indice, in fondo alla barra laterale
    @Published var radiciAccesso: [String] = []            // dischi e cartelle a cui l'utente ha dato accesso
    var regoleAccessi: [String: String] = [:]              // profilo di ogni accesso
    @Published var volumeNuovo: URL?                       // disco appena collegato, da proporre
    var indiceDaRifare = false                             // chiesto mentre un altro giro era in corso
    @Published var albero: [NodoAlbero] = []         // dall'indice, ricalcolato solo quando cambiano le cartelle
    @Published var ramiScelti: [String: Bool] = [:]  // rami aperti o chiusi a mano, per percorso; gli altri seguono ramoAperto
    var cartellePerPercorso: [String: Cartella] = [:]
    // ricerca nella barra: la griglia mostra i risultati di tutte le cartelle (o di quella aperta)
    @Published var inRisultati = false
    @Published var cercaSoloCartella = false { didSet { if inRisultati { mostraRisultati() } } }
    @Published var gruppiRisultati: [Ricerca.Gruppo] = []
    @Published var raccolta: Archivio.DaFare?        // nei risultati: una coda «Da fare» invece della ricerca
    @Published var daFare: [Archivio.DaFare: Int] = [:]  // foto in ogni coda, su tutto l'archivio
    var primaDellaRicerca: (scelta: FotoRecord.ID?, selezione: Set<FotoRecord.ID>)?
    // suggerimenti di tag: in quante foto compare ogni tag (confermate o aggiunti a mano) e i tag aggiunti a mano
    @Published var tagArchivio: [String: Int] = [:]
    @Published var tagManuali: [String: Int] = [:]
    var lavoroSuggerimenti: Task<Void, Never>?
    var ultimoDock = Date.distantPast
    var ultimoAlbero = Date.distantPast
    private var lavoroConteggi: Task<Void, Never>?

    @Published var scrittura: LavoroScrittura?   // foglio «Scrivi nei file» aperto
    @AppStorage("copiaDiSicurezza") var copiaDiSicurezza = true   // acceso per chi non l'ha mai scelto
    @AppStorage("nomeSidecar") var nomeSidecar = "lightroom"   // FotoTagCore.Scrittura.NomeSidecar
    @AppStorage("profiloPredefinito") var profiloPredefinito = Profilo.generico.id
    @Published var profili = [Profilo.generico]   // Generico è sempre il primo; si caricano nell'init
    var profiliBloccati = false                     // file dei profili non leggibile: non si salva sopra
    var lavoroFissi: Task<Void, Never>?
    @Published var radiciOriginali: [Archivio.RadiceOriginali] = []
    @Published var indiceInCorso: String?
    @AppStorage("modelloAnalisi") var sceltaModello = "auto"
    @Published var scaricamento: (id: String, fatti: Int64, totale: Int64)?
    private var modelloCaricato: String?
    @AppStorage("lingua") var codiceLingua = Lingua.italiano.codice
    var lingua: Lingua { Lingua.con(codice: codiceLingua) }

    let archivio: Archivio?
    let ricerca = StatoRicerca()
    private var tagger: Tagger?
    private var lavoro: Task<Void, Never>?
    private var accessi: [Int64: URL] = [:]  // cartelle aperte con il segnalibro
    weak var annulla: UndoManager?            // quello della finestra (Composizione ▸ Annulla)
    private var bersagliAnnulla: [FotoRecord.ID: BersaglioAnnulla] = [:]

    init() {
        do { archivio = try Archivio() } catch {
            archivio = nil
            messaggio = String(localized: "Database non disponibile: \(error.localizedDescription)")
        }
        do { profili = try Profilo.carica() } catch {
            profiliBloccati = true
            messaggio = String(localized: "Profili non letti (\(Profilo.url().path)): \(error.localizedDescription). Le modifiche ai profili non verranno salvate.")
        }
        ricerca.stato = self
        // un giro ogni 2 minuti: D61 copie di sicurezza oltre i 5 giorni, D62 foto scritte sul disco in cloud già caricate
        Task {
            while true {
                Task.detached(priority: .utility) { FotoTagCore.Scrittura.pulisciCopie() }
                Immagini.liberaCaricate()
                try? await Task.sleep(for: .seconds(120))
            }
        }
        intercettaSelezionaTutto()
        // azione «Mostra le foto da rivedere» della notifica (arriva dal delegato dell'app)
        NotificationCenter.default.addObserver(forName: Stato.notificaMostra, object: nil, queue: .main) { [weak self] n in
            guard let id = n.userInfo?["cartella"] as? Int64 else { return }
            MainActor.assumeIsolated { self?.mostraDaRivedere(cartella: id) }
        }
        ricaricaCartelle()
        ricaricaRadici()
        aggiornaSuggerimenti()
        preparaAccessi()
        try? archivio?.fissaProfiliAccessi(profiloPredefinito)
        ricaricaAccessi()
        indicizza()
        // disco collegato o staccato: si aggiorna l'albero senza aspettare ⌘R
        for n in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: n, object: nil, queue: .main) { [weak self] nota in
                let volume = nota.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
                MainActor.assumeIsolated {
                    self?.costruisciAlbero()
                    self?.indicizza()
                    if n == NSWorkspace.didMountNotification, let volume { self?.proponi(volume: volume) }
                    if n == NSWorkspace.didUnmountNotification, self?.volumeNuovo == volume { self?.volumeNuovo = nil }
                }
            }
        }
        // al giro dopo: `--analizza` aggiornava l'icona del Dock mentre SwiftUI costruiva ancora la finestra (crash)
        DispatchQueue.main.async { self.avvioDaRigaDiComando() }
        if let i = CommandLine.arguments.firstIndex(of: "--schermata"), i + 1 < CommandLine.arguments.count,
           let s = Schermata(rawValue: CommandLine.arguments[i + 1]) { schermata = s }
        // per le prove: `--seleziona N` seleziona le prime N foto (con ⇧-clic, come farebbe l'utente)
        if let i = CommandLine.arguments.firstIndex(of: "--seleziona"), i + 1 < CommandLine.arguments.count,
           let n = Int(CommandLine.arguments[i + 1]), n > 0, foto.count >= n {
            clic(foto[0].id, comando: false, maiuscolo: false)
            clic(foto[n - 1].id, comando: false, maiuscolo: true)
            clic(foto[n + 1 < foto.count ? n + 1 : n - 1].id, comando: true, maiuscolo: false)  // e una con ⌘-clic
        }
    }

    /// Con decine di migliaia di foto il conto prende qualche decimo di secondo: si fa fuori dal thread principale,
    /// poco dopo l'ultima modifica.
    func aggiornaConteggi() {
        guard let archivio else { return }
        lavoroConteggi?.cancel()
        lavoroConteggi = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled,
                  let (c, d) = try? await Task.detached(priority: .utility, operation: { (try archivio.conteggi(), try archivio.contaDaFare()) }).value,
                  !Task.isCancelled else { return }
            conteggi = c
            daFare = d
            aggiornaDistintivo()
        }
    }

    /// Quando il numero serve subito (notifica di fine analisi).
    func aggiornaConteggiSubito() {
        lavoroConteggi?.cancel()
        conteggi = (try? archivio?.conteggi()) ?? conteggi
        daFare = (try? archivio?.contaDaFare()) ?? daFare
        aggiornaDistintivo()
    }

    /// Apre una foto trovata con la ricerca nella schermata «Tagga».
    func apri(fotoID: Int64, percorso: String) {
        guard let c = cartelle.first(where: { percorso.hasPrefix($0.percorso + "/") }) else { return }
        cartellaScelta = c.id
        clic(fotoID, comando: false, maiuscolo: false)
        schermata = .tagga
    }

    func continua(_ c: Cartella) {
        cartellaScelta = c.id
        schermata = .tagga
    }

    /// Per le prove: `FotoTag --cartella <percorso> [--analizza]` aggiunge la cartella senza il pannello
    /// e, se richiesto, avvia subito l'analisi.
    private func avvioDaRigaDiComando() {
        let a = CommandLine.arguments
        // per le prove: `--cerca <frase>` scrive la frase nel campo e la cerca come con Invio (il campo di sistema
        // non si riempie dall'accessibilità)
        if let i = a.firstIndex(of: "--cerca"), i + 1 < a.count {
            let q = a[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.ricerca.frase = q
                self.ricerca.mostraQuandoPronti = true
                self.ricerca.cerca()
            }
        }
        // per le prove: `--originali <cartella>` aggiunge una cartella degli originali (solo copie in ~/TagTest-app) e la indicizza
        let copieApp = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("TagTest-app").path + "/"
        // per le prove: `--diagnostica <file>` scrive la diagnostica senza il pannello
        if let i = a.firstIndex(of: "--diagnostica"), i + 1 < a.count {
            try? testoDiagnostica().write(toFile: a[i + 1], atomically: true, encoding: .utf8)
        }
        if let i = a.firstIndex(of: "--originali"), i + 1 < a.count, a[i + 1].hasPrefix(copieApp) {
            try? archivio?.aggiungiRadiceOriginali(a[i + 1], segnalibro: nil, soloRaw: false,
                                                   profilo: a.firstIndex(of: "--profilo").map { a[$0 + 1] } ?? profiloPredefinito)
            ricaricaRadici()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.aggiornaIndiceOriginali() }
        }
        guard let i = a.firstIndex(of: "--cartella"), i + 1 < a.count else { return }
        let url = URL(fileURLWithPath: a[i + 1])
        let profilo = a.firstIndex(of: "--profilo").map { a[$0 + 1] } ?? profiloPredefinito
        if let id = try? archivio?.aggiungiCartella(url.path, segnalibro: try? url.bookmarkData(), profilo: profilo) {
            ricaricaCartelle()
            cartellaScelta = id
            schermata = .tagga
            if a.contains("--analizza") {
                analizza(daAnalizzare)
                if a.contains("--esci-alla-fine") {  // per le prove automatiche
                    Task { while inCorso || daAnalizzare.count == foto.count { try? await Task.sleep(nanoseconds: 1_000_000_000) }
                           try? await Task.sleep(nanoseconds: 3_000_000_000); NSApp.terminate(nil) }
                }
            }
            // prova della scrittura, permessa SOLO nella cartella di copie ~/TagTest-app
            let copie = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("TagTest-app").path + "/"
            if a.contains("--mostra-foglio"), url.path.hasPrefix(copie) { chiediScrittura(foto) }
            if a.contains("--prova-scrittura"), url.path.hasPrefix(copie) {
                chiediScrittura(daScrivere)
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self.eseguiScrittura() }
            }
        }
    }

    // MARK: cartelle

    func ricaricaCartelle() {
        cartelle = (try? archivio?.cartelle()) ?? []
        aggiornaConteggi()
        costruisciAlbero()
        if cartellaScelta == nil { cartellaScelta = recenti.first?.id ?? cartelle.first?.id }
    }

    /// File ▸ Apri recente: le ultime 5 cartelle usate.
    var recenti: [Cartella] {
        Array(cartelle.filter { $0.usataIl != nil }.sorted { $0.usataIl! > $1.usataIl! }.prefix(5))
    }

    func cancellaRecenti() {
        try? archivio?.cancellaRecenti()
        for i in cartelle.indices { cartelle[i].usataIl = nil }
    }

    /// Apre la cartella tramite il segnalibro (o il percorso) e restituisce l'URL da usare.
    func apri(_ c: Cartella) -> URL {
        if let u = accessi[c.id] { return u }
        var url = URL(fileURLWithPath: c.percorso)
        if let s = c.segnalibro {
            var vecchio = false
            if let u = try? URL(resolvingBookmarkData: s, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &vecchio)
                ?? URL(resolvingBookmarkData: s, options: [], relativeTo: nil, bookmarkDataIsStale: &vecchio) {
                url = u
                _ = u.startAccessingSecurityScopedResource()
            }
        }
        accessi[c.id] = url
        // il segnalibro segue la cartella spostata o rinominata nel Finder: si aggiornano i percorsi
        if url.path != c.percorso, !FileManager.default.fileExists(atPath: c.percorso) {
            Diario.info("cartella spostata: \(c.percorso) → \(url.path)")
            try? archivio?.riconnetti(cartella: c.id, a: url.path, segnalibro: nil)
            DispatchQueue.main.async { self.ricaricaCartelle() }
        }
        return url
    }

    /// Per una cartella che non si trova più: chiede dove sta ora e riallinea i percorsi delle foto.
    func riconnetti(_ c: Cartella) {
        let pannello = NSOpenPanel()
        pannello.canChooseDirectories = true
        pannello.canChooseFiles = false
        pannello.prompt = String(localized: "Riconnetti")
        pannello.message = String(localized: "Dove si trova ora «\(c.nome)»? Analisi, revisione e tag restano collegati alle foto.")
        guard pannello.runModal() == .OK, let url = pannello.url else { return }
        let segnalibro = (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData())
        do {
            try archivio?.riconnetti(cartella: c.id, a: url.path, segnalibro: segnalibro)
            Diario.info("cartella riconnessa: \(c.percorso) → \(url.path)")
            accessi[c.id] = nil
            ricaricaCartelle()
            caricaFoto()
        } catch { messaggio = String(localized: "Cartella non riconnessa: \(error.localizedDescription)") }
    }

    func caricaFoto() {
        guard let archivio, let c = cartelle.first(where: { $0.id == cartellaScelta }) else { foto = []; return }
        let url = apri(c)  // anche per seguire una cartella spostata
        do {
            // le foto vengono dall'indice: niente letture del disco sul thread principale. Solo una cartella
            // mai indicizzata (--cartella nelle prove) si legge qui
            var elenco = try archivio.foto(cartella: c.id)
            if elenco.isEmpty, c.nFoto == nil {
                try archivio.sincronizza(cartella: c.id, file: Immagini.fotoNellaCartella(url, saltate: profilo(id: profiloID(di: c.percorso)).sottocartelleSaltate))
                elenco = try archivio.foto(cartella: c.id)
            }
            Task.detached(priority: .utility) { try? archivio.completaImpronte(cartella: c.id) }
            if !includiSottocartelle { elenco = FotoRecord.dirette(elenco, in: c.percorso) }
            foto = elenco.sorted { Immagini.primaNelPercorso($0.url, $1.url) }
        } catch { messaggio = error.localizedDescription }
        if fotoScelta == nil || !foto.contains(where: { $0.id == fotoScelta }) { fotoScelta = foto.first?.id }
        // pellicole rimaste come sigla ma che ora hanno un nome nella tabella: si ricalcolano i tag fissi
        if foto.contains(where: { f in (f.fissi?.pellicole ?? []).contains { profilo(per: f).tabella.nome($0) != $0 } }) { ricalcolaFissi() }
        let ids = Set(foto.map(\.id))
        selezione = selezione.intersection(ids)
        if selezione.isEmpty, let f = fotoScelta { selezione = [f] }
    }

    // MARK: selezione

    /// Clic su una miniatura con le regole di macOS: clic semplice, ⌘ aggiunge/toglie, ⇧ seleziona l'intervallo.
    func clic(_ id: FotoRecord.ID, comando: Bool, maiuscolo: Bool) {
        let v = fotoVisibili  // l'intervallo è quello che si vede nella griglia filtrata
        if maiuscolo, let a = ancora, let i = v.firstIndex(where: { $0.id == a }),
           let j = v.firstIndex(where: { $0.id == id }) {
            let intervallo = v[min(i, j)...max(i, j)].map(\.id)
            selezione = comando ? selezione.union(intervallo) : Set(intervallo)
            fotoScelta = id
            return
        }
        if comando {
            if selezione.contains(id) {
                selezione.remove(id)
                if fotoScelta == id { fotoScelta = foto.first { selezione.contains($0.id) }?.id }
            } else {
                selezione.insert(id)
                fotoScelta = id
            }
        } else {
            selezione = [id]
            fotoScelta = id
        }
        ancora = id
    }

    /// Frecce nella griglia: ±1 a sinistra/destra, ±colonne su/giù; con ⇧ si estende la selezione.
    func sposta(di passo: Int, estendi: Bool) {
        let v = fotoVisibili
        guard !v.isEmpty else { return }
        let i = v.firstIndex { $0.id == fotoScelta } ?? (passo > 0 ? -1 : v.count)
        let id = v[min(max(i + passo, 0), v.count - 1)].id
        clic(id, comando: false, maiuscolo: estendi)
        scorriA = id
    }

    /// «Rivista, vai alla prossima» (pulsante del pannello, ↩ nella griglia). La prossima si cerca prima di
    /// segnare: col filtro «Da rivedere» la foto rivista sparisce dalla griglia.
    func rivistaEProssima() {
        guard let id = fotoScelta, let f = foto.first(where: { $0.id == id }) else { return }
        let v = fotoVisibili
        let i = v.firstIndex { $0.id == id } ?? -1
        let dopo = v[(i + 1)...].first { $0.stato == .proposta } ?? v.first { $0.stato == .proposta && $0.id != id }
        if f.stato == .proposta {
            var g = f
            g.stato = .rivista
            cambia([g], azione: NomiAzioni.conferma(1))
            // con più foto selezionate daScrivere vale solo per loro: la proposta è per la coda intera
            if dopo == nil, selezione.count <= 1, !daScrivere.isEmpty || prossimaDaRivedere != nil { fineCoda = true }
        }
        if let dopo { clic(dopo.id, comando: false, maiuscolo: false); scorriA = dopo.id }
    }

    /// Selezione a rettangolo nella griglia: le caselle toccate più quelle già scelte (con ⌘).
    func selezionaRettangolo(_ toccate: Set<FotoRecord.ID>, base: Set<FotoRecord.ID>) {
        let nuova = base.union(toccate)
        guard nuova != selezione else { return }
        selezione = nuova
        if let primo = fotoVisibili.first(where: { toccate.contains($0.id) }) { fotoScelta = primo.id; ancora = primo.id }
    }

    /// Tutte le foto visibili con il filtro attuale (anche nei risultati della ricerca).
    func selezionaTutte() {
        let v = fotoVisibili
        selezione = Set(v.map(\.id))
        if fotoScelta == nil || !selezione.contains(fotoScelta!) { fotoScelta = v.first?.id }
    }

    /// ⌘A (Composizione ▸ Seleziona tutto) seleziona le foto quando il fuoco non è in un campo di testo.
    /// Il comando del menu va al primo risponditore, e la griglia SwiftUI non lo riceveva: si intercetta il tasto.
    private func intercettaSelezionaTutto() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  e.charactersIgnoringModifiers == "a",
                  !(NSApp.keyWindow?.firstResponder is NSText),   // nei campi ⌘A resta «seleziona il testo»
                  let self else { return e }
            return MainActor.assumeIsolated {
                guard self.schermata == .tagga, !self.foto.isEmpty else { return e }
                self.selezionaTutte()
                return nil
            }
        }
    }

    /// Foto selezionate, nell'ordine della griglia.
    var selezionate: [FotoRecord] { foto.filter { selezione.contains($0.id) } }

    /// Foto su cui agisce il menu contestuale: la selezione se la foto ne fa parte, altrimenti solo lei.
    func bersaglio(_ f: FotoRecord) -> [FotoRecord] { selezione.contains(f.id) ? selezionate : [f] }

    func segna(_ quali: [FotoRecord], _ nuovo: StatoFoto) {
        let nuove = quali.filter { ($0.stato == .proposta || $0.stato == .rivista) && $0.stato != nuovo }.map { f in
            var g = f
            g.stato = nuovo
            return g
        }
        cambia(nuove, azione: nuovo == .rivista ? NomiAzioni.conferma(nuove.count) : NomiAzioni.riapri(nuove.count))
    }

    /// Composizione ▸ Conferma tag / Riapri: sulla selezione, o sulla foto scelta.
    func confermaSelezione() { if selezione.count > 1 { segna(selezionate, .rivista) } else { rivistaEProssima() } }
    func riapriSelezione() { segna(selezione.count > 1 ? selezionate : foto.filter { $0.id == fotoScelta }, .proposta) }

    func aggiungiTag(_ tag: String, a quali: [FotoRecord]) {
        let t = tag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return }
        cambia(quali.filter { !$0.parole.contains(t) }.map { f in
            var g = f
            g.parole.append(t)
            return g
        }, azione: NomiAzioni.aggiungiTag(t))
    }

    func togliTag(_ tag: String, da quali: [FotoRecord]) {
        cambia(quali.filter { $0.parole.contains(tag) }.map { f in
            var g = f
            g.parole.removeAll { $0 == tag }
            return g
        }, azione: NomiAzioni.togliTag(tag))
    }

    // MARK: annulla

    /// Salva le foto cambiate dall'utente e registra in Annulla il ritorno a com'erano, con il nome dell'azione.
    func cambia(_ nuove: [FotoRecord], azione: String) {
        let prima = nuove.compactMap { n in foto.first { $0.id == n.id } }
        guard !prima.isEmpty else { return }
        for f in nuove { aggiorna(f) }
        registraAnnulla(azione, prima: prima, dopo: nuove)
        aggiornaSuggerimenti()
    }

    /// Una registrazione per foto, con un bersaglio per foto: si possono dimenticare le azioni di una sola foto
    /// (scritta nei file, rianalizzata) senza svuotare la pila.
    func registraAnnulla(_ nome: String, prima: [FotoRecord], dopo: [FotoRecord]) {
        guard let annulla else { return }
        annulla.beginUndoGrouping()
        for p in prima {
            guard let d = dopo.first(where: { $0.id == p.id }) else { continue }
            let b = bersagliAnnulla[p.id] ?? BersaglioAnnulla()
            bersagliAnnulla[p.id] = b
            annulla.registerUndo(withTarget: b) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.ripristina(p)
                    self.registraAnnulla(nome, prima: [d], dopo: [p])  // per «Ripeti»
                }
            }
        }
        annulla.setActionName(nome)
        annulla.endUndoGrouping()
    }

    /// Rimette tag, didascalia, stato e tag fissi di una foto, anche se è in un'altra cartella.
    func ripristina(_ f: FotoRecord) {
        if let i = foto.firstIndex(where: { $0.id == f.id }) {
            foto[i].parole = f.parole
            foto[i].didascalia = f.didascalia
            foto[i].stato = f.stato
            foto[i].fissi = f.fissi
            foto[i].fissiModificati = f.fissiModificati
        }
        try? archivio?.salvaRevisione(f.id, parole: f.parole, didascalia: f.didascalia, stato: f.stato)
        if let t = f.fissi { try? archivio?.salvaFissi(f.id, t, saturazione: nil, manuale: f.fissiModificati) }
        aggiornaConteggi()
    }

    /// Dopo «Scrivi nei file» o un'analisi le azioni di quelle foto non si annullano più.
    func dimenticaAnnulla(_ ids: [FotoRecord.ID]) {
        for id in ids { if let b = bersagliAnnulla.removeValue(forKey: id) { annulla?.removeAllActions(withTarget: b) } }
    }

    // MARK: revisione

    func aggiorna(_ f: FotoRecord) {
        guard let i = foto.firstIndex(where: { $0.id == f.id }) else { return }
        let cambiaStato = foto[i].stato != f.stato
        foto[i] = f
        try? archivio?.salvaRevisione(f.id, parole: f.parole, didascalia: f.didascalia, stato: f.stato)
        if cambiaStato { aggiornaConteggi() }  // numeri «da rivedere» nella barra laterale
    }

    // MARK: analisi

    var daAnalizzare: [FotoRecord] { foto.filter { ($0.stato == .daAnalizzare || $0.stato == .errore) && analizzabile($0) } }

    /// Su cosa agisce «Analizza» (barra e menu Foto): le selezionate se sono più d'una, altrimenti tutta la vista.
    var daAnalizzareOra: [FotoRecord] {
        selezione.count > 1 ? selezionate.filter { ($0.stato == .daAnalizzare || $0.stato == .errore) && analizzabile($0) } : daAnalizzare
    }

    /// Prima cartella, diversa da quella aperta, con foto da rivedere: la proposta a fine coda.
    var prossimaDaRivedere: Cartella? { inRisultati ? nil : cartelle.first { $0.id != cartellaScelta && (conteggi[$0.id]?.daRivedere ?? 0) > 0 } }

    /// Tag aggiunti a mano: quelli che non vengono dalla risposta salvata del modello (restano con «Rianalizza»).
    func tagManuali(_ f: FotoRecord) -> [String] {
        guard let testo = try? archivio?.datiScrittura(f.id).risposta, let r = leggiRisposta(testo) else { return [] }
        let dalModello = Set(Pulizia.paroleChiave(r, lingua: lingua).parole)
        return f.parole.filter { !dalModello.contains($0) }
    }

    /// `diversa`: «Rianalizza» chiesto dall'utente: per le foto già analizzate il modello propone qualcosa
    /// di diverso (vedi Tagger.chiedi) e i tag aggiunti a mano restano.
    /// `scarica`: il modello manca e l'utente ha scelto «Scarica e analizza»: si scarica prima di cominciare.
    func analizza(_ tutte: [FotoRecord], diversa: Bool = false, scarica: Bool = false) {
        let quali = tutte.filter(analizzabile)  // i RAW senza JPG per ora si saltano (D37), ma si dice
        guard !inCorso, let archivio else { return }
        // se c'è altro da analizzare l'avviso compare una volta sola, per non fermare ogni analisi
        if quali.count < tutte.count, quali.isEmpty || !UserDefaults.standard.bool(forKey: "avvisoRAWVisto") {
            UserDefaults.standard.set(true, forKey: "avvisoRAWVisto")
            let n = tutte.count - quali.count
            messaggio = n == 1 ? String(localized: "Un RAW senza JPG resta solo da vedere: per ora FotoTag analizza JPG, HEIC e TIFF. Esporta un JPG per analizzarli.")
                : String(localized: "\(n) RAW senza JPG restano solo da vedere: per ora FotoTag analizza JPG, HEIC e TIFF. Esporta un JPG per analizzarli.")
        }
        guard !quali.isEmpty else { return }
        let manca = modelloCaricato != modelloAnalisi.id && Modelli.posizione(modelloAnalisi) == nil
        if manca && !scarica {
            attesaModello = (quali, diversa)  // si chiede lì dove si è, senza rimandare alle Impostazioni (D34.3)
            return
        }
        guard memoriaSufficiente() else { return }
        inCorso = true
        cartellaInAnalisi = cartellaScelta
        fatte = 0
        totale = quali.count
        secondiMedi = nil
        let lingua = self.lingua
        chiediPermessoNotifiche()
        aggiornaDock(forza: true)
        lavoro = Task {
            defer { inCorso = false; faseModello = nil; cartellaInAnalisi = nil; fotoInAnalisi = nil; aggiornaConteggi(); aggiornaDock() }
            do {
                let m = modelloAnalisi
                if tagger == nil || tagger?.lingua.codice != lingua.codice || modelloCaricato != m.id {
                    if Modelli.posizione(m) == nil, scarica {
                        guard scaricamento == nil else {
                            messaggio = String(localized: "C'è già un download in corso: riprova quando finisce.")
                            return
                        }
                        faseModello = String(localized: "Scarico \(m.nome): \(Modelli.gb(m.gigabyte)) GB…")
                        scaricamento = (m.id, 0, Int64(m.gigabyte * 1e9))
                        Diario.info("download di \(m.repo) prima dell'analisi")
                        defer { scaricamento = nil }
                        do {
                            _ = try await Modelli.scarica(m) { n, t in
                                Task { @MainActor in
                                    // finito o fermato: un avanzamento arrivato tardi non deve riaccendere il riquadro;
                                    // e basta un aggiornamento ogni decimo di GB
                                    guard let s = self.scaricamento, s.id == m.id, n / 100_000_000 != s.fatti / 100_000_000 else { return }
                                    self.scaricamento = (m.id, n, t)
                                    self.faseModello = String(localized: "Scarico \(m.nome): \(Modelli.gb(Double(n) / 1e9)) di \(Modelli.gb(Double(t) / 1e9)) GB")
                                }
                            }
                        } catch where !Task.isCancelled {
                            messaggio = String(localized: "Download non riuscito: \(error.localizedDescription)")
                            return
                        }
                        try Task.checkCancellation()
                        Diario.info("download di \(m.repo) finito")
                    }
                    guard let cartella = Modelli.posizione(m) else {
                        messaggio = String(format: String(localized: "Il modello %@ non è ancora sul Mac. Scaricalo in FotoTag ▸ Impostazioni ▸ Modelli (%.1f GB, una volta sola)."), m.nome, m.gigabyte)
                        return
                    }
                    faseModello = String(localized: "Carico \(m.nome)…")
                    Diario.info("carico il modello \(m.nome) da \(cartella.path)")
                    tagger = nil
                    tagger = try await Tagger(cartellaModello: cartella, lingua: lingua)
                    modelloCaricato = m.id
                }
            } catch where Task.isCancelled {  // «Ferma» durante il download
                Diario.info("download del modello fermato")
                return
            } catch {
                tagger = nil
                modelloCaricato = nil
                messaggio = String(localized: "Modello non caricato: \(error.localizedDescription).")
                    + (error is ErroreMLX ? String(localized: " Chiudi e riapri FotoTag, poi riprova.") : "")
                return
            }
            faseModello = nil
            Diario.info("analisi di \(quali.count) foto con \(modelloCaricato ?? "?")")
            var tempi: [Double] = []
            var errori = 0, interrotta = false
            for f in quali {
                if Task.isCancelled { break }
                fotoInAnalisi = f.id
                let eraInCloud = Immagini.daScaricare(f.url)
                do {
                    if await !Immagini.scarica(f.url, attesa: 30) {
                        throw NSError(domain: "FotoTag", code: 3, userInfo: [NSLocalizedDescriptionKey:
                            String(localized: "\(f.nome) non è ancora stata scaricata dal disco in cloud")])
                    }
                    await aggiornaFissi(f)
                    let giaAnalizzata = f.stato == .proposta || f.stato == .rivista
                    let manuali = diversa && giaAnalizzata ? tagManuali(f) : []
                    let a = try await Tagger.conUnaRiprova(ricarica: {
                        tagger = nil
                        Tagger.liberaMemoria()
                        guard let cartella = Modelli.posizione(modelloAnalisi) else {
                            throw NSError(domain: "FotoTag", code: 4, userInfo: [NSLocalizedDescriptionKey: String(localized: "modello non trovato")])
                        }
                        faseModello = String(localized: "Ricarico il modello dopo un errore della GPU…")
                        defer { faseModello = nil }
                        tagger = try await Tagger(cartellaModello: cartella, lingua: lingua)
                    }) {
                        try await tagger!.analizza(f.url, diversa: diversa && giaAnalizzata ? f.scartate : nil)
                    }
                    let (dalModello, scartate) = Pulizia.paroleChiave(a.risposta, lingua: lingua)
                    let parole = dalModello + manuali.filter { !dalModello.contains($0) }
                    try archivio.salvaAnalisi(f.id, parole: parole, didascalia: a.risposta.didascalia, scartate: scartate,
                                              risposta: a.testo, secondi: a.secondi, percorso: a.percorso,
                                              lingua: lingua.codice)
                    tempi.append(a.secondi)
                    dimenticaAnnulla([f.id])
                    // la foto ora è sul Mac: anteprima ed embedding prima di toglierla di nuovo
                    await salvaAnteprima(f)
                    await ricerca.indicizzaUna(f)
                    if eraInCloud { Immagini.libera(f.url) }
                    // la linea si spegne e il distintivo entra (D67): solo qui, la conferma con ↩ resta istantanea
                    withAnimation(Movimento.standard) {
                        fotoInAnalisi = nil
                        if let i = foto.firstIndex(where: { $0.id == f.id }) {
                            foto[i].stato = .proposta
                            foto[i].parole = parole
                            foto[i].didascalia = a.risposta.didascalia
                            foto[i].scartate = scartate
                            foto[i].secondi = a.secondi
                            foto[i].percorsoAnalisi = a.percorso
                        }
                    }
                } catch {
                    if eraInCloud { Immagini.libera(f.url) }
                    errori += 1
                    try? archivio.segnaErrore(f.id, messaggio: error.localizedDescription)
                    Diario.errore("analisi di \(f.nome): \(error.localizedDescription)")
                    withAnimation(Movimento.standard) {
                        fotoInAnalisi = nil
                        if let i = foto.firstIndex(where: { $0.id == f.id }) { foto[i].stato = .errore }
                    }
                    if error is ErroreMLX {
                        // il modello dopo un errore della GPU può non essere più affidabile: si scarica, e
                        // «Analizza» lo ricarica; se anche il caricamento fallisce, il messaggio chiede di riavviare
                        tagger = nil
                        modelloCaricato = nil
                        Tagger.liberaMemoria()
                        messaggio = String(localized: "Errore della GPU durante l'analisi di \(f.nome), anche dopo un secondo tentativo: l'analisi si è fermata. Riprova con «Analizza»; se si ripete, chiudi e riapri FotoTag.")
                        fatte += 1
                        interrotta = true
                        break
                    }
                }
                fatte += 1
                aggiornaConteggi()
                aggiornaDock()
                // media degli ultimi tempi, senza la prima foto (riscaldamento) se ce ne sono altre
                let utili = tempi.count > 1 ? Array(tempi.dropFirst().suffix(10)) : tempi
                secondiMedi = utili.isEmpty ? nil : utili.reduce(0, +) / Double(utili.count)
            }
            Diario.info("analisi finita: \(fatte)/\(quali.count)" + (secondiMedi.map { String(format: ", %.1f s/foto", $0) } ?? ""))
            if foto.contains(where: { $0.stato == .proposta }) {
                filtro = .daRivedere
                // si riparte dalla prima da rivedere, se si è ancora nella cartella analizzata (D34.3)
                if cartellaScelta == cartellaInAnalisi, !inRisultati, foto.first(where: { $0.id == fotoScelta })?.stato != .proposta,
                   let p = fotoVisibili.first { clic(p.id, comando: false, maiuscolo: false); scorriA = p.id }
            }
            aggiornaSuggerimenti()
            aggiornaConteggiSubito()
            notificaFineAnalisi(cartella: cartelle.first { $0.id == cartellaInAnalisi }, analizzate: tempi.count,
                                errori: errori, interrotta: interrotta)
        }
    }

    func ferma() { lavoro?.cancel() }

    /// Prima di partire: con poca memoria libera (es. una compilazione in corso) avvisa invece di partire e
    /// andare in errore; si può analizzare comunque.
    func memoriaSufficiente() -> Bool {
        let m = modelloAnalisi
        let libera = Memoria.disponibileGB()
        let pressione = Memoria.pressione()
        guard let avviso = Memoria.avvisoPrimaDellAnalisi(disponibileGB: libera, modelloGB: m.gigabyte,
                                                          caricato: tagger != nil && modelloCaricato == m.id,
                                                          pressione: pressione) else { return true }
        Diario.info(String(format: "poca memoria prima dell'analisi: %.1f GB disponibili, pressione %d", libera, pressione))
        if CommandLine.arguments.contains("--analizza") { return true }  // prove automatiche: niente finestre
        let a = NSAlert()
        a.messageText = String(localized: "Poca memoria libera")
        a.informativeText = avviso
        a.addButton(withTitle: String(localized: "Annulla"))
        a.addButton(withTitle: String(localized: "Analizza comunque"))
        let comunque = a.runModal() == .alertSecondButtonReturn
        if comunque { Diario.info("analisi avviata comunque") }
        return comunque
    }
}
