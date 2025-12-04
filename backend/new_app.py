import os
import json
import numpy as np
import cv2

from preprocess import preprocess_image
from ocr_engine import ocr_lines_with_bboxes, set_tesseract_path
from extractors import extract_by_doc_type
from compare import compare

# Set Tesseract
set_tesseract_path(os.environ.get("TESSERACT_CMD"))


# ---------------- IMAGE READER ----------------
def _read_cv2_image(file_bytes: bytes):
    nparr = np.frombuffer(file_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    return img


# ---------------- OCR PROCESSOR ----------------
def _ocr_extract(doc_type: str, img_bgr, lang: str):
    img_bin = preprocess_image(img_bgr)
    lines = ocr_lines_with_bboxes(img_bin, lang=lang, doc_type=doc_type)
    fields = extract_by_doc_type(doc_type, lines)
    return fields



# ===========================================================
#   1) →  FUNCTION VERSION OF /extract
# ===========================================================
def extract_text(doc_type: str, img_bytes: bytes, lang="eng"):
    img = _read_cv2_image(img_bytes)
    fields = _ocr_extract(doc_type, img, lang)
    return {"doc_type": doc_type, "extracted": fields}



# ===========================================================
#   2) → FUNCTION VERSION OF /verify  (JSON + Image)
# ===========================================================
def verify(doc_type: str, agreement_dict: dict, img_bytes: bytes, lang="eng"):
    img = _read_cv2_image(img_bytes)
    extracted = _ocr_extract(doc_type, img, lang)

    result = compare(doc_type, agreement_dict, extracted)

    return {
        "doc_type": doc_type,
        "agreement": agreement_dict,
        "ocr_extracted": extracted,
        "comparison": result,
    }



# ===========================================================
#   3) → FUNCTION VERSION OF /verify_both  (Image + Image)
# ===========================================================
def verify_both_images(doc_type: str, img1_bytes: bytes, img2_bytes: bytes, lang="eng"):
    img_a = _read_cv2_image(img1_bytes)
    img_b = _read_cv2_image(img2_bytes)

    agreement = _ocr_extract(doc_type, img_a, lang)
    document  = _ocr_extract(doc_type, img_b, lang)

    result = compare(doc_type, agreement, document)

    return {
        "doc_type": doc_type,
        "agreement_extracted": agreement,
        "doc_extracted": document,
        "comparison": result
    }


# ================= USAGE EXAMPLES ==================
# Use these like normal python:

# 👉 Single invoice OCR
# extract_text("invoice", open("invoice.jpg","rb").read())

# 👉 Invoice verification
# verify_invoice("invoice", agreement_dict, open("invoice.jpg","rb").read())

# 👉 Compare agreement image vs document image
# verify_both_images("invoice", open("agreement.jpg","rb").read(), open("doc.jpg","rb").read())
