const std = @import("std");
const builtin = @import("builtin");

fn makeOdinTargetString(allocator: std.mem.Allocator, target: std.Build.ResolvedTarget) !?[]const u8 {
    const arch = target.query.cpu_arch orelse return null;
    const arch_string = switch (arch) {
        .x86_64 => "amd64",
        .x86 => "i386",
        .arm => "arm32",
        .aarch64 => "arm64",
        else => @panic("unhandled cpu arch"),
    };

    const os_tag = target.query.os_tag orelse return null;

    return switch (os_tag) {
        .windows => try std.fmt.allocPrint(allocator, "windows_{s}", .{arch_string}),
        .linux => try std.fmt.allocPrint(allocator, "linux_{s}", .{arch_string}),
        .macos => try std.fmt.allocPrint(allocator, "darwin_{s}", .{arch_string}),
        else => std.debug.panic("can't build for {}", .{target}),
    };
}

fn applyZigOptimization(odin_compile: *std.Build.Step.Run, optimize: std.builtin.OptimizeMode) void {
    return switch (optimize) {
        .Debug => odin_compile.addArgs(&[_][]const u8{ "-debug", "-o:none" }),
        .ReleaseSafe => odin_compile.addArg("-o:minimal"),
        .ReleaseSmall => odin_compile.addArg("-o:size"),
        .ReleaseFast => odin_compile.addArg("-o:speed"),
        // else => std.debug.panic("unmapped odin optimization mode for zig OptimizeMode={}", .{optimize}),
    };
}

pub fn build(b: *std.Build) !void {
    const host = builtin.target;
    var target = b.standardTargetOptions(.{});
    if (target.query.os_tag == .windows) {
        target.query.abi = .msvc;
    }
    const optimize = b.standardOptimizeOption(.{});
    const target_os = target.query.os_tag orelse host.os.tag;

    // odin
    const odin_compile = b.addSystemCommand(&.{ "odin", "build", ".", "-build-mode:obj", "-out:zig-out/main.o", "-use-single-module" });
    applyZigOptimization(odin_compile, optimize);

    if (try makeOdinTargetString(b.allocator, target)) |odin_target_string| {
        const target_flag = try std.mem.concat(b.allocator, u8, &.{ "-target:", odin_target_string });
        odin_compile.addArg(target_flag);
    }

    const exe = b.addExecutable(.{
        .name = "game",
        .target = target,
        .optimize = optimize,
        // .link_libc = false,
    });

    if (target_os == .windows) {
        exe.addObjectFile(b.path("zig-out/main.obj"));
        exe.addLibraryPath(b.path("lib/SDL3/shared"));
        b.installBinFile("lib/SDL3/shared/SDL3.dll", "SDL3.dll");
        exe.linkSystemLibrary("SDL3");
    } else {
        exe.addObjectFile(b.path("zig-out/main.o"));
        //sdl
        const sdl_dep = b.dependency("sdl", .{
            .target = target,
            .optimize = optimize,
            // .preferred_linkage = .dynamic,
            .preferred_linkage = .static,
            //.strip = null,
            //.pic = null,
            //.lto = null,
            //.emscripten_pthreads = false,
            //.install_build_config_h = false,
        });
        const sdl_lib = sdl_dep.artifact("SDL3");
        // const sdl_test_lib = sdl_dep.artifact("SDL3_test");
        exe.linkLibrary(sdl_lib);
        exe.linkLibC();
    }
    exe.step.dependOn(&odin_compile.step);

    // build
    b.installArtifact(exe);
    // run
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
