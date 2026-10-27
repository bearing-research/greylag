#include "hello.h"
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    goose_init(argc, argv);
    int64_t len;
    const uint8_t *msg = hello_world(&len);
    fwrite(msg, 1, (size_t)len, stdout);
    putchar('\n');
    printf("add = %d\n", gl_add(20, 22));
    char bytes[] = "abc";
    sl_u8 s = { (uint8_t *)bytes, (int64_t)strlen(bytes) };
    printf("sum = %lld\n", (long long)gl_sum_bytes(s));
    return 0;
}
