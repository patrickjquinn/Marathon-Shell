#!/usr/bin/env python3
"""B5 (host side): multinomial logistic regression on the device embeddings.

Two splits: random 70/30 stratified by intent, and template-held-out (one of
six templates per intent never seen in training). Plain numpy.

usage: pilot_b5_head.py EMB.jsonl
"""
import json
import sys

import numpy as np


def train(X, y, k, l2=0.0, lr=8.0, steps=8000):
    W = np.zeros((X.shape[1], k))
    b = np.zeros(k)
    Y = np.eye(k)[y]
    for _ in range(steps):
        z = X @ W + b
        z -= z.max(1, keepdims=True)
        p = np.exp(z)
        p /= p.sum(1, keepdims=True)
        g = p - Y
        W -= lr * (X.T @ g / len(X) + l2 * W)
        b -= lr * g.mean(0)
    return W, b


def evaluate(X, y, tr, te, k):
    W, b = train(X[tr], y[tr], k)
    z = X[te] @ W + b
    p = np.exp(z - z.max(1, keepdims=True))
    p /= p.sum(1, keepdims=True)
    pred = p.argmax(1)
    acc = float((pred == y[te]).mean())
    conf = p.max(1)
    hi = conf >= 0.85
    return acc, int(te.sum()), float(hi.mean()), float((pred[hi] == y[te][hi]).mean()) if hi.any() else float("nan")


def main():
    rows = [json.loads(l) for l in open(sys.argv[1])]
    intents = sorted({r["intent"] for r in rows})
    X = np.array([r["emb"] for r in rows], dtype=np.float64)
    X /= np.linalg.norm(X, axis=1, keepdims=True)
    y = np.array([intents.index(r["intent"]) for r in rows])
    k = len(intents)
    rng = np.random.default_rng(16)
    te = np.zeros(len(rows), bool)
    for c in range(k):
        idx = np.flatnonzero(y == c)
        te[rng.choice(idx, size=int(round(0.3 * len(idx))), replace=False)] = True
    print("random 70/30: acc %.3f n=%d; share conf>=0.85 %.2f, acc there %.3f" % evaluate(X, y, ~te, te, k))
    held = np.array([int(r["template"].split("/")[1]) == (intents.index(r["intent"]) % 6) for r in rows])
    print("template held out: acc %.3f n=%d; share conf>=0.85 %.2f, acc there %.3f" % evaluate(X, y, ~held, held, k))
    ms = np.array([r["ms"] for r in rows])
    print("ms/sentence p50 %.1f p95 %.1f max %.1f n=%d" % (np.percentile(ms, 50), np.percentile(ms, 95), ms.max(), len(ms)))


if __name__ == "__main__":
    main()
