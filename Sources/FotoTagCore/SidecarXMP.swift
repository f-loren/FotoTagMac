import Foundation

/// Modifica di un sidecar .xmp come XML: cambia SOLO dc:subject, dc:description e lr:hierarchicalSubject.
/// Tutto il resto (storia di darktable, valutazioni, date, maschere…) resta com'è, carattere per carattere
/// dove possibile. Passare da ImageIO invece riscrive anche altri campi (es. exif:DateTimeOriginal).
enum SidecarXMP {
    static let rdf = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    static let dc = "http://purl.org/dc/elements/1.1/"
    static let lr = "http://ns.adobe.com/lightroom/1.0/"

    static let vuoto = """
        <?xml version="1.0" encoding="UTF-8"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="FotoTag">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""/>
         </rdf:RDF>
        </x:xmpmeta>
        """

    struct Contenuto {
        var parole: [String]; var gerarchia: [String]; var didascalia: String?
        /// proprietà semplici in più (namespace, prefisso, nome, valore), es. xmpMM:PreservedFileName
        var altre: [(String, String, String, String)] = []
    }
    static let xmpMM = "http://ns.adobe.com/xap/1.0/mm/"
    static let photoshop = "http://ns.adobe.com/photoshop/1.0/"

    static func documento(_ dati: Data?) throws -> XMLDocument {
        try XMLDocument(data: dati ?? Data(vuoto.utf8), options: [.nodePreserveAll])
    }

    /// Tutti gli rdf:Description (exiftool ne scrive uno per namespace); il primo riceve i campi nuovi.
    static func descrizioni(_ doc: XMLDocument) throws -> [XMLElement] {
        // l'XPath di Foundation non conosce namespace-uri(): si filtra a mano
        let d = try doc.nodes(forXPath: "//*[local-name()='Description']").compactMap({ $0 as? XMLElement }).filter { $0.uri == rdf }
        if d.isEmpty { throw Scrittura.errore(String(localized: "sidecar senza rdf:Description")) }
        return d
    }

    static func figli(_ d: XMLElement, _ ns: String, _ nome: String) -> [XMLElement] {
        (d.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.localName == nome && $0.uri == ns }
    }

    static func leggi(_ dati: Data?) throws -> Contenuto {
        let ds = try descrizioni(try documento(dati))
        func lista(_ ns: String, _ nome: String) -> [String] {
            ds.flatMap { d -> [String] in
                if let a = d.attribute(forLocalName: nome, uri: ns)?.stringValue { return [a] }
                return figli(d, ns, nome).flatMap { el in
                    (try? el.nodes(forXPath: ".//*[local-name()='li']"))?.compactMap { $0.stringValue } ?? []
                }
            }
        }
        return Contenuto(parole: lista(dc, "subject"), gerarchia: lista(lr, "hierarchicalSubject"),
                         didascalia: lista(dc, "description").first)
    }

    /// Prefisso già usato nel documento per un namespace, o quello indicato (dichiarandolo).
    static func prefisso(_ d: XMLElement, _ ns: String, _ preferito: String) -> String {
        var el: XMLNode? = d
        while let e = el as? XMLElement {
            if let p = e.namespaces?.first(where: { $0.stringValue == ns })?.name { return p }
            el = e.parent
        }
        d.addNamespace(XMLNode.namespace(withName: preferito, stringValue: ns) as! XMLNode)
        return preferito
    }

    static func sostituisci(_ tutte: [XMLElement], ns: String, prefDefault: String, nome: String, contenitore: String?, valori: [String]) {
        // il campo può stare in qualunque rdf:Description: si toglie ovunque e si rimette nel primo
        var posizione: Int?
        for (i, x) in tutte.enumerated() {
            for a in x.attributes ?? [] where a.localName == nome && a.uri == ns { x.removeAttribute(forName: a.name ?? "") }
            let vecchi = figli(x, ns, nome)
            if i == 0 { posizione = vecchi.first.map { $0.index } }
            for v in vecchi { v.detach() }
        }
        let d = tutte[0]
        guard !valori.isEmpty else { return }
        let p = prefisso(d, ns, prefDefault)
        let r = prefisso(d, rdf, "rdf")
        let el = XMLElement(name: "\(p):\(nome)", uri: ns)
        let cont = XMLElement(name: "\(r):\(contenitore ?? "Bag")", uri: rdf)
        for v in valori {
            let li = XMLElement(name: "\(r):li", uri: rdf)
            if contenitore == "Alt" { li.addAttribute(XMLNode.attribute(withName: "xml:lang", stringValue: "x-default") as! XMLNode) }
            li.stringValue = v
            cont.addChild(li)
        }
        el.addChild(cont)
        if let posizione, posizione <= d.childCount { d.insertChild(el, at: posizione) } else { d.addChild(el) }
    }

    /// Proprietà semplice (testo): tolta ovunque e rimessa come elemento nel primo rdf:Description.
    static func semplice(_ tutte: [XMLElement], ns: String, prefDefault: String, nome: String, valore: String) {
        for x in tutte {
            for a in x.attributes ?? [] where a.localName == nome && a.uri == ns { x.removeAttribute(forName: a.name ?? "") }
            for v in figli(x, ns, nome) { v.detach() }
        }
        let p = prefisso(tutte[0], ns, prefDefault)
        let el = XMLElement(name: "\(p):\(nome)", uri: ns)
        el.stringValue = valore
        tutte[0].addChild(el)
    }

    static func scrivi(_ dati: Data?, _ c: Contenuto) throws -> Data {
        let doc = try documento(dati)
        let d = try descrizioni(doc)
        sostituisci(d, ns: dc, prefDefault: "dc", nome: "subject", contenitore: "Bag", valori: c.parole)
        sostituisci(d, ns: lr, prefDefault: "lr", nome: "hierarchicalSubject", contenitore: "Bag", valori: c.gerarchia)
        if let t = c.didascalia { sostituisci(d, ns: dc, prefDefault: "dc", nome: "description", contenitore: "Alt", valori: [t]) }
        for (ns, pref, nome, valore) in c.altre { semplice(d, ns: ns, prefDefault: pref, nome: nome, valore: valore) }
        return doc.xmlData(options: [.nodePreserveAll])
    }
}
