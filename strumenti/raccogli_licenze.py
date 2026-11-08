"""Raccoglie licenze e avvisi delle librerie usate da FotoTag in Risorse/RICONOSCIMENTI.md.
Uso: python3 strumenti/raccogli_licenze.py   (dopo una compilazione, per avere i pacchetti scaricati)"""
from pathlib import Path

CHECKOUTS = Path(__file__).resolve().parents[2] / "_build/SourcePackages/checkouts"
OUT = Path(__file__).resolve().parent.parent / "Risorse/RICONOSCIMENTI.md"

# componente → (percorsi relativi ai checkout, descrizione)
LIBRERIE = [
    ("MLX Swift (ml-explore)", ["mlx-swift/LICENSE"], "calcolo sul processore grafico del Mac"),
    ("MLX (ml-explore)", ["mlx-swift/Source/Cmlx/mlx/LICENSE"], ""),
    ("MLX C (ml-explore)", ["mlx-swift/Source/Cmlx/mlx-c/LICENSE"], ""),
    ("metal-cpp (Apple)", ["mlx-swift/Source/Cmlx/metal-cpp/LICENSE.txt"], ""),
    ("{fmt}", ["mlx-swift/Source/Cmlx/fmt/LICENSE"], ""),
    ("JSON for Modern C++ (Niels Lohmann)", ["mlx-swift/Source/Cmlx/json/LICENSE.MIT"], ""),
    ("MLX Swift LM (ml-explore)", ["mlx-swift-lm/LICENSE"], "modelli visione-linguaggio"),
    ("XGrammar (MLC)", ["mlx-swift-lm/Libraries/MLXCXGrammar/xgrammar/LICENSE", "mlx-swift-lm/Libraries/MLXCXGrammar/xgrammar/NOTICE"], "risposte in formato JSON"),
    ("swift-transformers (Hugging Face)", ["swift-transformers/LICENSE"], "tokenizer"),
    ("swift-huggingface (Hugging Face)", ["swift-huggingface/LICENSE"], ""),
    ("swift-jinja (Hugging Face)", ["swift-jinja/LICENSE"], ""),
    ("yyjson (YaoYuan)", ["yyjson/LICENSE"], ""),
    ("EventSource (Mattt)", ["EventSource/LICENSE.md"], ""),
    ("Swift Collections (Apple)", ["swift-collections/LICENSE.txt"], ""),
    ("Swift Numerics (Apple)", ["swift-numerics/LICENSE.txt"], ""),
    ("Swift Crypto (Apple)", ["swift-crypto/LICENSE.txt", "swift-crypto/NOTICE.txt"], ""),
    ("SwiftASN1 (Apple)", ["swift-asn1/LICENSE.txt", "swift-asn1/NOTICE.txt"], ""),
    ("SwiftSyntax (Apple)", ["swift-syntax/LICENSE.txt"], "solo per compilare"),
]

MODELLI = """## Modelli

FotoTag non contiene i modelli: li scarica da Hugging Face e li usa solo su questo Mac.

- **Qwen3-VL 8B / 4B Instruct** — © Alibaba Cloud (Qwen Team), licenza Apache 2.0.
  Versioni quantizzate a 4 bit per MLX di [mlx-community](https://huggingface.co/mlx-community).
- **SigLIP 2 (base, patch16, 256)** — © Google LLC, licenza Apache 2.0.
  Convertito in Core ML per FotoTag senza modificare i pesi.

Il testo della licenza Apache 2.0 si trova più sotto, con le librerie che la usano.
"""


def tipo(testo):
    t = testo[:600].lower()
    if "apache license" in t: return "Apache 2.0"
    if "mit license" in t or "permission is hereby granted" in t: return "MIT"
    if "bsd" in t: return "BSD"
    return "vedi testo"


def main():
    righe = ["# Riconoscimenti\n",
             "FotoTag usa software e modelli di altri autori, che ringraziamo. Qui sotto le loro licenze.\n",
             MODELLI, "## Librerie\n"]
    indice, testi = [], []
    for nome, file, desc in LIBRERIE:
        parti = [(CHECKOUTS / f) for f in file if (CHECKOUTS / f).exists()]
        if not parti: continue
        corpo = "\n\n".join(p.read_text(errors="replace").strip() for p in parti)
        indice.append(f"- **{nome}** — {tipo(corpo)}" + (f" ({desc})" if desc else ""))
        testi.append(f"### {nome}\n\n```\n{corpo}\n```\n")
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text("\n".join(righe + indice + ["\n## Testi delle licenze\n"] + testi), encoding="utf-8")
    print(f"{len(indice)} librerie → {OUT}")


if __name__ == "__main__":
    main()
