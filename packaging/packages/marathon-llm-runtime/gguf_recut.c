// gguf_recut: (re)build the pruned LM head of a tied-embedding GGUF, on the TV itself.
// Same result as `tools/gguf_build.py --replace-head --head-ids` (the Python tool needs the file on the Mac,
// and moving GBs over adb/Wi-Fi is slow and flaky). Drops any existing output.weight / output_ids.weight,
// then appends output.weight = rows of token_embd listed in ids.txt (raw bytes, same type) and
// output_ids.weight (I32). All other tensors and all metadata are copied unchanged, except the
// tvbox.pruned_head.n_keep key, which is (re)written.
// usage: gguf_recut <in.gguf> <out.gguf> <ids.txt | none>   ("none": drop the pruned head, back to the tied full-vocab head)
#define _FILE_OFFSET_BITS 64
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { char *name; uint32_t nd; uint64_t ne[4]; uint32_t type; uint64_t off, size, new_off; } tinfo;

static FILE *fi;
static void rd(void *p, size_t n) { if (fread(p, 1, n, fi) != n) { fprintf(stderr, "short read\n"); exit(1); } }
static uint32_t u32(void) { uint32_t v; rd(&v, 4); return v; }
static uint64_t u64(void) { uint64_t v; rd(&v, 8); return v; }

// type sizes: block size, bytes per block (ggml.h type ids)
static void tsz(uint32_t t, int *bs, int *bb) {
    switch (t) {
        case 0: *bs = 1; *bb = 4; return;       case 1: *bs = 1; *bb = 2; return;      // f32 f16
        case 2: *bs = 32; *bb = 18; return;     case 3: *bs = 32; *bb = 20; return;    // q4_0 q4_1
        case 6: *bs = 32; *bb = 22; return;     case 7: *bs = 32; *bb = 24; return;    // q5_0 q5_1
        case 8: *bs = 32; *bb = 34; return;                                            // q8_0
        case 10: *bs = 256; *bb = 84; return;   case 11: *bs = 256; *bb = 110; return; // q2_K q3_K
        case 12: *bs = 256; *bb = 144; return;  case 13: *bs = 256; *bb = 176; return; // q4_K q5_K
        case 14: *bs = 256; *bb = 210; return;  case 20: *bs = 32; *bb = 18; return;   // q6_K iq4_nl
        case 23: *bs = 256; *bb = 136; return;  case 26: *bs = 1; *bb = 4; return;     // iq4_xs i32
        case 30: *bs = 1; *bb = 2; return;                                             // bf16
        case 34: *bs = 256; *bb = 54; return;   case 35: *bs = 256; *bb = 66; return;  // tq1_0 tq2_0
        case 42: *bs = 64; *bb = 18; return;                                           // q2_0 (PrismML, group 64)
    }
    fprintf(stderr, "unsupported tensor type %u\n", t); exit(1);
}

// skip one gguf value of type t, returning nothing (we copy raw bytes by file position)
static void skip_val(uint32_t t) {
    static const int sz[] = {1, 1, 2, 2, 4, 4, 4, 1, 0, 0, 8, 8, 8};
    if (t == 8) { uint64_t n = u64(); fseeko(fi, n, SEEK_CUR); return; }
    if (t == 9) { uint32_t et = u32(); uint64_t n = u64(); for (uint64_t i = 0; i < n; i++) skip_val(et); return; }
    if (t > 12) { fprintf(stderr, "bad kv type %u\n", t); exit(1); }
    fseeko(fi, sz[t], SEEK_CUR);
}

static void wstr(FILE *f, const char *s) { uint64_t n = strlen(s); fwrite(&n, 8, 1, f); fwrite(s, 1, n, f); }

