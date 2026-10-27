# greylag

An XML parser written in [Goose](https://github.com/aardappel/goose), for C.

Status: Phase 0 spike. A subset parser, a C API through integer handles, a contained-worker parse path, and a first comparison against libxml2 and expat. See `docs/spike-0.md` for the findings and `bench/results.md` for the numbers.

## Build

Requires a Goose compiler on `PATH` (built from source: `cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build`) and a C compiler.

```
goose --standalone --header build/greylag.h -o build/greylag.c src/greylag.goose
cc -O2 -Ibuild build/greylag.c c/host.c -o build/host -lm -pthread
./build/host file.xml [repeat] [direct|worker|pooled|all]
```

The parser alone, as a command-line tool:

```
goose src/parse_cli.goose -- file.xml [dump]
```

## Benchmarks

```
python3 bench/gen.py bench/data
cc -O2 $(pkg-config --cflags libxml-2.0) bench/libxml2_bench.c -o build/libxml2_bench $(pkg-config --libs libxml-2.0)
cc -O2 bench/expat_bench.c -o build/expat_bench -lexpat
python3 bench/run.py
```

## Limits (spike)

- Subset grammar: no namespaces, no DTD internal subset, no UTF-8 validation of content, no XML 1.1.
- One document at a time; a parse replaces the previous one.
- All API calls must come from the thread that called `goose_init`.
- `greylag_parse_direct` runs the parser on the calling thread; a parser bug aborts the process. `greylag_parse` and `greylag_parse_pooled` run it in a contained worker and report failures through `greylag_error`.

## License

Apache-2.0.
