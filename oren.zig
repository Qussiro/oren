const std = @import("std");

const rl = @cImport({
    @cInclude("raylib.h");
});
const ma = @cImport({
    @cInclude("miniaudio.h");
});

const DEVICE_FORMAT = ma.ma_format_f32;
const DEVICE_CHANNELS: c_int = 2;
const DEVICE_SAMPLE_RATE: c_int = 38000;
var time: f32 = 0;
const prikol = 1 / @as(f32, @floatFromInt(DEVICE_SAMPLE_RATE)) * 220;

fn data_callback(pDevice: [*c]ma.ma_device, pOutput: ?*anyopaque, pInput: ?*const anyopaque, frameCount: ma.ma_uint32) callconv(.c) void {
    var pSineWave: *ma.ma_waveform = undefined;

    std.debug.assert(pDevice.*.playback.channels == DEVICE_CHANNELS);

    pSineWave = @ptrCast(@alignCast(pDevice.*.pUserData));

    // _ = ma.ma_waveform_read_pcm_frames(pSineWave, pOutput, frameCount, null);
    const pOutoutF32: [*]f32 = @ptrCast(@alignCast(pOutput));
    for (0..frameCount) |iFrame| {
        const s = 0.2 * @sin(std.math.tau * time);
        time += prikol;
        for (0..DEVICE_CHANNELS) |iChannel| {
            pOutoutF32[iFrame * DEVICE_CHANNELS + iChannel] = s;
        }
    }
    // std.debug.print("DIED {}", .{frameCount});
    // _ = frameCount;
    // _ = pOutput;
    _ = pInput;
}

pub fn main() void {
    var engine: ma.ma_engine = undefined;
    if (ma.ma_engine_init(null, &engine) != 0) {
        std.debug.print("DIED", .{});
    }
    var sineWave: ma.ma_waveform = undefined;
    var deviceConfig: ma.ma_device_config = undefined;
    var device: ma.ma_device = undefined;
    var sineWaveConfig: ma.ma_waveform_config = undefined;

    deviceConfig = ma.ma_device_config_init(ma.ma_device_type_playback);
    deviceConfig.playback.format = DEVICE_FORMAT;
    deviceConfig.playback.channels = DEVICE_CHANNELS;
    deviceConfig.sampleRate = DEVICE_SAMPLE_RATE;
    deviceConfig.dataCallback = &data_callback;
    deviceConfig.pUserData = &sineWave;

    if (ma.ma_device_init(null, &deviceConfig, &device) != ma.MA_SUCCESS) {
        std.debug.print("No success", .{});
    }
    defer ma.ma_device_uninit(&device);

    std.debug.print("Device Name: {s}", .{device.playback.name});

    sineWaveConfig = ma.ma_waveform_config_init(device.playback.format, device.playback.channels, device.sampleRate, ma.ma_waveform_type_sine, 0.2, 220);
    _ = ma.ma_waveform_init(&sineWaveConfig, &sineWave);

    if (ma.ma_device_start(&device) != ma.MA_SUCCESS) {
        std.debug.print("Failed to start playback device.", .{});
        ma.ma_device_uninit(&device);
    }

    // const msg = ma.ma_engine_play_sound(&engine, "vine-boom.mp3", null);
    // std.debug.print("{}", .{msg});

    rl.InitWindow(1280, 720, "Oren");
    while (!rl.WindowShouldClose()) {
        rl.BeginDrawing();
        rl.ClearBackground(rl.RAYWHITE);
        rl.DrawText("It works!", 20, 20, 20, rl.BLACK);
        rl.EndDrawing();
    }
    rl.CloseWindow();
}
