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
    float4 renderSurface;
    float4 renderRidge;
    float4 renderEdge;
    float4 renderVisibility;
    float4 renderFlow;
    float4 viewOrientation;
};

struct ParticleVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float surfaceWeight;
    float surfaceLight;
    float ridge;
    float flowLight;
    float brightness;
    float alphaScale;
    float4 baseColor;
    float4 ridgeColor;
    float4 highlightColor;
};

constant float kMinimumAspect = 0.001;
constant float kMinimumRadius = 0.00001;
constant float kFullRotation = 6.2831853;

float hash11(float value) {
    return fract(sin(value) * 43758.5453123);
}

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
    const float3 bodyPosition = particle.xyz;
    const float3 bodyNormal = length(bodyPosition) > kMinimumRadius
        ? normalize(bodyPosition)
        : float3(0.0, 1.0, 0.0);
    const float particleSeed = hash11(
        float(vertexID) * 12.9898 + uniforms.renderRidge.y * 97.31
    );
    const float secondarySeed = hash11(
        float(vertexID) * 4.1414 + particleSeed * 19.17
    );
    float3 position = rotateByQuaternion(
        particle.xyz,
        uniforms.viewOrientation
    );
    const float surfaceWeight = saturate(particle.w);
    float3 normal = length(position) > kMinimumRadius
        ? normalize(position)
        : float3(0.0, 1.0, 0.0);
    const float grazing = 1 - abs(normal.z);
    const float rim = smoothstep(0.34, 0.82, grazing);
    const float edgeDust = saturate(uniforms.renderEdge.x) * 2;
    const float edgeFray = saturate(uniforms.renderEdge.y) * 2;
    const float dustVariation = mix(0.35, 1, secondarySeed);
    position += normal
        * rim
        * edgeDust
        * dustVariation
        * 0.022;
    normal = length(position) > kMinimumRadius
        ? normalize(position)
        : normal;
    const float aspect = uniforms.viewportAndRender.x
        / max(uniforms.viewportAndRender.y, kMinimumAspect);
    const float projectionScale = uniforms.interaction.w;
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
    const float ridgePhase = (
        uniforms.renderRidge.y - 0.5
    ) * kFullRotation;
    const float ridgeMotion = uniforms.renderEdge.w
        * saturate(uniforms.renderRidge.z);
    const float ridgeWidth = mix(
        0.025,
        0.18,
        saturate(uniforms.renderSurface.w)
    );
    const float ridgeWaveA = dot(
        bodyNormal,
        normalize(float3(0.81, 0.31, -0.49))
    ) * 12.4 + ridgeMotion + ridgePhase;
    const float ridgeWaveB = dot(
        bodyNormal,
        normalize(float3(-0.28, 0.90, 0.34))
    ) * 9.2 - ridgeMotion * 0.72 - ridgePhase * 0.63;
    const float ridgeLineA = 1 - smoothstep(
        ridgeWidth,
        ridgeWidth + 0.12,
        abs(sin(ridgeWaveA))
    );
    const float ridgeLineB = 1 - smoothstep(
        ridgeWidth * 0.82,
        ridgeWidth * 0.82 + 0.10,
        abs(sin(ridgeWaveB))
    );
    const float breakupPattern = smoothstep(
        saturate(uniforms.renderRidge.x) * 0.72,
        min(1.0, saturate(uniforms.renderRidge.x) * 0.72 + 0.24),
        hash11(particleSeed * 71.3 + secondarySeed * 29.7)
    );
    const float ridge = saturate(
        max(ridgeLineA, ridgeLineB * 0.72)
        * breakupPattern
        * saturate(uniforms.renderSurface.z)
        * 2
        * surfaceWeight
    );
    const float flowPhase = (
        uniforms.renderEdge.z - 0.5
    ) * kFullRotation;
    const float3 configuredFlowAxis = length(uniforms.renderFlow.xyz)
        > kMinimumRadius
        ? normalize(uniforms.renderFlow.xyz)
        : float3(1.0, 0.0, 0.0);
    const float3 flowReference = abs(configuredFlowAxis.y) < 0.92
        ? float3(0.0, 1.0, 0.0)
        : float3(1.0, 0.0, 0.0);
    const float3 flowCrossAxis = normalize(
        cross(flowReference, configuredFlowAxis)
    );
    const float flowWaveA = 0.5 + 0.5 * sin(
        dot(bodyNormal, configuredFlowAxis) * 8.4
            - uniforms.renderFlow.w * kFullRotation
            + flowPhase
    );
    const float flowWaveB = 0.5 + 0.5 * cos(
        dot(bodyNormal, flowCrossAxis) * 6.2
            + uniforms.renderFlow.w * kFullRotation * 0.74
            - flowPhase * 0.67
    );
    const float flowLight = smoothstep(
        0.38,
        0.88,
        flowWaveA * 0.62 + flowWaveB * 0.38
    ) * saturate(uniforms.renderRidge.w) * 2;
    const float frontVisibility = smoothstep(
        uniforms.renderVisibility.z,
        uniforms.renderVisibility.w,
        frontness
    );
    const float depthBrightness = mix(
        uniforms.renderVisibility.x,
        uniforms.renderVisibility.y,
        smoothstep(
            uniforms.renderVisibility.z,
            uniforms.renderVisibility.w,
            frontness
        )
    );

    float2 clipPosition = position.xy * projectionScale;
    clipPosition.x /= max(aspect, kMinimumAspect);

    ParticleVertexOut out;
    out.position = frontVisibility > 0.001
        ? float4(clipPosition, 0, 1)
        : float4(4, 4, 0, 1);
    out.pointSize = uniforms.viewportAndRender.z
        * depthScale
        * mix(uniforms.renderGeometry.z, uniforms.renderGeometry.w, surfaceWeight)
        * channelSizeScale
        * (
            1
                + rim
                * edgeFray
                * mix(0.08, 0.34, particleSeed)
        );
    out.surfaceWeight = surfaceWeight;
    const float rawSurfaceLight = saturate(
        dot(normal, normalize(uniforms.renderLight.xyz)) * 0.5 + 0.5
    );
    const float surfaceLightContrast = saturate(
        uniforms.renderSurface.y
    ) * 2;
    out.surfaceLight = saturate(
        0.5 + (rawSurfaceLight - 0.5) * surfaceLightContrast
    );
    out.ridge = ridge;
    out.flowLight = flowLight;
    out.brightness = uniforms.viewportAndRender.w
        * channelBrightness
        * (1 + flowLight * 0.42)
        * depthBrightness;
    out.alphaScale = mix(1, uniforms.renderAlpha.x, dissolution)
        * uniforms.highlightColor.a
        * uniforms.renderSurface.x
        * frontVisibility
        * (
            1
                - rim
                * edgeFray
                * mix(0.02, 0.18, secondarySeed)
        );
    out.baseColor = uniforms.baseColor;
    out.ridgeColor = uniforms.ridgeColor;
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
    const float surfaceWeight = saturate(in.surfaceWeight);
    const float light = saturate(in.surfaceLight);
    const float ridge = saturate(in.ridge);
    const float layerAlpha = mix(
        uniforms.renderAlpha.y,
        uniforms.renderAlpha.z,
        surfaceWeight
    );
    const float alpha = saturate(
        core * uniforms.renderAlpha.w + halo * uniforms.renderLight.w
    ) * layerAlpha * in.alphaScale;

    const half3 bodyColor = half3(in.baseColor.rgb);
    const half3 surfaceColor = half3(in.ridgeColor.rgb);
    const half3 highlightColor = half3(in.highlightColor.rgb);
    half3 color = bodyColor;
    color = mix(
        color,
        surfaceColor,
        half(saturate(
            surfaceWeight
                * (uniforms.renderColor.y + light * uniforms.renderColor.z)
                + ridge * 0.68
        ))
    );
    color = mix(
        color,
        highlightColor,
        half(saturate(
            light * surfaceWeight * uniforms.renderColor.w
                + ridge * 0.22
                + in.flowLight * surfaceWeight * 0.12
        ))
    );
    color *= half(in.brightness);
    return half4(color, half(alpha));
}
