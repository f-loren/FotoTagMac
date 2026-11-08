"""Converte SigLIP 2 (lo stesso checkpoint del prototipo) in Core ML per l'app.

Uso: ~/.venv-prova-mlx/bin/python strumenti/converti_siglip.py [cartella_uscita]
Crea ImageEncoder.mlpackage, TextEncoder.mlpackage, tokenizer e siglip.json (logit scale/bias, dimensioni),
poi confronta gli embedding Core ML con quelli PyTorch del prototipo.
"""
import json, shutil, sys
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
from PIL import Image
from transformers import AutoModel, AutoProcessor

CHECKPOINT = "google/siglip2-base-patch16-256"  # come SIGLIP in fototag/fototag.py
LUNGHEZZA_TESTO = 64                              # come embed_text nel prototipo
out = Path(sys.argv[1] if len(sys.argv) > 1 else Path.home() / "Library/Application Support/FotoTag/Modelli/SigLIP2")
out.mkdir(parents=True, exist_ok=True)

model = AutoModel.from_pretrained(CHECKPOINT, dtype=torch.float32).eval()
proc = AutoProcessor.from_pretrained(CHECKPOINT)
lato = proc.image_processor.size["height"]


def pooled(x):
    return getattr(x, "pooler_output", x)


class Immagine(torch.nn.Module):
    def __init__(self, m): super().__init__(); self.m = m
    def forward(self, pixel_values):
        return torch.nn.functional.normalize(pooled(self.m.get_image_features(pixel_values=pixel_values)), dim=-1)


class Testo(torch.nn.Module):
    def __init__(self, m): super().__init__(); self.m = m
    def forward(self, input_ids):
        return torch.nn.functional.normalize(pooled(self.m.get_text_features(input_ids=input_ids)), dim=-1)


esempio_img = torch.rand(1, 3, lato, lato) * 2 - 1
esempio_txt = proc(text=["prova"], padding="max_length", max_length=LUNGHEZZA_TESTO, return_tensors="pt")["input_ids"]

with torch.no_grad():
    ti = torch.jit.trace(Immagine(model), esempio_img)
    tt = torch.jit.trace(Testo(model), esempio_txt)

mean, std = proc.image_processor.image_mean, proc.image_processor.image_std
assert all(abs(v - 0.5) < 1e-6 for v in mean + std), (mean, std)
# l'immagine entra come immagine RGB 0–255: (x/255 - 0.5)/0.5 = x/127.5 - 1
img_ml = ct.convert(ti, inputs=[ct.ImageType(name="immagine", shape=(1, 3, lato, lato), scale=1 / 127.5, bias=[-1, -1, -1],
                                             color_layout=ct.colorlayout.RGB)],
                    outputs=[ct.TensorType(name="embedding")], minimum_deployment_target=ct.target.macOS14,
                    compute_precision=ct.precision.FLOAT16)
txt_ml = ct.convert(tt, inputs=[ct.TensorType(name="input_ids", shape=(1, LUNGHEZZA_TESTO), dtype=np.int32)],
                    outputs=[ct.TensorType(name="embedding")], minimum_deployment_target=ct.target.macOS14,
                    compute_precision=ct.precision.FLOAT16)
for nome, m in (("ImageEncoder.mlpackage", img_ml), ("TextEncoder.mlpackage", txt_ml)):
    shutil.rmtree(out / nome, ignore_errors=True)
    m.save(str(out / nome))
proc.tokenizer.save_pretrained(out / "tokenizer")
json.dump({"checkpoint": CHECKPOINT, "lato": lato, "lunghezza_testo": LUNGHEZZA_TESTO,
           "logit_scale": float(model.logit_scale.exp()), "logit_bias": float(model.logit_bias),
           "dimensione": int(ti(esempio_img).shape[-1])},
          open(out / "siglip.json", "w"), indent=1)

# verifica: Core ML contro PyTorch sulle stesse immagini e frasi
foto = sorted(Path.home().glob("TagTest-app/prova/*.jpg"))[:6]
cos = []
for p in foto:
    im = Image.open(p).convert("RGB")
    with torch.no_grad():
        x = proc(images=[im], return_tensors="pt")["pixel_values"]
        a = Immagine(model)(x)[0].numpy()
    b = np.array(img_ml.predict({"immagine": im.resize((lato, lato), Image.BILINEAR)})["embedding"])[0]
    cos.append(float(a @ b / np.linalg.norm(b)))
frasi = ["coppia al mare", "persone in piazza", "montagna con nebbia"]
cos_t = []
for f in frasi:
    ids = proc(text=[f.lower()], padding="max_length", max_length=LUNGHEZZA_TESTO, return_tensors="pt")["input_ids"]
    with torch.no_grad():
        a = Testo(model)(ids)[0].numpy()
    b = np.array(txt_ml.predict({"input_ids": ids.numpy().astype(np.int32)})["embedding"])[0]
    cos_t.append(float(a @ b / np.linalg.norm(b)))
    print("token", f, ids[0][:12].tolist())
print("coseno immagini:", [round(c, 4) for c in cos])
print("coseno testi:", [round(c, 4) for c in cos_t])
print("salvato in", out)
