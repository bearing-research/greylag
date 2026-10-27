// A C host for greylag: walks a document through the handle API, checks
// the error path, and times the two parse entry points.
//
// Build:
//   goose --standalone --header greylag.h -o greylag.c src/greylag.goose
//   cc -O2 greylag.c c/host.c -o host -lm -pthread
// Run:
//   ./host file.xml [repeat]

#include "greylag.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/resource.h>

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}

static long peak_rss_kb(void) {
    FILE *f = fopen("/proc/self/status", "r");
    char line[256];
    long kb = 0;
    if (f) { while (fgets(line, sizeof line, f)) if (sscanf(line, "VmHWM: %ld kB", &kb) == 1) break; fclose(f); }
    return kb;
}

static char *read_file(const char *path, size_t *len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc((size_t)n + 1);
    if (fread(buf, 1, (size_t)n, f) != (size_t)n) { fclose(f); free(buf); return NULL; }
    fclose(f);
    buf[n] = 0;
    *len = (size_t)n;
    return buf;
}

static void print_slice(const uint8_t *p, int64_t n) { fwrite(p, 1, (size_t)n, stdout); }

// Walks the tree, counting; a depth-limited print on the first call.
static void walk(int64_t h, int depth, long *elems, long *texts, long *attrs, int print) {
    for (; h >= 0; h = greylag_next(h)) {
        int32_t k = greylag_kind(h);
        int64_t len;
        if (k == 1) {
            (*elems)++;
            int64_t na = greylag_attr_count(h);
            *attrs += na;
            if (print && depth < 3) {
                printf("%*s<", depth * 2, "");
                const uint8_t *name = greylag_name(h, &len);
                print_slice(name, len);
                for (int64_t i = 0; i < na; i++) {
                    putchar(' ');
                    const uint8_t *an = greylag_attr_name(h, i, &len);
                    print_slice(an, len);
                    printf("=\"");
                    const uint8_t *av = greylag_attr_value(h, i, &len);
                    print_slice(av, len);
                    putchar('"');
                }
                printf(">\n");
            }
            walk(greylag_first_child(h), depth + 1, elems, texts, attrs, print);
        } else if (k == 2) {
            (*texts)++;
        }
    }
}

int main(int argc, char **argv) {
    goose_init(argc, argv);
    if (argc < 2) { fprintf(stderr, "usage: host file.xml [repeat]\n"); return 2; }
    int repeat = argc > 2 ? atoi(argv[2]) : 1;
    const char *mode = argc > 3 ? argv[3] : "all";
    int do_direct = !strcmp(mode, "all") || !strcmp(mode, "direct");
    int do_worker = !strcmp(mode, "all") || !strcmp(mode, "worker");
    int do_pooled = !strcmp(mode, "all") || !strcmp(mode, "pooled");
    long elems = 0, texts = 0, attrs = 0;
    double walk_ms = 0;

    size_t len;
    char *buf = read_file(argv[1], &len);
    if (!buf) { fprintf(stderr, "cannot read %s\n", argv[1]); return 1; }
    sl_u8 doc = { (uint8_t *)buf, (int64_t)len };

    // The error path: a malformed document and a hostile handle.
    char bad[] = "<a><b></a>";
    sl_u8 badsl = { (uint8_t *)bad, (int64_t)strlen(bad) };
    int64_t r = greylag_parse(badsl);
    int64_t elen;
    const uint8_t *e = greylag_error(&elen);
    printf("malformed: root %lld, error: ", (long long)r);
    print_slice(e, elen);
    printf("\n");
    int64_t glen;
    const uint8_t *g = greylag_name(123456789, &glen);
    printf("hostile handle: kind %d, name length %lld\n", greylag_kind(-7), (long long)glen);
    (void)g;

    int64_t clen;
    const uint8_t *c = greylag_selftest_crash(&clen);
    printf("contained crash: ");
    print_slice(c, clen);
    printf("\n");

    // Direct parse, timed.
    double best_direct = 1e30, best_worker = 1e30;
    int64_t root = -1;
    if (do_direct) for (int i = 0; i < repeat; i++) {
        double t0 = now_ms();
        root = greylag_parse_direct(doc);
        double t = now_ms() - t0;
        if (t < best_direct) best_direct = t;
    }
    if (do_direct) {
        if (root < 0) { e = greylag_error(&elen); printf("direct parse error: "); print_slice(e, elen); printf("\n"); return 1; }
        double w0 = now_ms();
        walk(root, 0, &elems, &texts, &attrs, 0);
        walk_ms = now_ms() - w0;
        printf("direct: %ld elements, %ld text, %ld attributes, %lld nodes, tree %lld bytes\n",
               elems, texts, attrs, (long long)greylag_node_count(), (long long)greylag_tree_bytes());
    }

    // Worker parse, timed.
    if (do_worker) for (int i = 0; i < repeat; i++) {
        double t0 = now_ms();
        root = greylag_parse(doc);
        double t = now_ms() - t0;
        if (t < best_worker) best_worker = t;
    }
    if (do_worker) {
        if (root < 0) { e = greylag_error(&elen); printf("worker parse error: "); print_slice(e, elen); printf("\n"); return 1; }
        long elems2 = 0, texts2 = 0, attrs2 = 0;
        double w0 = now_ms();
        walk(root, 0, &elems2, &texts2, &attrs2, 0);
        if (!do_direct) { walk_ms = now_ms() - w0; elems = elems2; texts = texts2; attrs = attrs2; }
        printf("worker: %ld elements, %ld text, %ld attributes, same tree: %s\n",
               elems2, texts2, attrs2, (elems == elems2 && texts == texts2 && attrs == attrs2) ? "yes" : "NO");
    }

    // Pooled worker parse, timed.
    double best_pooled = 1e30;
    if (do_pooled) for (int i = 0; i < repeat; i++) {
        double t0 = now_ms();
        root = greylag_parse_pooled(doc);
        double t = now_ms() - t0;
        if (t < best_pooled) best_pooled = t;
    }
    if (do_pooled) {
        if (root < 0) { e = greylag_error(&elen); printf("pooled parse error: "); print_slice(e, elen); printf("\n"); return 1; }
        long elems3 = 0, texts3 = 0, attrs3 = 0;
        double w0 = now_ms();
        walk(root, 0, &elems3, &texts3, &attrs3, 0);
        if (!do_direct && !do_worker) { walk_ms = now_ms() - w0; elems = elems3; texts = texts3; attrs = attrs3; }
        printf("pooled: %ld elements, %ld text, %ld attributes, same tree: %s\n",
               elems3, texts3, attrs3, (elems == elems3 && texts == texts3 && attrs == attrs3) ? "yes" : "NO");
    }

    printf("RESULT file=%s bytes=%zu mode=%s direct_ms=%.3f worker_ms=%.3f pooled_ms=%.3f walk_ms=%.3f tree_bytes=%lld peak_rss_kb=%ld\n",
           argv[1], len, mode, best_direct, best_worker, best_pooled, walk_ms, (long long)greylag_tree_bytes(), peak_rss_kb());
    if (len < 2000) { walk(root, 0, &elems, &texts, &attrs, 1); }
    free(buf);
    return 0;
}
