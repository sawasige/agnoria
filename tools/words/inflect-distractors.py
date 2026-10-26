#!/usr/bin/env python3
"""単語の穴埋めの誤答を作り直す（SPEC §2.1 / §3.1 [v2.2]）。

words.json の各単語の `en_distractors`（誤答の原形 3 つ。人手で選ぶ）から、例文ごとに
  - `blank`: 空欄にする語（例文中の形のまま。shipped、文頭なら Passengers）
  - `distractors`: `blank` と同じ活用形・大文字小文字にそろえた誤答 3 つ
を書き込む。空欄の形はアプリの `Cloze.fill` と同じ規則で探す（完全一致 → 規則的な語尾変化）。

usage: python3 tools/words/inflect-distractors.py Agnoria/Resources/Data/words.json [review.txt]
review.txt には空欄に正解と誤答を入れた一覧と、冠詞 a / an のずれ・数えられない名詞の複数形の注意を出す。
語を足したり誤答を変えたりしたら、必ず一覧を読んで、誤答が文として成り立たないことを確かめる。
"""
import json, re, sys


SUF = ["s","es","ed","d","ing","ly","er","est","ment","ion","tion","al"]
def infl(t, w):
    if t == w or len(w) < 3: return False
    if t.startswith(w) and t[len(w):] in SUF: return True
    if w.endswith("e") and t in (w[:-1]+"ing", w[:-1]+"ation"): return True
    if w.endswith("y") and t in [w[:-1]+s for s in ("ies","ied","ier","iest")]: return True
    d = w + w[-1]; return t in (d+"ing", d+"ed", d+"er")
def tokens(text):
    out=[]; start=None
    for i,c in enumerate(text):
        w = c.isalpha() or c in "'-’"
        if w and start is None: start=i
        elif not w and start is not None: out.append((start,i)); start=None
    if start is not None: out.append((start,len(text)))
    return out
def find_blank(text, word):
    w = word.lower(); toks = tokens(text)
    for s,e in toks:
        if text[s:e].lower() == w: return text[s:e]
    for s,e in toks:
        if infl(text[s:e].lower(), w): return text[s:e]
    return None

IRREG = {  # 過去形・過去分詞（同形でないものは過去分詞を優先しない。空欄の文脈で困る語は誤答に使わない）
 "say":"said","speak":"spoke","sell":"sold","take":"took","hear":"heard","lend":"lent","pay":"paid","choose":"chose",
 "bring":"brought","send":"sent","buy":"bought","make":"made","meet":"met","leave":"left","hold":"held","tell":"told",
}
DOUBLE = {"ship","plan","stop","admit","refer","prefer","occur","transfer","omit","permit","submit","commit","regret","incur",
          "concur","infer","compel","propel","equip","drop","shop","chat","fit","set","cut","put","get","run","swim","begin","forget","rob"}
UNCOUNT = {"luggage","equipment","advice","information","furniture","merchandise","stationery","staff","feedback","logistics",
           "retail","revenue","maintenance","training","morale","seniority","apparel","consensus","lodging","probation","freight","payroll"}
def kind(blank, word):
    b, w = blank.lower(), word.lower()
    if b == w: return "base"
    if b.endswith("ing"): return "ing"
    if b.endswith("ed") or (w.endswith("e") and b == w + "d"): return "ed"
    if b.endswith("s"): return "s"
    raise ValueError((blank, word))
def plural(w):
    if w.endswith("y") and w[-2] not in "aeiou": return w[:-1] + "ies"
    if re.search(r"(s|x|z|ch|sh)$", w): return w + "es"
    return w + "s"
def past(w):
    if w in IRREG: return IRREG[w]
    if w.endswith("e"): return w + "d"
    if w.endswith("y") and w[-2] not in "aeiou": return w[:-1] + "ied"
    if w in DOUBLE: return w + w[-1] + "ed"
    return w + "ed"
def ing(w):
    if w.endswith("ie"): return w[:-2] + "ying"
    if w.endswith("e") and not w.endswith("ee"): return w[:-1] + "ing"
    if w in DOUBLE: return w + w[-1] + "ing"
    return w + "ing"
def inflect(lemma, k):
    if " " in lemma: raise ValueError(lemma)
    return {"base": lemma, "s": plural(lemma), "ed": past(lemma), "ing": ing(lemma)}[k]
def match_case(form, blank):
    return form[:1].upper() + form[1:] if blank[:1].isupper() else form


path = sys.argv[1]
items = json.load(open(path, encoding="utf-8"))
review, warn = [], []
for x in items:
    lem = x.get("en_distractors")
    if not lem: warn.append(f"{x['id']} {x['word']}: en_distractors がない"); continue
    assert len(lem) == 3 and len(set(lem)) == 3 and x["word"].lower() not in [l.lower() for l in lem], x["id"]
    for e in x["examples"]:
        b = find_blank(e["en"], x["word"])
        if not b: warn.append(f"{x['id']}: 空欄にできない例文 {e['en']}"); continue
        k = kind(b, x["word"])
        ds = [match_case(inflect(l, k), b) for l in lem]
        if k == "s":
            for l in lem:
                if l in UNCOUNT: warn.append(f"{x['id']} {x['word']}: 不可算名詞 {l} を複数形に")
        e["blank"], e["distractors"] = b, ds
        m = re.search(r"\b(a|an)\s+$", e["en"][:e["en"].find(b)], re.I)
        if m:
            vowel = lambda s: (s[:1].lower() in "aeiou" and not s.lower().startswith(("uni", "unan", "use", "usu", "eu", "one"))) or s.lower().startswith(("hour", "honest"))
            for d in [b] + ds:
                if (m.group(1).lower() == "an") != vowel(d): warn.append(f"{x['id']}: 冠詞 {m.group(1)} と {d} が合わない")
        review.append(f"{x['id']} {x['word']}: {e['en'].replace(b, '[' + b + ']', 1)}  ×  " + " / ".join(ds))
with open(path, "w", encoding="utf-8") as f:
    json.dump(items, f, ensure_ascii=False, indent=2); f.write("\n")
if len(sys.argv) > 2:
    open(sys.argv[2], "w", encoding="utf-8").write("\n".join(review) + "\n")
print(len(review), "examples;", len(warn), "warnings"); print("\n".join(warn))
