import Testing
@testable import FotoTagCore

@Suite struct MemoriaTests {
    @Test func tettoDellaCacheSecondoLaMemoria() {
        let mb = 1 << 20
        #expect(Memoria.limiteCache(ramGB: 8) == 256 * mb)
        #expect(Memoria.limiteCache(ramGB: 16) == 1024 * mb)
        #expect(Memoria.limiteCache(ramGB: 15.9) == 1024 * mb)
        #expect(Memoria.limiteCache(ramGB: 32) == 2048 * mb)
    }
}

@Suite struct AvvisoMemoriaTests {
    @Test func modelloDaCaricare() {
        // 8B da caricare (5,8 GB) + margine 1,5: servono 7,3 GB
        #expect(Memoria.avvisoPrimaDellAnalisi(disponibileGB: 8, modelloGB: 5.8, caricato: false) == nil)
        let a = Memoria.avvisoPrimaDellAnalisi(disponibileGB: 3.2, modelloGB: 5.8, caricato: false)
        // i numeri seguono il formato regionale del Mac (D68)
        let gb = { (x: Double) in x.formatted(.number.precision(.fractionLength(1))) }
        #expect(a?.contains("\(gb(3.2)) GB") == true && a?.contains("circa \(gb(7.3))") == true)
    }

    @Test func modelloGiaCaricato() {
        #expect(Memoria.avvisoPrimaDellAnalisi(disponibileGB: 2, modelloGB: 5.8, caricato: true) == nil)
        #expect(Memoria.avvisoPrimaDellAnalisi(disponibileGB: 1, modelloGB: 5.8, caricato: true) != nil)
    }

    @Test func pressioneAlta() {
        #expect(Memoria.avvisoPrimaDellAnalisi(disponibileGB: 12, modelloGB: 5.8, caricato: false, pressione: 2) != nil)
        #expect(Memoria.avvisoPrimaDellAnalisi(disponibileGB: 12, modelloGB: 5.8, caricato: false, pressione: 1) == nil)
    }

    @Test func letturaDellaMemoria() {
        let g = Memoria.disponibileGB()
        #expect(g > 0 && g <= Modelli.ramGB + 0.1)
        #expect([1, 2, 4].contains(Memoria.pressione()))
    }
}
