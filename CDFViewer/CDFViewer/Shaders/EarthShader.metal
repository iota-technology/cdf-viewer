#include <metal_stdlib>
#include <SceneKit/scn_metal>
using namespace metal;

// Input from SceneKit
struct VertexInput {
    float3 position [[attribute(SCNVertexSemanticPosition)]];
    float3 normal [[attribute(SCNVertexSemanticNormal)]];
    float2 texCoord [[attribute(SCNVertexSemanticTexcoord0)]];
};

// Output to fragment shader
struct VertexOutput {
    float4 position [[position]];
    float3 worldNormal;
    float3 worldPosition;
    float2 texCoord;
};

// SceneKit node uniforms
struct NodeBuffer {
    float4x4 modelTransform;
    float4x4 modelViewProjectionTransform;
    float4x4 normalTransform;
};

// Custom uniforms for Earth rendering
struct EarthUniforms {
    float3 sunDirection;      // Normalized direction toward sun in world space
    float terminatorWidth;    // Width of day/night transition in radians (~0.26 for realistic)
};

// Vertex shader
vertex VertexOutput earthVertex(
    VertexInput in [[stage_in]],
    constant NodeBuffer& scn_node [[buffer(1)]]
) {
    VertexOutput out;

    // Transform position to clip space
    out.position = scn_node.modelViewProjectionTransform * float4(in.position, 1.0);

    // Transform normal to world space
    out.worldNormal = normalize((scn_node.normalTransform * float4(in.normal, 0.0)).xyz);

    // Transform position to world space
    out.worldPosition = (scn_node.modelTransform * float4(in.position, 1.0)).xyz;

    // Pass through texture coordinates
    out.texCoord = in.texCoord;

    return out;
}

// Fragment shader
fragment float4 earthFragment(
    VertexOutput in [[stage_in]],
    texture2d<float> dayTexture [[texture(0)]],       // Pre-blended day texture
    texture2d<float> nightTexture [[texture(1)]],     // Black marble city lights
    constant EarthUniforms& uniforms [[buffer(2)]],
    sampler texSampler [[sampler(0)]]
) {
    // Sample day texture (pre-blended for current month on CPU)
    float4 dayColor = dayTexture.sample(texSampler, in.texCoord);

    // Sample night texture (city lights intensity)
    float nightIntensity = nightTexture.sample(texSampler, in.texCoord).r;

    // Calculate sun illumination using world normal
    // Dot product: 1 = facing sun, -1 = facing away, 0 = terminator
    float sunDot = dot(normalize(in.worldNormal), uniforms.sunDirection);

    // Smooth terminator transition
    // Map from [-terminatorWidth, +terminatorWidth] to [0, 1]
    float dayFactor = smoothstep(-uniforms.terminatorWidth, uniforms.terminatorWidth, sunDot);

    // Apply basic lighting to day side
    float ambient = 0.15;
    float diffuse = max(0.0, sunDot);
    float dayLighting = ambient + diffuse * 0.85;
    float4 litDayColor = dayColor * dayLighting;

    // Night side: show city lights with warm yellow-orange tint
    float3 cityLightColor = float3(1.0, 0.85, 0.5);
    float nightEmission = nightIntensity * 2.5;  // Boost city lights visibility
    float3 nightColor = cityLightColor * nightEmission;

    // Night side base color (very dark version of day texture)
    float4 darkBase = dayColor * 0.02;

    // Composite: blend between lit day and (dark base + city lights)
    float3 finalColor = mix(
        darkBase.rgb + nightColor,   // Night side: dark terrain + city lights
        litDayColor.rgb,              // Day side: normally lit
        dayFactor
    );

    return float4(finalColor, 1.0);
}
