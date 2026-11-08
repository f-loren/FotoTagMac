import Foundation
import Testing
@testable import FotoTagCore

@Suite struct SidecarTests {
    /// Sidecar di darktable (come E.NEF.xmp delle prove): storia, valutazione e date devono restare identiche.
    static let darktable = """
        <?xml version="1.0" encoding="UTF-8"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="XMP Core 4.4.0-Exiv2">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:exif="http://ns.adobe.com/exif/1.0/"
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmlns:xmpMM="http://ns.adobe.com/xap/1.0/mm/"
            xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:lr="http://ns.adobe.com/lightroom/1.0/"
            xmlns:darktable="http://darktable.sf.net/"
           exif:DateTimeOriginal="2025:09:12 10:11:12"
           xmp:Rating="3"
           xmpMM:DerivedFrom="E.NEF"
           darktable:xmp_version="5"
           darktable:history_end="2">
           <darktable:history>
            <rdf:Seq>
             <rdf:li darktable:num="0" darktable:operation="exposure" darktable:enabled="1"
              darktable:params="00000000000080b9333333400000c03f00004842"/>
             <rdf:li darktable:num="1" darktable:operation="filmicrgb" darktable:enabled="1" darktable:params="abcd"/>
            </rdf:Seq>
           </darktable:history>
           <dc:subject>
            <rdf:Bag>
             <rdf:li>mio tag</rdf:li>
             <rdf:li>vecchio fototag</rdf:li>
            </rdf:Bag>
           </dc:subject>
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        """

    /// Tutto il documento tranne dc:subject, dc:description e lr:hierarchicalSubject, in forma canonica.
    static func resto(_ d: Data) throws -> String {
        let doc = try XMLDocument(data: d, options: [.nodePreserveAll])
        for n in try doc.nodes(forXPath: "//*[local-name()='subject' or local-name()='description' or local-name()='hierarchicalSubject']") {
            n.detach()
        }
        return doc.xmlString(options: [.nodeCompactEmptyElement])
            .replacingOccurrences(of: #">\s+<"#, with: "><", options: .regularExpression)
    }

    @Test func andataERitornoDarktable() throws {
        let prima = Data(Self.darktable.utf8)
        let letto = try SidecarXMP.leggi(prima)
        #expect(letto.parole == ["mio tag", "vecchio fototag"])
        let parole = Scrittura.unisci(esistenti: letto.parole, giaScritte: ["vecchio fototag"], nuove: ["mare", "barca"]).finali
        let dopo = try SidecarXMP.scrivi(prima, .init(parole: parole, gerarchia: ["Contenuto|luogo|mare"], didascalia: "Una barca"))
        let riletto = try SidecarXMP.leggi(dopo)
        #expect(riletto.parole == ["mio tag", "mare", "barca"])
        #expect(riletto.gerarchia == ["Contenuto|luogo|mare"])
        #expect(riletto.didascalia == "Una barca")
        #expect(try Self.resto(dopo) == Self.resto(prima))
        let testo = String(decoding: dopo, as: UTF8.self)
        for campo in [#"exif:DateTimeOriginal="2025:09:12 10:11:12""#, #"xmp:Rating="3""#, #"darktable:history_end="2""#,
                      #"darktable:params="00000000000080b9333333400000c03f00004842""#] {
            #expect(testo.contains(campo), "\(campo)")
        }
    }

    @Test func sidecarNuovo() throws {
        let d = try SidecarXMP.scrivi(nil, .init(parole: ["bosco"], gerarchia: [], didascalia: nil))
        let r = try SidecarXMP.leggi(d)
        #expect(r.parole == ["bosco"])
        #expect(r.didascalia == nil)
    }

    @Test func sidecarSenzaDescrizioneRifiutato() {
        #expect(throws: (any Error).self) { try SidecarXMP.leggi(Data("<a/>".utf8)) }
    }
}
