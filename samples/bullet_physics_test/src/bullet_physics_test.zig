const builtin = @import("builtin");
const std = @import("std");
const win32 = @import("win32");
const w = win32.base;
const d2d1 = win32.d2d1;
const d3d12 = win32.d3d12;
const dwrite = win32.dwrite;
const dml = win32.directml;
const common = @import("common");
const gr = common.graphics;
const lib = common.library;
const c = common.c;
const pix = common.pix;
const vm = common.vectormath;
const tracy = common.tracy;
const math = std.math;
const assert = std.debug.assert;
const hrPanic = lib.hrPanic;
const hrPanicOnFail = lib.hrPanicOnFail;
const Vec3 = vm.Vec3;
const L = std.unicode.utf8ToUtf16LeStringLiteral;

pub export var D3D12SDKVersion: u32 = 4;
pub export var D3D12SDKPath: [*:0]const u8 = ".\\d3d12\\";

const window_name = "zig-gamedev: bullet physics test";
const window_width = 1920;
const window_height = 1080;

const DemoState = struct {
    grfx: gr.GraphicsContext,
    gui: gr.GuiContext,
    frame_stats: lib.FrameStats,

    brush: *d2d1.ISolidColorBrush,
    info_txtfmt: *dwrite.ITextFormat,

    physics_world: c.plWorldHandle,
    physics_debug: *PhysicsDebug,
};

const PsoPhysicsDebug_Vertex = struct {
    position: [3]f32,
    color: u32,
};

const PhysicsDebug = struct {
    lines: std.ArrayList(PsoPhysicsDebug_Vertex),

    fn init(alloc: *std.mem.Allocator) PhysicsDebug {
        return .{ .lines = std.ArrayList(PsoPhysicsDebug_Vertex).init(alloc) };
    }

    fn deinit(debug: *PhysicsDebug) void {
        debug.lines.deinit();
        debug.* = undefined;
    }

    fn drawLine(debug: *PhysicsDebug, p0: Vec3, p1: Vec3, color: Vec3) void {
        _ = debug;
        _ = p0;
        _ = p1;
        _ = color;
    }

    fn drawLineCallback(p0: [*c]const f32, p1: [*c]const f32, color: [*c]const f32, user: ?*c_void) callconv(.C) void {
        const ptr = @ptrCast(*PhysicsDebug, @alignCast(@alignOf(PhysicsDebug), user.?));
        ptr.drawLine(
            Vec3.init(p0[0], p0[1], p0[2]),
            Vec3.init(p1[0], p1[1], p1[2]),
            Vec3.init(color[0], color[1], color[2]),
        );
    }

    fn errorWarningCallback(str: [*c]const u8) callconv(.C) void {
        std.log.info("{s}", .{str});
    }
};

fn init(gpa: *std.mem.Allocator) DemoState {
    const tracy_zone = tracy.zone(@src(), 1);
    defer tracy_zone.end();

    var physics_debug = gpa.create(PhysicsDebug) catch unreachable;
    physics_debug.* = PhysicsDebug.init(gpa);

    const physics_world = c.plWorldCreate();
    c.plWorldDebugSetErrorWarningCallback(physics_world, PhysicsDebug.errorWarningCallback);
    c.plWorldDebugSetDrawLineCallback(physics_world, PhysicsDebug.drawLineCallback, null);

    if (false) {
        const sphere = c.plShapeCreateSphere(1.0);
        var trans = [4]c.plVector3{
            c.plVector3{ 1.0, 0.0, 0.0 },
            c.plVector3{ 0.0, 1.0, 0.0 },
            c.plVector3{ 0.0, 0.0, 1.0 },
            c.plVector3{ 2.0, 2.0, 2.0 },
        };
        const body = c.plBodyCreate(physics_world, 1.0, &trans[0], sphere);

        trans[3] = c.plVector3{ 0.0, 0.0, 0.0 };
        c.plBodyGetGraphicsTransform(body, &trans[0]);

        c.plBodyDestroy(physics_world, body);
        c.plShapeDestroy(sphere);
        c.plWorldDestroy(physics_world);
    }

    const window = lib.initWindow(gpa, window_name, window_width, window_height) catch unreachable;

    var arena_allocator = std.heap.ArenaAllocator.init(gpa);
    defer arena_allocator.deinit();

    _ = pix.loadGpuCapturerLibrary();
    _ = pix.setTargetWindow(window);
    _ = pix.beginCapture(
        pix.CAPTURE_GPU,
        &pix.CaptureParameters{ .gpu_capture_params = .{ .FileName = L("capture.wpix") } },
    );

    var grfx = gr.GraphicsContext.init(window);

    const brush = blk: {
        var brush: *d2d1.ISolidColorBrush = undefined;
        hrPanicOnFail(grfx.d2d.context.CreateSolidColorBrush(
            &.{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 0.5 },
            null,
            @ptrCast(*?*d2d1.ISolidColorBrush, &brush),
        ));
        break :blk brush;
    };

    const info_txtfmt = blk: {
        var info_txtfmt: *dwrite.ITextFormat = undefined;
        hrPanicOnFail(grfx.dwrite_factory.CreateTextFormat(
            L("Verdana"),
            null,
            dwrite.FONT_WEIGHT.BOLD,
            dwrite.FONT_STYLE.NORMAL,
            dwrite.FONT_STRETCH.NORMAL,
            32.0,
            L("en-us"),
            @ptrCast(*?*dwrite.ITextFormat, &info_txtfmt),
        ));
        break :blk info_txtfmt;
    };
    hrPanicOnFail(info_txtfmt.SetTextAlignment(.LEADING));
    hrPanicOnFail(info_txtfmt.SetParagraphAlignment(.NEAR));

    //
    // Begin frame to init/upload resources to the GPU.
    //
    grfx.beginFrame();
    grfx.endFrame();
    grfx.beginFrame();

    pix.beginEventOnCommandList(@ptrCast(*d3d12.IGraphicsCommandList, grfx.cmdlist), "GPU init");

    var gui = gr.GuiContext.init(&arena_allocator.allocator, &grfx);

    _ = pix.endEventOnCommandList(@ptrCast(*d3d12.IGraphicsCommandList, grfx.cmdlist));

    grfx.endFrame();
    grfx.finishGpuCommands();

    _ = pix.endCapture();

    return .{
        .grfx = grfx,
        .gui = gui,
        .frame_stats = lib.FrameStats.init(),
        .brush = brush,
        .info_txtfmt = info_txtfmt,
        .physics_world = physics_world,
        .physics_debug = physics_debug,
    };
}

