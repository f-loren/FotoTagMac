import FotoTagCore
import SwiftUI

/// Un gruppo della griglia: una sottocartella, o una cartella nei risultati della ricerca.
struct GruppoFoto: Identifiable {
    let id: String
    let nome: String
    let madre: String?
    var foto: [FotoRecord]
}

/// Tag fissi: calcolo con il profilo della cartella, correzioni a mano, tabella delle pellicole.
extension Stato {
    var cartellaCorrente: Cartella? { cartelle.first { $0.id == cartellaScelta } }

    func profilo(per f: FotoRecord) -> Profilo { profilo(id: profiloID(di: f.percorso)) }

    /// Un profilo tolto o mai importato vale come Generico; l'id resta nel database, così reimportandolo torna.
    func profilo(id: String) -> Profilo { profili.first { $0.id == id } ?? profili[0] }
    func idValido(_ id: String) -> String { profilo(id: id).id }

    /// Foto che passano il filtro per stato, nell'ordine della griglia (anche per frecce e «vai alla prossima»).
    /// In una coda «Da fare» il filtro non vale: la coda è già filtrata, e la foto appena confermata deve restare.
    var fotoVisibili: [FotoRecord] { filtro == .tutte || raccolta != nil ? foto : foto.filter { filtro.ammette($0.stato) } }

    /// Foto della griglia divise per sottocartella (percorso relativo; la cartella stessa col suo nome);
    /// nei risultati della ricerca, per cartella con la madre accanto («gothic 12 2025 > dicembre»).
    var gruppiFoto: [GruppoFoto] {
        let visibili = Dictionary(uniqueKeysWithValues: fotoVisibili.map { ($0.id, $0) })
        if inRisultati {
            return gruppiRisultati.compactMap { g in
                let f = g.ids.compactMap { visibili[$0] }
                return f.isEmpty ? nil : GruppoFoto(id: g.cartella, nome: g.nome, madre: g.madre, foto: f)
            }
        }
        guard let c = cartellaCorrente else { return [] }
        var out: [GruppoFoto] = []
        for f in fotoVisibili {
            let dir = (f.percorso as NSString).deletingLastPathComponent
            let nome = dir.hasPrefix(c.percorso + "/") ? String(dir.dropFirst(c.percorso.count + 1)) : c.nome
            if out.last?.nome == nome { out[out.count - 1].foto.append(f) } else { out.append(GruppoFoto(id: dir, nome: nome, madre: nil, foto: [f])) }
        }
        return out
    }

    /// Calcola i tag fissi di una foto già scaricata (EXIF, saturazione, percorso). Lento solo per la miniatura.
    nonisolated static func calcolaFissi(_ url: URL, profilo: Profilo, pellicole: TabellaPellicole,
                                         saturazioneNota: Double?, originale: String?) -> (TagFissi, Double?) {
        let e = CalcoloFissi.exif(url)
        let sat = saturazioneNota ?? Immagini.miniatura(url, lato: 512).flatMap(CalcoloFissi.saturazione)
        return (CalcoloFissi.calcola(percorso: url.path, profilo: profilo, pellicole: pellicole, exif: e, saturazione: sat,
                                     originale: originale), sat)
    }

    func aggiornaFissi(_ f: FotoRecord) async {
        guard let archivio else { return }
        let p = profilo(per: f), (pell, url, sat) = (p.tabella, f.url, f.saturazione)
        if Immagini.daScaricare(url) { return }
        // 1. originale (se non scelto a mano): nome + data di scatto + cartella, come il prototipo
        var raw = f.raw, livello = f.rawLivello
        if !f.rawManuale {
            let e = await Task.detached { CalcoloFissi.exif(url) }.value
            (raw, livello) = trovaOriginale(f, scatto: e.dataScatto, impronta: e.scatto, profilo: p)
            try? archivio.salvaOriginale(f.id, raw: raw, livello: livello, manuale: false)
            if let i = foto.firstIndex(where: { $0.id == f.id }) { foto[i].raw = raw; foto[i].rawLivello = livello }
        }
        // 2. tag fissi; le cartelle dell'originale contano solo se il collegamento è affidabile
        guard !f.fissiModificati else { return }
        let o = (f.rawManuale || livello == .sicuro || livello == .probabile) ? raw : nil
        let (t, s) = await Task.detached(priority: .utility) {
            Stato.calcolaFissi(url, profilo: p, pellicole: pell, saturazioneNota: sat, originale: o)
        }.value
        try? archivio.salvaFissi(f.id, t, saturazione: s)
        if let i = foto.firstIndex(where: { $0.id == f.id }) { foto[i].fissi = t; foto[i].saturazione = s ?? foto[i].saturazione }
    }

