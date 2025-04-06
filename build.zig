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

pub fn build(b: *std.Build) !void {
    const host = builtin.target;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // odin_compile.addFileArg("odin");
    const odin_compile = b.addSystemCommand(&.{ "odin", "build", ".", "-build-mode:obj", "-out:zig-out/main.o", "-o:speed" });
    if (try makeOdinTargetString(b.allocator, target)) |odin_target_string| {
        const target_flag = try std.mem.concat(b.allocator, u8, &.{ "-target:", odin_target_string });
        odin_compile.addArg(target_flag);
    }

    const exe = b.addExecutable(.{
        .name = "game",
        .target = target,
        .optimize = optimize,
    });

    { // odin source
        const target_os = target.query.os_tag orelse host.os.tag;
        if (target_os == .windows) {
            exe.addObjectFile(b.path("zig-out/main.obj"));
        } else {
            exe.addObjectFile(b.path("zig-out/main.o"));
        }
        exe.step.dependOn(&odin_compile.step);
    }
    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .preferred_linkage = .dynamic,
        // .preferred_linkage = .static,
        //.strip = null,
        //.pic = null,
        //.lto = null,
        //.emscripten_pthreads = false,
        //.install_build_config_h = false,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");
    // const sdl_test_lib = sdl_dep.artifact("SDL3_test");
    exe.linkLibrary(sdl_lib);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
