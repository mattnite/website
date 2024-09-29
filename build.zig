const std = @import("std");
const Build = std.Build;

const zine = @import("zine");

pub fn build(b: *Build) void {
    const user = b.option([]const u8, "user", "rsync user");
    const host = b.option([]const u8, "host", "rsync host");

    zine.website(b, .{
        .title = "Matthew Knight's Website",
        .host_url = "https://mattnite.net",
        .content_dir_path = "content",
        .layouts_dir_path = "layouts",
        .assets_dir_path = "assets",
        .static_assets = &.{
            "fonts/Inter/Inter-VariableFont_slnt,wght.ttf",
            "fonts/Inter/static/Inter-Medium.ttf",
            "fonts/Inter/static/Inter-Light.ttf",
            "fonts/Inter/static/Inter-Thin.ttf",
            "fonts/Inter/static/Inter-Bold.ttf",
            "fonts/Inter/static/Inter-Regular.ttf",
            "fonts/Inter/static/Inter-ExtraBold.ttf",
            "fonts/Inter/static/Inter-ExtraLight.ttf",
            "fonts/Inter/static/Inter-Black.ttf",
            "fonts/Inter/static/Inter-SemiBold.ttf",
            //"assets/fonts/Inter/OFL.txt",
            //"assets/fonts/Inter/README.txt",
            "fonts/BerkeleyMono/WEB/BerkeleyMono-Regular.woff2",
            "fonts/BerkeleyMono/WEB/BerkeleyMono-Regular.woff",
            "fonts/BerkeleyMono/WEB/BerkeleyMono-BoldItalic.woff",
            "fonts/BerkeleyMono/WEB/BerkeleyMono-Bold.woff2",
            "fonts/BerkeleyMono/WEB/BerkeleyMono-Italic.woff",
            "fonts/BerkeleyMono/WEB/BerkeleyMono-BoldItalic.woff2",
            "fonts/BerkeleyMono/WEB/BerkeleyMono-Bold.woff",
            "fonts/BerkeleyMono/WEB/BerkeleyMono-Italic.woff2",
            "fonts/BerkeleyMono/TTF/BerkeleyMono-Regular.ttf",
            "fonts/BerkeleyMono/TTF/BerkeleyMono-Bold.ttf",
            "fonts/BerkeleyMono/TTF/BerkeleyMono-BoldItalic.ttf",
            "fonts/BerkeleyMono/TTF/BerkeleyMono-Italic.ttf",
            "fonts/BerkeleyMono/OTF/BerkeleyMono-Regular.otf",
            "fonts/BerkeleyMono/OTF/BerkeleyMono-Bold.otf",
            "fonts/BerkeleyMono/OTF/BerkeleyMono-Italic.otf",
            "fonts/BerkeleyMono/OTF/BerkeleyMono-BoldItalic.otf",
            //"assets/fonts/mandatory-plaything-font/misc/FSLA_NonCommercial_License-4726.html",
            //"assets/fonts/mandatory-plaything-font/misc/Get Commercial License-cca5.url",
            "fonts/mandatory-plaything-font/MandatoryPlaything-nRRd0.ttf",
            //"assets/fonts/mandatory-plaything-font/info.txt",
        },
    });

    const rsync = b.addSystemCommand(&.{
        "rsync",
        "-v",
        "-r",
        "--delete",
        "./zig-out/",
    });
    rsync.step.dependOn(b.getInstallStep());

    if (user != null and host != null)
        rsync.addArg(b.fmt("{s}@{s}:/root/config/www/", .{ user.?, host.? }));

    const deploy = b.step("deploy", "Deploy website to prod");
    deploy.dependOn(&rsync.step);
}
