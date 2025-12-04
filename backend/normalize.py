import re
from typing import Dict, List, Optional, Tuple
from mock_db import STATE_CODES

DIGIT_FROM_LETTER: Dict[str, List[str]] = {
    "O": ["0"], "D": ["0"],
    "I": ["1"], "L": ["1"],
    "Z": ["2"],
    "S": ["5", "3"],
    "B": ["8"],
    "G": ["6"],
    "E": ["3"],
}

LETTER_FROM_DIGIT: Dict[str, List[str]] = {
    "0": ["O", "D"],
    "1": ["I", "L"],
    "2": ["Z"],
    "3": ["B", "E"],
    "5": ["S"],
    "6": ["G"],
    "8": ["B"],
}

STATE_LETTER_CONFUSIONS = {"A": ["N"], "N": ["A"]}  # TN vs TA errors

CONF = {
    "A": {"N"}, "N": {"A"},
    "O": {"0","D"}, "0": {"O","D"}, "D": {"0","O"},
    "I": {"1","L"}, "1": {"I","L"}, "L": {"1","I"},
    "Z": {"2"}, "2": {"Z"},
    "S": {"5","3"}, "5": {"S"}, "3": {"S","B","E"},
    "B": {"8","3"}, "8": {"B"},
    "G": {"6"}, "6": {"G"},
    "E": {"3","B"},
}

def sub_cost(a: str, b: str) -> float:
    if a == b:
        return 0.0
    if b in CONF.get(a, set()) or a in CONF.get(b, set()):
        return 0.25
    return 1.0

