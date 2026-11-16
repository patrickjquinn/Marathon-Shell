"""A pruned LM head for Pilot: smolmaxxing's ml60k-p8 plus every token Pilot's prompts, tools,
placeholders, tasks and Marathon's UI text use; padded to a multiple of 8 (smolmaxxing section 17)."""
import glob, json, re, sys
from tokenizers import Tokenizer
tok = Tokenizer.from_file(sys.argv[1]); base = [int(l) for l in open(sys.argv[2]) if l.strip()]
repo, request, out = sys.argv[3], sys.argv[4], sys.argv[5]
kept = set(base); texts = []
req = json.load(open(request))
for m in req["messages"]: texts.append(m["content"] or "")
for t in req["tools"]:
    f = t["function"]; texts += [json.dumps(t), f["name"], f["description"]]
    params = f["parameters"].get("properties", {})
    for p in params:
        texts.append("<tool_call>\n<function=%s>\n<parameter=%s>\nx\n</parameter>\n</function>\n</tool_call>" % (f["name"], p))
for kind in ("PHONE", "EMAIL", "CONTACT", "ADDRESS", "NAME", "URL", "IBAN", "CARD"):
    for n in range(1, 31): texts += ["<%s_%d>" % (kind, n), " <%s_%d>" % (kind, n)]
for t in json.load(open(repo + "/crates/pilotd/tests/eval/tasks.json")):
    for turn in t["turns"]:
        texts.append(turn["say"]); texts += [str(x) for x in turn.get("expect", {}).get("answer_any", [])]
for f in glob.glob(repo + "/**/*.qml", recursive=True):
    if "/target/" in f or "/.claude/" in f: continue
    try: texts += re.findall(r'qsTr\("((?:[^"\\]|\\.)*)"', open(f, encoding="utf-8").read())
    except UnicodeDecodeError: pass
src = open(repo + "/crates/pilotd/src/pipeline.rs", encoding="utf-8").read()
texts += re.findall(r'"((?:[^"\\]|\\.){20,})"', src)
added = set()
for t in texts:
    for i in tok.encode(t, add_special_tokens=False).ids:
        if i not in kept: added.add(i)
ids = sorted(kept | added)
# Pad to a multiple of 8 with the next most frequent-looking ids not yet kept (lowest ids first).
pad = (-len(ids)) % 8; extra = [i for i in range(tok.get_vocab_size()) if i not in kept and i not in added][:pad]
ids = sorted(set(ids) | set(extra))
open(out, "w").write("\n".join(map(str, ids)) + "\n")
print("texts %d; added %d Pilot tokens to %d; head %d rows (multiple of 8: %s)" % (len(texts), len(added), len(base), len(ids), len(ids) % 8 == 0))