fn deinit(demo: *DemoState, gpa: *std.mem.Allocator) void {
    demo.grfx.finishGpuCommands();
    _ = demo.brush.Release();
    _ = demo.info_txtfmt.Release();
    demo.gui.deinit(&demo.grfx);
    demo.grfx.deinit();
    lib.deinitWindow(gpa);
    demo.physics_debug.deinit();
    gpa.destroy(demo.physics_debug);
    c.plWorldDestroy(demo.physics_world);
    demo.* = undefined;
}

fn update(demo: *DemoState) void {
    demo.frame_stats.update();
    lib.newImGuiFrame(demo.frame_stats.delta_time);
}

fn draw(demo: *DemoState) void {
    var grfx = &demo.grfx;
    grfx.beginFrame();

    const back_buffer = grfx.getBackBuffer();

    grfx.addTransitionBarrier(back_buffer.resource_handle, d3d12.RESOURCE_STATE_RENDER_TARGET);
    grfx.flushResourceBarriers();

    grfx.cmdlist.OMSetRenderTargets(
        1,
        &[_]d3d12.CPU_DESCRIPTOR_HANDLE{back_buffer.descriptor_handle},
        w.TRUE,
        null,
    );
    grfx.cmdlist.ClearRenderTargetView(
        back_buffer.descriptor_handle,
        &[4]f32{ 0.1, 0.2, 0.4, 1.0 },
        0,
        null,
    );

    demo.gui.draw(grfx);

    grfx.beginDraw2d();
    {
        const stats = &demo.frame_stats;
        var buffer = [_]u8{0} ** 64;
        const text = std.fmt.bufPrint(
            buffer[0..],
            "FPS: {d:.1}\nCPU time: {d:.3} ms",
            .{ stats.fps, stats.average_cpu_time },
        ) catch unreachable;

        demo.brush.SetColor(&.{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 });
        lib.drawText(
            grfx.d2d.context,
            text,
            demo.info_txtfmt,
            &d2d1.RECT_F{
                .left = 10.0,
                .top = 10.0,
                .right = @intToFloat(f32, grfx.viewport_width),
                .bottom = @intToFloat(f32, grfx.viewport_height),
            },
            @ptrCast(*d2d1.IBrush, demo.brush),
        );
    }
    grfx.endDraw2d();

    grfx.endFrame();
}

pub fn main() !void {
    lib.init();
    defer lib.deinit();

    var gpa_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa_allocator.deinit();
        std.debug.assert(leaked == false);
    }
    const gpa = &gpa_allocator.allocator;

    var demo = init(gpa);
    defer deinit(&demo, gpa);

    while (true) {
        var message = std.mem.zeroes(w.user32.MSG);
        const has_message = w.user32.peekMessageA(&message, null, 0, 0, w.user32.PM_REMOVE) catch false;
        if (has_message) {
            _ = w.user32.translateMessage(&message);
            _ = w.user32.dispatchMessageA(&message);
            if (message.message == w.user32.WM_QUIT) {
                break;
            }
        } else {
            update(&demo);
            draw(&demo);
        }
    }
}