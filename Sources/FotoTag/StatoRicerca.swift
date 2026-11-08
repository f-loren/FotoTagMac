import AppKit
import FotoTagCore
import IOKit.ps
import SwiftUI

/// Ricerca: indice SigLIP delle foto (nel database) e risultati.
/// L'indice si prepara da solo in sottofondo (D65): dopo l'indice delle cartelle e dopo il download del modello,
/// prima la cartella aperta. Va in pausa durante l'analisi e a batteria; le foto solo in cloud non si scaricano
/// mai da sole, ma solo con «Includi le foto del disco in cloud…».
@MainActor
final class StatoRicerca: ObservableObject {
    @Published var frase = ""
    @Published var risultati: [Ricerca.Risultato] = []
    @Published var cercata: String?             // ultima frase cercata (per «nessun risultato»)
    @Published var indicizzate = 0
    @Published var daIndicizzare = 0
    @Published var preparazione: String?        // messaggio mentre carica il modello o indicizza
    @Published var inPausa = false
    @Published var errore: String?
    @Published var avviso: String?              // nota non bloccante nella riga di stato
    @Published var soloInCloud = 0              // foto del disco in cloud senza anteprima: non cercabili
    @Published var rawInCloud: [String] = []    // RAW del disco in cloud senza impronta dello scatto (D66)
    @Published var fotoCercate = 0              // voci su cui ha lavorato l'ultima ricerca
    @Published var esito: String?               // a fine lavoro, nella barra laterale
    @AppStorage("ricercaInSottofondo") var inSottofondo = true
    var mostraQuandoPronti = false              // Invio nel campo: i risultati vanno nella griglia

    private var siglip: SigLIP?
    private var caricamento: Task<SigLIP, Error>?
    private var lavoro: Task<Void, Never>?
    private var daRifare = false                // richiesta arrivata mentre lavorava: un altro giro alla fine
    @Published private(set) var fermataDallUtente = false  // «Ferma»: niente avvii da soli finché non si preme Riprendi
    private var cloudInAttesa = false           // «Includi» premuto mentre lavorava: parte appena il giro si chiude
    private var ricercaInCorso: Task<Void, Never>?
    private var fallite: Set<Int64> = []        // non lette in questo giro: non si riprovano subito
    private var voci: [Ricerca.Voce] = []       // tenute in memoria fra una ricerca e l'altra (criterio 10)
    private var versioneVoci: Int32 = -1
    weak var stato: Stato?

    var disponibile: Bool { SigLIP.disponibile }
    var inCorso: Bool { lavoro != nil }

    /// Il modello si carica una volta sola, anche se lo chiedono insieme indice e ricerca.
    func modello() async throws -> SigLIP {
        if let siglip { return siglip }
        if caricamento == nil {
            preparazione = String(localized: "Carico il modello di ricerca…")
            caricamento = Task { try await SigLIP() }
        }
        do {
            let s = try await caricamento!.value
            siglip = s
            return s
        } catch {
            caricamento = nil  // al prossimo uso si riprova
            preparazione = nil
            throw error
        }
    }

    /// Toglie SigLIP dalla memoria (a fine lavoro o in pausa); al prossimo uso si ricarica.
    private func liberaModello() {
        siglip = nil
        caricamento = nil
    }

