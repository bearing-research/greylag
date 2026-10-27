// libxml2 DOM parse, timed the same way as the greylag host.
// cc -O2 $(pkg-config --cflags libxml-2.0) bench/libxml2_bench.c -o build/libxml2_bench $(pkg-config --libs libxml-2.0)
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/resource.h>

static double now_ms(void) { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6; }
static long peak_rss_kb(void) {
    FILE *f = fopen("/proc/self/status", "r");
    char line[256];
    long kb = 0;
    if (f) { while (fgets(line, sizeof line, f)) if (sscanf(line, "VmHWM: %ld kB", &kb) == 1) break; fclose(f); }
    return kb;
}

static void walk(xmlNode *n, long *elems, long *texts, long *attrs) {
    for (; n; n = n->next) {
        if (n->type == XML_ELEMENT_NODE) {
            (*elems)++;
            for (xmlAttr *a = n->properties; a; a = a->next) (*attrs)++;
            walk(n->children, elems, texts, attrs);
        } else if (n->type == XML_TEXT_NODE || n->type == XML_CDATA_SECTION_NODE) {
            (*texts)++;
        }
    }
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: libxml2_bench file.xml [repeat]\n"); return 2; }
    int repeat = argc > 2 ? atoi(argv[2]) : 1;
    FILE *f = fopen(argv[1], "rb"); if (!f) return 1;
    fseek(f, 0, SEEK_END); long len = ftell(f); fseek(f, 0, SEEK_SET);
    char *buf = malloc(len); if (fread(buf, 1, len, f) != (size_t)len) return 1; fclose(f);
    LIBXML_TEST_VERSION
    double best = 1e30;
    xmlDoc *doc = NULL;
    for (int i = 0; i < repeat; i++) {
        if (doc) xmlFreeDoc(doc);
        double t0 = now_ms();
        doc = xmlReadMemory(buf, (int)len, argv[1], NULL, XML_PARSE_NONET | XML_PARSE_NOENT);
        double t = now_ms() - t0;
        if (t < best) best = t;
    }
    if (!doc) { fprintf(stderr, "parse failed\n"); return 1; }
    long elems = 0, texts = 0, attrs = 0;
    double w0 = now_ms();
    walk(xmlDocGetRootElement(doc), &elems, &texts, &attrs);
    double walk_ms = now_ms() - w0;
    printf("libxml2 %s: %ld elements, %ld text, %ld attributes\n", xmlParserVersion, elems, texts, attrs);
    printf("RESULT file=%s bytes=%ld parse_ms=%.3f walk_ms=%.3f peak_rss_kb=%ld\n", argv[1], len, best, walk_ms, peak_rss_kb());
    xmlFreeDoc(doc);
    xmlCleanupParser();
    return 0;
}
