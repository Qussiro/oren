const std = @import("std");

fn buildMiniaudio(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const miniaudio_root = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });

    miniaudio_root.addCSourceFile(.{
        .file = b.path("miniaudio-0.11.25/miniaudio.c"),
    });
    miniaudio_root.linkSystemLibrary("pthread", .{});

    return b.addLibrary(.{
        .name = "miniaudio",
        .linkage = .static,
        .root_module = miniaudio_root,
    });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const miniaudio = buildMiniaudio(b, target, optimize);

    const exe = b.addExecutable(.{
        .name = "oren",
        .root_module = b.createModule(.{
            .root_source_file = b.path("oren.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    exe.root_module.linkLibrary(miniaudio);
    exe.root_module.addIncludePath(b.path("miniaudio-0.11.25"));
    exe.root_module.addIncludePath(b.path("raylib-5.5_win64_mingw-w64/include"));
    exe.root_module.addLibraryPath(b.path("raylib-5.5_win64_mingw-w64/lib"));
    exe.root_module.linkSystemLibrary("opengl32", .{});
    exe.root_module.linkSystemLibrary("gdi32", .{});
    exe.root_module.linkSystemLibrary("user32", .{});
    exe.root_module.linkSystemLibrary("winmm", .{});
    exe.root_module.linkSystemLibrary("kernel32", .{});
    exe.root_module.linkSystemLibrary("shell32", .{});
    exe.root_module.linkSystemLibrary("raylib", .{ .preferred_link_mode = .static });
    b.installArtifact(exe);
    const run_exe = b.addRunArtifact(exe);

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}
