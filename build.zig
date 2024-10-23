const std = @import("std");

const version = "1.0.0";

pub const Engine = enum {
    pub const all_engines = &[_]Engine{ .sw, .gl, .wg };
    pub const default_engines = &[_]Engine{.sw};

    sw,
    gl,
    wg,
};

pub const Loader = enum {
    pub const all_loaders = &[_]Loader{ .svg, .png, .jpg, .lottie, .ttf, .webp };
    pub const default_loaders = &[_]Loader{ .svg, .lottie, .ttf };

    svg,
    png,
    jpg,
    lottie,
    ttf,
    webp,
};

pub const Saver = enum {
    pub const all_savers = &[_]Saver{.gif};
    pub const default_savers = &[_]Saver{.gif};

    gif,
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const engines = b.option(
        []const Engine,
        "engines",
        "Which engines should be built?",
    ) orelse Engine.default_engines;
    const engine_set = std.EnumSet(Engine).initMany(engines);

    const loaders = b.option(
        []const Loader,
        "loaders",
        "Which loaders should be built?",
    ) orelse Loader.default_loaders;
    const loader_set = std.EnumSet(Loader).initMany(loaders);

    const savers = b.option(
        []const Saver,
        "savers",
        "Which savers should be built?",
    ) orelse Saver.default_savers;
    const saver_set = std.EnumSet(Saver).initMany(savers);

    const threads = b.option(
        bool,
        "threads",
        "Enable the multi-threading task scheduler in thorvg",
    ) orelse true;

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
        .THORVG_SW_RASTER_SUPPORT = 1,
        .THORVG_CAPI_BINDING_SUPPORT = 1,
        .WIN32_LEAN_AND_MEAN = 1,
    });

    for (engines) |engine| try config_h.values.put(
        b.fmt("THORVG_{s}_RASTER_SUPPORT", .{
            try std.ascii.allocUpperString(b.allocator, @tagName(engine)),
        }),
        .{ .int = 1 },
    );

    for (loaders) |loader| try config_h.values.put(
        b.fmt("THORVG_{s}_LOADER_SUPPORT", .{
            try std.ascii.allocUpperString(b.allocator, @tagName(loader)),
        }),
        .{ .int = 1 },
    );

    for (savers) |saver| try config_h.values.put(
        b.fmt("THORVG_{s}_SAVER_SUPPORT", .{
            try std.ascii.allocUpperString(b.allocator, @tagName(saver)),
        }),
        .{ .int = 1 },
    );

    if (threads) {
        config_h.addValues(.{ .THORVG_THREAD_SUPPORT = 1 });

        if (target.result.os.tag != .windows and !target.result.isAndroid()) {
            lib.linkSystemLibrary("pthread");
        }
    }

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

    if (engine_set.contains(.sw)) {
        lib.addIncludePath(upstream.path("src/renderer/sw_engine"));
        lib.addCSourceFiles(.{
            .files = sw_engine_sources,
            .root = upstream.path("src/renderer/sw_engine"),
            .flags = flags,
        });
    }

    if (engine_set.contains(.gl) or engine_set.contains(.wg)) {
        @panic("TODO: support gl and wg engines");
    }

    if (loader_set.contains(.svg)) {
        lib.addIncludePath(upstream.path("src/loaders/svg"));
        lib.addCSourceFiles(.{
            .files = loaders_svg_sources,
            .root = upstream.path("src/loaders/svg"),
            .flags = flags,
        });
    }

    if (loader_set.contains(.lottie)) {
        lib.addIncludePath(upstream.path("src/loaders/lottie"));
        lib.addCSourceFiles(.{
            .files = loaders_lottie_sources,
            .root = upstream.path("src/loaders/lottie"),
            .flags = flags,
        });
    }

    if (loader_set.contains(.ttf)) {
        lib.addIncludePath(upstream.path("src/loaders/ttf"));
        lib.addCSourceFiles(.{
            .files = loaders_ttf_sources,
            .root = upstream.path("src/loaders/ttf"),
            .flags = flags,
        });
    }

    if (loader_set.contains(.png) or loader_set.contains(.jpg) or loader_set.contains(.webp)) {
        @panic("TODO: support png, jpg, and webp loadesr");
    }

    if (saver_set.contains(.gif)) {
        lib.addIncludePath(upstream.path("src/savers/gif"));
        lib.addCSourceFiles(.{
            .files = savers_gif_sources,
            .root = upstream.path("src/savers/gif"),
            .flags = flags,
        });
    }

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

const loaders_svg_sources = &.{
    "tvgSvgCssStyle.cpp",
    "tvgSvgLoader.cpp",
    "tvgSvgPath.cpp",
    "tvgSvgSceneBuilder.cpp",
    "tvgSvgUtil.cpp",
    "tvgXmlParser.cpp",
};

const loaders_lottie_sources = &.{
    "tvgLottieAnimation.cpp",
    "tvgLottieBuilder.cpp",
    "tvgLottieExpressions.cpp",
    "tvgLottieInterpolator.cpp",
    "tvgLottieLoader.cpp",
    "tvgLottieModel.cpp",
    "tvgLottieModifier.cpp",
    "tvgLottieParserHandler.cpp",
    "tvgLottieParser.cpp",
};

const loaders_ttf_sources = &.{
    "tvgTtfLoader.cpp",
    "tvgTtfReader.cpp",
};

const savers_gif_sources = &.{
    "tvgGifEncoder.cpp",
    "tvgGifSaver.cpp",
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
