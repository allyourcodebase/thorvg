const std = @import("std");

const version = "1.0.0";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("thorvg", .{});

    const lib = b.addStaticLibrary(.{
        .name = "thorvg",
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibCpp();

    const config_h = b.addConfigHeader(.{
        .include_path = "config.h",
    }, .{
        .THORVG_VERSION_STRING = version,
        .THORVG_THREAD_SUPPORT = 1,
        .THORVG_SW_RASTER_SUPPORT = 1,
        .THORVG_CAPI_BINDING_SUPPORT = 1,
        .WIN32_LEAN_AND_MEAN = 1,
    });
    lib.addConfigHeader(config_h);
    lib.installConfigHeader(config_h);

    lib.addIncludePath(upstream.path("inc"));
    lib.addIncludePath(upstream.path("src/common"));
    lib.addIncludePath(upstream.path("src/renderer"));
    lib.addIncludePath(upstream.path("src/loaders/raw"));

    lib.installHeadersDirectory(upstream.path("inc"), "", .{});

    lib.root_module.addCMacro("TVG_STATIC", "");
    lib.addCSourceFiles(.{
        .files = sources,
        .root = upstream.path("src"),
        .flags = flags,
    });

    lib.addIncludePath(upstream.path("src/renderer/sw_engine"));
    lib.addCSourceFiles(.{
        .files = sw_engine_sources,
        .root = upstream.path("src/renderer/sw_engine"),
        .flags = flags,
    });

    lib.installHeadersDirectory(upstream.path("src/bindings/capi"), "", .{});
    lib.addIncludePath(upstream.path("src/bindings/capi"));
    lib.addCSourceFile(.{
        .file = upstream.path("src/bindings/capi/tvgCapi.cpp"),
        .flags = flags,
    });

    b.installArtifact(lib);

    const tests = b.addExecutable(.{
        .name = "thorvg-tests",
        .target = target,
        .optimize = optimize,
    });

    tests.linkLibCpp();
    tests.linkLibrary(lib);
    tests.installLibraryHeaders(lib);
    tests.root_module.addCMacro("TVG_STATIC", "");
    tests.root_module.addCMacro("TEST_DIR", "\".\"");
    tests.addCSourceFiles(.{
        .files = test_sources,
        .root = upstream.path("test"),
        .flags = flags,
    });

    const run_tests = b.addRunArtifact(tests);
    if (b.args) |args| run_tests.addArgs(args);

    const test_step = b.step("test", "Run thorvg tests");
    test_step.dependOn(&run_tests.step);
}

const flags = &.{"-std=c++14"};

const sources = &.{
    "common/tvgCompressor.cpp",
    "common/tvgMath.cpp",
    "common/tvgStr.cpp",

    "renderer/tvgAccessor.cpp",
    "renderer/tvgAnimation.cpp",
    "renderer/tvgCanvas.cpp",
    "renderer/tvgFill.cpp",
    "renderer/tvgGlCanvas.cpp",
    "renderer/tvgInitializer.cpp",
    "renderer/tvgLoader.cpp",
    "renderer/tvgPaint.cpp",
    "renderer/tvgPicture.cpp",
    "renderer/tvgRender.cpp",
    "renderer/tvgSaver.cpp",
    "renderer/tvgScene.cpp",
    "renderer/tvgShape.cpp",
    "renderer/tvgSwCanvas.cpp",
    "renderer/tvgTaskScheduler.cpp",
    "renderer/tvgText.cpp",
    "renderer/tvgWgCanvas.cpp",

    "loaders/raw/tvgRawLoader.cpp",
};

const sw_engine_sources = &.{
    "tvgSwFill.cpp",
    "tvgSwImage.cpp",
    "tvgSwMath.cpp",
    "tvgSwMemPool.cpp",
    "tvgSwPostEffect.cpp",
    "tvgSwRaster.cpp",
    "tvgSwRenderer.cpp",
    "tvgSwRle.cpp",
    "tvgSwShape.cpp",
    "tvgSwStroke.cpp",
};

const test_sources = &.{
    "testAccessor.cpp",
    "testAnimation.cpp",
    "testFill.cpp",
    "testInitializer.cpp",
    "testLottie.cpp",
    "testMain.cpp",
    "testPaint.cpp",
    "testPicture.cpp",
    "testSavers.cpp",
    "testScene.cpp",
    "testShape.cpp",
    "testSwCanvas.cpp",
    "testSwEngine.cpp",
    "testText.cpp",
};
