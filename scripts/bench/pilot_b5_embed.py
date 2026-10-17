#!/usr/bin/env python3
"""B5 (device side): embed each utterance via llama-server /v1/embeddings,
one request per sentence, and record client wall time per sentence.

usage: pilot_b5_embed.py PORT UTTS.jsonl OUT.jsonl
"""
import json
import sys
import time
import urllib.request


def main():
    port, utts, path = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(path, "w") as out:
        for line in open(utts):
            r = json.loads(line)
            body = json.dumps({"input": r["text"], "model": "minilm"}).encode()
            req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/embeddings", data=body,
                                         headers={"Content-Type": "application/json"})
            t = time.monotonic()
            o = json.loads(urllib.request.urlopen(req, timeout=60).read())
            r["ms"] = (time.monotonic() - t) * 1000
            r["emb"] = o["data"][0]["embedding"]
            out.write(json.dumps(r) + "\n")


if __name__ == "__main__":
    main()
