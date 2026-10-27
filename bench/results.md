# Spike results

Machine: x86_64, 2 vCPU, Linux-6.18.44-fc-v165-x86_64-with-glibc2.39. 
Goose compiler built from source at master, generated C compiled with gcc 13 -O2. libxml2 and expat are the Ubuntu 24.04 packages. 
Times are the best of N runs of the parse call alone (N=2000 for the small files, 7 for the large ones). 
Greylag is a subset parser (no namespaces, no DTD subset, no UTF-8 validation), so this is the parse structure's cost, not a conformance-equal comparison.

## Parse time (ms)

| file | bytes | greylag direct | greylag pooled worker | greylag worker per call | libxml2 DOM | expat SAX |
|---|---:|---:|---:|---:|---:|---:|
| small-orders.xml | 1,253 | 0.004 | 0.017 | 0.085 | 0.022 | 0.011 |
| small-svg.xml | 1,002 | 0.003 | 0.019 | 0.078 | 0.009 | 0.007 |
| orders-50k.xml | 13,428,400 | 29.8 | 55.6 | 97.5 | 155.3 | 86.4 |
| svg-50k.xml | 6,872,476 | 6.6 | 12.1 | 25.9 | 40.0 | 41.9 |

## Peak RSS (MB) and tree size

| file | greylag tree bytes | tree / input | greylag direct RSS | greylag pooled RSS | libxml2 RSS | expat RSS (no tree) |
|---|---:|---:|---:|---:|---:|---:|
| small-orders.xml | 3,674 | 2.93x | 2.0 | 2.0 | 5.3 | 2.0 |
| small-svg.xml | 2,004 | 2.00x | 2.0 | 2.0 | 5.3 | 2.0 |
| orders-50k.xml | 39,643,049 | 2.95x | 52.6 | 229.4 | 250.5 | 27.6 |
| svg-50k.xml | 12,481,709 | 1.82x | 20.4 | 81.2 | 84.9 | 15.1 |

## Full-tree walk (ms)

| file | greylag handle API | libxml2 pointers |
|---|---:|---:|
| small-orders.xml | 0.001 | 0.001 |
| small-svg.xml | 0.001 | 0.001 |
| orders-50k.xml | 6.3 | 23.0 |
| svg-50k.xml | 0.670 | 7.4 |
