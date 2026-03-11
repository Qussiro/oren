const std = @import("std");

const rl = @cImport({
    @cInclude("raylib.h");
});
const ma = @cImport({
    @cInclude("miniaudio.h");
});

const print = std.debug.print;
const DEVICE_FORMAT = ma.ma_format_f32;
const DEVICE_CHANNELS: c_int = 2;
const DEVICE_SAMPLE_RATE: c_int = 48000;
const image_width: usize = 800;
const image_height: usize = 600;

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

fn audio_sampling(samples: []f32, waves: std.ArrayList(Wave)) void {
    var time: f32 = 0;
    for (samples) |*sample| {
        var sum: f32 = 0;
        for (waves.items) |wave| {
            sum += wave.value(time);
        }
        sample.* = sum;
        time += 1.0 / @as(f32, @floatFromInt(DEVICE_SAMPLE_RATE));
    }
}

fn Jean_Baptiste_Joseph_Fourier(samples: []const f32, frequencies: []f32, channels: usize) void {
    const c = std.math.Complex(f32);
    for (frequencies, 0..) |*m, f| {
        var time: f32 = 0;
        var sum = c.init(0, 0);
        const ff: f32 = @floatFromInt(f);
        for (0..samples.len/channels) |i| {
            const sample = samples[i * channels];
            const p = c.init(-std.math.tau * ff * time, 0).mulbyi();
            const v = std.math.complex.pow(c.init(std.math.e, 0), p).mul(c.init(sample, 0));
            sum = sum.add(v);
            time += 1.0 / @as(f32, @floatFromInt(DEVICE_SAMPLE_RATE));
        }
        m.* = sum.magnitude();
        // print("{} \t {}\n", .{ f, m.* });
    }
}

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

fn spectrogram(allocator: std.mem.Allocator, file: [*:0]const u8) !void {
    var decoder: ma.ma_decoder = undefined;
    if (ma.ma_decoder_init_file(file, null, &decoder) != ma.MA_SUCCESS) {
        return error.DecoderInitFailed;
    }
    defer _ = ma.ma_decoder_uninit(&decoder);
    const channels = decoder.outputChannels;
    const format = decoder.outputFormat;
    std.debug.assert(format == ma.ma_format_f32);

    var frameCount: ma.ma_uint64 = 0;
    _ = ma.ma_decoder_get_length_in_pcm_frames(&decoder, &frameCount);

    const samplesPerColumn = frameCount / image_width;
    const samples = try allocator.alloc(f32, samplesPerColumn);
    defer allocator.free(samples);
    const image = try allocator.alloc(u32, image_width * image_height);
    defer allocator.free(image);

    var magnitudes: [20000]f32 = undefined;
    for (0..image_width) |i| {
        _ = ma.ma_decoder_read_pcm_frames(&decoder, samples.ptr, samplesPerColumn / channels, null);
        Jean_Baptiste_Joseph_Fourier(samples, &magnitudes, @intCast(channels));

        var max: f32 = 0;
        for (magnitudes) |m| {
            max = @max(@log10(1 + m), max);
        }

        const magPerPixel = magnitudes.len / image_height;
        for (0..image_height) |j| {
            const k = j * magPerPixel;
            var avg: f32 = 0;
            for (k..k + magPerPixel) |m| {
                avg += magnitudes[m];
            }
            avg /= magPerPixel;
            avg = @log10(1 + avg);
            const color: u8 = @intFromFloat(avg / max * 255);

            image[j * image_width + i] = 
                @as(u32, 0xFF)  << (8 * 3) | 
                @as(u32, color) << (8 * 2) | 
                @as(u32, color) << (8 * 1) | 
                @as(u32, color) << (8 * 0);
        }
    }
    const rlImg: rl.Image = .{ 
        .data = image.ptr,
        .width = @intCast(image_width), 
        .height = @intCast(image_height), 
        .mipmaps = 0, 
        .format = rl.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 
    };
    _ = rl.ExportImage(rlImg, "spectro.png");
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;
    var waves = std.ArrayList(Wave).empty;
    try waves.append(allocator, .{
        .frequency = 2,
        .amplitude = 0.1,
        .kind = .sine,
    });
    try waves.append(allocator, .{
        .frequency = 69,
        .amplitude = 0.5,
        .kind = .sine,
    });
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
    // try waves.append(allocator, .{
    //     .frequency = 100,
    //     .amplitude = 0.1,
    //     .kind = .random,
    // });

    var engine: ma.ma_engine = undefined;
    if (ma.ma_engine_init(null, &engine) != 0) {
        print("DIED", .{});
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
        print("No success", .{});
    }
    defer ma.ma_device_uninit(&device);

    print("Device Name: {s}", .{device.playback.name});

    // if (ma.ma_device_start(&device) != ma.MA_SUCCESS) {
    //     std.debug.print("Failed to start playback device.", .{});
    //     ma.ma_device_uninit(&device);
    // }

    // const msg = ma.ma_engine_play_sound(&engine, "vine-boom.mp3", null);
    // std.debug.print("{}", .{msg});

    rl.InitWindow(1280, 720, "Oren");
    var scale: f32 = 0.05;
    // var maxY: f32 = 0;
    var samples: [DEVICE_SAMPLE_RATE]f32 = undefined;
    audio_sampling(&samples, waves);
    // var magnitudes: [100]f32 = undefined;
    // Jean_Baptiste_Joseph_Fourier(&samples, &magnitudes);

    try spectrogram(allocator, "sad-trombone.mp3");
    while (!rl.WindowShouldClose()) {
        scale += rl.GetMouseWheelMove() * scale / 100;

        rl.BeginDrawing();
        rl.ClearBackground(rl.RAYWHITE);
        rl.DrawText("It works!", 20, 20, 20, rl.BLACK);

        for (0..@intCast(rl.GetScreenWidth())) |i| {
            rl.DrawPixel(@intCast(i), @divTrunc(rl.GetScreenHeight(), 2), rl.BLACK);
            // const x = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(rl.GetScreenWidth())) * scale * std.math.tau * 0.2;

            // var sum: f32 = 0;
            // for (waves.items) |*wave| {
            //     sum += wave.value(x + gtime * scale);
            // }
            // maxY = @max(maxY, @abs(sum));

            // const quatWindow = @as(f32, @floatFromInt(rl.GetScreenHeight())) / 4;
            // const y: c_int = @intFromFloat((1 - ((sum + maxY) / (2 * maxY)) * 2 * quatWindow) + quatWindow);
            // rl.DrawPixel(@intCast(i), y + @divTrunc(rl.GetScreenHeight(), 2), rl.RED);
        }
        rl.EndDrawing();
    }
    rl.CloseWindow();
}
