#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float2 uv;
};

struct Uniforms {
    float4 color;
    float2 resolution;
    float time;
};

vertex VertexOut chart_vertex(uint vertexID [[vertex_id]],
                             constant float2 *positions [[buffer(0)]],
                             constant Uniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    float2 pos = positions[vertexID];
    
    // Map 0-1 range to -1 to 1 for Metal NDC
    out.position = float4(pos.x * 2.0 - 1.0, pos.y * 2.0 - 1.0, 0.0, 1.0);
    
    // Simple vertical gradient based on Y position
    float4 topColor = uniforms.color;
    float4 bottomColor = float4(topColor.rgb * 0.1, 0.2);
    out.color = mix(bottomColor, topColor, pos.y);
    out.uv = pos;
    
    return out;
}

fragment float4 chart_fragment(VertexOut in [[stage_in]],
                               constant Uniforms &uniforms [[buffer(1)]]) {
    float2 uv = in.uv;
    float4 baseColor = in.color;
    
    // Scanline effect
    float scanline = sin(uv.y * 150.0 - uniforms.time * 2.0) * 0.5 + 0.5;
    float4 finalColor = baseColor + (uniforms.color * scanline * 0.05);
    
    // Grid lines (horizontal)
    float grid = step(0.99, fract(uv.y * 5.0));
    finalColor += float4(1.0, 1.0, 1.0, 0.05) * grid;
    
    // Leading edge glow
    float pulse = exp(-15.0 * (1.0 - uv.x));
    finalColor += uniforms.color * pulse * 0.6;
    
    // Add a slight "flicker" to make it feel electronic
    float flicker = sin(uniforms.time * 20.0) * 0.01 + 0.99;
    finalColor *= flicker;
    
    return finalColor;
}

// MARK: - Ambient Background Shaders

struct AmbientUniforms {
    float4 color;
    float2 resolution;
    float time;
    float intensity; // 0-1 based on stress/wellbeing
    float2 tilt;     // tilt.x = pitch, tilt.y = roll
};

// Pseudo-random noise functions
float hash(float n) { return fract(sin(n) * 43758.5453123); }

float noise(float3 x) {
    float3 p = floor(x);
    float3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float n = p.x + p.y * 57.0 + 113.0 * p.z;
    return mix(mix(mix(hash(n + 0.0), hash(n + 1.0), f.x),
                   mix(hash(n + 57.0), hash(n + 58.0), f.x), f.y),
               mix(mix(hash(n + 113.0), hash(n + 114.0), f.x),
                   mix(hash(n + 170.0), hash(n + 171.0), f.x), f.y), f.z);
}

vertex VertexOut ambient_vertex(uint vertexID [[vertex_id]],
                               constant float2 *positions [[buffer(0)]]) {
    VertexOut out;
    float2 pos = positions[vertexID];
    out.position = float4(pos, 0.0, 1.0);
    out.uv = pos * 0.5 + 0.5;
    return out;
}

fragment float4 ambient_fragment(VertexOut in [[stage_in]],
                                 constant AmbientUniforms &uniforms [[buffer(1)]]) {
    float2 uv = in.uv;
    float t = uniforms.time * 0.3;
    float intensity = uniforms.intensity;
    
    // Apply tilt to UVs for parallax effect
    float2 tiltedUV = uv + uniforms.tilt * 0.05;
    
    // Organic fluid motion using layered noise
    float n = noise(float3(tiltedUV * 2.0, t));
    n += 0.5 * noise(float3(tiltedUV * 4.0, t * 1.5));
    n += 0.25 * noise(float3(tiltedUV * 8.0, t * 2.0));
    
    // Base colors based on intensity
    // Intensity 0 (Calm): Deep Blue to Teal
    // Intensity 1 (Stressed): Deep Purple to Crimson
    float4 calmColor1 = float4(0.05, 0.2, 0.4, 1.0);
    float4 calmColor2 = float4(0.1, 0.4, 0.6, 1.0);
    float4 stressedColor1 = float4(0.3, 0.05, 0.1, 1.0);
    float4 stressedColor2 = float4(0.6, 0.1, 0.2, 1.0);
    
    float4 color1 = mix(calmColor1, stressedColor1, intensity);
    float4 color2 = mix(calmColor2, stressedColor2, intensity);
    
    float4 baseColor = mix(color1, color2, n);
    
    // Add "floating orbs"
    float orbs = 0.0;
    for(int i=0; i<4; i++) {
        float fi = float(i);
        float2 pos = float2(
            hash(fi * 123.456) + sin(t * (0.5 + hash(fi) * 0.5)) * 0.2,
            hash(fi * 456.789) + cos(t * (0.4 + hash(fi + 1.0) * 0.5)) * 0.2
        );
        float dist = length(uv - pos);
        float size = 0.05 + hash(fi * 789.123) * 0.1;
        orbs += smoothstep(size, 0.0, dist) * (0.2 + 0.3 * intensity);
    }
    
    float4 finalColor = baseColor + float4(1.0, 1.0, 1.0, 0.0) * orbs;
    
    // "Breath" effect: subtle pulse in brightness
    float breath = sin(t * 0.5) * 0.05 + 0.95;
    finalColor *= breath;
    
    // Vignette
    float vignette = 1.0 - length(uv - 0.5) * 1.1;
    finalColor *= saturate(vignette);
    
    // Increase saturation and brightness when stressed
    finalColor.rgb *= (1.0 + intensity * 0.5);
    
    return float4(finalColor.rgb, 0.4 + intensity * 0.2);
}

