# Reproducers for upstream Goose issues

All reproduced at Goose commit 64d62fc on Linux x86-64 (gcc 13, glibc 2.39)
and Linux aarch64 (gcc 11, glibc 2.35).

- `from_bytes_dest.goose`: `from_bytes` is rejected at any destination but a
  fresh local, while a user call of the same type is constructed in place.
- `two_result_assign.goose`: multi-value whole assignment of a relative-ref
  array result to an existing destination is rejected for user calls too.
- `stale_in_pool_link.goose`: an `in pool` link kept outside the pool survives
  `pool.clear()`; on a variable-mode pool a release build reads a corrupt tag
  (no `match` arm runs), a `--debug` build reports `corrupt ADT tag`.
