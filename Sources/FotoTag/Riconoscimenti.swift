import AppKit
import SwiftUI

/// Testi inclusi nell'app (Risorse/ copiate da crea_app.sh).
enum TestiApp {
    static func testo(_ nome: String) -> String {
        if let u = Bundle.main.url(forResource: nome, withExtension: "md"), let t = try? String(contentsOf: u, encoding: .utf8) { return t }
        return "Testo non trovato: \(nome).md"
    }

    /// Pannello «Informazioni su FotoTag» con autore e riconoscimenti principali.
    static func mostraInformazioni() {
        let crediti = NSMutableAttributedString(string: """
            Tag e ricerca per le tue foto, tutto sul tuo Mac.
            © 2026 Lorenzo Zanna. Software libero, licenza GPL 3.0.

            Usa Qwen3-VL (Alibaba Cloud, Apache 2.0), SigLIP 2 (Google, Apache 2.0), MLX e MLX Swift LM (Apple, MIT), swift-transformers (Hugging Face, Apache 2.0), XGrammar (Apache 2.0) e altre librerie: vedi FotoTag ▸ Riconoscimenti.
            """, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: crediti, .applicationName: "FotoTag"])
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Finestra «Riconoscimenti»: licenze delle librerie e dei modelli usati.
struct FinestraRiconoscimenti: View {
    var body: some View {
        TestoMarkdown(testo: TestiApp.testo("RICONOSCIMENTI") + "\n\n---\n\n" + TestiApp.testo("LICENSE"))
            .frame(minWidth: 620, minHeight: 520)
    }
}

/// Markdown in una vista di testo selezionabile (anche testi lunghi).
struct TestoMarkdown: NSViewRepresentable {
    let testo: String

    func makeNSView(context: Context) -> NSScrollView {
        let s = NSTextView.scrollableTextView()
        let tv = s.documentView as! NSTextView
        tv.isEditable = false
        tv.textContainerInset = NSSize(width: 16, height: 16)
        let opzioni = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        // titoli (# …) in grassetto e blocchi ``` senza i segni: il parser «inline» non li gestisce
        let pulito = testo.split(separator: "\n", omittingEmptySubsequences: false).compactMap { r -> String? in
            if r.hasPrefix("```") { return nil }
            if let m = r.range(of: #"^#{1,4} "#, options: .regularExpression) { return "**" + r[m.upperBound...] + "**" }
            return String(r)
        }.joined(separator: "\n")
        let a = (try? AttributedString(markdown: pulito, options: opzioni)) ?? AttributedString(testo)
        let ns = NSMutableAttributedString(a)
        ns.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: ns.length))
        ns.enumerateAttribute(.font, in: NSRange(location: 0, length: ns.length)) { v, r, _ in
            if v == nil { ns.addAttribute(.font, value: NSFont.systemFont(ofSize: 12), range: r) }
        }
        tv.textStorage?.setAttributedString(ns)
        return s
    }

    func updateNSView(_ v: NSScrollView, context: Context) {}
}
