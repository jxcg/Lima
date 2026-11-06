#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] half4 limaRipple(float2 position, SwiftUI::Layer layer, float2 size,
                                  float2 layerOrigin, float waveWidth,
                                  device const float *ripples, int count, half4 background) {
    float2 bend = float2(0);
    // Each record contains the tap's normalised x/y, progress and size multiplier.
    for (int i = 0; i + 3 < count; i += 4) {
        float progress = ripples[i + 2];
        if (progress <= 0 || progress >= 1) continue;
        float scale = max(ripples[i + 3], 0.01);
        float2 offset = position + layerOrigin - size * float2(ripples[i], ripples[i + 1]);
        float radius = length(offset);
        // A wider window must not widen or accelerate the wave around the same text.
        float wave = radius - progress * waveWidth * 16.0;
        float width = max(waveWidth * scale, 1.0);
        float phase = wave / width;
        // Beyond six widths, displacement is too small to change a sampled pixel.
        if (abs(phase) > 6.0) continue;
        float envelope = exp(-phase * phase);
        // Keep the original gentle fade; size changes only widen the wave.
        float strength = sin(progress * M_PI_F);
        float displacement = 9.0 * sin(phase * 3.0)
            * envelope * strength;
        bend += offset / max(radius, 1.0) * displacement;
    }
    // Overlapping waves must stay inside SwiftUI's 12-point sampling allowance.
    bend *= min(1.0, 9.0 / max(length(bend), 0.001));
    if (length(bend) == 0) return layer.sample(position);
    // Add just 12% to the original colour separation for a subtle glass edge.
    float dispersion = 0.22 * 1.12;
    half4 red = layer.sample(position + bend * (1.0 + dispersion));
    half4 green = layer.sample(position + bend);
    half4 blue = layer.sample(position + bend * (1.0 - dispersion));
    half alpha = max(red.a, max(green.a, blue.a));
    half3 colour = half3(red.r, green.g, blue.b)
        + background.rgb * (alpha - half3(red.a, green.a, blue.a));
    return half4(colour, alpha);
}
