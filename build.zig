const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("juicebox", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackage(.{ .name = "x11", .path = "src/x11/x11.zig" });
    exe.install();

    // Running the binary
    {
        const run_cmd = exe.run();
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    // Xephyr building steps
    {
        const size = b.option([]const u8, "size", "Sets the Xephyr window size") orelse "800x600";

        const xinit = b.addSystemCommand(&[_][]const u8{
            "xinit",           "./xinitrc",  "--",
            "/usr/bin/Xephyr", ":2",         "-ac",
            "-screen",         size,         "-host-cursor",
            "-reset",          "-terminate",
        });

        const xephyr_step = b.step(
            "xephyr",
            "Runs the window manager inside Xephyr. Useful for testing without obstructing your current window manager",
        );
        xephyr_step.dependOn(b.getInstallStep());
        xephyr_step.dependOn(&xinit.step);
    }
}
