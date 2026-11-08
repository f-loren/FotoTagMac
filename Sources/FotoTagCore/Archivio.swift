import Foundation
import SQLite3

public enum StatoFoto: String, Sendable, CaseIterable {
    case daAnalizzare = "da analizzare"
    case proposta = "proposta"   // tag proposti dal modello, non ancora rivisti
    case rivista = "rivista"     // controllata dall'utente
    case errore = "errore"

    /// Come lo vede l'utente: «proposta» è «da rivedere», «rivista» è «confermata» (nel database restano).
    public var etichetta: String {
        switch self {
        case .proposta: return String(localized: "da rivedere")
        case .rivista: return String(localized: "confermata")
        case .daAnalizzare: return String(localized: "da analizzare")
        case .errore: return String(localized: "errore")
        }
    }
}

public struct Cartella: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let percorso: String
    public let segnalibro: Data?
    public var profilo: String = Profilo.generico.id
    /// ultimo uso (datetime di SQLite, UTC): per l'avvio e File ▸ Apri recente
    public var usataIl: String?
    /// foto dentro la cartella (non nelle sottocartelle) all'ultima indicizzazione; 0 = solo un passaggio nel percorso
    public var nFoto: Int?
    public var nome: String { (percorso as NSString).lastPathComponent }
}

public struct FotoRecord: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let cartellaID: Int64
    public let percorso: String
    public var stato: StatoFoto
    public var parole: [String]
    public var didascalia: String
    public var scartate: [String]
    public var secondi: Double?
    public var percorsoAnalisi: String?
    public var scrittaIl: String?          // ultima scrittura nei file
    public var modificataDopo = false      // tag o didascalia cambiati dopo l'ultima scrittura
    public var fissi: TagFissi?            // origine, tono, data, rullino, pellicola…
    public var fissiModificati = false     // corretti a mano: non si ricalcolano
    public var saturazione: Double?
    public var raw: String?                // originale collegato (RAW, TIFF…)
    public var rawLivello: Originali.Livello = .nessuno
    public var rawManuale = false          // scelto o scollegato a mano
    public var impronta: String?           // dimensione + sha256 di inizio e fine: chiave delle anteprime
    public var rawURL: URL? { raw.map { URL(fileURLWithPath: $0) } }
    public var nome: String { (percorso as NSString).lastPathComponent }
    public var url: URL { URL(fileURLWithPath: percorso) }
    /// RAW senza JPG: per ora solo da vedere, non si analizza e non si scrive.
    public var eRAW: Bool { Scrittura.eRAW(url) }

    /// Solo le foto che stanno proprio in questa cartella, non nelle sottocartelle.
    public static func dirette(_ foto: [FotoRecord], in cartella: String) -> [FotoRecord] {
        foto.filter { ($0.percorso as NSString).deletingLastPathComponent == cartella }
    }
}

/// Database locale (SQLite) con cartelle, foto e tag. Le foto non vengono mai modificate.
public final class Archivio: @unchecked Sendable {
    private var db: OpaquePointer?
    private let coda = DispatchQueue(label: "FotoTag.Archivio")
    public let url: URL

