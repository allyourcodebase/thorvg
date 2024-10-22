# thorvg built with build.zig

C API accessible via header `thorvg_capi.h`.

## Tests

`zig build test`.

Two tests, "Missing Initialization" and "Negative termination," are failing; I believe this is
an upstream issue and it doesn't seem like these failures break anything major.
