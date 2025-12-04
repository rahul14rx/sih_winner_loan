import re
from typing import Dict, Any
from normalize import normalize_make_model, canonical_color

def norm_phone(p: str) -> str:
    d = re.sub(r"\D", "", p or "")
    return d[-10:] if len(d) >= 10 else d

def levenshtein(a: str, b: str) -> int:
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    cur = [0] * (len(b) + 1)
    for i in range(1, len(a) + 1):
        cur[0] = i
        for j in range(1, len(b) + 1):
            cost = 0 if a[i - 1] == b[j - 1] else 1
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        prev, cur = cur, prev
    return prev[len(b)]

def strict_similarity(a: str, b: str) -> float:
    a = normalize_make_model(a)
    b = normalize_make_model(b)
    if not a or not b:
        return 0.0
    mx = max(len(a), len(b))
    return max(0.0, min(1.0, 1.0 - (levenshtein(a, b) / float(mx))))

import re
from typing import Dict, Any
from normalize import normalize_make_model, canonical_color

def norm_phone(p: str) -> str:
    d = re.sub(r"\D", "", p or "")
    return d[-10:] if len(d) >= 10 else d

def norm_text(s: str) -> str:
    s = (s or "").upper()
    s = re.sub(r"[^A-Z0-9 ]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s

def levenshtein(a: str, b: str) -> int:
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    cur = [0] * (len(b) + 1)
    for i in range(1, len(a) + 1):
        cur[0] = i
        for j in range(1, len(b) + 1):
            cost = 0 if a[i - 1] == b[j - 1] else 1
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        prev, cur = cur, prev
    return prev[len(b)]

def strict_similarity(a: str, b: str) -> float:
    a = norm_text(a)
    b = norm_text(b)
    if not a or not b:
        return 0.0
    mx = max(len(a), len(b))
    return max(0.0, min(1.0, 1.0 - (levenshtein(a, b) / float(mx))))

def compare_officer_vs_api(officer: Dict[str, str], api_vehicle: Dict[str, str]) -> Dict[str, Any]:
    # officer
    o_name = norm_text(officer.get("name", ""))
    o_addr = norm_text(officer.get("address", ""))
    o_phone = norm_phone(officer.get("phone", ""))

    o_make = normalize_make_model(officer.get("vehicle_make", ""))
    o_model = normalize_make_model(officer.get("vehicle_model", ""))
    o_color = canonical_color(officer.get("vehicle_color", ""))

    # api/mock
    a_name = norm_text(api_vehicle.get("owner_name", ""))
    a_addr = norm_text(api_vehicle.get("owner_address", ""))
    a_phone = norm_phone(api_vehicle.get("owner_phone", ""))

    a_make = normalize_make_model(api_vehicle.get("maker", ""))
    a_model = normalize_make_model(api_vehicle.get("model", ""))
    a_color = canonical_color(api_vehicle.get("color", ""))

    fields: Dict[str, str] = {}
    hard_fail = False

    # PHONE (hard): easiest & most reliable
    if not o_phone:
        fields["phone"] = "not_present"
        hard_fail = True
    else:
        fields["phone"] = "match" if (a_phone and o_phone == a_phone) else "mismatch"
        if fields["phone"] == "mismatch":
            hard_fail = True

    # NAME (soft strict)
    if not o_name:
        fields["name"] = "not_present"
        hard_fail = True
    else:
        s = strict_similarity(o_name, a_name)
        fields["name"] = "match" if s >= 0.90 else ("weakMatch" if s >= 0.82 else "mismatch")
        if fields["name"] == "mismatch":
            hard_fail = True

    # ADDRESS (soft, not too strict)
    if not o_addr:
        fields["address"] = "not_present"
    else:
        s = strict_similarity(o_addr, a_addr)
        fields["address"] = "match" if s >= 0.85 else ("weakMatch" if s >= 0.75 else "mismatch")
        # don't hard fail on address

    # MAKE (hard)
    if not o_make:
        fields["make"] = "not_present"
        hard_fail = True
    else:
        fields["make"] = "match" if o_make == a_make else "mismatch"
        if fields["make"] == "mismatch":
            hard_fail = True

    # COLOR (hard)
    if not o_color:
        fields["color"] = "not_present"
        hard_fail = True
    else:
        fields["color"] = "match" if o_color == a_color else "mismatch"
        if fields["color"] == "mismatch":
            hard_fail = True

    # MODEL (soft strict)
    if not o_model:
        fields["model"] = "not_present"
    else:
        s = strict_similarity(o_model, a_model)
        fields["model"] = "match" if s >= 0.85 else ("weakMatch" if s >= 0.78 else "mismatch")

    # score (weighted)
    weights = {"match": 1.0, "weakMatch": 0.6, "not_present": 0.0, "mismatch": 0.0}
    wmap = {"phone": 6, "name": 4, "make": 4, "color": 3, "model": 3, "address": 2}

    total_w = sum(wmap.values())
    score = sum(weights.get(fields.get(k, "not_present"), 0.0) * w for k, w in wmap.items()) / max(1, total_w)

    if hard_fail:
        level, reason = "rejected", "Hard mismatch in critical fields (phone/name/make/color)."
    elif score >= 0.90:
        level, reason = "trusted", "Officer-entered details match RC details under strict normalization."
    else:
        level, reason = "suspicious", "No hard mismatches, but similarity below strict threshold."

    overall = {"trusted": "MATCH", "suspicious": "PARTIAL_MATCH", "rejected": "MISMATCH"}[level]

    return {"overall": overall, "level": level, "score": score, "reason": reason, "fields": fields}
