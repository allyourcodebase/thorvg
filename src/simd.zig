const std = @import("std");

pub const SimdOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Optimize,
    openmp: bool,
};

const flags_aarch64 = &.{
    "-std=c++14",
    "-mfpu=neon",
};

const flags_x86_64 = &.{
    "-std=c++14",
    "-mavx2",
};

const flags_wasm = &.{
    "-std=c++14",
    "-mfpu=neon",
    "-msimd128",
};

pub fn buildSimdModule(b: *std.Build, options: SimdOptions) *std.Build.Step {
    const simd_lib = b.addLibrary(.{
        .name = "thorvg-sw-simd",
        .root_module = b.createModule(.{
            .target = options.target,
            .optimize = options.optimize,
            .link_libcpp = true,
        }),
    });
    simd_lib.sanitize_c = .off;
    simd_lib.addCMacro("_USE_MATH_DEFINES", "1");
}