int main(int argc, char **argv) {
    if (argc != 4) { fprintf(stderr, "usage: gguf_recut <in.gguf> <out.gguf> <ids.txt>\n"); return 1; }
    fi = fopen(argv[1], "rb"); if (!fi) { perror(argv[1]); return 1; }
    char magic[4]; rd(magic, 4); if (memcmp(magic, "GGUF", 4)) { fprintf(stderr, "not gguf\n"); return 1; }
    uint32_t ver = u32(); uint64_t nt = u64(), nkv = u64();

    // metadata: remember the raw byte ranges of the keys we keep
    off_t *kb = calloc(nkv, sizeof(off_t)), *ke = calloc(nkv, sizeof(off_t)); uint64_t nkeep = 0;
    uint32_t align = 32;
    for (uint64_t i = 0; i < nkv; i++) {
        off_t b = ftello(fi);
        uint64_t kl = u64(); char *k = malloc(kl + 1); rd(k, kl); k[kl] = 0;
        uint32_t t = u32();
        if (!strcmp(k, "general.alignment") && t == 4) { align = u32(); fseeko(fi, -4, SEEK_CUR); }
        skip_val(t);
        if (strncmp(k, "tvbox.pruned_head", 17)) { kb[nkeep] = b; ke[nkeep] = ftello(fi); nkeep++; }
        free(k);
    }
    tinfo *ts = calloc(nt + 2, sizeof(tinfo)); uint64_t n = 0; int emb = -1;
    for (uint64_t i = 0; i < nt; i++) {
        tinfo t = {0};
        uint64_t l = u64(); t.name = malloc(l + 1); rd(t.name, l); t.name[l] = 0;
        t.nd = u32(); uint64_t ne = 1;
        for (uint32_t d = 0; d < t.nd; d++) { t.ne[d] = u64(); ne *= t.ne[d]; }
        t.type = u32(); t.off = u64();
        int bs, bb; tsz(t.type, &bs, &bb); t.size = ne / bs * bb;
        if (!strcmp(t.name, "output.weight") || !strcmp(t.name, "output_ids.weight")) { fprintf(stderr, "dropping %s\n", t.name); continue; }
        if (!strcmp(t.name, "token_embd.weight")) emb = (int) n;
        ts[n++] = t;
    }
    off_t data_start = (ftello(fi) + align - 1) / align * align;
    if (emb < 0) { fprintf(stderr, "no token_embd\n"); return 1; }

    // ids
    int nohead = !strcmp(argv[3], "none");
    int32_t *ids = malloc(sizeof(int32_t) * ts[emb].ne[1]); uint64_t nk = 0; long v;
    if (!nohead) {
        FILE *fid = fopen(argv[3], "r"); if (!fid) { perror(argv[3]); return 1; }
        while (fscanf(fid, "%ld", &v) == 1) { if (v < 0 || (uint64_t) v >= ts[emb].ne[1]) { fprintf(stderr, "bad id %ld\n", v); return 1; } ids[nk++] = (int32_t) v; }
        fclose(fid);
    }
    int bs, bb; tsz(ts[emb].type, &bs, &bb);
    uint64_t row = ts[emb].ne[0] / bs * bb;

    tinfo head = { "output.weight", 2, { ts[emb].ne[0], nk }, ts[emb].type, 0, row * nk, 0 };
    tinfo hid  = { "output_ids.weight", 1, { nk }, 26, 0, 4 * nk, 0 };
    // new layout: kept tensors in original data order, then head, ids
    tinfo **ord = malloc(sizeof(tinfo *) * (n + 2));
    for (uint64_t i = 0; i < n; i++) ord[i] = &ts[i];
    for (uint64_t i = 0; i < n; i++) for (uint64_t j = i + 1; j < n; j++) if (ord[j]->off < ord[i]->off) { tinfo *x = ord[i]; ord[i] = ord[j]; ord[j] = x; }
    ord[n] = &head; ord[n + 1] = &hid;
    uint64_t nh = nohead ? 0 : 2, o = 0;
    for (uint64_t i = 0; i < n + nh; i++) { ord[i]->new_off = o; o += (ord[i]->size + align - 1) / align * align; }

    FILE *fo = fopen(argv[2], "wb"); if (!fo) { perror(argv[2]); return 1; }
    uint64_t nt2 = n + nh, nkv2 = nkeep + (nohead ? 0 : 1);
    fwrite("GGUF", 1, 4, fo); fwrite(&ver, 4, 1, fo); fwrite(&nt2, 8, 1, fo); fwrite(&nkv2, 8, 1, fo);
    char *buf = malloc(8 << 20);
    for (uint64_t i = 0; i < nkeep; i++) {
        fseeko(fi, kb[i], SEEK_SET); size_t len = ke[i] - kb[i];
        while (len) { size_t c = len < (8u << 20) ? len : (8u << 20); rd(buf, c); fwrite(buf, 1, c, fo); len -= c; }
    }
    if (!nohead) { wstr(fo, "tvbox.pruned_head.n_keep"); uint32_t t4 = 4, nk32 = (uint32_t) nk; fwrite(&t4, 4, 1, fo); fwrite(&nk32, 4, 1, fo); }
    tinfo *all[2] = { &head, &hid };
    for (uint64_t i = 0; i < n + nh; i++) {
        tinfo *t = i < n ? &ts[i] : all[i - n];
        wstr(fo, t->name); fwrite(&t->nd, 4, 1, fo); fwrite(t->ne, 8, t->nd, fo); fwrite(&t->type, 4, 1, fo); fwrite(&t->new_off, 8, 1, fo);
    }
    off_t base = (ftello(fo) + align - 1) / align * align;
    static const char zero[64] = {0};
    while (ftello(fo) < base) fwrite(zero, 1, 1, fo);
    for (uint64_t i = 0; i < n; i++) {
        tinfo *t = ord[i];
        fseeko(fo, base + t->new_off, SEEK_SET); fseeko(fi, data_start + t->off, SEEK_SET);
        uint64_t left = t->size;
        while (left) { size_t c = left < (8u << 20) ? left : (8u << 20); rd(buf, c); fwrite(buf, 1, c, fo); left -= c; }
    }
    if (!nohead) {
        fseeko(fo, base + head.new_off, SEEK_SET);
        for (uint64_t i = 0; i < nk; i++) { fseeko(fi, data_start + ts[emb].off + (uint64_t) ids[i] * row, SEEK_SET); rd(buf, row); fwrite(buf, 1, row, fo); }
        fseeko(fo, base + hid.new_off, SEEK_SET); fwrite(ids, 4, nk, fo);
    }
    uint64_t end = base + o, cur = ftello(fo);
    while (cur < end) { size_t c = end - cur < 64 ? end - cur : 64; fwrite(zero, 1, c, fo); cur += c; }
    fclose(fo);
    printf("wrote %s: %llu kept + %llu head tensors, head %llu rows (%.1f MB, type %u), %llu bytes\n", argv[2],
           (unsigned long long) n, (unsigned long long) nh, (unsigned long long) nk, row * nk / 1e6, ts[emb].type, (unsigned long long) end);
    return 0;
}
