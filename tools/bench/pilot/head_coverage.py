"""Which tokens Pilot needs fall outside smolmaxxing's pruned 65K head."""
import glob, json, re, sys, collections
from tokenizers import Tokenizer
tok = Tokenizer.from_file(sys.argv[1])
kept = {int(l) for l in open(sys.argv[2]) if l.strip()}
repo = sys.argv[3]
def rate(name, texts):
    total = miss = 0; worst = collections.Counter(); bad_texts = 0
    for t in texts:
        ids = tok.encode(t, add_special_tokens=False).ids
        m = [i for i in ids if i not in kept]
        total += len(ids); miss += len(m); bad_texts += bool(m)
        for i in m: worst[tok.decode([i])] += 1
    print("%-28s %7d tokens  %5d outside head (%.2f%%)  %4d of %d texts affected  e.g. %s" % (
        name, total, miss, 100.0 * miss / max(total, 1), bad_texts, len(texts),
        ", ".join(repr(w) for w, _ in worst.most_common(6))))
# Pilot's own task texts (requests and expected answers).
tasks = json.load(open(repo + "/crates/pilotd/tests/eval/tasks.json"))
texts = []
for t in tasks:
    for turn in t["turns"]:
        texts.append(turn["say"])
        texts += [str(x) for x in turn.get("expect", {}).get("answer_any", [])]
rate("eval requests + answers", texts)
# What Pilot copies into tool arguments.
synthetic = ["<PHONE_1>", "<EMAIL_1>", "<CONTACT_1>", "<CONTACT_12>", "+353 87 123 4567", "+358 40 123 4567",
    "anna@example.com", "seán.ó.briain@example.ie", "https://www.rte.ie/news/2026/1116/", "07:30", "14:45",
    "1800", "604800", "Dún Laoghaire", "Carrauntoohil", "Gweedore", "Cill Chainnigh", "Ennistymon",
    "Ballyjamesduff", "Muineachán", "Kraków", "Zürich", "Göteborg", "Þórshöfn", "Ljubljana", "Tallinn",
    "Αθήνα", "Москва", "東京", "北京", "القاهرة", "Μύκονος", "€12.50", "£7.99", "3½ cups", "−5°C", "20 °C",
    '{"seconds": 1800, "label": "pasta"}', '{"to": "<EMAIL_1>", "subject": "Thursday", "body": "Can we move it?"}']
rate("arguments Pilot copies", synthetic)
# Marathon's UI text in each language Pilot speaks.
by_lang = collections.defaultdict(list)
for f in glob.glob(repo + "/translations/**/*.ts", recursive=True):
    m = re.search(r"_([a-z]{2,3}(?:_[A-Z]{2})?)\.ts$", f)
    if not m or m.group(1) in ("en", "en_XA"): continue
    for t in re.findall(r"<translation[^>]*>(.*?)</translation>", open(f, encoding="utf-8").read(), re.S):
        t = re.sub(r"</?numerusform>", " ", t).strip()
        if t: by_lang[m.group(1).split("_")[0]].append(t)
for lang in sorted(by_lang):
    rate("UI text: " + lang, by_lang[lang])

# What the model must emit to speak and to call tools.
special = ["<|im_end|>", "<|im_start|>", "<|endoftext|>", "<tool_call>", "</tool_call>", "<think>", "</think>"]
for sp in special:
    i = tok.token_to_id(sp)
    print("special %-14s id %-7s %s" % (sp, i, "kept" if i in kept else "MISSING"))
fmt = '<tool_call>\n<function=timer_set>\n<parameter=seconds>\n1800\n</parameter>\n</function>\n</tool_call>'
rate("Qwen3.5 tool-call markup", [fmt])
byte_ids = [tok.token_to_id(c) for c in ["\u0120", "\u010a"]]
print("lowest kept ids:", sorted(kept)[:3], "n_kept", len(kept), "vocab", tok.get_vocab_size())