    func ricalcolaFissi() {
        let quali = foto.filter { $0.stato != .daAnalizzare }
        lavoroFissi?.cancel()   // un giro vecchio non deve scrivere tag con le regole di prima
        lavoroFissi = Task { for f in quali { if Task.isCancelled { return }; await aggiornaFissi(f) } }
    }

    /// Correzione a mano dello stesso campo su più foto (annullabile in un passo: «Correggi origine (14 foto)»).
    func correggiFissi(_ quali: [FotoRecord], campo: String, _ cambia: (inout TagFissi) -> Void) {
        var prima: [FotoRecord] = [], dopo: [FotoRecord] = []
        for f in quali {
            guard let i = foto.firstIndex(where: { $0.id == f.id }), var t = foto[i].fissi else { continue }
            prima.append(foto[i])
            cambia(&t)
            try? archivio?.salvaFissi(f.id, t, saturazione: nil, manuale: true)
            foto[i].fissi = t
            foto[i].fissiModificati = true
            dopo.append(foto[i])
        }
        guard !dopo.isEmpty else { return }
        registraAnnulla(NomiAzioni.correggi(campo, foto: dopo.count), prima: prima, dopo: dopo)
    }

    /// Correzione a mano dall'utente (annullabile: «Correggi rullino»…).
    func correggiFissi(_ f: FotoRecord, _ t: TagFissi, campo: String = "tag fissi") {
        guard let prima = foto.first(where: { $0.id == f.id }) else {
            try? archivio?.salvaFissi(f.id, t, saturazione: nil, manuale: true)
            return
        }
        try? archivio?.salvaFissi(f.id, t, saturazione: nil, manuale: true)
        if let i = foto.firstIndex(where: { $0.id == f.id }) { foto[i].fissi = t; foto[i].fissiModificati = true }
        var dopo = prima
        dopo.fissi = t
        dopo.fissiModificati = true
        registraAnnulla(NomiAzioni.correggi(campo), prima: [prima], dopo: [dopo])
    }

    /// Salva i profili e rifà ciò che ne dipende: tag fissi delle foto aperte (non quelli corretti a mano) e indice.
    func salvaProfili(_ nuovi: [Profilo]) {
        guard nuovi != profili else { return }
        let regole = { (p: [Profilo]) in p.map { q in var q = q; q.nome = ""; q.descrizione = ""; return q } }
        let (cambiaRegole, cambiaSaltate) = (regole(nuovi) != regole(profili), nuovi.map(\.sottocartelleSaltate) != profili.map(\.sottocartelleSaltate))
        profili = nuovi
        if profiliBloccati { messaggio = String(localized: "Profili non salvati: il file dei profili non si è letto all'avvio.") } else {
            do { try Profilo.salva(nuovi) } catch { messaggio = String(localized: "Profili non salvati: \(error.localizedDescription)") }
        }
        if cambiaRegole { ricalcolaFissi() }
        if cambiaSaltate { indicizza() }
    }
}

extension Profilo {
    /// D70: nome e descrizione del profilo predefinito nella lingua dell'interfaccia, finché l'utente non li cambia.
    var nomeVisto: String { id == Profilo.generico.id && nome == Profilo.generico.nome ? String(localized: "Generico") : nome }
    var descrizioneVista: String {
        id == Profilo.generico.id && descrizione == Profilo.generico.descrizione
            ? String(localized: "Data dallo scatto (EXIF), nome della cartella come tag, pellicola solo con indizi chiari.") : descrizione
    }
}