    static var aBatteria: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let tipo = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (tipo as String) == "Battery Power"  // kIOPMBatteryPower, macro non importata in Swift
    }

    /// Avvio da solo (fine dell'indice delle cartelle, modello scaricato): solo con «In sottofondo» e se l'utente
    /// non ha premuto Ferma. Le foto non lette nel giro prima si riprovano (un disco può essere tornato).
    func avviaInSottofondo() {
        versioneVoci = -1  // l'indice delle cartelle può aver spostato o tolto foto
        guard inSottofondo, !fermataDallUtente else { return }
        if lavoro == nil { fallite = [] }
        indicizza(daSolo: true)
    }

    func ferma() {
        fermataDallUtente = true
        daRifare = false
        cloudInAttesa = false
        lavoro?.cancel()
    }

    /// «Includi le foto del disco in cloud…»: dopo la conferma le scarica una alla volta, calcola embedding e
    /// anteprima e le libera (D65).
    /// Anche i RAW del disco in cloud: si leggono data e fotocamera per collegarli ai JPG (D66), poi si liberano.
    func includiCloud() {
        guard soloInCloud + rawInCloud.count > 0 else { return }
        let a = NSAlert()
        let parti = [soloInCloud > 0 ? String(localized: "\(soloInCloud) foto") : nil,
                     rawInCloud.isEmpty ? nil : "\(rawInCloud.count.formatted()) RAW"].compactMap { $0 }
        a.messageText = String(localized: "Includere \(parti.formatted(.list(type: .and))) del disco in cloud?")
        a.informativeText = String(localized: "FotoTag le scarica una alla volta e poi le toglie di nuovo dal Mac: delle foto prepara la ricerca e un'anteprima, dei RAW legge data e fotocamera per collegarli ai JPG (ogni RAW è un download intero, 15-60 MB). Ci vuole tempo e traffico di rete; puoi fermarlo quando vuoi.")
        a.addButton(withTitle: String(localized: "Includi"))
        a.addButton(withTitle: String(localized: "Annulla"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        guard lavoro != nil else { indicizza(cloud: true); return }
        // il giro in corso si chiude e, alla chiusura, parte quello del cloud (Ferma lo annulla)
        cloudInAttesa = true
        daRifare = false
        lavoro?.cancel()
    }

    /// Calcola l'embedding delle foto che non l'hanno ancora, una alla volta. Con `cloud` solo le foto del disco
    /// in cloud senza anteprima, scaricandole; altrimenti mai nulla dal cloud (per quelle si usa l'anteprima).
    func indicizza(daSolo: Bool = false, cloud: Bool = false) {
        guard lavoro == nil else { daRifare = true; return }
        guard disponibile, let archivio = stato?.archivio else { return }
        if !daSolo { fermataDallUtente = false }
        esito = nil
        let aperta = stato?.cartellaCorrente.map { $0.percorso + "/" }
        let saltare = fallite
        preparazione = String(localized: "Preparo la ricerca…")
        lavoro = Task {
            var lette = 0, nonLette = 0
            defer {
                let fermato = Task.isCancelled
                lavoro = nil; preparazione = nil; inPausa = false
                liberaModello()
                if !fermato && lette + nonLette > 0 {
                    esito = String(localized: "Ricerca pronta su altre \(lette) foto")
                        + (nonLette > 0 ? String(localized: ". \(nonLette.formatted()) non lette (disco staccato o file illeggibile, vedi Diario).") : ".")
                }
                if cloudInAttesa { cloudInAttesa = false; indicizza(cloud: true) }
                else if daRifare && !fermataDallUtente { daRifare = false; indicizza(daSolo: true) }
            }
            do {
                let cartellaAnteprime = Stato.cartellaAnteprimeImpostata
                // la scelta dei file tocca il disco per ogni foto: fuori dal thread principale.
                // Foto solo sul disco in cloud: si usa l'anteprima salvata, senza scaricare nulla
                let scansione = Task.detached(priority: .utility) { () -> ([(id: Int64, file: URL)], Int) in
                    var prima: [(id: Int64, file: URL)] = [], dopo: [(id: Int64, file: URL)] = [], inCloud = 0
                    for f in try archivio.senzaEmbedding() where !saltare.contains(f.id) {
                        try Task.checkCancellation()
                        let url = URL(fileURLWithPath: f.percorso)
                        let anteprima = Anteprime.trova(impronta: f.impronta, in: cartellaAnteprime)
                        let file = Ricerca.fileDaIndicizzare(url, anteprima: anteprima)
                        // senza file né anteprima: solo nel cloud (da includere) o su un disco staccato (si salta, senza contarla)
                        let daIncludere = file == nil && Immagini.daScaricare(url)
                        if daIncludere { inCloud += 1 }
                        guard let scelto = cloud ? (daIncludere ? url : nil) : file else { continue }
                        if let aperta, f.percorso.hasPrefix(aperta) { prima.append((f.id, scelto)) } else { dopo.append((f.id, scelto)) }
                    }
                    return (prima + dopo, inCloud)
                }
                // il task staccato non eredita l'annullamento: Ferma glielo passa
                let (scelte, inCloud) = try await withTaskCancellationHandler { try await scansione.value } onCancel: { scansione.cancel() }
                try Task.checkCancellation()
                soloInCloud = inCloud
                rawInCloud = await Task.detached(priority: .utility) {
                    ((try? archivio.originaliSenzaScatto()) ?? []).filter { Immagini.daScaricare(URL(fileURLWithPath: $0)) }
                }.value
                avviso = nil
                if cloud { await leggiRAWInCloud(archivio) }
                guard !scelte.isEmpty else { return }
                daIndicizzare = scelte.count
                indicizzate = 0
                let inizio = Date()
                var s: SigLIP?
                var primaFallita = true
                for (id, file) in scelte {
                    if await aspettaSePausa(daSolo: daSolo) { s = nil }
                    if Task.isCancelled { break }
                    preparazione = String(localized: "Preparo la ricerca: \(indicizzate.formatted()) di \(daIndicizzare.formatted()) foto")
                        + Self.attesa(inizio: inizio, fatte: indicizzate, totale: daIndicizzare)
                    if s == nil { s = try await modello() }
                    let modello = s!
                    let eraInCloud = cloud && Immagini.daScaricare(file)
                    if eraInCloud, await !Immagini.scarica(file, attesa: 60) {
                        Immagini.liberaQuandoCaricate([file])  // se arriva dopo, si toglie lo stesso (D62)
                        nonLette += 1; fallite.insert(id); indicizzate += 1
                        continue
                    }
                    // può essere stata tolta dal Mac dopo la scelta: leggerla bloccherebbe senza scadenza
                    if !eraInCloud && Immagini.daScaricare(file) { indicizzate += 1; continue }
                    let (lato, dest) = (Stato.latoAnteprimeImpostato, cartellaAnteprime)
                    // calcolo e salvataggi fuori dal thread principale: il database può aspettare l'indice delle cartelle
                    let salvato = await Task.detached(priority: .utility) { () -> Bool in
                        // dal cloud: anche l'anteprima, così la foto si vede senza riscaricarla
                        if eraInCloud, let i = Immagini.impronta(file), (try? Anteprime.salva(da: file, impronta: i, lato: lato, in: dest)) != nil {
                            try? archivio.salvaImpronta(id, i)
                        }
                        guard let e = try? modello.embedding(foto: file) else { return false }
                        do { try archivio.salvaEmbedding(id, e); return true } catch {
                            Diario.errore("indice di ricerca: embedding non salvato: \(error.localizedDescription)")
                            return false
                        }
                    }.value
                    if eraInCloud { Immagini.libera(file) }
                    if salvato {
                        lette += 1
                        if eraInCloud { soloInCloud = max(0, soloInCloud - 1) }
                    } else {
                        nonLette += 1
                        fallite.insert(id)
                        if primaFallita { primaFallita = false; Diario.info("indice di ricerca: \(file.path) non letto") }
                    }
                    indicizzate += 1
                }
                if nonLette > 1 { Diario.info("indice di ricerca: \(nonLette) foto non lette in questo giro") }
            } catch is CancellationError {
            } catch { errore = error.localizedDescription }
        }
    }

    /// Pausa durante l'analisi (la GPU serve a lei) e, se partito da solo, a batteria. Vero se c'è stata una pausa
    /// (SigLIP è stato tolto dalla memoria).
    private func aspettaSePausa(daSolo: Bool) async -> Bool {
        var fatta = false
        while !Task.isCancelled, let motivo = stato?.inCorso == true ? String(localized: "Ricerca in pausa durante l'analisi")
                : (daSolo && Self.aBatteria ? String(localized: "Ricerca in pausa: Mac a batteria") : nil) {
            if !fatta { fatta = true; inPausa = true; liberaModello() }
            preparazione = motivo
            try? await Task.sleep(for: .seconds(5))
        }
        inPausa = false
        return fatta
    }

    /// RAW del disco in cloud senza impronta: scaricati uno alla volta, letto l'EXIF, tolti subito dal Mac (D66).
    /// Leggere l'EXIF di un RAW in cloud lo scarica intero (provato l'8/11: 16 MB, 4,6 s su BeeStation).
    private func leggiRAWInCloud(_ archivio: Archivio) async {
        let elenco = rawInCloud
        guard !elenco.isEmpty else { return }
        // l'indice degli originali riscrive le righe: una impronta salvata nel frattempo andrebbe persa
        while stato?.indiceInCorso != nil, !Task.isCancelled {
            preparazione = String(localized: "Aspetto la fine dell'indice degli originali…")
            try? await Task.sleep(for: .seconds(2))
        }
        var lette: Set<String> = [], conImpronta = 0
        for (n, p) in elenco.enumerated() {
            _ = await aspettaSePausa(daSolo: false)
            if Task.isCancelled { break }
            preparazione = String(localized: "Leggo i RAW del disco in cloud: \(n.formatted()) di \(elenco.count.formatted())")
            let u = URL(fileURLWithPath: p)
            guard await Immagini.scarica(u, attesa: 120) else {
                Immagini.liberaQuandoCaricate([u])  // se arriva dopo, si toglie lo stesso
                continue
            }
            // il file va chiuso prima di toglierlo dal Mac: exif() lo apre e lo chiude. "": letto, senza impronta
            let scatto = await Task.detached(priority: .utility) { () -> String in
                let s = CalcoloFissi.exif(u).scatto ?? ""
                try? archivio.salvaScatto(p, s)
                return s
            }.value
            Immagini.libera(u)
            lette.insert(p)
            if !scatto.isEmpty { conImpronta += 1 }
        }
        Diario.info("RAW del disco in cloud: \(lette.count) letti su \(elenco.count), \(conImpronta) con l'impronta dello scatto")
        rawInCloud = elenco.filter { !lette.contains($0) }
        if conImpronta > 0 { stato?.ricollegaOriginali() }
    }

    /// « · circa 3 h» dopo qualche foto, quando la stima ha senso.
    static func attesa(inizio: Date, fatte: Int, totale: Int) -> String {
        guard fatte >= 20 else { return "" }
        let resto = Date().timeIntervalSince(inizio) / Double(fatte) * Double(totale - fatte)
        if resto < 90 { return String(localized: " · meno di 2 min") }
        if resto < 5400 { return String(localized: " · circa \(Int(resto / 60)) min") }
        return String(localized: " · circa \(Int((resto / 3600).rounded())) h")
    }

    /// Embedding di una foto appena analizzata, mentre il file è ancora sul Mac.
    func indicizzaUna(_ f: FotoRecord) async {
        guard disponibile, let archivio = stato?.archivio else { return }
        let s: SigLIP
        do { s = try await modello() } catch {
            Diario.errore("modello di ricerca non caricato: \(error.localizedDescription)")
            return
        }
        if lavoro == nil { preparazione = nil }
        let u = f.url
        if let e = try? await Task.detached(priority: .utility, operation: { try s.embedding(foto: u) }).value {
            try? archivio.salvaEmbedding(f.id, e)
        }
    }

    /// Voci della ricerca: si rileggono dal database (fuori dal thread principale) solo se è cambiato qualcosa.
    private func vociAggiornate(_ archivio: Archivio) async throws -> [Ricerca.Voce] {
        let v = await Task.detached { archivio.versione() }.value  // la coda del database può essere occupata
        if v != versioneVoci {
            voci = try await Task.detached(priority: .userInitiated) { try archivio.vociRicerca() }.value
            versioneVoci = v
        }
        return voci
    }

    /// Fuori dai risultati le voci non servono: si libera la memoria (centinaia di MB su un archivio grande).
    func dimenticaVoci() {
        voci = []
        versioneVoci = -1
    }

    func cerca(_ testo: String? = nil) {
        let q = (testo ?? frase).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let archivio = stato?.archivio else { risultati = []; cercata = nil; return }
        // senza modello i risultati mostrano «Modello di ricerca da scaricare»
        guard disponibile else { mostraSeChiesto(); return }
        ricercaInCorso?.cancel()  // una ricerca vecchia che finisce dopo non deve sostituire quella nuova
        ricercaInCorso = Task {
            do {
                let s = try await modello()
                if lavoro == nil { preparazione = nil }
                let t = try await Task.detached { try s.embedding(frase: q) }.value
                let voci = try await vociAggiornate(archivio)
                let (scala, bias) = (s.scala, s.bias)
                let trovati = await Task.detached(priority: .userInitiated) {
                    Ricerca.cerca(q, testo: t, scala: scala, bias: bias, in: voci, limite: 300)
                }.value
                if Task.isCancelled { return }
                risultati = trovati
                fotoCercate = voci.count
                cercata = q
                // in una coda «Da fare» una ricerca arrivata tardi non deve prenderne il posto
                errore = nil
                if stato?.inRisultati == true && stato?.raccolta == nil { mostraQuandoPronti = true }
                mostraSeChiesto()
            } catch {
                if Task.isCancelled { return }
                errore = String(localized: "Ricerca non riuscita: \(error.localizedDescription)")
                mostraSeChiesto()  // l'errore si legge nella striscia sopra i risultati
            }
        }
    }

    private func mostraSeChiesto() {
        guard mostraQuandoPronti else { return }
        mostraQuandoPronti = false
        stato?.mostraRisultati()
    }
}

/// Barra laterale: avanzamento dell'indice di ricerca, con Ferma; foto in cloud da includere; esito.
struct RiquadroRicerca: View {
    @ObservedObject var ricerca: StatoRicerca

    var body: some View {
        let daIncludere = ricerca.soloInCloud + ricerca.rawInCloud.count
        if ricerca.inCorso || ricerca.esito != nil || ricerca.fermataDallUtente || (daIncludere > 0 && !ricerca.inCorso) {
            VStack(alignment: .leading, spacing: 6) {
                if let p = ricerca.preparazione {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if ricerca.inPausa { Image(systemName: "pause.circle").foregroundStyle(.secondary) } else { ProgressView().controlSize(.small) }
                        Text(p).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        Spacer(minLength: 4)
                        Button("Ferma") { ricerca.ferma() }.controlSize(.small)
                    }
                } else if ricerca.fermataDallUtente && !ricerca.inCorso {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "stop.circle").foregroundStyle(.secondary)
                        Text("Ricerca fermata: cerca solo nelle foto già pronte.").font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        Spacer(minLength: 4)
                        Button("Riprendi") { ricerca.indicizza() }.controlSize(.small)
                    }
                } else if let e = ricerca.esito {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        Text(e).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                        Spacer(minLength: 4)
                        Button { ricerca.esito = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Chiudi")
                    }
                }
                if daIncludere > 0 && !ricerca.inCorso {
                    Text(ricerca.soloInCloud > 0 ? String(localized: "\(ricerca.soloInCloud.formatted()) foto del disco in cloud non sono cercabili.")
                         : String(localized: "\(ricerca.rawInCloud.count.formatted()) RAW del disco in cloud non sono ancora collegabili ai JPG."))
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Includi (le scarico una alla volta e poi le libero)…") { ricerca.includiCloud() }
                        .controlSize(.small)
                }
            }
            .padding(10)
        }
    }
}
