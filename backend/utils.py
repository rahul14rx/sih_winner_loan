import re

def norm_text(s: str) -> str:
    if not s:
        return ""
    s = s.lower()
    s = re.sub(r"[^a-z0-9\s]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s

def tokens(s: str):
    s = norm_text(s)
    if not s:
        return []
    stop = {"the", "of", "and", "for", "to", "in"}
    t = [x for x in s.split() if x not in stop]
    return t

def parse_phone(text: str):
    if not text:
        return ""
    digs = re.sub(r"\D", "", text)
    if len(digs) >= 10:
        return digs[-10:]
    return ""

def money_candidates(text: str):
    if not text:
        return []
    raw = text.replace(",", "")
    pats = [
        r"(?:₹|rs\.?|inr)\s*([0-9]+(?:\.[0-9]{1,2})?)",
        r"([0-9]+(?:\.[0-9]{1,2})?)\s*(?:₹|rs\.?|inr)",
    ]
    out = []
    for p in pats:
        for m in re.finditer(p, raw, flags=re.IGNORECASE):
            try:
                out.append(float(m.group(1)))
            except:
                pass
    return out

def best_labeled_value(lines, keys):
    # keys: list of regex fragments e.g. ["name", "student name"]
    for ln in lines:
        s = ln.strip()
        for k in keys:
            m = re.search(rf"\b{k}\b\s*[:\-]\s*(.+)$", s, flags=re.IGNORECASE)
            if m:
                v = m.group(1).strip()
                if v:
                    return v
    return ""

def pick_top_region(lines_with_meta, frac=0.35):
    # lines_with_meta: [{"text":..., "y":..., "h":...}, ...]
    if not lines_with_meta:
        return []
    ys = [x["y"] for x in lines_with_meta]
    y0, y1 = min(ys), max(ys)
    cut = y0 + (y1 - y0) * frac
    return [x for x in lines_with_meta if x["y"] <= cut]

def contains_any(s, words):
    ss = s.lower()
    return any(w in ss for w in words)