def wedit(a: str, b: str) -> float:
    # weighted edit distance (insertion/deletion cost=1)
    n, m = len(a), len(b)
    dp = [[0.0] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        dp[i][0] = float(i)
    for j in range(1, m + 1):
        dp[0][j] = float(j)

    for i in range(1, n + 1):
        ai = a[i - 1]
        for j in range(1, m + 1):
            bj = b[j - 1]
            dp[i][j] = min(
                dp[i - 1][j] + 1.0,                 # delete
                dp[i][j - 1] + 1.0,                 # insert
                dp[i - 1][j - 1] + sub_cost(ai, bj) # substitute
            )
    return dp[n][m]

def best_prefer_match(text: str, prefer: set) -> str:
    s = only_alnum(text)
    if not s or not prefer:
        return ""

    best_plate = ""
    best_score = 1e9

    for plate in prefer:
        L = len(plate)
        # scan windows around target length (handles extra digits/noise in OCR)
        for win_len in range(max(6, L - 2), min(len(s), L + 2) + 1):
            for i in range(0, len(s) - win_len + 1):
                chunk = s[i:i + win_len]
                dist = wedit(chunk, plate)
                if dist < best_score:
                    best_score = dist
                    best_plate = plate

    # strict threshold: tune if needed
    return best_plate if best_score <= 2.5 else ""


def only_alnum(s: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", (s or "").upper())


def diff_count(a: str, b: str) -> int:
    n = min(len(a), len(b))
    d = abs(len(a) - len(b))
    for i in range(n):
        if a[i] != b[i]:
            d += 1
    return d


def _gen_conversions(raw: str, kind: str) -> List[Tuple[str, int]]:
    # kind: "digit" or "letter"
    acc = [("", 0)]
    for ch in raw:
        nxt: List[Tuple[str, int]] = []
        for pref, cost in acc:
            if kind == "digit":
                if ch.isdigit():
                    nxt.append((pref + ch, cost))
                elif ch.isalpha() and ch in DIGIT_FROM_LETTER:
                    for d in DIGIT_FROM_LETTER[ch]:
                        nxt.append((pref + d, cost + 1))
            else:
                if ch.isalpha():
                    nxt.append((pref + ch, cost))
                elif ch.isdigit() and ch in LETTER_FROM_DIGIT:
                    for c in LETTER_FROM_DIGIT[ch]:
                        nxt.append((pref + c, cost + 1))

        acc = nxt
        if not acc:
            return []

    dedup: Dict[str, int] = {}
    for s, c in acc:
        if s not in dedup or c < dedup[s]:
            dedup[s] = c
    return [(s, dedup[s]) for s in dedup]


def _state_variants(st: str) -> List[Tuple[str, int]]:
    vars = {(st, 0)}
    for i, ch in enumerate(st):
        if ch in STATE_LETTER_CONFUSIONS:
            for rep in STATE_LETTER_CONFUSIONS[ch]:
                t = list(st)
                t[i] = rep
                vars.add(("".join(t), 1))
    return list(vars)


def _all_rc_candidates_from_alnum(s: str) -> List[Tuple[int, str]]:
    out: Dict[str, int] = {}
    if len(s) < 8 or len(s) > 12:
        return []

    for rto_len in (1, 2):
        for series_len in (1, 2, 3):
            min_len = 2 + rto_len + series_len + 1
            max_len = 2 + rto_len + series_len + 4
            if len(s) < min_len or len(s) > max_len:
                continue

            num_len = len(s) - (2 + rto_len + series_len)
            if num_len < 1 or num_len > 4:
                continue

            raw_state = s[:2]
            raw_rto = s[2:2 + rto_len]
            raw_series = s[2 + rto_len:2 + rto_len + series_len]
            raw_num = s[2 + rto_len + series_len:]

            st_opts = _gen_conversions(raw_state, "letter")
            rto_opts = _gen_conversions(raw_rto, "digit")
            ser_opts = _gen_conversions(raw_series, "letter")
            num_opts = _gen_conversions(raw_num, "digit")

            for st, cst in st_opts:
                for st2, extra in _state_variants(st):
                    if st2 not in STATE_CODES:
                        continue
                    cst2 = cst + extra
                    for rto, crto in rto_opts:
                        for ser, cser in ser_opts:
                            for num, cnum in num_opts:
                                cand = f"{st2}{rto}{ser}{num}"
                                if not re.fullmatch(r"[A-Z]{2}\d{1,2}[A-Z]{1,3}\d{1,4}", cand):
                                    continue
                                cost = cst2 + crto + cser + cnum
                                if cand not in out or cost < out[cand]:
                                    out[cand] = cost

    res = [(out[k], k) for k in out]
    res.sort(key=lambda x: x[0])
    return res


def find_best_rc(text: str, prefer: Optional[set] = None, prefer_only: bool = False) -> str:
    # If demo mode: return ONLY something from MOCK_DB (closest match)
    if prefer and prefer_only:
        hit = best_prefer_match(text, prefer)
        if hit:
            return hit
        return ""

    # else: do your existing logic (sliding windows + candidate generation)
    s = only_alnum(text)
    if not s:
        return ""

    best: Optional[str] = None
    best_key = (2, 10**9)

    for L in range(8, 13):
        if len(s) < L:
            continue
        for i in range(0, len(s) - L + 1):
            chunk = s[i:i + L]
            cands = _all_rc_candidates_from_alnum(chunk)
            if not cands:
                continue

            cost, cand = cands[0]
            key = (0 if (prefer and cand in prefer) else 1, cost)
            if key < best_key:
                best_key = key
                best = cand

    if best is None:
        return ""
    return best if best_key[1] <= 6 else ""

def normalize_make_model(s: str) -> str:
    t = (s or "").upper()
    t = re.sub(r"[^A-Z0-9 ]", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    reps = {
        "MARUTI": "MARUTI SUZUKI",
        "MARUTI SUZUKI INDIA": "MARUTI SUZUKI",
        "HERO HONDA": "HERO",
        "BAJAJ AUTO": "BAJAJ",
        "TVS MOTOR": "TVS",
    }
    return reps.get(t, t)


def canonical_color(raw: str) -> str:
    t = (raw or "").upper()
    t = re.sub(r"[^A-Z ]", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    if not t:
        return ""

    m = {
        "PEARL WHITE": "WHITE",
        "OFF WHITE": "WHITE",
        "WHITE": "WHITE",
        "BLACK": "BLACK",
        "DARK BLACK": "BLACK",
        "SILVER": "SILVER",
        "METALLIC SILVER": "SILVER",
        "GREY": "GREY",
        "GRAY": "GREY",
        "METALLIC GREY": "GREY",
        "RED": "RED",
        "BLUE": "BLUE",
        "GREEN": "GREEN",
        "YELLOW": "YELLOW",
        "BROWN": "BROWN",
        "ORANGE": "ORANGE",
        "MAROON": "MAROON",
        "BEIGE": "BEIGE",
    }
    if t in m:
        return m[t]
    for k, v in m.items():
        if k in t:
            return v
    return t.split(" ")[0]
