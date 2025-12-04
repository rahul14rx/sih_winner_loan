from rapidfuzz import fuzz
from utils import norm_text, parse_phone

def sim_text(a: str, b: str) -> float:
    a = norm_text(str(a or ""))
    b = norm_text(str(b or ""))
    if not a or not b:
        return 0.0
    # tolerant for name/address/vendor
    return fuzz.token_set_ratio(a, b) / 100.0

def sim_phone(a: str, b: str) -> float:
    a = parse_phone(str(a or ""))
    b = parse_phone(str(b or ""))
    if not a or not b:
        return 0.0
    return 1.0 if a == b else 0.0

def sim_amount(a, b) -> float:
    if a is None or b is None:
        return 0.0
    try:
        a = float(a)
        b = float(b)
    except Exception:
        return 0.0
    if a <= 0 or b <= 0:
        return 0.0

    diff = abs(a - b)
    tol = max(1.0, 0.01 * max(a, b))  # 1% tolerance
    if diff <= tol:
        return 1.0

    # fade out; beyond 20% diff basically 0
    return max(0.0, 1.0 - diff / (0.20 * max(a, b)))

def sim_item(a: str, b: str) -> float:
    # Make sure partial “Mahindra” doesn’t become 100 against “Mahindra 275 DI TU”
    a = norm_text(str(a or ""))
    b = norm_text(str(b or ""))
    if not a or not b:
        return 0.0

    a_tokens = set(a.split())
    b_tokens = set(b.split())
    if not a_tokens:
        return 0.0

    coverage = len(a_tokens & b_tokens) / len(a_tokens)  # how much of agreement is covered
    base = fuzz.token_sort_ratio(a, b) / 100.0

    # cap by coverage (+ a little slack)
    return min(base, min(1.0, coverage + 0.10))

def verdict(score: float, hard_fail: bool) -> str:
    if hard_fail or score < 60:
        return "likely_fake"
    if score < 60:
        return "suspicious"
    return "trusted"
import re
from rapidfuzz import fuzz
from utils import norm_text

def _name_tokens(s: str):
    s = norm_text(str(s or ""))
    s = re.sub(r"[^a-z0-9\s]", " ", s)
    toks = [t for t in s.split() if t and t not in {"mr", "mrs", "ms"}]
    return toks

def _tok_match(a_tok: str, b_tok: str) -> bool:
    if a_tok == b_tok:
        return True
    # initial match: "r" matches "reina" or "reina" matches "r"
    if len(a_tok) == 1 and b_tok.startswith(a_tok):
        return True
    if len(b_tok) == 1 and a_tok.startswith(b_tok):
        return True
    return False

def sim_name(a: str, b: str) -> float:
    A = _name_tokens(a)
    B = _name_tokens(b)
    if not A or not B:
        return 0.0

    matched = 0
    used = set()
    for at in A:
        for j, bt in enumerate(B):
            if j in used:
                continue
            if _tok_match(at, bt):
                matched += 1
                used.add(j)
                break

    precision = matched / max(1, len(B))
    recall = matched / max(1, len(A))
    f1 = (2 * precision * recall / (precision + recall)) if (precision + recall) else 0.0

    # token_sort is stricter than token_set (doesn't give 100 for subsets)
    base = fuzz.token_sort_ratio(" ".join(A), " ".join(B)) / 100.0

    return max(f1, base)

def compare(doc_type: str, agreement: dict, extracted: dict):
    
    dt = (doc_type or "").lower().strip()

    # weights
    if dt in ["invoice", "bill"]:
        W = {
            "name": 20,
            "phone": 15,
            "address": 15,
            "amount": 20,
            "vendor_name": 10,
            "item": 15,
            "color": 5,
        }
    elif dt in ["fees_receipt", "fee_receipt", "fee", "receipt"]:
        W = {"name": 45, "college": 35, "amount": 20}
    elif dt in ["marksheet", "mark_sheet", "result"]:
        W = {"name": 60, "college": 40}
    elif dt in ["student_id", "id_card", "id"]:
        W = {"name": 40, "college": 60}
    else:
        W = {"name": 50, "college": 30, "amount": 20}

    fs = {}
    hard_fail = False

    for k, w in W.items():
        a = agreement.get(k)
        b = extracted.get(k)
        if a is None or (isinstance(a, str) and a.strip() == ""):
            fs[k] = {"score": 100.0, "weight": 0, "agreement": a, "extracted": b}
            continue
        
        # ALWAYS set s so it can never be unbound
        s = 0.0

        try:
            if k == "phone":
                s = sim_phone(a, b)
                if a and b and s == 0.0:
                    hard_fail = True

            elif k == "amount":
                s = sim_amount(a, b)
                if a is not None and b is not None and s < 0.3:
                    hard_fail = True

            elif k == "item":
                s = sim_item(a, b)
                if a and b and s < 0.4:
                    hard_fail = True

            elif k == "name":
                s = sim_name(a, b)
                # student docs often miss first/last token in OCR
                name_fail_thresh = 0.25 if dt in {"student_id","id_card","id","marksheet","mark_sheet","result"} else 0.4
                if a and b and s < name_fail_thresh:
                    hard_fail = True

            else:
                s = sim_text(a, b)

        except Exception:
            s = 0.0  # safety

        fs[k] = {
            "score": round(s * 100, 2),
            "weight": w,
            "agreement": a,
            "extracted": b,
        }

    total_w = sum(v["weight"] for v in fs.values())
    if total_w == 0:
        final = 100.0
    else:
        weighted = sum((v["score"] / 100.0) * v["weight"] for v in fs.values())
        final = (weighted / total_w) * 100.0

    final = round(final, 2)


    reasons = [f"{k} mismatch ({obj['score']}%)" for k, obj in fs.items() if obj["score"] < 60]

    return {
        "final_score": round(final, 2),
        "verdict": verdict(final, hard_fail=hard_fail),
        "hard_fail": hard_fail,
        "field_scores": fs,
        "reasons": reasons[:8],
    }
