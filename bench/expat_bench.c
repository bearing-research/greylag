// expat SAX parse: no tree is built, so this is the floor for parse-only
// time in C. Counts elements, text runs and attributes through callbacks.
// cc -O2 bench/expat_bench.c -o build/expat_bench -lexpat
#include <expat.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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

static long elems, texts, attrs;
static void start(void *ud, const XML_Char *name, const XML_Char **atts) {
    (void)ud; (void)name;
    elems++;
    for (int i = 0; atts[i]; i += 2) attrs++;
}
static void chars(void *ud, const XML_Char *s, int len) { (void)ud; (void)s; (void)len; texts++; }

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: expat_bench file.xml [repeat]\n"); return 2; }
    int repeat = argc > 2 ? atoi(argv[2]) : 1;
    FILE *f = fopen(argv[1], "rb"); if (!f) return 1;
    fseek(f, 0, SEEK_END); long len = ftell(f); fseek(f, 0, SEEK_SET);
    char *buf = malloc(len); if (fread(buf, 1, len, f) != (size_t)len) return 1; fclose(f);
    double best = 1e30;
    for (int i = 0; i < repeat; i++) {
        elems = texts = attrs = 0;
        XML_Parser p = XML_ParserCreate(NULL);
        XML_SetElementHandler(p, start, NULL);
        XML_SetCharacterDataHandler(p, chars);
        double t0 = now_ms();
        if (XML_Parse(p, buf, (int)len, 1) != XML_STATUS_OK) { fprintf(stderr, "expat error: %s\n", XML_ErrorString(XML_GetErrorCode(p))); return 1; }
        double t = now_ms() - t0;
        if (t < best) best = t;
        XML_ParserFree(p);
    }
    printf("expat %s: %ld elements, %ld text callbacks, %ld attributes\n", XML_ExpatVersion(), elems, texts, attrs);
    printf("RESULT file=%s bytes=%ld parse_ms=%.3f peak_rss_kb=%ld\n", argv[1], len, best, peak_rss_kb());
    return 0;
}
