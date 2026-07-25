#include <metal_stdlib>
using namespace metal;

struct ParticleFrameUniforms {
    float4 viewportAndRender;
    float4 interaction;
    float4 visualChannelsA;
    float4 visualChannelsB;
    float4 baseColor;
    float4 ridgeColor;
    float4 dimColor;
    float4 highlightColor;
    float4 renderGeometry;
    float4 renderChannels;
    float4 renderAlpha;
    float4 renderPoint;
    float4 renderLight;
    float4 renderColor;
    float4 viewOrientation;
};

struct ParticleVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float depth;
    float surfaceWeight;
    float surfaceLight;
    float brightness;
    float alphaScale;
    float4 baseColor;
    float4 ridgeColor;
    float4 dimColor;
    float4 highlightColor;
};

constant float kMinimumAspect = 0.001;
constant float kMinimumRadius = 0.00001;

float3 rotateByQuaternion(float3 vector, float4 quaternion) {
    return vector + 2 * cross(
        quaternion.xyz,
        cross(quaternion.xyz, vector) + quaternion.w * vector
    );
}

vertex ParticleVertexOut particleVertex(
    const device float4 *particles [[buffer(0)]],
    constant ParticleFrameUniforms &uniforms [[buffer(1)]],
    uint vertexID [[vertex_id]]
) {
    const float4 particle = particles[vertexID];
    const float3 position = rotateByQuaternion(
        particle.xyz,
        uniforms.viewOrientation
    );
    const float surfaceWeight = saturate(particle.w);
    const float aspect = uniforms.viewportAndRender.x
        / max(uniforms.viewportAndRender.y, kMinimumAspect);
    const float projectionScale = uniforms.interaction.w;
    const float3 normal = length(position) > kMinimumRadius
        ? normalize(position)
        : float3(0.0, 1.0, 0.0);
    const float frontness = saturate(position.z * uniforms.renderColor.x + 0.5);
    const float depthScale = mix(
        uniforms.renderGeometry.x,
        uniforms.renderGeometry.y,
        frontness
    );
    const float focus = saturate(uniforms.visualChannelsA.x);
    const float pulse = saturate(uniforms.visualChannelsA.y);
    const float circulation = saturate(uniforms.visualChannelsA.z);
    const float disruption = saturate(uniforms.visualChannelsA.w);
    const float dissolution = saturate(uniforms.visualChannelsB.x);
    const float channelSizeScale = 1
        - focus * uniforms.renderChannels.x
        + pulse * uniforms.renderChannels.y;
    const float channelBrightness = 1
        + (pulse + circulation) * uniforms.renderChannels.z
        - disruption * uniforms.renderChannels.w;

    float2 clipPosition = position.xy * projectionScale;
    clipPosition.x /= max(aspect, kMinimumAspect);

    ParticleVertexOut out;
    out.position = float4(clipPosition, 0, 1);
    out.pointSize = uniforms.viewportAndRender.z
        * depthScale
        * mix(uniforms.renderGeometry.z, uniforms.renderGeometry.w, surfaceWeight)
        * channelSizeScale;
    out.depth = frontness;
    out.surfaceWeight = surfaceWeight;
    out.surfaceLight = saturate(
        dot(normal, normalize(uniforms.renderLight.xyz)) * 0.5 + 0.5
    );
    out.brightness = uniforms.viewportAndRender.w * channelBrightness;
    out.alphaScale = mix(1, uniforms.renderAlpha.x, dissolution)
        * uniforms.highlightColor.a;
    out.baseColor = uniforms.baseColor;
    out.ridgeColor = uniforms.ridgeColor;
    out.dimColor = uniforms.dimColor;
    out.highlightColor = uniforms.highlightColor;
    return out;
}

fragment half4 particleFragment(
    ParticleVertexOut in [[stage_in]],
    float2 pointCoord [[point_coord]],
    constant ParticleFrameUniforms &uniforms [[buffer(1)]]
) {
    const float distanceFromCenter = distance(pointCoord, float2(0.5));
    const float core = 1 - smoothstep(
        uniforms.renderPoint.x,
        uniforms.renderPoint.y,
        distanceFromCenter
    );
    const float halo = 1 - smoothstep(
        uniforms.renderPoint.z,
        uniforms.renderPoint.w,
        distanceFromCenter
    );
    const float frontness = saturate(in.depth);
    const float surfaceWeight = saturate(in.surfaceWeight);
    const float light = saturate(in.surfaceLight);
    const float layerAlpha = mix(
        uniforms.renderAlpha.y,
        uniforms.renderAlpha.z,
        surfaceWeight
    );
    const float alpha = saturate(
        core * uniforms.renderAlpha.w + halo * uniforms.renderLight.w
    ) * layerAlpha * in.alphaScale;

    const half3 backColor = half3(in.dimColor.rgb);
    const half3 bodyColor = half3(in.baseColor.rgb);
    const half3 surfaceColor = half3(in.ridgeColor.rgb);
    const half3 highlightColor = half3(in.highlightColor.rgb);
    half3 color = mix(backColor, bodyColor, half(frontness));
    color = mix(
        color,
        surfaceColor,
        half(surfaceWeight * (uniforms.renderColor.y + light * uniforms.renderColor.z))
    );
    color = mix(
        color,
        highlightColor,
        half(light * surfaceWeight * uniforms.renderColor.w)
    );
    color *= half(in.brightness);
    return half4(color, half(alpha));
}
