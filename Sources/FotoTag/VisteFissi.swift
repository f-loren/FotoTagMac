import FotoTagCore
import SwiftUI

/// Gruppo «Tag fissi» nella revisione: origine, tono, data, rullino, pellicola, contesto. Correggibili a mano.
struct SezioneFissi: View {
    @EnvironmentObject var stato: Stato
    @Binding var foto: FotoRecord

    var body: some View {
        if let t = foto.fissi {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tag fissi").font(.subheadline).foregroundStyle(.secondary)
                    Text("da cartella, EXIF e colori").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if foto.fissiModificati { Text("corretti a mano").font(.caption).foregroundStyle(.secondary) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    riga("Origine", "origine", t) {
                        Picker("", selection: legame(\.origine)) {
                            // niente «non so»: è l'una o l'altra; le incerte non ne mostrano nessuna, con «da verificare»
                            Text("analogica").tag(String?.some("analogica"))
                            Text("digitale").tag(String?.some("digitale"))
                        }.labelsHidden().pickerStyle(.segmented)
                    }
                    riga("Tono", "tono", t) {
                        Picker("", selection: legame(\.biancoNero)) {
                            Text("bianco e nero").tag(Bool?.some(true))
                            Text("colore").tag(Bool?.some(false))
                        }.labelsHidden().pickerStyle(.segmented)
                    }
                    riga("Data", "data", t) {
                        VStack(alignment: .leading, spacing: 2) {
                            CampoTesto(valore: t.testoData, suggerimento: "AAAA, AAAA-MM o AAAA-MM-GG") { leggiData($0) }
                            if let d = t.digitalizzata {
                                // salvata come «3 ottobre 2025»: il mese si mostra nella lingua dell'interfaccia
                                let data = d.split(separator: " ").map { w in Contesto.mesi.firstIndex(of: String(w)).map { Calendar.current.monthSymbols[$0] } ?? String(w) }.joined(separator: " ")
                                Text("La cartella indica la digitalizzazione (\(data)), non lo scatto.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if t.origine != "digitale" {
                        riga("Rullino", nil, t) {
                            CampoTesto(valore: t.rullini.joined(separator: ", "), suggerimento: "es. 1048") { modifica("rullino") { $0.rullini = lista($1) }($0) }
                        }
                    }
                    riga("Pellicola", "pellicola", t) {
                        CampoTesto(valore: t.pellicole.joined(separator: ", "), suggerimento: "es. Ilford HP5 Plus 400") { modifica("pellicola") { $0.pellicole = lista($1) }($0) }
                    }
                    if t.origine != "digitale" {
                        riga("Esposta a", nil, t) {
                            CampoTesto(valore: t.tiraggio.map(String.init) ?? "", suggerimento: "ISO di esposizione") { modifica("esposizione") { $0.tiraggio = Int($1) }($0) }
                        }
                    }
                    riga("Contesto", nil, t) {
                        CampoTesto(valore: t.contesto.joined(separator: ", "), suggerimento: "luogo, evento…") { modifica("contesto") { $0.contesto = lista($1) }($0) }
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))
        }
    }

    @ViewBuilder
    func riga<C: View>(_ titolo: LocalizedStringKey, _ chiave: String?, _ t: TagFissi, @ViewBuilder _ contenuto: () -> C) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(titolo).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
            contenuto().frame(maxWidth: .infinity, alignment: .leading)
            if let chiave, t.daVerificare.contains(chiave) || (chiave == "origine" && t.origine == nil) {
                Button { modifica(chiave) { t, _ in t.daVerificare.remove(chiave) }("") } label: {
                    Label { Text("da verificare").foregroundStyle(.secondary) } icon: {
                        Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
                    }
                    .font(.caption).fixedSize()
                }
                .buttonStyle(.plain)
                .help("Valore incerto: correggilo o clicca per confermarlo")
            }
        }
    }

    /// Applica una modifica ai tag fissi e la salva come correzione a mano.
    func modifica(_ campo: String = "tag fissi", _ cambia: @escaping (inout TagFissi, String) -> Void) -> (String) -> Void {
        { testo in
            guard var t = foto.fissi else { return }
            cambia(&t, testo)
            foto.fissi = t
            foto.fissiModificati = true
            stato.correggiFissi(foto, t, campo: campo)
        }
    }

    func legame<V>(_ kp: WritableKeyPath<TagFissi, V>) -> Binding<V> {
        Binding(get: { foto.fissi![keyPath: kp] }, set: { v in
            let chiave = kp == \TagFissi.origine ? "origine" : "tono"
            modifica(chiave) { t, _ in t[keyPath: kp] = v; t.daVerificare.remove(chiave) }("")
        })
    }

    func lista(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func leggiData(_ s: String) { modifica("data") { t, testo in t.impostaData(testo) }(s) }
}

/// Tag fissi nella revisione di più foto: ogni campo mostra il valore se è uguale in tutte, altrimenti
/// «valori diversi»; una modifica vale per tutte le foto (annullabile: «Correggi origine (14 foto)»).
struct SezioneFissiMultipla: View {
    @EnvironmentObject var stato: Stato
    let quali: [FotoRecord]

    var body: some View {
        let fissi = quali.compactMap(\.fissi)
        if !fissi.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tag fissi delle foto selezionate").font(.subheadline).foregroundStyle(.secondary)
                riga("Origine", ValoreComune(fissi.map(\.origine)), daVerificare: fissi.contains { $0.origine == nil }) {
                    Picker("", selection: Binding(get: { ValoreComune(fissi.map(\.origine)).valore ?? nil }, set: { v in
                        guard let v else { return }
                        stato.correggiFissi(quali, campo: "origine") { $0.origine = v; $0.daVerificare.remove("origine") }
                    })) {
                        Text("analogica").tag(String?.some("analogica"))
                        Text("digitale").tag(String?.some("digitale"))
                    }.labelsHidden().pickerStyle(.segmented)
                }
                riga("Tono", ValoreComune(fissi.map(\.biancoNero)), daVerificare: false) {
                    Picker("", selection: Binding(get: { ValoreComune(fissi.map(\.biancoNero)).valore ?? nil }, set: { v in
                        guard let v else { return }
                        stato.correggiFissi(quali, campo: "tono") { $0.biancoNero = v; $0.daVerificare.remove("tono") }
                    })) {
                        Text("bianco e nero").tag(Bool?.some(true))
                        Text("colore").tag(Bool?.some(false))
                    }.labelsHidden().pickerStyle(.segmented)
                }
                testo("Data", "data", fissi.map(\.testoData), "AAAA, AAAA-MM o AAAA-MM-GG") { t, s in t.impostaData(s) }
                testo("Rullino", "rullino", fissi.map { $0.rullini.joined(separator: ", ") }, "es. 1048") { t, s in t.rullini = lista(s) }
                testo("Pellicola", "pellicola", fissi.map { $0.pellicole.joined(separator: ", ") }, "es. Ilford HP5 Plus 400") { t, s in
                    t.pellicole = lista(s)
                    t.daVerificare.remove("pellicola")
                }
                testo("Esposta a", "esposizione", fissi.map { $0.tiraggio.map(String.init) ?? "" }, "ISO di esposizione") { t, s in t.tiraggio = Int(s) }
                testo("Contesto", "contesto", fissi.map { $0.contesto.joined(separator: ", ") }, "luogo, evento…") { t, s in t.contesto = lista(s) }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))
        }
    }

    func riga<T: Equatable, C: View>(_ titolo: LocalizedStringKey, _ v: ValoreComune<T>, daVerificare: Bool, @ViewBuilder _ contenuto: () -> C) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(titolo).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
            contenuto().frame(maxWidth: .infinity, alignment: .leading)
            if v == .diversi {
                Text("valori diversi").font(.caption).foregroundStyle(.secondary).fixedSize()
            } else if daVerificare {
                Label { Text("da verificare").foregroundStyle(.secondary) } icon: {
                    Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
                }
                .font(.caption).fixedSize()
            }
        }
    }

    /// Campo di testo: valore comune, o vuoto con «valori diversi»; Invio scrive il valore in tutte le foto.
    func testo(_ titolo: LocalizedStringKey, _ campo: String, _ valori: [String], _ suggerimento: LocalizedStringKey,
               _ cambia: @escaping (inout TagFissi, String) -> Void) -> some View {
        let v = ValoreComune(valori)
        return riga(titolo, v, daVerificare: false) {
            CampoTesto(valore: v.valore ?? "", suggerimento: v == .diversi ? "valori diversi" : suggerimento) { s in
                stato.correggiFissi(quali, campo: campo) { cambia(&$0, s) }
            }
        }
    }

    func lista(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// Campo di testo che salva con Invio o quando perde il fuoco.
struct CampoTesto: View {
    let valore: String
    let suggerimento: LocalizedStringKey
    let salva: (String) -> Void
    @State private var testo = ""
    @FocusState private var attivo: Bool

    var body: some View {
        TextField(suggerimento, text: $testo)
            .textFieldStyle(.roundedBorder)
            .focused($attivo)
            .onAppear { testo = valore }
            .onChange(of: valore) { _, v in if !attivo { testo = v } }
            .onSubmit { if testo != valore { salva(testo) } }
            .onChange(of: attivo) { _, a in if !a && testo != valore { salva(testo) } }
    }
}
