const std = @import("std");
const builtin = @import("builtin");
const sources = @import("src/thorvg.zon");
const version = "1.1.4";

pub const Engine = enum {
    pub const all_engines = &[_]Engine{ .cpu, .gl, .wg };
    pub const default_engines = &[_]Engine{ .cpu, .gl, .wg };

    cpu,
    gl,
    wg,
};

pub const Loader = enum {
    pub const all_loaders = &[_]Loader{ .svg, .png, .jpg, .lottie, .sfnt, .otf, .webp, .gif, .media };
    pub const default_loaders = &[_]Loader{ .svg, .lottie, .sfnt, .png, .jpg, .webp, .gif, .media };

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

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const static = b.option(
        bool,
        "static",
        "Force to use static linking module",
    ) orelse true;

    const upstream_dev = b.option(
        bool,
        "upstream-dev",
        "Should build.zig be configured to allow upstream dev work?",
    ) orelse false;

    const engines = b.option(
        []const Engine,
        "engines",
        "Enable Rasterizer Engine in thorvg",
    ) orelse Engine.default_engines;
    const engine_set = std.EnumSet(Engine).initMany(engines);

    const loaders = b.option(
        []const Loader,
        "loaders",
        "Enable File Loaders in thorvg",
    ) orelse Loader.default_loaders;
    const loader_set = std.EnumSet(Loader).initMany(loaders);

    const savers = b.option(
        []const Saver,
        "savers",
        "Enable File Savers in thorvg",
    ) orelse Saver.default_savers;
    const saver_set = std.EnumSet(Saver).initMany(savers);

    const extras = b.option(
        []const Extra,
        "extras",
        "Enable support for extra options",
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

    sharedModuleSetup(lib.root_module, static);

    const config_h = b.addConfigHeader(.{
        .include_path = "config.h",
    }, .{
        .THORVG_VERSION_STRING = version,
        .THORVG_CAPI_BINDING_SUPPORT = 1,
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
        config_h.addValues(.{ .THORVG_OTF_LOADER_SUPPORT = 1 });
    }

    for (savers) |saver| try config_h.values.put(
        b.allocator,
        b.fmt("THORVG_{s}_SAVER_SUPPORT", .{
            try std.ascii.allocUpperString(b.allocator, @tagName(saver)),
        }),
        .{ .int = 1 },
    );
    if (threads) {
        config_h.addValues(.{ .THORVG_THREAD_SUPPORT = 1 });
        if (target.result.os.tag != .windows and !target.result.abi.isAndroid()) {
            lib.root_module.linkSystemLibrary("pthread", .{});
        }
    }

    if (b.option(
        bool,
        "partial",
        "Enable Partial Rendering in thorvg",
    ) orelse true) {
        config_h.addValues(.{ .THORVG_PARTIAL_RENDER_SUPPORT = 1 });
    }

    if (b.option(bool, "log", "Enable log message") orelse false) {
        config_h.addValues(.{ .THORVG_LOG_ENABLED = 1 });
    }

    if (b.option(bool, "file", "Enable File IO support") orelse true) {
        config_h.addValues(.{ .THORVG_FILE_IO_SUPPORT = 1 });
    }

    lib.root_module.addConfigHeader(config_h);
    lib.root_module.addIncludePath(upstream.path("inc"));
    lib.root_module.addIncludePath(upstream.path("src/common"));
    lib.root_module.addIncludePath(upstream.path("src/renderer"));
    lib.root_module.addIncludePath(upstream.path("src/modules/raw"));

    lib.installHeadersDirectory(upstream.path("inc"), "", .{});

    lib.root_module.addCSourceFiles(.{
        .files = &sources.common,
        .root = upstream.path("src/common"),
        .flags = flags,
    });

    lib.root_module.addCSourceFiles(.{
        .files = &sources.renderer.files,
        .root = upstream.path("src/renderer"),
        .flags = flags,
    });

    lib.root_module.addCSourceFiles(.{
        .files = &sources.modules.raw,
        .root = upstream.path("src/modules/raw"),
        .flags = flags,
    });

    if (engine_set.contains(.cpu)) {
        if (b.option(
            bool,
            "simd",
            "Enable CPU vectorization (AVX2 on x86, NEON on ARM)",
        ) orelse true) {
            const cpu = target.result.cpu;
            var simd = false;

            var simd_flags: std.ArrayList([]const u8) = .empty;

            inline for (flags) |flag| {
                try simd_flags.append(b.allocator, flag);
            }

            if (cpu.has(.x86, .avx)) {
                simd = true;
                config_h.addValues(.{ .THORVG_AVX_SUPPORT = 1 });
                try simd_flags.append(b.allocator, "-mavx2");
            } else if (cpu.has(.aarch64, .neon) or cpu.has(.arm, .neon) or cpu.arch.isWasm()) {
                simd = true;
                config_h.addValues(.{ .THORVG_NEON_SUPPORT = 1 });
                try simd_flags.append(b.allocator, "-mfpu=neon");
                if (cpu.arch.isWasm()) {
                    try simd_flags.append(b.allocator, "-msimd128");
                }
            }

            if (simd) {
                if (extra_set.contains(.openmp)) {
                    config_h.addValues(.{ .THORVG_OPENMP_SUPPORT = 1 });
                }

                lib.root_module.addCSourceFile(.{
                    .file = upstream.path("src/renderer/cpu_engine/tvgSwRasterSimd.cpp"),
                    .flags = simd_flags.items,
                });
            }
        }

        lib.root_module.addIncludePath(upstream.path("src/renderer/cpu_engine"));
        lib.root_module.addCSourceFiles(.{
            .files = &sources.renderer.cpu_engine,
            .root = upstream.path("src/renderer/cpu_engine"),
            .flags = flags,
        });
    }

    if (engine_set.contains(.gl)) {
        if (target.result.os.tag == .emscripten or extra_set.contains(.opengl_es)) {
            config_h.addValues(.{ .THORVG_GL_TARGET_GLES = 1 });
        } else {
            config_h.addValues(.{ .THORVG_GL_TARGET_GL = 1 });
        }
        lib.root_module.addIncludePath(upstream.path("src/renderer/gpu_engine/gl"));
        lib.root_module.addCSourceFiles(.{
            .files = &sources.renderer.gpu_engine.gl,
            .root = upstream.path("src/renderer/gpu_engine/gl"),
            .flags = flags,
        });
        lib.root_module.linkSystemLibrary("egl", .{});
    }

    if (engine_set.contains(.wg)) {
        lib.root_module.addIncludePath(upstream.path("src/renderer/gpu_engine/wg"));
        lib.root_module.addCSourceFiles(.{
            .files = &sources.renderer.gpu_engine.wg,
            .root = upstream.path("src/renderer/gpu_engine/wg"),
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

        if (target.result.os.tag != .emscripten) {
            lib.root_module.linkSystemLibrary("wgpu_native", .{});
        }
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

    if (loader_set.contains(.png)) {
        if (static) {
            const png_path = mods_path.path(b, "png/static");
            lib.root_module.addIncludePath(png_path);
            lib.root_module.addCSourceFiles(.{
                .files = &sources.modules.png.static,
                .root = png_path,
                .flags = flags,
            });
        } else {
            const png_path = mods_path.path(b, "png/external");
            lib.root_module.addIncludePath(png_path);
            lib.root_module.addCSourceFiles(.{
                .files = &sources.modules.png.external,
                .root = png_path,
                .flags = flags,
            });
        }
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
        lib.installHeader(media_path.path(b, "thorvg_media.h"), "thorvg_media.h");
        lib.root_module.addIncludePath(media_path);
        lib.root_module.addCSourceFiles(.{
            .files = &sources.modules.media.files,
            .root = media_path,
            .flags = flags,
        });

        if (target.result.os.tag == .emscripten) {
            lib.root_module.addIncludePath(media_path.path(b, "web"));
            lib.root_module.addCSourceFiles(.{
                .files = &sources.modules.media.web,
                .root = media_path.path(b, "web"),
                .flags = flags,
            });
        } else if (target.result.os.tag == .ios or target.result.os.tag == .tvos) {
            lib.root_module.addIncludePath(media_path.path(b, "apple"));
            lib.root_module.addCSourceFiles(.{
                .files = &sources.modules.media.apple,
                .root = media_path.path(b, "apple"),
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

    // -- lottie2gif --
    const lottie2gif_step = b.step("lottie2gif", "Build the tvg-lottie2gif tool");
    const lottie2gif = b.addExecutable(.{
        .name = "tvg-lottie2gif",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libcpp = true,
        }),
    });

    sharedModuleSetup(lottie2gif.root_module, static);
    lottie2gif.root_module.linkLibrary(lib);
    lottie2gif.root_module.addConfigHeader(config_h);
    lottie2gif.root_module.addCSourceFile(.{
        .file = upstream.path("tools/lottie2gif/lottie2gif.cpp"),
        .flags = flags,
    });

    const install_lottie2gif = b.addInstallArtifact(lottie2gif, .{});
    lottie2gif.root_module.linkLibrary(lib);
    lottie2gif_step.dependOn(&install_lottie2gif.step);

    // -- svg2png --
    const svg2png_step = b.step("svg2png", "Build the tvg-svg2png tool");
    const svg2png = b.addExecutable(.{
        .name = "tvg-svg2png",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libcpp = true,
        }),
    });

    sharedModuleSetup(svg2png.root_module, static);
    svg2png.root_module.linkLibrary(lib);
    svg2png.root_module.addConfigHeader(config_h);
    svg2png.root_module.addCSourceFiles(.{
        .files = &.{ "svg2png.cpp", "lodepng.cpp" },
        .root = upstream.path("tools/svg2png/"),
        .flags = flags,
    });

    const install_svg2png = b.addInstallArtifact(svg2png, .{});
    svg2png.root_module.linkLibrary(lib);
    svg2png_step.dependOn(&install_svg2png.step);

    const tests = b.addExecutable(.{
        .name = "thorvg-tests",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libcpp = true,
        }),
    });

    sharedModuleSetup(tests.root_module, static);

    const test_step = b.step("test", "Run thorvg tests");

    if (engine_set.contains(.gl)) {
        tests.root_module.addCMacro("THORVG_GL_TEST_SUPPORT", "");
    }
    if (engine_set.contains(.wg)) {
        tests.root_module.addCMacro("THORWG_WG_TEST_SUPPORT", "");
    }

    tests.root_module.linkLibrary(lib);
    tests.root_module.addConfigHeader(config_h);

    tests.root_module.addCMacro("TEST_DIR", "\"resources\"");
    tests.root_module.addCSourceFiles(.{
        .files = test_sources,
        .root = upstream.path("test"),
        .flags = flags,
    });

    const run_tests = b.addRunArtifact(tests);
    run_tests.cwd = upstream.path("test");
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

        c_api_example.root_module.linkLibrary(sdl);
        c_api_example.root_module.linkLibrary(lib);
        c_api_example.root_module.addCMacro("TVG_STATIC", "");
        // c_api_example.root_module.addCMacro("EXAMPLE_DIR", b.fmt("\"{f}\"", .{
        //     PathFormatter{ .path = path_string.items },
        // }));

        if (engine_set.contains(.gl)) {
            c_api_example.root_module.addCSourceFile(.{
                .file = b.path("CapiExampleGl.cpp"),
                .flags = flags,
            });
        } else if (engine_set.contains(.cpu)) {
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

fn sharedModuleSetup(mod: *std.Build.Module, static: bool) void {
    mod.sanitize_c = .off;
    if (static) {
        mod.addCMacro("TVG_STATIC", "");
    } else {
        mod.addCMacro("TVG_EXPORT", "");
        mod.addCMacro("TVG_BUILD", "");
    }
    mod.addCMacro("_USE_MATH_DEFINES", "1");
}

const flags = &.{"-std=c++14"};

const test_sources = &.{
    "testAccessor.cpp",
    "testAnimation.cpp",
    "testFill.cpp",
    "testGlCanvas.cpp",
    "testGlEngine.cpp",
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
    "testWgCanvas.cpp",
    "testWgEngine.cpp",
};
