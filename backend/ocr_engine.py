import pytesseract
import numpy as np
import cv2

from typing import Optional

def set_tesseract_path(win_path: Optional[str] = None):
    if win_path:
        pytesseract.pytesseract.tesseract_cmd = win_path

def preprocess_receipt(img):
    """
    Accepts BGR or grayscale image and returns a binarized image for OCR.
    """
    if img is None:
        return img

    if len(img.shape) == 3:
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    else:
        gray = img.copy()

    gray = cv2.normalize(gray, None, 0, 255, cv2.NORM_MINMAX)
    gray = cv2.GaussianBlur(gray, (3, 3), 0)

    th = cv2.adaptiveThreshold(
        gray, 255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        31, 10
    )
    return th


def ocr_lines_with_bboxes(img, lang="eng", doc_type=""):
    dt = (doc_type or "").lower().strip()

    # Detect binary image (already thresholded)
    is_binary = False
    try:
        if len(img.shape) == 2:
            vals = np.unique(img)
            if len(vals) <= 3 and set(vals.tolist()).issubset({0, 255}):
                is_binary = True
    except Exception:
        pass

    if dt in ["fees_receipt", "fee_receipt", "fee", "receipt"] and not is_binary:
        img_for_ocr = preprocess_receipt(img)   # only when it's NOT already binary
        cfg = "--oem 1 --psm 6"
    else:
        img_for_ocr = img
        cfg = "--oem 1 --psm 6"

    data = pytesseract.image_to_data(img_for_ocr, lang=lang, config=cfg,
                                     output_type=pytesseract.Output.DICT)

    n = len(data["text"])
    items = []
    for i in range(n):
        txt = (data["text"][i] or "").strip()
        conf = data["conf"][i]
        if not txt:
            continue
        try:
            if float(conf) < 40:
                continue
        except:
            pass

        x, y, w, h = data["left"][i], data["top"][i], data["width"][i], data["height"][i]
        items.append({
            "text": txt,
            "x": x, "y": y, "w": w, "h": h,
            "block": data["block_num"][i],
            "par": data["par_num"][i],
            "line": data["line_num"][i],
        })

    lines = {}
    for it in items:
        k = (it["block"], it["par"], it["line"])
        lines.setdefault(k, []).append(it)

    out = []
    for k, arr in lines.items():
        arr = sorted(arr, key=lambda z: z["x"])
        text = " ".join([a["text"] for a in arr]).strip()
        if not text:
            continue
        xs = [a["x"] for a in arr]
        ys = [a["y"] for a in arr]
        xe = [a["x"] + a["w"] for a in arr]
        ye = [a["y"] + a["h"] for a in arr]
        x0, y0, x1, y1 = min(xs), min(ys), max(xe), max(ye)
        out.append({"text": text, "bbox": (x0, y0, x1-x0, y1-y0), "x": x0, "y": y0, "h": y1-y0})

    out = sorted(out, key=lambda z: (z["y"], z["x"]))
    return out