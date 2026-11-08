import AppKit
import FotoTagCore
import SwiftUI

/// Foto a tutta area nella colonna centrale (doppio clic, Spazio, clic sull'anteprima del pannello), con
/// la striscia delle miniature sotto. Frecce, ↩ e T come nella griglia; Spazio o Esc tornano alla griglia.
/// Fondo scuro neutro, che non falsa toni e bianchi; Z o clic sulla foto la mostrano al 100% (D34.5).
struct FotoGrande: View {
    @EnvironmentObject var stato: Stato
    @FocusState private var attiva: Bool
    @State private var versione = 0       // cambia dopo «Scarica l'originale»: si ricarica la foto
    @State private var scaricando = false

    var body: some View {
        let visibili = stato.fotoVisibili
        let i = visibili.firstIndex { $0.id == stato.fotoScelta }
        VStack(spacing: 0) {
            ZStack {
                if let i, let punto = stato.zoom {
                    CentoPerCento(url: visibili[i].url, punto: punto) { stato.zoom = nil }
                        .id("\(visibili[i].id)-\(versione)-cento")
                } else if let i {
                    Miniatura(url: visibili[i].url, lato: 2048, impronta: visibili[i].impronta, proporzioni: true)
                        .overlay {
                            // il punto cliccato, in proporzione alla foto, resta al centro del 100%
                            GeometryReader { g in
                                Color.clear.contentShape(Rectangle())
                                    .onTapGesture { p in stato.apriZoom(visibili[i], UnitPoint(x: p.x / g.size.width, y: p.y / g.size.height)) }
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id("\(visibili[i].id)-\(versione)")
                }
                HStack {
                    freccia("chevron.left", "Foto precedente", passo: -1).disabled(i == nil || i == 0)
                    Spacer()
                    freccia("chevron.right", "Foto successiva", passo: 1).disabled(i == nil || i == visibili.count - 1)
                }
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            if let i, let a = Anteprime.trova(impronta: visibili[i].impronta, in: Stato.cartellaAnteprimeImpostata),
               Immagini.daScaricare(visibili[i].url) {
                let lato = a.deletingPathExtension().lastPathComponent.split(separator: "_").last.map(String.init) ?? ""
                HStack(spacing: 10) {
                    Label("Foto grande: anteprima da \(lato) px. L'originale si scarica solo se lo chiedi.", systemImage: "icloud")
                        .foregroundStyle(.secondary)
                    if scaricando { ProgressView().controlSize(.small) }
                    Button("Scarica l'originale") { scarica(visibili[i].url) }.disabled(scaricando)
                }
                .font(.callout)
                .padding(.bottom, 8)
            }
            Divider()
            Striscia(visibili: visibili)
        }
        .background(Color(white: 0.11))  // grigio neutro, uguale in tema chiaro e scuro
        .environment(\.colorScheme, .dark)
        .onChange(of: stato.fotoScelta) { _, _ in stato.zoom = nil }
        .onDisappear { stato.zoom = nil }
        .focusable()
        .focusEffectDisabled()
        .focused($attiva)
        .onAppear { attiva = true }
        // tornando a FotoTag da un'altra app il fuoco non tornava qui e Z non faceva nulla
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in attiva = true }
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { k in
            stato.sposta(di: k.key == .leftArrow ? -1 : 1, estendi: false)
            return .handled
        }
        .onKeyPress(keys: [.space, .escape]) { _ in
            if stato.zoom != nil { stato.zoom = nil } else { stato.fotoGrande = false }  // dal 100% si torna prima alla foto intera
            return .handled
        }
        .onKeyPress(characters: ["z"]) { k in
            guard k.modifiers.isEmpty, let f = visibili.first(where: { $0.id == stato.fotoScelta }) else { return .ignored }
            stato.cambiaZoom(f)
            return .handled
        }
        .onKeyPress(.return) { stato.rivistaEProssima(); return .handled }
        .onKeyPress(characters: ["t"]) { k in
            guard k.modifiers.isEmpty else { return .ignored }
            stato.fuocoTag = true
            return .handled
        }
    }

    /// Scaricamento asincrono (coda dedicata, Immagini.scarica): a file arrivato la foto si ricarica.
    func scarica(_ url: URL) {
        scaricando = true
        Task {
            let ok = await Immagini.scarica(url, attesa: 300)
            scaricando = false
            if ok { versione += 1 } else { stato.messaggio = String(localized: "L'originale non è arrivato dal disco in cloud: riprova più tardi.") }
        }
    }

    func freccia(_ simbolo: String, _ voce: LocalizedStringKey, passo: Int) -> some View {
        Button { stato.sposta(di: passo, estendi: false) } label: {
            Image(systemName: simbolo).font(.title2.weight(.semibold))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(voce)
    }
}

/// Striscia di miniature sotto la foto grande: la corrente al centro, con il bordo d'accento; segue il filtro.
struct Striscia: View {
    @EnvironmentObject var stato: Stato
    let visibili: [FotoRecord]

    var body: some View {
        ScrollViewReader { scorri in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(visibili) { f in
                        // proporzioni vere: una verticale si riconosce già dalla striscia
                        Miniatura(url: f.url, lato: 160, impronta: f.impronta, proporzioni: true, dissolvenza: true).allowsHitTesting(false)
                            .frame(height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .overlay {
                                if f.id == stato.fotoScelta {
                                    RoundedRectangle(cornerRadius: 3).strokeBorder(Color.accentColor, lineWidth: 2)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { stato.clic(f.id, comando: false, maiuscolo: false) }
                            .accessibilityLabel(f.nome)
                            .id(f.id)
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 64)
            .onAppear { if let id = stato.fotoScelta { scorri.scrollTo(id, anchor: .center) } }
            .onChange(of: stato.fotoScelta) { _, id in if let id { withAnimation { scorri.scrollTo(id, anchor: .center) } } }
        }
    }
}

/// La foto al 100%: un pixel della foto per ogni pixel dello schermo, da far scorrere; clic per tornare.
struct CentoPerCento: View {
    let url: URL
    let punto: UnitPoint
    let esci: () -> Void
    @State private var immagine: CGImage?
    @State private var illeggibile = false
    @Environment(\.displayScale) private var scala

    var body: some View {
        Group {
            if let immagine {
                ScrollView([.horizontal, .vertical]) {
                    Image(decorative: immagine, scale: scala)
                        .onTapGesture { esci() }
                }
                .defaultScrollAnchor(punto)
            } else if illeggibile {
                ContentUnavailableView("Non si apre al 100%", systemImage: "exclamationmark.triangle",
                                       description: Text("Il file non si legge per intero. Clic o Esc per tornare alla foto."))
                    .onTapGesture { esci() }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .help("Foto al 100%: clic, Z o Esc per vederla intera")
        .task(id: url) {
            let u = url
            immagine = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                // tutta la risoluzione, già girata secondo l'EXIF
                guard let s = CGImageSourceCreateWithURL(u as CFURL, nil),
                      let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any],
                      let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(s, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(w, h)] as CFDictionary)
            }.value
            illeggibile = immagine == nil
        }
    }
}

/// Foto al 100% (D34.5): dallo stato, così la apre anche il menu Foto.
extension Stato {
    /// Il 100% legge l'originale: se è solo sul disco in cloud non si scarica da solo (D36).
    func apriZoom(_ f: FotoRecord, _ punto: UnitPoint) {
        if Immagini.daScaricare(f.url) {
            notizia = String(localized: "Per vedere la foto al 100% scarica prima l'originale (pulsante sotto la foto).")
            return
        }
        zoom = UnitPoint(x: min(max(punto.x, 0), 1), y: min(max(punto.y, 0), 1))
    }

    /// Z e menu Foto: dalla foto intera al 100% al centro e ritorno; dalla griglia apre prima la foto grande.
    func cambiaZoom(_ f: FotoRecord? = nil) {
        guard let f = f ?? foto.first(where: { $0.id == fotoScelta }) else { return }
        if zoom != nil { zoom = nil; return }
        fotoGrande = true
        apriZoom(f, .center)
    }
}
