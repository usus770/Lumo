#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// 1. Neon Glitch Art Effect for Background
[[ stitchable ]] half4 neonGlitchEffect(float2 position, SwiftUI::Layer layer, float time, float intensity) {
    // We want a constantly moving, stylized, glitchy neon effect.
    float2 uv = position;
    
    // Time-based shifting
    float shift = sin(time * 2.0 + uv.y * 0.05) * 10.0 * intensity;
    float shift2 = cos(time * 3.0 - uv.y * 0.1) * 5.0 * intensity;
    
    // Occasional horizontal glitch slices
    float slice = fract(sin(dot(float2(uv.y * 0.01, time), float2(12.9898, 78.233))) * 43758.5453);
    if (slice > 0.95 - (intensity * 0.1)) {
        uv.x += (slice - 0.95) * 200.0 * intensity;
    }
    
    // Sample RGB channels with slight offsets for chromatic aberration
    half4 rColor = layer.sample(uv + float2(shift, 0));
    half4 gColor = layer.sample(uv + float2(shift2, 0));
    half4 bColor = layer.sample(uv + float2(-shift, 0));
    
    // Stylized neon colors (boost saturation and contrast)
    half3 finalRGB = half3(rColor.r, gColor.g, bColor.b);
    
    // Apply scanlines
    float scanline = sin(position.y * 1.5 + time * 5.0) * 0.1 * intensity;
    finalRGB -= scanline;
    
    // Boost neon glow
    finalRGB = pow(finalRGB, half3(0.8)) * 1.2;
    
    return half4(finalRGB, max(max(rColor.a, gColor.a), bColor.a));
}

// 2. Glitch Distortion Effect
[[ stitchable ]] float2 glitchDistortion(float2 position, float time, float intensity) {
    // Generate noise based on y position and time
    float noise1 = fract(sin(dot(float2(position.y * 0.01, time * 0.1), float2(12.9898, 78.233))) * 43758.5453);
    float noise2 = fract(sin(dot(float2(position.y * 0.05, time * 0.5), float2(39.346, 11.135))) * 43758.5453);
    
    float offset = 0.0;
    
    // Large occasional glitches
    if (noise1 > 0.98 - (intensity * 0.05)) {
        offset += (noise2 - 0.5) * 60.0 * intensity;
    }
    
    // Micro jitter
    if (noise2 > 0.8 - (intensity * 0.2)) {
        offset += (noise1 - 0.5) * 10.0 * intensity;
    }
    
    return float2(position.x + offset, position.y);
}

// 3. Neon RGB Split Layer Effect (Chromatic Aberration)
[[ stitchable ]] half4 rgbSplitEffect(float2 position, SwiftUI::Layer layer, float time, float intensity) {
    float splitAmount = 6.0 * intensity;
    
    // Sample channels with offsets
    half4 colorR = layer.sample(position + float2(splitAmount, 0));
    half4 colorG = layer.sample(position);
    half4 colorB = layer.sample(position + float2(-splitAmount, 0));
    
    return half4(colorR.r, colorG.g, colorB.b, max(max(colorR.a, colorG.a), colorB.a));
}

// 4. Dot-Grid Mosaic & Slice Displacement
[[ stitchable ]] half4 mosaicGlitchEffect(float2 position, SwiftUI::Layer layer, float time, float intensity) {
    float2 uv = position;
    
    // Horizontal slice displacement
    float sliceY = floor(uv.y / 24.0);
    float sliceNoise = fract(sin(dot(float2(sliceY, floor(time * 8.0)), float2(12.9898, 78.233))) * 43758.5453);
    if (sliceNoise > 0.85) {
        float shift = (sliceNoise - 0.85) * 80.0 * intensity * (fract(sliceNoise * 31.0) > 0.5 ? 1.0 : -1.0);
        uv.x += shift;
    }
    
    // Pixelation / dot-grid region sweeping across
    float sweep = sin(time * 1.5) * 0.5 + 0.5;
    float distFromSweep = abs((uv.y / 800.0) - sweep);
    if (distFromSweep < 0.15 && intensity > 0.2) {
        float gridSize = 8.0 * (1.0 - distFromSweep / 0.15);
        uv = floor(uv / gridSize) * gridSize + (gridSize * 0.5);
    }
    
    return layer.sample(uv);
}

