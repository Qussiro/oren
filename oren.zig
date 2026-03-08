const std = @import("std");

const rl = @cImport({
    @cInclude("raylib.h");
});
const ma = @cImport({
    @cInclude("miniaudio.h");
});

const DEVICE_FORMAT = ma.ma_format_f32;
const DEVICE_CHANNELS: c_int = 2;
const DEVICE_SAMPLE_RATE: c_int = 48000;

var gtime: f32 = 0;
const Wave = struct {
    frequency: f32,
    amplitude: f32,
    kind: WaveKind,
    fn value(wave: *const @This(), time: f32) f32 {
        switch (wave.kind) {
            .sine => return wave.amplitude * @sin(std.math.tau * time * wave.frequency),
            .square => {
                const period = 1 / wave.frequency * std.math.tau;
                const periods = @floor(time / period);
                const t = time - period * periods;

                if (t < period / 2) return wave.amplitude;
                return -wave.amplitude;
            },
            .triangle => {
                const period = 1 / wave.frequency * std.math.tau;
                const periods = @floor(time / period);
                const t = time - period * periods;

                if (t < period / 2) return std.math.lerp(-wave.amplitude, wave.amplitude, t / (period / 2));
                return std.math.lerp(wave.amplitude, -wave.amplitude, (t - period / 2) / (period / 2));
            },
            .sawtooth => {
                const period = 1 / wave.frequency * std.math.tau;
                const periods = @floor(time / period);
                const t = time - period * periods;

                return std.math.lerp(wave.amplitude, -wave.amplitude, t / period);
            },
            .random => {
                var prng = std.Random.DefaultPrng.init(@bitCast(@as(f64, gtime)));
                const phase = prng.random().float(f32) * std.math.tau;

                return wave.amplitude * @sin(std.math.tau * time * wave.frequency + phase);
            },
        }
    }
};

const WaveKind = enum {
    sine,
    square,
    triangle,
    sawtooth,
    random,
};

fn data_callback(pDevice: [*c]ma.ma_device, pOutput: ?*anyopaque, pInput: ?*const anyopaque, frameCount: ma.ma_uint32) callconv(.c) void {
    std.debug.assert(pDevice.*.playback.channels == DEVICE_CHANNELS);

    const waves: *std.ArrayList(Wave) = @ptrCast(@alignCast(pDevice.*.pUserData));

    const pOutoutF32: [*]f32 = @ptrCast(@alignCast(pOutput));

    for (0..frameCount) |iFrame| {
        var sum: f32 = 0;
        for (waves.items) |*wave| {
            sum += wave.value(gtime);
        }
        gtime += 1 / @as(f32, @floatFromInt(DEVICE_SAMPLE_RATE));
        for (0..DEVICE_CHANNELS) |iChannel| {
            pOutoutF32[iFrame * DEVICE_CHANNELS + iChannel] = sum;
        }
    }
    _ = pInput;
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;
    var waves = std.ArrayList(Wave).empty;
    // try waves.append(allocator, .{
    //     .frequency = 200,
    //     .amplitude = 0.1,
    //     .kind = .sine,
    // });
    // try waves.append(allocator, .{
    //     .frequency = 69,
    //     .amplitude = 0.5,
    //     .kind = .sine,
    // });
    // try waves.append(allocator, .{
    //     .frequency = 178,
    //     .amplitude = 0.1,
    //     .kind = .sine,
    // });
    // try waves.append(allocator, .{
    //     .frequency = 447,
    //     .amplitude = 0.1,
    //     .kind = .sine,
    // });
    // try waves.append(allocator, .{
    //     .frequency = 80,
    //     .amplitude = 0.5,
    //     .kind = .sine,
    // });
    // try waves.append(allocator, .{
    //     .frequency = 100,
    //     .amplitude = 0.1,
    //     .kind = .square,
    // });
    // try waves.append(allocator, .{
    //     .frequency = 200,
    //     .amplitude = 0.5,
    //     .kind = .triangle,
    // });
    // try waves.append(allocator, .{
    //     .frequency = 457,
    //     .amplitude = 0.3,
    //     .kind = .triangle,
    // });
    // try waves.append(allocator, .{
    //     .frequency = 10,
    //     .amplitude = 0.2,
    //     .kind = .sawtooth,
    // });
    try waves.append(allocator, .{
        .frequency = 100,
        .amplitude = 0.1,
        .kind = .random,
    });

    var engine: ma.ma_engine = undefined;
    if (ma.ma_engine_init(null, &engine) != 0) {
        std.debug.print("DIED", .{});
    }
    var deviceConfig: ma.ma_device_config = undefined;
    var device: ma.ma_device = undefined;

    deviceConfig = ma.ma_device_config_init(ma.ma_device_type_playback);
    deviceConfig.playback.format = DEVICE_FORMAT;
    deviceConfig.playback.channels = DEVICE_CHANNELS;
    deviceConfig.sampleRate = DEVICE_SAMPLE_RATE;
    deviceConfig.dataCallback = &data_callback;
    deviceConfig.pUserData = &waves;

    if (ma.ma_device_init(null, &deviceConfig, &device) != ma.MA_SUCCESS) {
        std.debug.print("No success", .{});
    }
    defer ma.ma_device_uninit(&device);

    std.debug.print("Device Name: {s}", .{device.playback.name});

    if (ma.ma_device_start(&device) != ma.MA_SUCCESS) {
        std.debug.print("Failed to start playback device.", .{});
        ma.ma_device_uninit(&device);
    }

    // const msg = ma.ma_engine_play_sound(&engine, "vine-boom.mp3", null);
    // std.debug.print("{}", .{msg});

    rl.InitWindow(1280, 720, "Oren");
    var scale: f32 = 0.005;
    var maxY: f32 = 0;

    while (!rl.WindowShouldClose()) {
        scale += rl.GetMouseWheelMove() * scale / 100;

        rl.BeginDrawing();
        rl.ClearBackground(rl.RAYWHITE);
        rl.DrawText("It works!", 20, 20, 20, rl.BLACK);

        for (0..@intCast(rl.GetScreenWidth())) |i| {
            rl.DrawPixel(@intCast(i), @divTrunc(rl.GetScreenHeight(), 2), rl.BLACK);
            const x = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(rl.GetScreenWidth())) * scale * std.math.tau;

            var sum: f32 = 0;
            for (waves.items) |*wave| {
                sum += wave.value(x + gtime * scale);
            }
            maxY = @max(maxY, @abs(sum));

            const quatWindow = @as(f32, @floatFromInt(rl.GetScreenHeight())) / 4;
            const y: c_int = @intFromFloat((1 - ((sum + maxY) / (2 * maxY)) * 2 * quatWindow) + quatWindow);
            rl.DrawPixel(@intCast(i), y + @divTrunc(rl.GetScreenHeight(), 2), rl.RED);
        }
        rl.EndDrawing();
    }
    rl.CloseWindow();
}
