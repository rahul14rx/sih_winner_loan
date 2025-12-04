import io
import os
from typing import Any, Dict

from PIL import Image, ImageFilter, ImageOps
import pytesseract

from mock_db import MOCK_DB
from normalize import find_best_rc

# If macOS can’t find tesseract automatically, set env TESSERACT_CMD
if os.getenv("TESSERACT_CMD"):
    pytesseract.pytesseract.tesseract_cmd = os.environ["TESSERACT_CMD"]


def ocr_plate_bytes(img_bytes: bytes) -> Dict[str, Any]:
    img = Image.open(io.BytesIO(img_bytes)).convert("RGB")
    img = ImageOps.exif_transpose(img)
    gray = ImageOps.autocontrast(ImageOps.grayscale(img))

    # Upscale for better OCR
    w, h = gray.size
    if w < 1100:
        scale = 1100 / max(1, w)
        gray = gray.resize((int(w * scale), int(h * scale)))

    variants = [
        ("base", gray),
        ("sharpen", gray.filter(ImageFilter.SHARPEN)),
        ("threshold", gray.point(lambda p: 0 if p < 165 else 255)),
    ]

    cfg = "-c tessedit_char_whitelist=ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    psms = ["--psm 7", "--psm 6"]

    prefer = set(MOCK_DB.keys())

    best_text = ""
    best_rc = ""

    for tag, vimg in variants:
        for psm in psms:
            text = pytesseract.image_to_string(vimg, config=f"{psm} {cfg}") or ""
            if len(text) > len(best_text):
                best_text = text
            rc = find_best_rc(text, prefer=prefer, prefer_only=True)
            if rc:
                return {"text": text, "vehicle_no": rc, "variant": tag, "psm": psm}

    if best_text:
        best_rc = find_best_rc(best_text, prefer=prefer)

    return {"text": best_text, "vehicle_no": best_rc, "variant": "best_text", "psm": None}
