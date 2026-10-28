#!/usr/bin/env python3
"""Converts intfloat/multilingual-e5-small to GGUF with llama.cpp's converter.

The model is a BERT whose vocabulary is XLM-R's SentencePiece. The
converter's BERT path writes it as WordPiece, which llama.cpp then splits
into almost the same tokens for every sentence (every published GGUF of the
model routed Pilot's tools at random). This takes the XLM-R vocabulary and
leaves BERT's positions as they are.

usage: convert-e5.py LLAMA_CPP_DIR MODEL_DIR OUT.gguf
"""
import runpy
import sys

llama, model, out = sys.argv[1:4]
sys.path.insert(0, llama)
from conversion import bert  # noqa: E402

bert_vocab = bert.BertModel.set_vocab


def set_vocab(self):
    if self.hparams.get("tokenizer_class") == "XLMRobertaTokenizer":
        return self._xlmroberta_set_vocab()
    return bert_vocab(self)


bert.BertModel.set_vocab = set_vocab
sys.argv = ["convert_hf_to_gguf.py", model, "--outtype", "q8_0", "--outfile", out]
runpy.run_path(f"{llama}/convert_hf_to_gguf.py", run_name="__main__")
