const std = @import("std");
const builtin = @import("builtin");
const sources = @import("src/thorvg.zon");
const version = "1.1.4";

pub const Engine = enum {
    pub const all_engines = &[_]Engine{ .sw, .gl, .wg };
    pub const default_engines = &[_]Engine{.sw};

    sw,
    gl,
    wg,
};

pub const Loader = enum {
    pub const all_loaders = &[_]Loader{ .svg, .png, .jpg, .lottie, .sfnt, .otf, .webp, .gif, .media };
    pub const default_loaders = &[_]Loader{ .svg, .lottie, .sfnt };

    svg,
    png,
    jpg,
    lottie,
    sfnt,
    webp,
    gif,
    media,
};

pub const Saver = enum {
    pub const all_savers = &[_]Saver{.gif};
    pub const default_savers = &[_]Saver{.gif};

    gif,
};

pub const Extra = enum {
    pub const default_extras = &[_]Extra{};

    openmp,
    opengl_es,
};

// TODO: Remove sanitize_c, path stripping function in common tvgStr causing UB

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const static = b.option(bool, "static", "Build as static library") orelse true;
    const upstream_dev = b.option(
        bool,
        "upstream-dev",
        "Should build.zig be configured to allow upstream dev work?",
    ) orelse false;

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

    const extras = b.option(
        []const Extra,
        "extras",
        "Which extra features should be enabled?",
    ) orelse Extra.default_extras;
    const extra_set = std.EnumSet(Extra).initMany(extras);

    const threads = b.option(
        bool,
        "threads",
        "Enable the multi-threading task scheduler in thorvg",
    ) orelse true;

    const upstream = b.dependency("thorvg", .{});

    const lib = b.addLibrary(.{
        .name = "thorvg",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libcpp = true,
        }),
    });

    lib.root_module.sanitize_c = .off;
    lib.root_module.addCMacro("_USE_MATH_DEFINES", "1");

    const config_h = b.addConfigHeader(.{
        .include_path = "config.h",
    }, .{
        .THORVG_VERSION_STRING = version,
        .THORVG_CAPI_BINDING_SUPPORT = 1,
        .THORVG_FILE_IO_SUPPORT = 1,
        .WIN32_LEAN_AND_MEAN = 1,
    });

    for (engines) |engine| try config_h.values.put(
        b.allocator,
        b.fmt("THORVG_{s}_ENGINE_SUPPORT", .{
            try std.ascii.allocUpperString(b.allocator, @tagName(engine)),
        }),
        .{ .int = 1 },
    );

    for (loaders) |loader| {
        try config_h.values.put(
            b.allocator,
            b.fmt("THORVG_{s}_LOADER_SUPPORT", .{
                try std.ascii.allocUpperString(b.allocator, @tagName(loader)),
            }),
            .{ .int = 1 },
        );
    }
    if (loader_set.contains(.sfnt)) {
        config_h.addValues(.{ .THORVG_SFNT_LOADER_SUPPORT = 1 });
    }

    for (savers) |saver| try config_h.values.put(
        b.allocator,
        b.fmt("THORVG_{s}_SAVER_SUPPORT", .{
            try std.ascii.allocUpperString(b.allocator, @tagName(saver)),
        }),
        .{ .int = 1 },
    );

    if (extra_set.contains(.openmp)) {
        config_h.addValues(.{ .THORVG_OPENMP_SUPPORT = 1 });
    }

    if (threads) {
        config_h.addValues(.{ .THORVG_THREAD_SUPPORT = 1 });
        if (target.result.os.tag != .windows and !target.result.abi.isAndroid()) {
            lib.root_module.linkSystemLibrary("pthread", .{});
        }
    }

    if (b.option(bool, "verbose-logging", "Verbose ThorVG logs") orelse false) {
        config_h.addValues(.{ .THORVG_LOG_ENABLED = 1 });
    }

    lib.root_module.addConfigHeader(config_h);

    lib.root_module.addIncludePath(upstream.path("inc"));
    lib.root_module.addIncludePath(upstream.path("src/common"));
    lib.root_module.addIncludePath(upstream.path("src/renderer"));
    lib.root_module.addIncludePath(upstream.path("src/modules/raw"));

    lib.installHeadersDirectory(upstream.path("inc"), "", .{});

    if (static) {
        lib.root_module.addCMacro("TVG_STATIC", "");
    }

    lib.root_module.addCSourceFiles(.{
        .files = &sources.common,
        .root = upstream.path("src/common"),
        .flags = flags,
    });

    if (engine_set.contains(.sw)) {
        lib.root_module.addIncludePath(upstream.path("src/renderer/cpu_engine"));
        lib.root_module.addCSourceFiles(.{
            .files = &sources.renderer.cpu_engine,
            .root = upstream.path("src/renderer/cpu_engine"),
            .flags = flags,
        });
    }

    if (engine_set.contains(.gl)) {
        // TODO: Support GLES
        config_h.addValues(.{ .THORVG_GL_TARGET_GL = 1 });
        lib.root_module.addIncludePath(b.path("include"));
        lib.root_module.addIncludePath(upstream.path("src/renderer/gpu_engine/gl"));
        lib.root_module.addCSourceFiles(.{
            .files = &sources.renderer.gpu_engine.gl,
            .root = upstream.path("src/renderer/gpu_engine/gl"),
            .flags = flags,
        });
    }

    if (engine_set.contains(.wg)) {
        lib.root_module.addIncludePath(upstream.path("src/renderer/gpu_engine/wg"));
        lib.root_module.addCSourceFiles(.{
            .files = &sources.renderer.gpu_engine.wg,
            .root = upstream.path("src/renderer/gpu_engine/gl"),
            .flags = flags,
        });
    }

    if (engine_set.contains(.gl) or engine_set.contains(.wg)) {
        lib.root_module.addIncludePath(upstream.path("src/renderer/gpu_engine"));
        lib.root_module.addCSourceFiles(.{
            .files = &sources.renderer.gpu_engine.files,
            .root = upstream.path("src/renderer/gpu_engine"),
            .flags = flags,
        });
    }

    const mods_path = upstream.path("src/modules");

    if (loader_set.contains(.gif)) {
        const gifload_path = mods_path.path(b, "gif/load");
        lib.root_module.addIncludePath(gifload_path);
        lib.root_module.addCSourceFiles(.{
            .files = &sources.modules.gif.load,
            .root = gifload_path,
            .flags = flags,
        });
    }

    if (saver_set.contains(.gif)) {
        const gifsave_path = mods_path.path(b, "gif/save");
        lib.root_module.addIncludePath(gifsave_path);
        lib.root_module.addCSourceFiles(.{
            .files = &sources.modules.gif.save,
            .root = gifsave_path,
            .flags = flags,
        });
    }

    if (loader_set.contains(.jpg)) {
        if (static) {
            const jpeg_path = mods_path.path(b, "jpg/static");
            lib.root_module.addIncludePath(jpeg_path);
            lib.root_module.addCSourceFiles(.{
                .files = &sources.modules.jpg.static,
                .root = jpeg_path,
                .flags = flags,
            });
        } else {
            const jpeg_path = mods_path.path(b, "jpg/external");
            lib.root_module.linkSystemLibrary("turbojpeg", .{});
            lib.root_module.addIncludePath(jpeg_path);
            lib.root_module.addCSourceFiles(.{
                .files = &sources.modules.jpg.external,
                .root = jpeg_path,
                .flags = flags,
            });
        }
    }

    if (loader_set.contains(.lottie)) {
        const lottie_path = mods_path.path(b, "lottie");
        // TODO: Support Lottie expressions
        lib.root_module.addIncludePath(lottie_path);
        lib.installHeader(lottie_path.path(b, "thorvg_lottie.h"), "thorvg_lottie.h");
        lib.root_module.addCSourceFiles(.{
            .files = &sources.modules.lottie,
            .root = lottie_path,
            .flags = flags,
        });
    }

    // Experimental video loader
    if (loader_set.contains(.media)) {
        const media_path = mods_path.path(b, "media");
        lib.root_module.addIncludePath(media_path);
        lib.root_module.addCSourceFiles(.{
            .files = &sources.modules.media.files,
            .root = media_path,
            .flags = flags,
        });

        if (builtin.os.tag == .emscripten) {
            lib.root_module.addIncludePath(media_path(b, "web"));
            lib.root_module.addCSourceFiles(.{
                .files = &sources.modules.media.web,
                .root = media_path(b, "web"),
                .flags = flags,
            });
        } else if (builtin.os.tag == .ios or builtin.os.tag == .tvos) {
            lib.root_module.addIncludePath(media_path(b, "apple"));
            lib.root_module.addCSourceFiles(.{
                .files = &sources.modules.media.apple,
                .root = media_path(b, "apple"),
                .flags = flags,
            });
        }
        // TODO: Android module here
    }

    if (loader_set.contains(.sfnt)) {
        const sfnt_path = mods_path.path(b, "sfnt");
        lib.root_module.addIncludePath(sfnt_path);
        lib.root_module.addCSourceFiles(.{
            .files = &sources.modules.sfnt,
            .root = sfnt_path,
            .flags = flags,
        });
    }

    if (loader_set.contains(.svg)) {
        const svg_path = mods_path.path(b, "svg");
        lib.root_module.addIncludePath(svg_path);
        lib.root_module.addCSourceFiles(.{
            .files = &sources.modules.svg,
            .root = svg_path,
            .flags = flags,
        });
    }

    if (loader_set.contains(.webp)) {
        if (static) {
            const webp_path = mods_path.path(b, "webp/static");
            lib.root_module.addIncludePath(webp_path);
            lib.root_module.addIncludePath(webp_path.path(b, "webp"));
            lib.root_module.addCSourceFiles(.{
                .files = &sources.modules.webp.static.files,
                .root = webp_path,
                .flags = flags,
            });

            lib.root_module.addIncludePath(webp_path.path(b, "dec"));
            lib.root_module.addCSourceFiles(.{
                .files = &sources.modules.webp.static.dec,
                .root = webp_path.path(b, "dec"),
                .flags = flags,
            });

            lib.root_module.addIncludePath(webp_path.path(b, "dsp"));
            lib.root_module.addCSourceFiles(.{
                .files = &sources.modules.webp.static.dsp,
                .root = webp_path.path(b, "dsp"),
                .flags = flags,
            });
            lib.root_module.addIncludePath(webp_path.path(b, "utils"));
            lib.root_module.addCSourceFiles(.{
                .files = &sources.modules.webp.static.utils,
                .root = webp_path.path(b, "utils"),
                .flags = flags,
            });
        } else {
            const webp_path = mods_path.path(b, "webp/external");
            lib.root_module.addIncludePath(webp_path);
            lib.root_module.addCSourceFiles(.{
                .files = &sources.modules.webp.external,
                .root = webp_path,
                .flags = flags,
            });
            lib.root_module.linkSystemLibrary("webp", .{});
        }
    }

    lib.installHeadersDirectory(upstream.path("src/bindings/capi"), "", .{});
    lib.root_module.addIncludePath(upstream.path("src/bindings/capi"));
    lib.root_module.addCSourceFile(.{
        .file = upstream.path("src/bindings/capi/tvgCapi.cpp"),
        .flags = flags,
    });

    b.installArtifact(lib);

    const tests = b.addExecutable(.{
        .name = "thorvg-tests",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libcpp = true,
        }),
    });
    tests.root_module.sanitize_c = .off;

    const test_step = b.step("test", "Run thorvg tests");

    tests.root_module.linkLibrary(lib);
    tests.root_module.addConfigHeader(config_h);

    if (static) {
        tests.root_module.addCMacro("TVG_STATIC", "");
    }

    var path_writer: std.Io.Writer.Allocating = std.Io.Writer.Allocating.init(b.allocator);
    try upstream.path("test/resources").format(&path_writer.writer);
    var path_string = path_writer.toArrayList();

    tests.root_module.addCMacro("TEST_DIR", b.fmt("\"{f}\"", .{
        PathFormatter{ .path = path_string.items },
    }));
    tests.root_module.addCSourceFiles(.{
        .files = test_sources,
        .root = upstream.path("test"),
        .flags = flags,
    });
    path_string.deinit(b.allocator);

    const run_tests = b.addRunArtifact(tests);
    run_tests.addPassthruArgs();

    test_step.dependOn(&run_tests.step);

    if (upstream_dev) {
        const sdl_dep = b.lazyDependency("sdl", .{
            .target = target,
            .optimize = optimize,
        }) orelse return;

        const sdl = sdl_dep.artifact("SDL2");

        const c_api_example = b.addExecutable(.{
            .name = "c-api-example",
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libcpp = true,
            }),
        });

        try upstream.path("examples/resources").format(&path_writer.writer);
        path_string = path_writer.toArrayList();

        c_api_example.root_module.linkLibrary(sdl);
        c_api_example.root_module.linkLibrary(lib);
        c_api_example.root_module.addCMacro("TVG_STATIC", "");
        c_api_example.root_module.addCMacro("EXAMPLE_DIR", b.fmt("\"{f}\"", .{
            PathFormatter{ .path = path_string.items },
        }));
        path_string.deinit(b.allocator);

        if (engine_set.contains(.gl)) {
            c_api_example.root_module.addCSourceFile(.{
                .file = b.path("CapiExampleGl.cpp"),
                .flags = flags,
            });
        } else if (engine_set.contains(.sw)) {
            c_api_example.root_module.addCSourceFile(.{
                .file = upstream.path("examples/Capi.cpp"),
                .flags = flags,
            });
        } else {
            @panic("No example available to run");
        }

        b.installArtifact(c_api_example);

        const run_c_api_example = b.addRunArtifact(c_api_example);
        run_c_api_example.addPassthruArgs();

        const example_step = b.step("example", "Run C API example");
        example_step.dependOn(&run_c_api_example.step);
    }
}

const PathFormatter = struct {
    path: []const u8,

    pub fn format(
        formatter: PathFormatter,
        writer: *std.Io.Writer,
    ) !void {
        for (formatter.path) |char| {
            if (char == '\\')
                try writer.writeAll("/")
            else
                try writer.writeByte(char);
        }
    }
};

const flags = &.{"-std=c++14"};

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