    public static func percorsoPredefinito() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FotoTag", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("fototag.db")
    }

    /// Apre un database altrui (es. quello del prototipo) senza poterlo modificare.
    public init(url: URL, soloLettura: Bool) throws {
        self.url = url
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw errore("apertura") }
    }

    /// Indice degli originali del prototipo (tabella originals), per la regressione.
    public func vociOriginaliPrototipo() throws -> [Originali.Voce] {
        var out: [Originali.Voce] = []
        try query("select path, stem, ext, year, month, mtime from originals") { st in
            out.append(Originali.Voce(
                percorso: Archivio.testo(st, 0) ?? "", radice: Archivio.testo(st, 1) ?? "",
                ext: String((Archivio.testo(st, 2) ?? "").dropFirst()),
                anno: sqlite3_column_type(st, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(st, 3)),
                mese: sqlite3_column_type(st, 4) == SQLITE_NULL ? nil : Int(sqlite3_column_int(st, 4)),
                mtime: sqlite3_column_double(st, 5)))
        }
        return out
    }

    public init(url: URL = Archivio.percorsoPredefinito()) throws {
        self.url = url
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw errore("apertura") }
        sqlite3_busy_timeout(db, 5000)  // l'app e fototag-cli possono usare lo stesso database
        try esegui("""
            pragma journal_mode = wal;
            create table if not exists cartelle(
                id integer primary key, percorso text unique not null, segnalibro blob,
                aggiunta text default (datetime('now')));
            create table if not exists foto(
                id integer primary key, cartella_id integer not null references cartelle(id),
                percorso text unique not null, stato text not null default 'da analizzare',
                parole text not null default '[]', didascalia text not null default '',
                scartate text not null default '[]', risposta text, secondi real, percorso_analisi text,
                lingua text, analizzata text, modificata text);
            create index if not exists foto_cartella on foto(cartella_id);
            """)
        // colonne aggiunte dopo la prima versione
        var colonne: Set<String> = []
        try query("pragma table_info(foto)") { colonne.insert(Archivio.testo($0, 1) ?? "") }
        for (c, tipo) in [("scritta_il", "text"), ("parole_scritte", "text"), ("gerarchia_scritta", "text"),
                          ("didascalia_scritta", "text"), ("file_scritti", "text"),
                          ("embedding", "blob"), ("saturazione", "real"), ("fissi", "text"), ("fissi_modificati", "integer"), ("impronta", "text")]
            where !colonne.contains(c) {
            try esegui("alter table foto add column \(c) \(tipo)")
        }
        var colonneCartelle: Set<String> = []
        try query("pragma table_info(cartelle)") { colonneCartelle.insert(Archivio.testo($0, 1) ?? "") }
        if !colonneCartelle.contains("profilo") { try esegui("alter table cartelle add column profilo text") }
        if !colonneCartelle.contains("usata_il") { try esegui("alter table cartelle add column usata_il text") }
        if !colonneCartelle.contains("n_foto") { try esegui("alter table cartelle add column n_foto integer") }
        try esegui("create table if not exists accessi(percorso text primary key, segnalibro blob, profilo text)")
        var colonneAccessi: Set<String> = []
        try query("pragma table_info(accessi)") { colonneAccessi.insert(Archivio.testo($0, 1) ?? "") }
        if !colonneAccessi.contains("profilo") { try esegui("alter table accessi add column profilo text") }
        var colonneFoto: Set<String> = []
        try query("pragma table_info(foto)") { colonneFoto.insert(Archivio.testo($0, 1) ?? "") }
        for (c, tipo) in [("dimensione", "integer"), ("mtime", "real")] where !colonneFoto.contains(c) {
            try esegui("alter table foto add column \(c) \(tipo)")
        }
        try esegui("create index if not exists foto_impronta on foto(impronta)")
        try esegui("""
            create table if not exists radici_originali(id integer primary key, percorso text unique not null,
                segnalibro blob, solo_raw integer not null default 0, aggiornata text);
            create table if not exists originali(percorso text primary key, radice text not null, ext text,
                anno integer, mese integer, mtime real, radice_id integer);
            create index if not exists originali_radice on originali(radice);
            """)
        var colonneRadici: Set<String> = []
        try query("pragma table_info(radici_originali)") { colonneRadici.insert(Archivio.testo($0, 1) ?? "") }
        if !colonneRadici.contains("profilo") { try esegui("alter table radici_originali add column profilo text") }
        for (c, tipo) in [("raw", "text"), ("raw_livello", "text"), ("raw_manuale", "integer")] where !colonne.contains(c) {
            try esegui("alter table foto add column \(c) \(tipo)")
        }
        var colonneOriginali: Set<String> = []
        try query("pragma table_info(originali)") { colonneOriginali.insert(Archivio.testo($0, 1) ?? "") }
        if !colonneOriginali.contains("scatto") { try esegui("alter table originali add column scatto text") }
        try esegui("create index if not exists originali_scatto on originali(scatto)")
    }

    deinit { sqlite3_close(db) }

    func errore(_ dove: String) -> NSError {
        NSError(domain: "FotoTag.Archivio", code: Int(sqlite3_errcode(db)),
                userInfo: [NSLocalizedDescriptionKey: "\(dove): " + String(cString: sqlite3_errmsg(db))])
    }

    func esegui(_ sql: String) throws {
        try coda.sync { if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { throw errore(sql.prefix(40).description) } }
    }

    enum Valore { case testo(String?), intero(Int64), reale(Double?), dati(Data?) }

    /// Esegue una query con parametri e passa ogni riga a `riga`.
    func query(_ sql: String, _ parametri: [Valore] = [], riga: (OpaquePointer) -> Void = { _ in }) throws {
        try coda.sync {
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { throw errore("prepare") }
            defer { sqlite3_finalize(st) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for (i, p) in parametri.enumerated() {
                let n = Int32(i + 1)
                switch p {
                case .testo(let s): if let s { sqlite3_bind_text(st, n, s, -1, transient) } else { sqlite3_bind_null(st, n) }
                case .intero(let v): sqlite3_bind_int64(st, n, v)
                case .reale(let v): if let v { sqlite3_bind_double(st, n, v) } else { sqlite3_bind_null(st, n) }
                case .dati(let d):
                    if let d { _ = d.withUnsafeBytes { sqlite3_bind_blob(st, n, $0.baseAddress, Int32(d.count), transient) } }
                    else { sqlite3_bind_null(st, n) }
                }
            }
            while true {
                let rc = sqlite3_step(st)
                if rc == SQLITE_ROW { riga(st!) } else if rc == SQLITE_DONE { break } else { throw errore("step") }
            }
        }
    }

    static func testo(_ st: OpaquePointer, _ i: Int32) -> String? {
        sqlite3_column_text(st, i).map { String(cString: $0) }
    }

    static func lista(_ s: String?) -> [String] {
        (s.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String]) ?? []
    }

    static func json(_ l: [String]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: l)) ?? Data("[]".utf8), as: UTF8.self)
    }

    // MARK: cartelle

    public func cartelle() throws -> [Cartella] {
        var out: [Cartella] = []
        try query("select id, percorso, segnalibro, profilo, usata_il, n_foto from cartelle order by percorso") { st in
            let blob = sqlite3_column_blob(st, 2).map { Data(bytes: $0, count: Int(sqlite3_column_bytes(st, 2))) }
            out.append(Cartella(id: sqlite3_column_int64(st, 0), percorso: Archivio.testo(st, 1) ?? "", segnalibro: blob,
                                profilo: Archivio.testo(st, 3) ?? Profilo.generico.id, usataIl: Archivio.testo(st, 4),
                                nFoto: sqlite3_column_type(st, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(st, 5))))
        }
        return out
    }

    /// Segna la cartella come usata adesso; ritorna il valore scritto.
    @discardableResult
    public func segnaUsata(_ id: Int64) throws -> String? {
        try query("update cartelle set usata_il = strftime('%Y-%m-%d %H:%M:%f', 'now') where id = ?", [.intero(id)])
        var t: String?
        try query("select usata_il from cartelle where id = ?", [.intero(id)]) { t = Archivio.testo($0, 0) }
        return t
    }

    /// File ▸ Apri recente ▸ Cancella menu: le cartelle restano.
    public func cancellaRecenti() throws { try query("update cartelle set usata_il = null") }

    @discardableResult
    public func aggiungiCartella(_ percorso: String, segnalibro: Data?, profilo: String = Profilo.generico.id) throws -> Int64 {
        try query("insert into cartelle(percorso, segnalibro, profilo) values(?, ?, ?) on conflict(percorso) do update set segnalibro = excluded.segnalibro",
                  [.testo(percorso), .dati(segnalibro), .testo(profilo)])
        var id: Int64 = 0
        try query("select id from cartelle where percorso = ?", [.testo(percorso)]) { id = sqlite3_column_int64($0, 0) }
        return id
    }

    /// Riga per una cartella senza foto proprie, per aprirla con tutte le sue sottocartelle: resta un passaggio
    /// dell'albero (n_foto 0). Se la cartella c'è già, non cambia nulla.
    public func aggiungiPassaggio(_ percorso: String, profilo: String) throws -> Int64 {
        try query("insert into cartelle(percorso, profilo, n_foto) values(?, ?, 0) on conflict(percorso) do nothing",
                  [.testo(percorso), .testo(profilo)])
        var id: Int64 = 0
        try query("select id from cartelle where percorso = ?", [.testo(percorso)]) { id = sqlite3_column_int64($0, 0) }
        return id
    }

    public struct Conteggi: Sendable, Hashable {
        public var totale = 0, analizzate = 0, daRivedere = 0, riviste = 0
    }

    /// Per ogni cartella (sottocartelle comprese): foto note, analizzate, da rivedere, riviste.
    /// Prima si conta per cartella della foto, poi si risale: con migliaia di cartelle un join sarebbe troppo lento.
    public func conteggi() throws -> [Int64: Conteggi] {
        var ids: [String: Int64] = [:]
        try query("select id, percorso from cartelle") { ids[Archivio.testo($0, 1) ?? ""] = sqlite3_column_int64($0, 0) }
        var perDir: [String: Conteggi] = [:]
        try query("select percorso, stato from foto") { st in
            let dir = ((Archivio.testo(st, 0) ?? "") as NSString).deletingLastPathComponent
            let s = Archivio.testo(st, 1)
            var c = perDir[dir] ?? Conteggi()
            c.totale += 1
            if s == StatoFoto.proposta.rawValue { c.daRivedere += 1; c.analizzate += 1 }
            if s == StatoFoto.rivista.rawValue { c.riviste += 1; c.analizzate += 1 }
            perDir[dir] = c
        }
        var out: [Int64: Conteggi] = [:]
        for (dir, c) in perDir {
            var d = dir
            while d.count > 1 {
                if let id = ids[d] {
                    var t = out[id] ?? Conteggi()
                    t.totale += c.totale; t.analizzate += c.analizzate; t.daRivedere += c.daRivedere; t.riviste += c.riviste
                    out[id] = t
                }
                d = (d as NSString).deletingLastPathComponent
            }
        }
        return out
    }

    /// Le code di lavoro di tutto l'archivio (sezione «Da fare» della barra laterale).
    public enum DaFare: String, CaseIterable, Sendable {
        case daRivedere, daScrivere, errori
        var condizione: String {
            switch self {
            case .daRivedere: return "stato = 'proposta'"
            case .daScrivere: return "stato = 'rivista' and (scritta_il is null or modificata > scritta_il)"
            case .errori: return "stato = 'errore'"
            }
        }
    }

    /// Quante foto in ogni coda, su tutto l'archivio.
    public func contaDaFare() throws -> [DaFare: Int] {
        var out: [DaFare: Int] = [:]
        for d in DaFare.allCases {
            try query("select count(*) from foto where \(d.condizione)") { out[d] = Int(sqlite3_column_int64($0, 0)) }
        }
        return out
    }

    /// Le foto di una coda, in ordine di percorso (le cartelle restano insieme).
    public func foto(daFare d: DaFare) throws -> [FotoRecord] {
        try leggiFoto("where \(d.condizione) order by percorso", [])
    }

    /// Conteggi per la diagnostica: cartelle, foto per stato, foto con embedding.
    public func riepilogo() throws -> [(String, Int)] {
        var out: [(String, Int)] = []
        try query("select count(*) from cartelle") { out.append(("cartelle", Int(sqlite3_column_int64($0, 0)))) }
        try query("select stato, count(*) from foto group by stato order by stato") {
            out.append(("foto «\(Archivio.testo($0, 0) ?? "")»", Int(sqlite3_column_int64($0, 1))))
        }
        try query("select count(*) from foto where embedding is not null") { out.append(("foto con embedding", Int(sqlite3_column_int64($0, 0)))) }
        return out
    }

    // MARK: foto

    /// Aggiunge al database i JPG nuovi della cartella (quelli già presenti restano come sono). Un file nuovo con
    /// la stessa impronta di una foto il cui percorso non esiste più è quella foto spostata o rinominata:
    /// si aggiorna il percorso e si tengono analisi, revisione ed embedding.
    /// L'impronta si legge solo se c'è una foto scomparsa della stessa dimensione: leggere la cartella resta veloce.
    public func sincronizza(cartella: Int64, file: [URL]) throws {
        var noti = Set<String>()
        try query("select percorso from foto where \(Archivio.sottoCartella)", [.intero(cartella), .intero(cartella)]) {
            noti.insert(Archivio.testo($0, 0) ?? "")
        }
        var scomparse: [String: [(id: Int64, impronta: String)]] = [:]  // dimensione → foto il cui file non c'è più
        var lette = false
        // una sola transazione: migliaia di foto nuove si registrano in un attimo. «immediate»: con due connessioni
        // una transazione che legge e poi scrive fallisce subito con «database is locked», senza aspettare
        try esegui("begin immediate")
        defer { try? esegui("commit") }
        for u in file where !noti.contains(u.path) {
            if !lette {
                lette = true
                let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser.path
                try query("select id, percorso, impronta from foto where impronta is not null") { st in
                    let p = Archivio.testo(st, 1) ?? "", i = Archivio.testo(st, 2) ?? ""
                    // su un disco staccato il file non è sparito: una copia altrove resta una foto a sé
                    if !fm.fileExists(atPath: p), fm.fileExists(atPath: Indicizzatore.radiceAccesso(di: p, home: home)),
                       let n = i.split(separator: "-").first {
                        scomparse[String(n), default: []].append((sqlite3_column_int64(st, 0), i))
                    }
                }
            }
            let n = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(String.init) ?? ""
            if let c = scomparse[n], let impronta = Immagini.impronta(u), let i = c.firstIndex(where: { $0.impronta == impronta }) {
                let vecchio = c[i].id
                scomparse[n]!.remove(at: i)
                try query("update foto set percorso = ?, cartella_id = ? where id = ?", [.testo(u.path), .intero(cartella), .intero(vecchio)])
                Diario.info("foto ritrovata con l'impronta: \(u.lastPathComponent) (id \(vecchio))")
                continue
            }
            try query("insert into foto(cartella_id, percorso) values(?, ?) on conflict(percorso) do nothing",
                      [.intero(cartella), .testo(u.path)])
        }
    }

    /// Toglie le foto ancora «da analizzare» che stanno in una sottocartella saltata (es. «cornici»): erano state
    /// elencate prima che si saltassero. Quelle già analizzate restano. Ritorna (tolte, rimaste analizzate).
    public func togliSaltate(cartella: Int64, saltate: [String]) throws -> (tolte: Int, analizzate: Int) {
        guard !saltate.isEmpty else { return (0, 0) }
        var radice = ""
        try query("select percorso from cartelle where id = ?", [.intero(cartella)]) { radice = Archivio.testo($0, 0) ?? "" }
        var daTogliere: [Int64] = [], analizzate = 0
        try query("select id, percorso, stato from foto where \(Archivio.sottoCartella)", [.intero(cartella), .intero(cartella)]) { st in
            let relativo = (Archivio.testo(st, 1) ?? "").dropFirst(radice.count + 1)
            guard relativo.split(separator: "/").dropLast().contains(where: { saltate.contains($0.lowercased()) }) else { return }
            if Archivio.testo(st, 2) == StatoFoto.daAnalizzare.rawValue { daTogliere.append(sqlite3_column_int64(st, 0)) } else { analizzate += 1 }
        }
        for id in daTogliere { try query("delete from foto where id = ?", [.intero(id)]) }
        return (daTogliere.count, analizzate)
    }

    /// Foto che stanno sotto la cartella (anche nelle sottocartelle, anche se aggiunte con un'altra cartella).
    /// Due parametri: l'id della cartella, due volte. substr e non like: «_» e «%» nei nomi restano lettera.
    static let sottoCartella = """
        substr(percorso, 1, (select length(percorso) + 1 from cartelle where id = ?)) = (select percorso || '/' from cartelle where id = ?)
        """

    /// Calcola le impronte mancanti delle foto di una cartella (da chiamare fuori dal thread principale).
    /// I file solo in cloud restano senza: si riprova alla prossima lettura.
    public func completaImpronte(cartella: Int64) throws {
        var senza: [(Int64, String)] = []
        try query("select id, percorso from foto where impronta is null and \(Archivio.sottoCartella)", [.intero(cartella), .intero(cartella)]) {
            senza.append((sqlite3_column_int64($0, 0), Archivio.testo($0, 1) ?? ""))
        }
        for (id, p) in senza {
            if let i = Immagini.impronta(URL(fileURLWithPath: p)) {
                try query("update foto set impronta = ? where id = ?", [.testo(i), .intero(id)])
            }
        }
    }

    /// La cartella è stata spostata o rinominata: tutti i percorsi passano sotto `nuovo`. Se `nuovo` è già
    /// nell'elenco, le foto si uniscono a quella cartella (le sue foto mai analizzate lasciano il posto alle vecchie).
    public func riconnetti(cartella id: Int64, a nuovo: String, segnalibro: Data?) throws {
        var vecchio = ""
        try query("select percorso from cartelle where id = ?", [.intero(id)]) { vecchio = Archivio.testo($0, 0) ?? "" }
        guard !vecchio.isEmpty, vecchio != nuovo else { return }
        let nuovoPercorso: Valore = .testo(nuovo)
        let taglio: Valore = .intero(Int64(vecchio.unicodeScalars.count + 1))
        var esistente: Int64?
        try query("select id from cartelle where percorso = ?", [nuovoPercorso]) { esistente = sqlite3_column_int64($0, 0) }
        guard let dest = esistente else {
            try query("update cartelle set percorso = ?, segnalibro = coalesce(?, segnalibro) where id = ?",
                      [nuovoPercorso, .dati(segnalibro), .intero(id)])
            try query("update foto set percorso = ? || substr(percorso, ?) where cartella_id = ?", [nuovoPercorso, taglio, .intero(id)])
            return
        }
        try query("""
            delete from foto where cartella_id = ? and stato = 'da analizzare'
            and percorso in (select ? || substr(percorso, ?) from foto where cartella_id = ?)
            """, [.intero(dest), nuovoPercorso, taglio, .intero(id)])
        try query("update or ignore foto set percorso = ? || substr(percorso, ?), cartella_id = ? where cartella_id = ?",
                  [nuovoPercorso, taglio, .intero(dest), .intero(id)])
        var resto = 0
        try query("select count(*) from foto where cartella_id = ?", [.intero(id)]) { resto = Int(sqlite3_column_int64($0, 0)) }
        if resto == 0 { try query("delete from cartelle where id = ?", [.intero(id)]) }
    }

    public func foto(cartella: Int64) throws -> [FotoRecord] {
        try leggiFoto("where \(Archivio.sottoCartella) order by percorso", [.intero(cartella), .intero(cartella)])
    }

    /// Tag dell'archivio per i suggerimenti: quelli delle foto confermate e quelli aggiunti a mano
    /// (anche sulle foto da rivedere); non le proposte del modello non ancora confermate.
    public func tagPerSuggerimenti() throws -> (archivio: [String: Int], manuali: [String: Int]) {
        var confermati: [[String]] = [], manuali: [[String]] = []
        try query("select parole, risposta, stato from foto where stato in ('proposta', 'rivista')") { st in
            let parole = Archivio.lista(Archivio.testo(st, 0))
            let m = Suggerimenti.manuali(parole: parole, risposta: Archivio.testo(st, 1))
            manuali.append(m)
            confermati.append(Archivio.testo(st, 2) == StatoFoto.rivista.rawValue ? parole : m)
        }
        return (Suggerimenti.conta(confermati), Suggerimenti.conta(manuali))
    }

    public func salvaImpronta(_ id: Int64, _ impronta: String) throws {
        try query("update foto set impronta = ? where id = ?", [.testo(impronta), .intero(id)])
    }

    // MARK: indice

    /// Radici a cui l'utente ha dato accesso (dischi o cartelle), col segnalibro e il profilo scelto per loro.
    public func accessi() throws -> [(percorso: String, segnalibro: Data?, profilo: String?)] {
        var out: [(percorso: String, segnalibro: Data?, profilo: String?)] = []
        try query("select percorso, segnalibro, profilo from accessi order by percorso") { st in
            let blob = sqlite3_column_blob(st, 1).map { Data(bytes: $0, count: Int(sqlite3_column_bytes(st, 1))) }
            out.append((Archivio.testo(st, 0) ?? "", blob, Archivio.testo(st, 2)))
        }
        return out
    }

    public func aggiungiAccesso(_ percorso: String, segnalibro: Data?, profilo: String? = nil) throws {
        try query("""
            insert into accessi(percorso, segnalibro, profilo) values(?, ?, ?)
            on conflict(percorso) do update set segnalibro = excluded.segnalibro, profilo = coalesce(excluded.profilo, accessi.profilo)
            """, [.testo(percorso), .dati(segnalibro), .testo(profilo)])
    }

    public func impostaProfiloAccesso(_ percorso: String, _ profilo: String) throws {
        try query("update accessi set profilo = ? where percorso = ?", [.testo(profilo), .testo(percorso)])
    }

    /// Le foto già indicizzate restano: togliere l'accesso non cancella analisi.
    /// Accessi senza regole, dati prima che le regole stessero qui: da ora restano fissi, qualunque sia il predefinito.
    public func fissaProfiliAccessi(_ profilo: String) throws {
        try query("update accessi set profilo = ? where profilo is null", [.testo(profilo)])
    }

    public func togliAccesso(_ percorso: String) throws { try query("delete from accessi where percorso = ?", [.testo(percorso)]) }

    /// Porta il database allo stato trovato su disco, in modo incrementale: nuove cartelle e foto, file cambiati
    /// (dimensione o data: si rifà l'impronta), cartelle e foto sparite. Le foto analizzate non si cancellano mai:
    /// se il file si è spostato, sincronizza le ricollega con l'impronta; se è sparito la riga resta.
    /// Con la radice non letta non cambia nulla; sotto i percorsi illeggibili non si toglie nulla.
    /// `avanzamento` arriva ogni 25 cartelle: l'albero può crescere mentre si lavora.
    /// `annidate`: altri accessi dentro questa radice (un disco in cloud sotto la cartella utente), che hanno il loro giro.
    public func applicaIndice(_ r: Indicizzatore.Risultato, profilo: String, saltate: [String], annidate: [String] = [],
                              avanzamento: (Int) -> Void = { _ in }) throws {
        guard r.letta else { return }
        let base = Albero.base(r.radice)
        func sotto(_ p: String) -> Bool { Albero.contiene(r.radice, p) && !annidate.contains { Albero.contiene($0, p) } }
        var noti: [String: (dimensione: Int?, mtime: Double?, id: Int64, stato: String?, cartella: Int64)] = [:]
        try query("select id, percorso, dimensione, mtime, stato, cartella_id from foto") { st in
            let p = Archivio.testo(st, 1) ?? ""
            guard sotto(p) else { return }
            noti[p] = (sqlite3_column_type(st, 2) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(st, 2)),
                       sqlite3_column_type(st, 3) == SQLITE_NULL ? nil : sqlite3_column_double(st, 3),
                       sqlite3_column_int64(st, 0), Archivio.testo(st, 4), sqlite3_column_int64(st, 5))
        }
        // i RAW collegati a un JPG restano una foto sola: non diventano righe a sé
        var collegati = Set<String>()
        try query("select raw from foto where raw is not null") { collegati.insert(Archivio.testo($0, 0) ?? "") }

        var trovate = Set<String>()
        var conteggio: [String: Int] = [:]
        for (n, (dir, tutti)) in r.perCartella.sorted(by: { $0.key < $1.key }).enumerated() {
            if n > 0, n % 25 == 0 { avanzamento(n) }
            let file = Indicizzatore.senzaCompagniRAW(tutti).filter { !collegati.contains($0.percorso) }
            guard !file.isEmpty else { continue }
            conteggio[dir] = file.count
            trovate.formUnion(file.map(\.percorso))
            try query("insert into cartelle(percorso, profilo, n_foto) values(?, ?, ?) on conflict(percorso) do update set n_foto = excluded.n_foto",
                      [.testo(dir), .testo(profilo), .intero(Int64(file.count))])
            var id: Int64 = 0
            try query("select id from cartelle where percorso = ?", [.testo(dir)]) { id = sqlite3_column_int64($0, 0) }
            let nuovi = file.filter { noti[$0.percorso] == nil }
            if !nuovi.isEmpty { try sincronizza(cartella: id, file: nuovi.map { URL(fileURLWithPath: $0.percorso) }) }
            let cambiati = file.filter { f in
                guard let n = noti[f.percorso] else { return true }
                return n.dimensione != f.dimensione || n.mtime != f.mtime
            }
            // foto registrate sotto una cartella madre, com'erano prima dell'indice
            let altrove = file.compactMap { f in noti[f.percorso].flatMap { $0.cartella == id ? nil : $0.id } }
            guard !cambiati.isEmpty || !altrove.isEmpty else { continue }
            try esegui("begin immediate")
            defer { try? esegui("commit") }
            for foto in altrove { try query("update foto set cartella_id = ? where id = ?", [.intero(id), .intero(foto)]) }
            for f in cambiati {
                // la prima volta si registrano e basta; se il file è cambiato davvero l'impronta va rifatta
                let eraNoto = noti[f.percorso]?.dimensione != nil
                try query("update foto set dimensione = ?, mtime = ?\(eraNoto ? ", impronta = null" : "") where percorso = ?",
                          [.intero(Int64(f.dimensione)), .reale(f.mtime), .testo(f.percorso)])
            }
        }

        // disco staccato durante il giro: quello che manca non è sparito
        guard FileManager.default.fileExists(atPath: r.radice) else { return }

        // foto sparite, saltate o di un formato non più ammesso: via solo quelle da analizzare; l'accesso negato non conta come sparizione
        func illeggibile(_ p: String) -> Bool { r.illeggibili.contains { p == $0 || p.hasPrefix($0 + "/") } }
        func inSaltata(_ p: String) -> Bool {
            p.dropFirst(base.count).split(separator: "/").dropLast().contains { saltate.contains($0.lowercased()) }
        }
        let daTogliere = noti.filter { p, n in
            !trovate.contains(p) && n.stato == StatoFoto.daAnalizzare.rawValue && !illeggibile(p)
                && (inSaltata(p) || !Immagini.estensioni.contains((p as NSString).pathExtension.lowercased())
                    || !FileManager.default.fileExists(atPath: p))
        }
        try esegui("begin immediate")
        defer { try? esegui("commit") }
        for (_, n) in daTogliere { try query("delete from foto where id = ?", [.intero(n.id)]) }

        // conteggio per cartella; una cartella sparita e senza più foto esce dal database
        var cartelle: [(id: Int64, percorso: String)] = []
        try query("select id, percorso from cartelle") { st in
            let p = Archivio.testo(st, 1) ?? ""
            if sotto(p) { cartelle.append((sqlite3_column_int64(st, 0), p)) }
        }
        for c in cartelle where !illeggibile(c.percorso) {
            // senza foto trovate restano quelle con del lavoro (file sparito, PNG già analizzato)
            var rimaste = conteggio[c.percorso] ?? 0
            if conteggio[c.percorso] == nil {
                try query("select count(*) from foto where cartella_id = ?", [.intero(c.id)]) { rimaste = Int(sqlite3_column_int64($0, 0)) }
            }
            try query("update cartelle set n_foto = ? where id = ?", [.intero(Int64(rimaste)), .intero(c.id)])
            if rimaste == 0, !FileManager.default.fileExists(atPath: c.percorso) { try query("delete from cartelle where id = ?", [.intero(c.id)]) }
        }
    }

    /// Foto con questi id (per i risultati della ricerca), in ordine di id.
    public func foto(ids: [Int64]) throws -> [FotoRecord] {
        guard !ids.isEmpty else { return [] }
        return try leggiFoto("where id in (\(ids.map { _ in "?" }.joined(separator: ",")))", ids.map { .intero($0) })
    }

    func leggiFoto(_ dove: String, _ parametri: [Valore]) throws -> [FotoRecord] {
        var out: [FotoRecord] = []
        try query("""
            select id, cartella_id, percorso, stato, parole, didascalia, scartate, secondi, percorso_analisi,
                   scritta_il, coalesce(modificata > scritta_il, 0), fissi, coalesce(fissi_modificati, 0), saturazione,
                   raw, raw_livello, coalesce(raw_manuale, 0), impronta
            from foto \(dove)
            """, parametri) { st in
            out.append(FotoRecord(
                id: sqlite3_column_int64(st, 0), cartellaID: sqlite3_column_int64(st, 1),
                percorso: Archivio.testo(st, 2) ?? "",
                stato: StatoFoto(rawValue: Archivio.testo(st, 3) ?? "") ?? .daAnalizzare,
                parole: Archivio.lista(Archivio.testo(st, 4)), didascalia: Archivio.testo(st, 5) ?? "",
                scartate: Archivio.lista(Archivio.testo(st, 6)),
                secondi: sqlite3_column_type(st, 7) == SQLITE_NULL ? nil : sqlite3_column_double(st, 7),
                percorsoAnalisi: Archivio.testo(st, 8), scrittaIl: Archivio.testo(st, 9),
                modificataDopo: sqlite3_column_int(st, 10) != 0,
                fissi: Archivio.testo(st, 11).flatMap { try? JSONDecoder().decode(TagFissi.self, from: Data($0.utf8)) },
                fissiModificati: sqlite3_column_int(st, 12) != 0,
                saturazione: sqlite3_column_type(st, 13) == SQLITE_NULL ? nil : sqlite3_column_double(st, 13),
                raw: Archivio.testo(st, 14),
                rawLivello: Archivio.testo(st, 15).flatMap(Originali.Livello.init(rawValue:)) ?? .nessuno,
                rawManuale: sqlite3_column_int(st, 16) != 0,
                impronta: Archivio.testo(st, 17)))
        }
        return out
    }

    public func salvaAnalisi(_ id: Int64, parole: [String], didascalia: String, scartate: [String],
                             risposta: String, secondi: Double, percorso: String, lingua: String) throws {
        try query("""
            update foto set stato = 'proposta', parole = ?, didascalia = ?, scartate = ?, risposta = ?, secondi = ?,
            percorso_analisi = ?, lingua = ?, analizzata = datetime('now'), modificata = datetime('now') where id = ?
            """, [.testo(Archivio.json(parole)), .testo(didascalia), .testo(Archivio.json(scartate)), .testo(risposta),
                  .reale(secondi), .testo(percorso), .testo(lingua), .intero(id)])
    }

    /// Quello che serve per scrivere una foto: risposta grezza del modello e ciò che FotoTag ha già scritto.
    public func datiScrittura(_ id: Int64) throws -> (risposta: String?, parole: [String], gerarchia: [String], didascalia: String?) {
        var out: (String?, [String], [String], String?) = (nil, [], [], nil)
        try query("select risposta, parole_scritte, gerarchia_scritta, didascalia_scritta from foto where id = ?", [.intero(id)]) { st in
            out = (Archivio.testo(st, 0), Archivio.lista(Archivio.testo(st, 1)), Archivio.lista(Archivio.testo(st, 2)),
                   Archivio.testo(st, 3))
        }
        return out
    }

    public func salvaScrittura(_ id: Int64, parole: [String], gerarchia: [String], didascalia: String?, file: [String]) throws {
        try query("""
            update foto set scritta_il = datetime('now'), parole_scritte = ?, gerarchia_scritta = ?,
            didascalia_scritta = coalesce(?, didascalia_scritta), file_scritti = ? where id = ?
            """, [.testo(Archivio.json(parole)), .testo(Archivio.json(gerarchia)), .testo(didascalia),
                  .testo(Archivio.json(file)), .intero(id)])
    }

    // MARK: tag fissi

    /// Salva i tag fissi calcolati (non tocca quelli corretti a mano, a meno di `forza`).
    public func salvaFissi(_ id: Int64, _ f: TagFissi, saturazione: Double?, manuale: Bool = false) throws {
        let j = String(decoding: try JSONEncoder().encode(f), as: UTF8.self)
        if manuale {
            try query("""
                update foto set fissi = ?, fissi_modificati = 1,
                modificata = case when fissi is not ? then datetime('now') else modificata end where id = ?
                """, [.testo(j), .testo(j), .intero(id)])
        } else {
            try query("""
                update foto set fissi = ?, saturazione = coalesce(?, saturazione),
                modificata = case when fissi is not ? and scritta_il is not null then datetime('now') else modificata end
                where id = ? and coalesce(fissi_modificati, 0) = 0
                """, [.testo(j), .reale(saturazione), .testo(j), .intero(id)])
        }
    }

    // MARK: originali

    public struct RadiceOriginali: Identifiable, Hashable, Sendable {
        public let id: Int64
        public let percorso: String
        public let segnalibro: Data?
        public var soloRaw: Bool
        public var aggiornata: String?
        public var voci: Int
        public var profilo: String
    }

    public func radiciOriginali() throws -> [RadiceOriginali] {
        var out: [RadiceOriginali] = []
        try query("select r.id, r.percorso, r.segnalibro, r.solo_raw, r.aggiornata, (select count(*) from originali o where o.radice_id = r.id), r.profilo from radici_originali r order by r.percorso") { st in
            out.append(RadiceOriginali(id: sqlite3_column_int64(st, 0), percorso: Archivio.testo(st, 1) ?? "",
                                       segnalibro: sqlite3_column_blob(st, 2).map { Data(bytes: $0, count: Int(sqlite3_column_bytes(st, 2))) },
                                       soloRaw: sqlite3_column_int(st, 3) != 0, aggiornata: Archivio.testo(st, 4),
                                       voci: Int(sqlite3_column_int64(st, 5)),
                                       profilo: Archivio.testo(st, 6) ?? Profilo.generico.id))
        }
        return out
    }

    public func aggiungiRadiceOriginali(_ percorso: String, segnalibro: Data?, soloRaw: Bool, profilo: String) throws {
        try query("insert into radici_originali(percorso, segnalibro, solo_raw, profilo) values(?, ?, ?, ?) on conflict(percorso) do update set profilo = excluded.profilo",
                  [.testo(percorso), .dati(segnalibro), .intero(soloRaw ? 1 : 0), .testo(profilo)])
    }

    public func impostaProfiloRadice(_ id: Int64, _ profilo: String) throws {
        try query("update radici_originali set profilo = ? where id = ?", [.testo(profilo), .intero(id)])
    }

    public func impostaSoloRaw(_ id: Int64, _ v: Bool) throws {
        try query("update radici_originali set solo_raw = ? where id = ?", [.intero(v ? 1 : 0), .intero(id)])
    }

    public func rimuoviRadiceOriginali(_ id: Int64) throws {
        try query("delete from originali where radice_id = ?", [.intero(id)])
        try query("delete from radici_originali where id = ?", [.intero(id)])
    }

    /// Sostituisce l'indice di una cartella degli originali (in una transazione).
    public func salvaIndice(radice id: Int64, _ voci: [Originali.Voce]) throws {
        try esegui("begin")
        do {
            try query("delete from originali where radice_id = ?", [.intero(id)])
            for v in voci {
                try query("insert or replace into originali(percorso, radice, ext, anno, mese, mtime, radice_id, scatto) values(?, ?, ?, ?, ?, ?, ?, ?)",
                          [.testo(v.percorso), .testo(v.radice), .testo(v.ext), v.anno.map { .intero(Int64($0)) } ?? .testo(nil),
                           v.mese.map { .intero(Int64($0)) } ?? .testo(nil), .reale(v.mtime), .intero(id), .testo(v.scatto)])
            }
            try query("update radici_originali set aggiornata = datetime('now') where id = ?", [.intero(id)])
            try esegui("commit")
        } catch { try? esegui("rollback"); throw error }
    }

    /// Impronte già lette di una cartella degli originali: percorso → (mtime, impronta). Si rileggono solo i file cambiati.
    public func scattiNoti(radice id: Int64) throws -> [String: (mtime: Double, scatto: String)] {
        var out: [String: (Double, String)] = [:]
        try query("select percorso, mtime, scatto from originali where radice_id = ? and scatto is not null", [.intero(id)]) {
            out[Archivio.testo($0, 0) ?? ""] = (sqlite3_column_double($0, 1), Archivio.testo($0, 2) ?? "")
        }
        return out
    }

    /// Originali con questa impronta dello scatto (D66).
    public func originaliPerScatto(_ scatto: String) throws -> [String] {
        var out: [String] = []
        try query("select percorso from originali where scatto = ?", [.testo(scatto)]) { out.append(Archivio.testo($0, 0) ?? "") }
        return out
    }

    /// RAW dell'indice di cui non si conosce l'impronta (di solito quelli solo nel disco in cloud).
    public func originaliSenzaScatto() throws -> [String] {
        let ext = Originali.soloRAW.map { "'\($0)'" }.joined(separator: ",")
        var out: [String] = []
        try query("select percorso from originali where scatto is null and ext in (\(ext))") { out.append(Archivio.testo($0, 0) ?? "") }
        return out
    }

    public func salvaScatto(_ percorso: String, _ scatto: String) throws {
        try query("update originali set scatto = ? where percorso = ?", [.testo(scatto), .testo(percorso)])
    }

    public func candidatiOriginali(radice r: String) throws -> [Originali.Voce] {
        var out: [Originali.Voce] = []
        try query("select percorso, radice, ext, anno, mese, mtime from originali where radice = ?", [.testo(r)]) { st in
            out.append(Originali.Voce(percorso: Archivio.testo(st, 0) ?? "", radice: Archivio.testo(st, 1) ?? "",
                                      ext: Archivio.testo(st, 2) ?? "",
                                      anno: sqlite3_column_type(st, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(st, 3)),
                                      mese: sqlite3_column_type(st, 4) == SQLITE_NULL ? nil : Int(sqlite3_column_int(st, 4)),
                                      mtime: sqlite3_column_double(st, 5)))
        }
        return out
    }

    public func salvaOriginale(_ id: Int64, raw: String?, livello: Originali.Livello, manuale: Bool) throws {
        if manuale {
            try query("update foto set raw = ?, raw_livello = ?, raw_manuale = 1 where id = ?",
                      [.testo(raw), .testo(livello.rawValue), .intero(id)])
        } else {
            try query("update foto set raw = ?, raw_livello = ? where id = ? and coalesce(raw_manuale, 0) = 0",
                      [.testo(raw), .testo(livello.rawValue), .intero(id)])
        }
    }

    // MARK: ricerca

    /// Foto senza embedding SigLIP (da indicizzare per la ricerca).
    public func senzaEmbedding() throws -> [(id: Int64, percorso: String, impronta: String?)] {
        var out: [(Int64, String, String?)] = []
        try query("select id, percorso, impronta from foto where embedding is null order by id") {
            out.append((sqlite3_column_int64($0, 0), Archivio.testo($0, 1) ?? "", Archivio.testo($0, 2)))
        }
        return out
    }

    /// Cambia a ogni modifica fatta da questa connessione: basta a sapere se le voci della ricerca vanno rilette.
    public func versione() -> Int32 { coda.sync { sqlite3_total_changes(db) } }

    public func salvaEmbedding(_ id: Int64, _ e: [Float]) throws {
        let d = e.withUnsafeBufferPointer { Data(buffer: $0) }
        try query("update foto set embedding = ? where id = ?", [.dati(d), .intero(id)])
    }

    public func vociRicerca() throws -> [Ricerca.Voce] {
        var out: [Ricerca.Voce] = []
        try query("select id, percorso, parole, didascalia, embedding from foto where embedding is not null") { st in
            let n = Int(sqlite3_column_bytes(st, 4)) / MemoryLayout<Float>.size
            var e = [Float](repeating: 0, count: n)
            if let p = sqlite3_column_blob(st, 4) { _ = e.withUnsafeMutableBytes { memcpy($0.baseAddress, p, n * 4) } }
            out.append(Ricerca.Voce(id: sqlite3_column_int64(st, 0), percorso: Archivio.testo(st, 1) ?? "",
                                    parole: Archivio.lista(Archivio.testo(st, 2)), didascalia: Archivio.testo(st, 3) ?? "",
                                    embedding: e))
        }
        return out
    }

    public func segnaErrore(_ id: Int64, messaggio: String) throws {
        try query("update foto set stato = 'errore', risposta = ? where id = ?", [.testo(messaggio), .intero(id)])
    }

    /// Modifiche dell'utente: tag, didascalia, stato.
    public func salvaRevisione(_ id: Int64, parole: [String], didascalia: String, stato: StatoFoto) throws {
        // «modificata» cambia solo se cambiano tag o didascalia (serve a sapere cosa va riscritto nei file)
        try query("""
            update foto set modificata = case when parole is not ?1 or didascalia is not ?2 then datetime('now') else modificata end,
            parole = ?1, didascalia = ?2, stato = ?3 where id = ?4
            """,
                  [.testo(Archivio.json(parole)), .testo(didascalia), .testo(stato.rawValue), .intero(id)])
    }
}
