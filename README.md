# ThorVG ported to the Zig build system

Requires Zig 0.17.1.

The C API accessible via the header `thorvg_capi.h`. Add them to your include
path from a build.zig like this:

```zig
const tvg_bindings = thorvg.namedWriteFiles("bindings").getDirectory();
module.addIncludePath(tvg_bindings);
```

Everything works except:

- Lottie expressions
  - This requires building the Jerryscript library from upstream. It's doable,
  it's just a lot of files.
- OpenMP support
  - Requires a system <omp.h> to be available for include.

## Tools

You can use `zig build lottie2gif` or `zig build svg2png` to build the
respective tools from the repo. Don't forget to enable the loaders for those
formats too!

## Tests

`zig build test` compiles and runs the test suite from the upstream repo.

## Upstream Dev

If you'd like to work on the upstream source without using meson, you can modify the
`build.zig.zon` to point to a local clone of the upstream `thorvg` and then use
`zig build -Dupstream-dev [upstream-dev-command]`.

You can also use this to run the upstream SDL2 + CApi example: `zig build -Dupstream-dev example`
