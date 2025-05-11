# thorvg built with build.zig

C API accessible via header `thorvg_capi.h`.

## Tests

`zig build test`.

Two tests, "Missing Initialization" and "Negative termination," are failing; I believe this is
an upstream issue and it doesn't seem like these failures break anything major.

## Upstream Dev

If you'd like to work on the upstream source without using meson, you can modify the
`build.zig.zon` to point to a local clone of the upstream `thorvg` and then use
`zig build -Dupstream-dev [upstream-dev-command]`.

You can also use this to run the upstream SDL2 + CApi example: `zig build -Dupstream-dev example`
