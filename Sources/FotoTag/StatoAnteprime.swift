import AppKit
import FotoTagCore
import SwiftUI

/// Anteprime delle foto analizzate, per vedere quelle del BeeStation senza scaricarle (Impostazioni ▸
/// Generali ▸ Anteprime). Mai download o letture sincrone di file in cloud dal thread principale.
extension Stato {
    static var salvaAnteprimeImpostato: Bool { UserDefaults.standard.object(forKey: "salvaAnteprime") as? Bool ?? true }
    static var latoAnteprimeImpostato: Int {
        let l = UserDefaults.standard.integer(forKey: "latoAnteprime")
        return Anteprime.lati.contains(l) ? l : Anteprime.latoPredefinito
    }
    static var cartellaAnteprimeImpostata: URL {
        UserDefaults.standard.string(forKey: "cartellaAnteprime").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? Anteprime.cartellaPredefinita()
    }

    /// Dopo l'analisi la foto è sul Mac: impronta e anteprima, fuori dal thread principale.
    func salvaAnteprima(_ f: FotoRecord) async {
        guard Stato.salvaAnteprimeImpostato, let archivio else { return }
        let (u, lato, dest, id) = (f.url, Stato.latoAnteprimeImpostato, Stato.cartellaAnteprimeImpostata, f.id)
        let impronta = await Task.detached(priority: .utility) { () -> String? in
            guard let i = Immagini.impronta(u) else { return nil }
            do { try Anteprime.salva(da: u, impronta: i, lato: lato, in: dest) } catch {
                Diario.errore("anteprima di \(u.lastPathComponent): \(error.localizedDescription)")
            }
            return i
        }.value
        guard let impronta else { return }
        try? archivio.salvaImpronta(id, impronta)
        if let i = foto.firstIndex(where: { $0.id == id }) { foto[i].impronta = impronta }
    }

    /// Menu della cartella ▸ Crea anteprime mancanti: per le foto analizzate senza anteprima. Le foto del disco
    /// in cloud si scaricano (in modo asincrono), si salva l'anteprima e si libera di nuovo il download.
    func creaAnteprimeMancanti(_ c: Cartella) {
        guard let archivio, indiceInCorso == nil else { return }
        let (lato, dest) = (Stato.latoAnteprimeImpostato, Stato.cartellaAnteprimeImpostata)
        let tutte = ((try? archivio.foto(cartella: c.id)) ?? []).filter { $0.stato != .daAnalizzare && $0.stato != .errore }
        let mancanti = tutte.filter { Anteprime.trova(impronta: $0.impronta, in: dest) == nil }
        guard !mancanti.isEmpty else { notizia = String(localized: "Tutte le foto analizzate di «\(c.nome)» hanno già l'anteprima."); return }
        Task {
            var fatte = 0, nonScaricate = 0
            defer { indiceInCorso = nil }
            for (n, f) in mancanti.enumerated() {
                indiceInCorso = String(localized: "Anteprime di \(c.nome): \(n + 1) di \(mancanti.count)")
                let eraInCloud = Immagini.daScaricare(f.url)
                if eraInCloud, await !Immagini.scarica(f.url, attesa: 60) { nonScaricate += 1; continue }
                let u = f.url
                let impronta = await Task.detached(priority: .utility) { () -> String? in
                    guard let i = Immagini.impronta(u), (try? Anteprime.salva(da: u, impronta: i, lato: lato, in: dest)) != nil else { return nil }
                    return i
                }.value
                if eraInCloud { Immagini.libera(u) }
                guard let impronta else { continue }
                try? archivio.salvaImpronta(f.id, impronta)
                if let i = foto.firstIndex(where: { $0.id == f.id }) { foto[i].impronta = impronta }
                fatte += 1
            }
            Diario.info("anteprime di \(c.nome): \(fatte) create, \(nonScaricate) non scaricate")
            notizia = String(localized: "Anteprime di «\(c.nome)»: \(fatte) create")
                + (nonScaricate > 0 ? String(localized: ", \(nonScaricate) foto non sono arrivate dal disco in cloud (riprova più tardi).") : ".")
        }
    }
}

/// Impostazioni ▸ Generali ▸ Anteprime.
struct SezioneAnteprime: View {
    @EnvironmentObject var stato: Stato
    @AppStorage("salvaAnteprime") private var salva = true
    @AppStorage("latoAnteprime") private var lato = Anteprime.latoPredefinito
    @AppStorage("cartellaAnteprime") private var cartella = Anteprime.cartellaPredefinita().path
    @State private var campioni: [Anteprime.Campione]?

    var body: some View {
        Section("Anteprime") {
            Toggle("Salva un'anteprima di ogni foto analizzata", isOn: $salva)
                .help("Serve a vedere le foto dei dischi in cloud senza scaricarle")
            Picker("Lato lungo", selection: $lato) {
                ForEach(Anteprime.lati, id: \.self) { Text("\($0) px").tag($0) }
            }
            if let campioni { Text(stima(campioni)).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Text("Dove")
                Spacer()
                Text(cartella).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(cartella)
                Button("Cambia…") { scegli() }
            }
            if poco { Text("Sul disco interno restano meno di 10 GB: conviene una cartella sul disco esterno.").font(.caption).foregroundStyle(.secondary) }
        }
        .task(id: cartella) {
            let c = URL(fileURLWithPath: cartella)
            campioni = await Task.detached(priority: .utility) { Anteprime.campioni(in: c) }.value
        }
    }

    /// «circa 120 KB a foto, per 5.375 foto circa 650 MB», dal peso vero delle anteprime già salvate.
    func stima(_ c: [Anteprime.Campione]) -> String {
        let n = stato.conteggi.values.reduce(0) { $0 + $1.totale }
        let s = Anteprime.stima(c, lato: lato, foto: n)
        return String(localized: "circa \(s.kbAFoto) KB a foto, per \(n.formatted()) foto circa \(s.totaleMB.formatted()) MB")
    }

    var poco: Bool {
        let casa = FileManager.default.homeDirectoryForCurrentUser
        let liberi = (try? casa.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? .max
        return liberi < 10_000_000_000 && !cartella.hasPrefix("/Volumes/")
    }

    func scegli() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = String(localized: "Scegli")
        p.message = String(localized: "Dove salvare le anteprime delle foto (quelle già salvate restano dove sono).")
        if p.runModal() == .OK, let u = p.url { cartella = u.path }
    }
}
