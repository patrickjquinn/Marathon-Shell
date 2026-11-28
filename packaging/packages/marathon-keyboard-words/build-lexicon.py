#!/usr/bin/env python3
"""Builds the keyboard's word lists from the AOSP wordlists.

    build-lexicon.py main_en_US.combined main_en_GB__experimental.combined OUTDIR

writes OUTDIR/en_US.lex and OUTDIR/en_GB.lex: one `word<TAB>frequency` line
per word (frequency 0-255, the AOSP log scale; a trailing `!` marks a word
never offered unless typed in full), then `%next` and one
`word<TAB>next next ...` line per word with what usually follows it.

The AOSP list is curated and is the base; the British list adds its common
words and, for en_GB, outranks the American spelling of each word it spells
the British way.
"""

import re
import sys
from pathlib import Path

GB_MIN = 40
MAX_NEXT = 6
WORD = re.compile(r"^[^\W\d_](?:[\w'’-]*[^\W\d_])?$")


def read(path):
    words, nexts, head = {}, {}, None
    for line in open(path, encoding="utf-8"):
        if line.startswith(" word="):
            fields = dict(kv.split("=", 1) for kv in line.strip().split(",") if "=" in kv)
            head = fields["word"]
            f = fields.get("f", "0")
            words[head] = {
                "f": int(f) if f.isdigit() else 255,
                "skip": fields.get("not_a_word") == "true",
                "offensive": fields.get("possibly_offensive") == "true"
                or "offensive" in fields.get("flags", ""),
            }
        elif line.startswith("  bigram=") and head is not None:
            fields = dict(kv.split("=", 1) for kv in line.strip().split(","))
            f = fields.get("f", "0")
            nexts.setdefault(head, {})[fields["bigram"]] = int(f) if f.isdigit() else 0
    return words, nexts


def british(word):
    """The British spellings an American one could have."""
    out = set()
    for a, b in (("or", "our"), ("iz", "is"), ("yz", "ys"), ("ense", "ence"), ("og", "ogue")):
        i = word.find(a)
        while i > 0:
            out.add(word[:i] + b + word[i + len(a):])
            i = word.find(a, i + 1)
    m = re.match(r"^(.*[^aeiou])er(s?)$", word)
    if m:
        out.add(m.group(1) + "re" + m.group(2))
    m = re.match(r"^(.*[aeiou])l(ed|ing|er|ers)$", word)
    if m:
        out.add(m.group(1) + "ll" + m.group(2))
    return out


def build(us, gb, british_spelling):
    words = {}
    for w, e in us[0].items():
        if not e["skip"] and e["f"] > 0 and WORD.match(w):
            words[w] = dict(e)
    for w, e in gb[0].items():
        if w not in words and e["f"] >= GB_MIN and WORD.match(w):
            words[w] = dict(e)
    if british_spelling:
        for w in list(words):
            for b in british(w):
                if b in gb[0] and gb[0][b]["f"] >= GB_MIN and b not in us[0]:
                    words.setdefault(b, dict(gb[0][b]))
                    words[b]["f"] = max(words[b]["f"], words[w]["f"])
                    words[w]["f"] = max(1, words[w]["f"] - 40)
    # Corpus capitals at a sentence's start: "The" is "the".
    for w in list(words):
        if w != w.lower() and w.lower() in words and w[1:] == w[1:].lower():
            words[w.lower()]["f"] = max(words[w.lower()]["f"], words.pop(w)["f"])
    # A next word's f is how likely it is (AOSP: "thank" goodness 1, God 2,
    # you 3); both lists' votes add up.
    votes = {}
    for source in (us[1], gb[1]):
        for head, follow in source.items():
            if head in words:
                for n, f in follow.items():
                    if n in words:
                        votes.setdefault(head, {})
                        votes[head][n] = votes[head].get(n, 0) + f
    nexts = {
        head: sorted(follow, key=lambda n: (-follow[n], -words[n]["f"]))
        for head, follow in votes.items()
    }
    return words, nexts


def write(path, words, nexts):
    with open(path, "w", encoding="utf-8") as out:
        for w in sorted(words):
            e = words[w]
            out.write(f"{w}\t{e['f']}{'!' if e['offensive'] else ''}\n")
        out.write("%next\n")
        for head in sorted(nexts):
            out.write(f"{head}\t{' '.join(nexts[head][:MAX_NEXT])}\n")


def main():
    us, gb, outdir = read(sys.argv[1]), read(sys.argv[2]), Path(sys.argv[3])
    outdir.mkdir(parents=True, exist_ok=True)
    for name, british_spelling in (("en_US", False), ("en_GB", True)):
        words, nexts = build(us, gb, british_spelling)
        write(outdir / f"{name}.lex", words, nexts)
        print(f"{name}: {len(words)} words, {len(nexts)} with next words")


if __name__ == "__main__":
    main()
