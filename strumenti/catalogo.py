#!/usr/bin/env python3
"""Scrive Sources/FotoTag/Localizable.xcstrings (D68) da un elenco di chiavi e dalle traduzioni.

Uso: python3 strumenti/catalogo.py strumenti/chiavi.json strumenti/traduzioni.py
- chiavi.json: chiavi estratte dal compilatore. Per rifarlo dopo testi nuovi: aggiungere per un momento a FotoTag e
  FotoTagCore in Package.swift `.unsafeFlags(["-emit-localized-strings", "-emit-localized-strings-path", "<cartella>"])`,
  `swift build --scratch-path ../_build/spm --product FotoTag`, poi raccogliere le "key" dei file .stringsdata;
- traduzioni.py: dizionari EN (inglese) e IT (plurali dell'italiano). Le chiavi senza traduzione vengono elencate.
Nelle traduzioni {uno|altri} è un plurale sul prossimo argomento, {N:uno|altri} sull'argomento N;
«=» davanti a una forma la scrive senza il numero.
"""
import json, re, sys

SPEC = re.compile(r'%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:ll|l|h)?[@dDuUxXoOfeEgGcCsSpaA]')

def forma(s):
    """«=testo» senza il numero davanti; altrimenti «%arg testo»."""
    return s[1:] if s.startswith('=') else "%arg " + s

def valore(chiave, testo):
    """Testo con {…} → stringUnit (+ substitutions)."""
    if '{' not in testo:
        return {"stringUnit": {"state": "translated", "value": testo}}
    specs = [m.group(0) for m in SPEC.finditer(chiave)]
    out, sost, n, i = '', {}, 0, 0
    tok = re.compile(r'\{(?:(\d+):)?([^|{}]*)\|([^{}]*)\}|' + SPEC.pattern)
    for m in tok.finditer(testo):
        out += testo[i:m.start()]
        i = m.end()
        if m.group(0).startswith('{'):
            if m.group(1): arg = int(m.group(1))
            else: n += 1; arg = n
            nome = f"a{len(sost) + 1}"
            fmt = specs[arg - 1].lstrip('%').split('$')[-1]
            sost[nome] = {"argNum": arg, "formatSpecifier": fmt, "variations": {"plural": {
                "one": {"stringUnit": {"state": "translated", "value": forma(m.group(2))}},
                "other": {"stringUnit": {"state": "translated", "value": forma(m.group(3))}}}}}
            out += f"%{arg}$#@{nome}@"
        else:
            n += 1
            out += f"%{n}$" + m.group(0)[1:]
    out += testo[i:]
    return {"stringUnit": {"state": "translated", "value": out}, "substitutions": sost}

chiavi = json.load(open(sys.argv[1]))
t = {}
exec(open(sys.argv[2]).read(), t)
EN, IT = t["EN"], t["IT"]
mancano = [k for k in chiavi if k not in EN and SPEC.sub('', k).strip(' %/()…«»+⌥↩.,0123456789') and k not in ("FotoTag",)]
if mancano: print("senza traduzione:", *mancano, sep="\n  ")
stringhe = {}
for k in sorted(set(chiavi) | set(EN)):
    loc = {}
    if k in EN: loc["en"] = valore(k, EN[k])
    if k in IT: loc["it"] = valore(k, IT[k])
    stringhe[k] = {"localizations": loc} if loc else {}
json.dump({"sourceLanguage": "it", "strings": stringhe, "version": "1.0"},
          open("Sources/FotoTag/Localizable.xcstrings", "w"), ensure_ascii=False, indent=2, sort_keys=True)
print(len(stringhe), "voci")
