import re
from typing import List, Dict, Any, Optional

from utils import best_labeled_value, parse_phone, pick_top_region, money_candidates

COLLEGE_HINTS = ["college", "university", "institute", "engineering", "technology", "polytechnic", "school"]

COLORS = {
    "black", "white", "red", "blue", "green", "yellow", "orange", "pink", "purple", "violet",
    "grey", "gray", "silver", "gold", "brown", "beige", "maroon", "navy", "teal"
}

import re

COLLEGE_WORDS = ["college", "university", "institute", "technology", "polytechnic", "school"]
ID_STOP_WORDS = ["autonomous", "principal", "valid", "id", "identity", "institute", "technology", "college", "university"]

def _clean(s: str) -> str:
    s = (s or "").replace("|", " ").replace("_", " ").replace("—", " ")
    s = re.sub(r"\s+", " ", s).strip()
    return s

def _fix_common_ocr(s: str) -> str:
    s = _clean(s)
    s = re.sub(r"\bNSTITUTE\b", "INSTITUTE", s, flags=re.I)  # OCR drops leading I
    s = re.sub(r"\bCHENNAL\b", "CHENNAI", s, flags=re.I)
    return s

def extract_fee_receipt_amount(lines):
    texts = [x["text"] for x in lines if x.get("text")]
    best = None
    best_rank = -1

    KEYWORDS = ["total", "payable", "bank", "cash", "amount", "receipt"]
    IGNORE = ["roll", "sem", "period", "date", "receipt no", "register"]

    for t in texts:
        tl = t.lower()

        if any(w in tl for w in IGNORE):
            continue

        vals = money_candidates(t)  # uses your existing money parser
        if not vals:
            continue

        v = max(vals)
        rank = 0

        if any(k in tl for k in KEYWORDS):
            rank += 80
        if "total" in tl:
            rank += 40
        if "bank" in tl or "cash" in tl:
            rank += 25

        # receipts usually have amounts like 5k–5L; prefer plausible ones
        if 1000 <= v <= 500000:
            rank += 10

        # prefer larger amounts (total) over smaller line items
        rank += min(30, int(v // 1000))

        if rank > best_rank:
            best_rank = rank
            best = v

    if best is not None:
        return best

    # fallback: sum item lines if we can find 2+ fee lines
    item_vals = []
    for t in texts:
        tl = t.lower()
        if "fee" in tl or "tuition" in tl or "development" in tl or "training" in tl:
            vals = money_candidates(t)
            if vals:
                item_vals.append(max(vals))
    if len(item_vals) >= 2:
        return float(sum(item_vals))

    return None


def extract_college_header(lines):
    texts = [_fix_common_ocr(x["text"]) for x in lines if x.get("text")]
    top = texts[:12]

    # Strong exact match anywhere in header lines
    joined = " ".join(top).upper()
    m = re.search(r"CHENNAI\s+INSTITUTE\s+OF\s+TECHNOLOGY", joined)
    if m:
        return "Chennai Institute of Technology"


    # Otherwise score best header-like line (prefer institute/university + technology + location name)
    best, best_score = "", -1
    for i in range(len(top)):
        cand1 = top[i]
        cand2 = top[i] + " " + (top[i + 1] if i + 1 < len(top) else "")
        for cand in (cand1, cand2):
            c = _fix_common_ocr(cand)
            cl = c.lower()

            # strip address-ish tails if present
            c = re.split(r"\b(sarathy|nagar|kundrathur|chennai\s*-|\b\d{6}\b)\b", c, 1, flags=re.I)[0].strip(" ,.-")
            cl = c.lower()

            score = 0
            if "institute" in cl or "university" in cl or "college" in cl:
                score += 50
            if "technology" in cl:
                score += 25
            if "chennai" in cl:
                score += 15
            score += min(20, len(c) // 4)

            if score > best_score and len(c.split()) >= 3:
                best_score, best = score, c

    return best

def extract_marksheet_name(lines):
    texts = [_fix_common_ocr(x["text"]) for x in lines if x.get("text")]

    for t in texts:
        if re.search(r"\bname\b", t, re.I):
            after = re.split(r"\bname\b", t, maxsplit=1, flags=re.I)[1]
            after = after.replace(":", " ").strip()
            # cut off at common fields on marksheets
            after = re.split(r"\b(dept|department|year|register|reg|roll|semester|batch|programme|program)\b", after, 1, flags=re.I)[0]
            after = re.sub(r"[^A-Za-z.\s]", " ", after)
            after = re.sub(r"\s+", " ", after).strip()
            if after:
                return after.title()

    return ""  # let fallback handle if needed

def extract_student_id_name(lines):
    texts = [_fix_common_ocr(x["text"]) for x in lines if x.get("text")]

    # Find where college header likely ends, then search after it
    start = 0
    for i, t in enumerate(texts[:12]):
        tl = t.lower()
        if any(w in tl for w in ["institute", "technology", "college", "university", "school"]):
            start = i + 1

    # Scan a small window after the header (this is where the name is on most IDs)
    window = texts[start:start + 12]

    stop_contains = [
        "autonomous", "principal", "valid", "institute", "technology", "college",
        "university", "school", "department"
    ]

    best = ""
    best_score = -10**9

    for t in window:
        s = _clean(t)
        sl = s.lower()

        if not s or len(s) < 2:
            continue
        if any(x in sl for x in stop_contains):
            continue
        if re.search(r"\b\d{4}\s*-\s*\d{4}\b", s):  # 2023-2027
            continue
        if re.search(r"\b(b\.?e|b\.?tech|m\.?e|mba|cse|ece|eee|it)\b", s, re.I):
            continue
        if re.fullmatch(r"[A-Za-z]", s):  # single letter like "A"
            continue
        if re.fullmatch(r"\(.*\)", s):  # anything purely in brackets like "(Autonomous)"
            continue
        if any(ch.isdigit() for ch in s):
            continue

        # Must contain letters
        alpha = sum(ch.isalpha() for ch in s)
        if alpha < 3:
            continue

        words = s.split()
        # Score: prefer 1–4 word names, and prefer uppercase/titlecase name-like strings
        score = 0
        score += 30 if 1 <= len(words) <= 4 else -20
        score += min(20, alpha)  # more letters = better
        score += 10 if s.isupper() else 0

        # Penalize obvious non-name symbols
        if "|" in t or "_" in t:
            score -= 5

        if score > best_score:
            best_score = score
            best = s

    return best.title() if best else ""

# -------------------------
# Generic extractors (IDs/marksheets/receipts)
# -------------------------

def extract_name(lines: List[Dict[str, Any]]) -> str:
    plain = [x["text"] for x in lines if x.get("text")]
    v = best_labeled_value(plain, ["student name", "name", "candidate", "applicant"])
    if v:
        return v.strip()

    # fallback: pick best alpha-heavy 2-5 words line
    best = ""
    bestscore = -1
    for ln in plain:
        s = ln.strip()
        if len(s) < 4:
            continue
        if re.search(r"\b(dob|date|roll|reg|id|class|dept|semester|year)\b", s, re.I):
            continue
        alpha = sum(c.isalpha() for c in s)
        dig = sum(c.isdigit() for c in s)
        words = s.split()
        if dig > alpha:
            continue
        if not (2 <= len(words) <= 5):
            continue
        score = alpha - dig + len(words) * 2
        if score > bestscore:
            bestscore = score
            best = s
    return best


def extract_college(lines: List[Dict[str, Any]]) -> str:
    top = pick_top_region(lines, frac=0.35)
    cand = ""
    cscore = -1
    for it in top:
        s = (it.get("text") or "").strip()
        if not s:
            continue
        sl = s.lower()

        score = len(s)
        if any(h in sl for h in COLLEGE_HINTS):
            score += 25

        if len(s.split()) >= 3 and score > cscore and not re.search(r"\b(name|dob|id|roll|reg)\b", s, re.I):
            cscore = score
            cand = s

    if cand:
        return cand

    for it in lines:
        s = (it.get("text") or "").strip()
        if any(h in s.lower() for h in COLLEGE_HINTS):
            return s
    return ""


def extract_amount_generic(lines: List[Dict[str, Any]]) -> Optional[float]:
    # Works for receipts that include ₹/Rs/INR in text
    best_val = None
    best_rank = -1
    AMOUNT_HINTS = ["total", "grand total", "amount", "paid", "payable", "net", "fee", "inr", "rs", "₹"]

    for it in lines:
        tx = it.get("text") or ""
        vals = money_candidates(tx)
        if not vals:
            continue

        rank = 0
        tl = tx.lower()
        if any(k in tl for k in AMOUNT_HINTS):
            rank += 50
        if "total" in tl or "grand" in tl:
            rank += 30

        v = max(vals)
        rank += min(20, int(v // 1000))
        if rank > best_rank:
            best_rank = rank
            best_val = v

    if best_val is not None:
        return float(best_val)

    allv = []
    for it in lines:
        allv += money_candidates(it.get("text") or "")
    if allv:
        return float(max(allv))
    return None


# -------------------------
# Invoice extractor (robust)
# -------------------------

def _nums_from_text(s: str) -> List[float]:
    # Extract numbers like 5,30,000 or 95400.00; ignore dates containing "/"
    if not s or "/" in s:
        return []
    s2 = s.replace(",", "")
    found = re.findall(r"\b\d+(?:\.\d{1,2})?\b", s2)
    out = []
    for x in found:
        try:
            out.append(float(x))
        except Exception:
            pass
    return out


def _max_num_from_text(s: str, min_value: float = 0.0) -> Optional[float]:
    nums = [n for n in _nums_from_text(s) if n >= min_value]
    return max(nums) if nums else None


def _find_first_index(texts: List[str], patterns: List[str]) -> int:
    for i, t in enumerate(texts):
        for p in patterns:
            if re.search(p, t, re.I):
                return i
    return -1

import re
from utils import parse_phone

COLORS = {
    "black","white","red","blue","green","yellow","orange","pink","purple","violet",
    "grey","gray","silver","gold","brown","beige","maroon","navy","teal"
}

def _nums_from_text(s: str):
    if not s or "/" in s:
        return []
    s2 = s.replace(",", "")
    found = re.findall(r"\b\d+(?:\.\d{1,2})?\b", s2)
    out = []
    for x in found:
        try:
            out.append(float(x))
        except Exception:
            pass
    return out

def _max_num_from_text(s: str, min_value: float = 0.0):
    nums = [n for n in _nums_from_text(s) if n >= min_value]
    return max(nums) if nums else None

def _dedupe_exact_repeat_words(s: str) -> str:
    w = s.split()
    n = len(w)
    if n >= 2 and n % 2 == 0 and w[: n // 2] == w[n // 2 :]:
        return " ".join(w[: n // 2])
    return s

def _take_left_columnish(s: str) -> str:
    s = s.strip()
    s = _dedupe_exact_repeat_words(s)

    # If we have clear column spacing, take left column
    if re.search(r"\s{2,}", s):
        return re.split(r"\s{2,}", s)[0].strip()

    # If we see 2 occurrences of "6," style starts, cut at 2nd
    starts = [m.start() for m in re.finditer(r"\b\d+\s*,", s)]
    if len(starts) >= 2:
        return s[: starts[1]].strip()

    # If we see 2 pincodes, cut after first pincode
    pm = re.search(r"\b[1-9][0-9]{5}\b", s)
    if pm:
        idx = pm.end()
        return s[:idx].strip(" .,-")

    return s

def extract_invoice(lines):
    texts = [x["text"].strip() for x in lines if x.get("text")]

    # ---------- Vendor ----------
    vendor_name = ""
    if texts:
        # Often vendor + TAX INVOICE is on same line
        first = texts[0]
        parts = re.split(r"\bTAX\s+INVOICE\b|\bINVOICE\b", first, maxsplit=1, flags=re.I)
        left = parts[0].strip(" -:") if parts else ""
        if len(left.split()) >= 2 and re.search(r"[A-Za-z]", left):
            vendor_name = left

    if not vendor_name:
        # fallback: pick a company-like header line
        for t in texts[:15]:
            tl = t.lower()
            if re.search(r"\b(gstin|invoice no|invoice date|tax invoice)\b", tl):
                continue
            if len(t.split()) >= 2 and re.search(r"(private limited|pvt|ltd|limited|services|traders|enterprise)", tl):
                vendor_name = t
                break

    # ---------- Customer name + phone ----------
    cust_name, cust_phone = "", ""

    # 1) Bill To style
    bill_to_idx = next((i for i,t in enumerate(texts) if re.search(r"\bbill\s*to\b|\bbilled\s*to\b", t, re.I)), -1)
    if bill_to_idx != -1:
        for j in range(bill_to_idx + 1, min(bill_to_idx + 18, len(texts))):
            t = texts[j]
            if not cust_name and 1 < len(t.split()) <= 6 and re.search(r"[A-Za-z]", t):
                if not re.search(r"(address|phone|gstin|invoice|date|place of supply|tax)", t, re.I):
                    cust_name = t
            if re.search(r"\bphone\b|\bmobile\b", t, re.I):
                p = parse_phone(t)
                if p:
                    cust_phone = p
            if re.search(r"(item details|description|hsn|s\.?no|particulars)", t, re.I):
                break

    # 2) Customer: style (VERVE invoice)
    if not cust_name:
        cust_idx = next((i for i,t in enumerate(texts) if re.search(r"^\s*customer\s*:", t, re.I)), -1)
        if cust_idx != -1:
            after = re.sub(r"(?i)^\s*customer\s*:\s*", "", texts[cust_idx]).strip()
            after = _dedupe_exact_repeat_words(after)
            if len(after.split()) >= 2:
                cust_name = after
            else:
                # look for next good name line
                for j in range(cust_idx + 1, min(cust_idx + 6, len(texts))):
                    cand = _dedupe_exact_repeat_words(texts[j])
                    if 1 < len(cand.split()) <= 5 and re.search(r"[A-Za-z]", cand):
                        if not re.search(r"(billing address|shipping address|gstin|invoice)", cand, re.I):
                            cust_name = cand
                            break

    cust_name = _dedupe_exact_repeat_words(cust_name)

    # ---------- Address ----------
    cust_addr = ""

    # Prefer explicit Address: label (Bill-To invoices)
    for t in texts:
        if re.search(r"\baddress\b\s*:", t, re.I):
            cust_addr = re.sub(r"(?i)\*?\s*address\s*:\s*", "", t).strip()
            break

    # VERVE invoice: Billing Address / Shipping Address block
    if not cust_addr:
        hdr_idx = next((i for i,t in enumerate(texts) if re.search(r"\bbilling\s+address\b", t, re.I)), -1)
        if hdr_idx != -1:
            parts = []
            for j in range(hdr_idx + 1, min(hdr_idx + 10, len(texts))):
                t = texts[j]
                if re.search(r"(taxable|gst registration|central goods|thank you|powered by)", t, re.I):
                    break
                t2 = _take_left_columnish(t)
                t2 = _dedupe_exact_repeat_words(t2)
                if cust_name and t2.strip().lower() == cust_name.strip().lower():
                    continue
                if re.search(r"billing address|shipping address", t2, re.I):
                    continue
                if len(t2.strip()) < 2:
                    continue
                parts.append(t2.strip())

            # Join into a single address string
            if parts:
                # remove trailing INDIA noise if present
                parts = [re.sub(r"(?i)\bindia\b.*$", "", p).strip(" ,") for p in parts]
                cust_addr = ", ".join([p for p in parts if p])

    # ---------- Item ----------
    item = ""

    # Prefer line-item rows: find a line with text + multiple numbers (like VERVE)
    for i, t in enumerate(texts):
        tl = t.lower()
        if re.search(r"(gst registration|standard package|package|service|consult|subscription)", tl):
            if len(_nums_from_text(t)) >= 2:
                base = re.sub(r"\s+\d[\d,]*(?:\.\d{1,2})?\b.*$", "", t).strip()
                base = base.rstrip("-").strip()
                # if next line is a short descriptor, append it
                nxt = texts[i + 1] if i + 1 < len(texts) else ""
                if nxt and re.search(r"[A-Za-z]", nxt) and len(nxt.split()) <= 6 and not re.search(r"(tax|gst|invoice)", nxt, re.I):
                    item = f"{base} - {nxt.strip()}" if base else nxt.strip()
                else:
                    item = base
                break

    # fallback: the “S.No row” style (tractor invoice)
    if not item:
        for t in texts:
            if re.match(r"^\d+\s+", t) and not re.search(r"\bdescription\b|\bhsn\b|\bqty\b|\brate\b|\bamount\b", t, re.I):
                row = re.sub(r"^\d+\s+", "", t).strip()
                m = re.search(r"^(?P<desc>.+?)\s+\d{4,8}\s+\d+\s+", row)
                item = (m.group("desc").strip() if m else re.split(r"\s+\d{4,}\b", row)[0].strip())
                break

    # ---------- Color ----------
    color = ""
    for t in texts:
        tl = t.lower()
        for c in COLORS:
            if re.search(rf"\b{re.escape(c)}\b", tl):
                color = c.title()
                break
        if color:
            break

    # ---------- Amount ----------
    amount = None

    # direct total payable / grand total
    for i, t in enumerate(texts):
        if re.search(r"(total payable|grand total|invoice amount|total payable)", t, re.I):
            v = _max_num_from_text(t, min_value=1)
            if v is None and i + 1 < len(texts):
                v = _max_num_from_text(texts[i + 1], min_value=1)
            if v is not None:
                amount = v
                break

    # VERVE invoice often OCR misses "Total Payable" but we can compute:
    # total = taxable + cgst + sgst from the item row numbers
    if amount is None:
        for t in texts:
            tl = t.lower()
            if re.search(r"(gst registration|standard package|taxable)", tl):
                nums = [n for n in _nums_from_text(t) if n >= 1]
                if not nums:
                    continue
                taxable = max(nums)
                taxes = [n for n in nums if 0 < n < 0.60 * taxable]  # exclude duplicate taxable/rate
                if len(taxes) >= 2:
                    taxes = sorted(taxes, reverse=True)[:2]
                    amount = taxable + sum(taxes)
                    break

    return {
        "name": cust_name,
        "college": "",
        "phone": cust_phone,
        "address": cust_addr,
        "amount": float(amount) if amount is not None else None,
        "vendor_name": vendor_name,
        "item": item,
        "color": color,
        "raw_ocr_lines": texts,
    }

import re

def _num_candidates_loose(text: str):
    """
    Extract numbers like 79,000 or 70000 or 4,899.36 from messy OCR.
    Filters out dates-ish etc later via caller.
    """
    if not text:
        return []
    # remove obvious separators that break OCR
    t = text.replace("O", "0")
    # find comma-formatted and plain numbers
    raw = re.findall(r"\b\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?\b|\b\d+(?:\.\d{1,2})?\b", t)
    out = []
    for x in raw:
        try:
            out.append(float(x.replace(",", "")))
        except Exception:
            pass
    return out

def extract_fee_receipt_amount(lines):
    texts = [x["text"] for x in lines if x.get("text")]

    KEYWORDS = ["total", "payable", "amount", "bank", "cash", "received", "receipt"]
    IGNORE_HINTS = ["date", "receipt no", "roll", "register", "reg", "sem", "period", "class"]

    best_val = None
    best_rank = -10**9

    for t in texts:
        tl = t.lower()

        # skip obvious non-amount lines
        if any(h in tl for h in IGNORE_HINTS):
            continue
        # skip date formats like 02/07/2025
        if re.search(r"\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b", t):
            continue

        vals = _num_candidates_loose(t)
        if not vals:
            continue

        # keep only plausible fee-like amounts
        vals = [v for v in vals if 1000 <= v <= 5_000_000]
        if not vals:
            continue

        v = max(vals)
        rank = 0

        if any(k in tl for k in KEYWORDS):
            rank += 80
        if "total" in tl:
            rank += 50
        if "bank" in tl or "cash" in tl:
            rank += 30

        # Prefer larger values (total) over small line items
        rank += min(40, int(v // 1000))

        if rank > best_rank:
            best_rank = rank
            best_val = v

    if best_val is not None:
        return best_val

    # fallback: just take the maximum plausible number in the entire receipt
    all_vals = []
    for t in texts:
        if re.search(r"\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b", t):
            continue
        all_vals += [v for v in _num_candidates_loose(t) if 1000 <= v <= 5_000_000]
    return max(all_vals) if all_vals else None

# -------------------------
# Dispatcher
# -------------------------
def extract_by_doc_type(doc_type: str, lines: List[Dict[str, Any]]) -> Dict[str, Any]:
    dt = (doc_type or "").lower().strip()
    raw = [x["text"] for x in lines if x.get("text")]

    if dt in ["invoice", "bill"]:
        return extract_invoice(lines)

    if dt in ["fees_receipt", "fee_receipt", "fee", "receipt"]:
        return {
            "name": extract_name(lines),
            "college": extract_college(lines),
            "phone": "",
            "address": "",
            "amount": extract_fee_receipt_amount(lines),
            "vendor_name": "",
            "item": "",
            "color": "",
            "raw_ocr_lines": raw,
        }

    if dt in ["student_id", "id_card", "id"]:
        college = extract_college_header(lines) or extract_college(lines)
        name = extract_student_id_name(lines) or extract_name(lines)
        return {
            "name": name,
            "college": college,
            "phone": "",
            "address": "",
            "amount": None,
            "vendor_name": "",
            "item": "",
            "color": "",
            "raw_ocr_lines": raw,
        }

    if dt in ["marksheet", "mark_sheet", "result"]:
        college = extract_college_header(lines) or extract_college(lines)
        name = extract_marksheet_name(lines) or extract_name(lines)
        return {
            "name": name,
            "college": college,
            "phone": "",
            "address": "",
            "amount": None,
            "vendor_name": "",
            "item": "",
            "color": "",
            "raw_ocr_lines": raw,
        }

    # default fallback
    return {
        "name": extract_name(lines),
        "college": extract_college(lines),
        "phone": "",
        "address": "",
        "amount": extract_amount_generic(lines),
        "vendor_name": "",
        "item": "",
        "color": "",
        "raw_ocr_lines": raw,
    }
