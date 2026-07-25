#include <metal_stdlib>
using namespace metal;

struct ParticleFrameUniforms {
    float time;
    float breathing;
    float edgeBreathing;
    float coreStability;
    float2 resolution;
    uint seed;
    uint particleCount;
    float2 mousePosition;
    float2 mouseVelocity;
    float mouseInfluence;
    uint visualChannelsVersion;
    float focusStrength;
    float pulseStrength;
    float circulationStrength;
    float disruptionStrength;
    float dissolutionStrength;
    float transitionElapsedTime;
    float globalScale;
    float pointSizeScale;
    float brightness;
    float alphaScale;
    float ridgeStrength;
    float ridgeWidth;
    float ridgeBreakup;
    float ridgeSeed;
    float ridgeFlowBinding;
    float breathingAmount;
    float breathingTime;
    float flowStrength;
    float flowTime;
    float flowDirection;
    float flowSeed;
    float flowBrightnessStrength;
    float rotationSpeed;
    float rotationDirection;
    float edgeDustAmount;
    float edgeFrayAmount;
    float surfaceLightStrength;
    float4 baseColor;
    float4 ridgeColor;
    float4 dimColor;
    float4 highlightColor;
    float colorAlphaScale;
};

struct ParticleVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float ridge;
    float depth;
    float shimmer;
    float flow;
    float density;
    float frontness;
    float surfaceLight;
    float surfaceWake;
    float focus;
    float pulse;
    float pulseWave;
    float circulation;
    float circulationCycle;
    float circulationLane;
    float disruption;
    float disruptionPulse;
    float fragmentation;
    float edgePresence;
    float dissolutionState;
    float dissolutionFade;
    float dissolutionLocalFade;
    float dissolutionBreak;
    float dissolutionDust;
    float brightness;
    float alphaScale;
    float4 baseColor;
    float4 ridgeColor;
    float4 dimColor;
    float4 highlightColor;
    float colorAlphaScale;
    float instabilityPlaceholder;
};

float hash11(float n) {
    return fract(sin(n) * 43758.5453123);
}

float scaleAroundOne(float value, float range) {
    return max(0.0, 1.0 + (saturate(value) - 0.5) * 2.0 * range);
}

float centeredControl(float value, float maximum) {
    float control = saturate(value);
    return control <= 0.5
        ? control * 2.0
        : 1.0 + (control - 0.5) * 2.0 * (maximum - 1.0);
}

float2 rotate2(float2 p, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

float3 rotateX(float3 p, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

float3 rotateY(float3 p, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
}

float3 rotateZ(float3 p, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float3(p.x * c - p.y * s, p.x * s + p.y * c, p.z);
}

float3 rotateBody(float3 p, float3 angles) {
    p = rotateY(p, angles.y);
    p = rotateX(p, angles.x);
    return rotateZ(p, angles.z);
}

float morphField(float angle, float depth, float slowTime, float seed) {
    float phase = seed * 6.2831853;
    float lobeA = 2.2 + hash11(seed * 11.7) * 1.4;
    float lobeB = 3.7 + hash11(seed * 17.3) * 1.8;
    float lobeC = 5.1 + hash11(seed * 23.9) * 2.2;
    float a = sin(angle * lobeA + depth * 2.1 + slowTime * (0.42 + hash11(seed * 31.1) * 0.20) + phase);
    float b = sin(angle * lobeB - depth * 2.8 - slowTime * (0.30 + hash11(seed * 37.5) * 0.18) + phase * 1.7);
    float c = sin(angle * lobeC + depth * 1.4 + slowTime * (0.18 + hash11(seed * 43.2) * 0.16) + phase * 2.4);
    return (a * 0.48 + b * 0.34 + c * 0.22) / 1.04;
}

float2 globalDirection(float time) {
    float2 direction = float2(
        cos(time * 0.27 + 0.65) + sin(time * 0.13 + 1.9) * 0.34,
        sin(time * 0.23 + 1.15) + cos(time * 0.17 + 0.4) * 0.28
    );
    return normalize(direction + float2(0.001, 0.001));
}

float2 cardinalDirection(float value) {
    float bucket = floor(saturate(value) * 3.0 + 0.5);
    if (bucket < 0.5) {
        return float2(0.0, 1.0);
    }
    if (bucket < 1.5) {
        return float2(0.0, -1.0);
    }
    if (bucket < 2.5) {
        return float2(-1.0, 0.0);
    }
    return float2(1.0, 0.0);
}

float globalTurnAngle(float time) {
    return sin(time * 0.11 + 2.1) * 0.62
        + sin(time * 0.07 + 4.4) * 0.38
        + cos(time * 0.045 + 0.9) * 0.24;
}

float globalTurnChangePulse(float time) {
    return time * 0.0;
}

float globalShapeWave(float2 p, float depth, float time, float2 axis, float2 side) {
    float travel = dot(p, axis);
    float cross = dot(p, side);
    float primary = sin(travel * 5.4 + cross * 1.2 - time * 0.88 + depth * 1.2);
    float secondary = sin(travel * 2.8 - cross * 3.2 - time * 0.54 + depth * 2.0 + 1.7);
    float tertiary = sin(travel * 7.0 + cross * 2.4 - time * 1.05 - depth * 1.5 + 0.8);
    return primary * 0.58 + secondary * 0.30 + tertiary * 0.12;
}

float2 coherentDirectionField(float2 p,
                              float radius,
                              float depth,
                              float time,
                              float edge,
                              float interior,
                              float midBand,
                              float2 axis,
                              float2 side,
                              float wave) {
    float travel = dot(p, axis);
    float cross = dot(p, side);
    float2 radial = normalize(p + float2(0.001, 0.001));
    float2 tangent = float2(-radial.y, radial.x);
    float layer = 0.34 + interior * 0.44 + midBand * 0.78 + edge * 0.88;
    float roll = sin(travel * 4.1 + cross * 2.0 - time * 0.76 + depth * 1.5);
    float fold = sin(cross * 5.5 - travel * 1.4 + time * 0.62 + depth * 2.4);
    float membrane = smoothstep(0.34, 0.72, radius);

    float2 field = axis * wave * (0.018 + layer * 0.023);
    field += side * roll * (0.010 + midBand * 0.020 + edge * 0.014);
    field += radial * wave * (midBand * 0.018 + edge * 0.032);
    field += tangent * fold * membrane * (0.012 + edge * 0.034 + midBand * 0.014);
    field += axis * sin(time * 0.42 + 0.6) * 0.012;
    return field;
}

float2 localNoiseField(float2 p,
                       float depth,
                       float time,
                       float particleSeed,
                       float seedB,
                       float edge,
                       float interior,
                       float midBand,
                       float2 axis,
                       float2 side,
                       float globalWave) {
    float phase = particleSeed * 6.2831853;
    float detail = sin(dot(p, axis) * (7.0 + seedB * 1.8)
        + dot(p, side) * (4.2 + particleSeed * 1.4)
        - time * (0.82 + seedB * 0.22)
        + depth * 1.8
        + phase);
    float coupled = 0.45 + 0.55 * abs(globalWave);
    float strength = (0.0035 + midBand * 0.0090 + edge * 0.0125 + interior * 0.0045) * coupled;
    float2 diagonal = normalize(axis * (0.65 + seedB * 0.35) + side * (particleSeed - 0.5));
    return diagonal * detail * strength;
}

float3 materialFlowField(float3 body,
                         float time,
                         float particleSeed,
                         float seedB,
                         float edge,
                         float interior,
                         float midBand,
                         float globalWave,
                         float2 axis,
                         float2 side) {
    float sharedPhase = globalWave * 1.4 + dot(body.xy, axis) * 2.2 - dot(body.xy, side) * 1.1;
    float seedPhase = (particleSeed - 0.5) * 0.55 + (seedB - 0.5) * 0.35;
    float waveA = sin(body.y * 4.1 + body.z * 5.0 - time * 0.72 + sharedPhase + seedPhase);
    float waveB = sin(body.z * 4.6 - body.x * 3.4 + time * 0.58 + sharedPhase * 0.62 + 1.3);
    float waveC = cos(body.x * 3.7 + body.y * 2.9 - time * 0.46 + sharedPhase * 0.38 + 2.1);
    float coreWeight = interior * 1.10 + midBand * 1.35 + edge * 0.48;
    float strength = 0.012 + coreWeight * 0.026;
    float3 swirl = float3(
        waveA - waveB * 0.38,
        waveB - waveC * 0.34,
        waveC - waveA * 0.28
    );
    float3 conveyor = float3(axis.x, axis.y, 0.42) * sin(dot(body.xy, side) * 3.0 + body.z * 3.8 - time * 0.52 + globalWave);
    return (swirl * 0.72 + conveyor * 0.28) * strength;
}

float3 volumetricCloudFlowField(float3 body,
                                float time,
                                float particleSeed,
                                float seedB,
                                float edge,
                                float interior,
                                float midBand,
                                float globalWave,
                                float2 axis,
                                float2 side) {
    float travel = dot(body.xy, axis);
    float cross = dot(body.xy, side);
    float phase = particleSeed * 6.2831853 + seedB * 2.4;
    float broadRoll = sin(travel * 2.6 + body.z * 4.8 - time * 0.82 + globalWave * 1.1);
    float innerCurl = cos(cross * 3.8 - body.z * 4.4 + time * 0.68 + phase * 0.18);
    float pocketDrift = sin((travel - cross) * 2.2 + body.z * 5.6 - time * 0.52 + phase * 0.12);
    float cloudWeight = interior * 1.32 + midBand * 1.22 + edge * 0.38;
    float strength = 0.012 + cloudWeight * 0.028;
    float2 curlXY = axis * innerCurl + side * broadRoll;
    float3 roll = float3(curlXY.x, curlXY.y, pocketDrift * 0.74 - broadRoll * 0.22);
    float3 drift = float3(axis.x, axis.y, 0.24) * sin(cross * 2.1 + body.z * 3.6 - time * 0.44 + globalWave);
    return (roll * 0.74 + drift * 0.26) * strength;
}

vertex ParticleVertexOut particleVertex(const device float4 *particles [[buffer(0)]],
                                   const device ParticleFrameUniforms &uniforms [[buffer(1)]],
                                   uint vid [[vertex_id]]) {
    float4 particle = particles[vid];
    float2 p = particle.xy;
    float ridge = saturate(particle.z);
    float depth = particle.w;
    float3 stableShapeLocal = float3(particle.x, particle.y, depth * 0.58);
    float stableShellRadius = length(float3(
        stableShapeLocal.x / 0.58,
        stableShapeLocal.y / 0.44,
        stableShapeLocal.z / 0.58
    ));
    float staticProtrusion = smoothstep(1.04, 1.18, stableShellRadius);
    float id = float(vid);
    float t = uniforms.time;
    float lengthP = length(p);
    float edge = smoothstep(0.28, 0.64, lengthP);
    float interior = 1.0 - smoothstep(0.18, 0.58, lengthP);
    float centerMotionGate = 1.0;
    float shellLayer = saturate(abs(depth) * 1.35 + edge * 0.35);
    float particleSeed = hash11(id * 12.9898 + float(uniforms.seed) * 0.017);
    float seedB = hash11(id * 4.1414 + particleSeed * 19.17);
    float angle = atan2(p.y, p.x);
    float localPhase = particleSeed * 6.2831853 + angle * 1.15 + shellLayer * 2.4 + ridge * 0.9;
    float phaseB = seedB * 6.2831853 - angle * 0.55 + depth * 2.1;
    float2 radial = normalize(p + float2(0.001, 0.001));
    float2 tangent = float2(-radial.y, radial.x);
    float tuneGlobalScale = scaleAroundOne(uniforms.globalScale, 0.36);
    float tunePointSize = scaleAroundOne(uniforms.pointSizeScale, 0.82);
    float tuneBrightness = scaleAroundOne(uniforms.brightness, 0.90);
    float tuneAlpha = scaleAroundOne(uniforms.alphaScale, 0.90);
    float tuneRidgeStrength = 1.08;
    float ridgeSeedPhase = 0.74;
    float ridgeVisibility = saturate(tuneRidgeStrength);
    float tuneFlowStructure = centeredControl(uniforms.flowStrength, 2.65);
    float tuneFlowBrightness = centeredControl(uniforms.flowBrightnessStrength, 2.85);
    float tuneRotationSpeed = centeredControl(uniforms.rotationSpeed, 2.40);
    float tuneEdgeDust = centeredControl(uniforms.edgeDustAmount, 2.20);
    float tuneEdgeFray = centeredControl(uniforms.edgeFrayAmount, 2.20);
    float tuneSurfaceLightContrast = saturate(uniforms.surfaceLightStrength) * 2.0;
    float focusRaw = saturate(uniforms.focusStrength);
    float focus = smoothstep(0.0, 1.0, focusRaw);
    float pulseRaw = saturate(uniforms.pulseStrength);
    float pulse = smoothstep(0.0, 1.0, pulseRaw);
    float circulationRaw = saturate(uniforms.circulationStrength);
    float circulation = smoothstep(0.0, 1.0, circulationRaw);
    float disruptionRaw = saturate(uniforms.disruptionStrength);
    float disruption = smoothstep(0.0, 1.0, disruptionRaw);
    float dissolutionState = saturate(uniforms.dissolutionStrength);
    float dissolutionElapsed = max(uniforms.transitionElapsedTime, 0.0);
    float dissolutionWarmup = smoothstep(0.00, 0.12, dissolutionElapsed);
    float dissolutionContract = dissolutionWarmup * (1.0 - smoothstep(0.28, 0.44, dissolutionElapsed));
    float dissolutionDisconnect = smoothstep(0.24, 0.82, dissolutionElapsed);
    float dissolutionDisperse = smoothstep(0.64, 2.05, dissolutionElapsed);
    float dissolutionFade = smoothstep(1.55, 2.85, dissolutionElapsed);
    float instabilityPlaceholder = saturate(max(disruption, dissolutionState));
    float pulseWaveA = 0.5 + 0.5 * sin(t * 1.08 + localPhase * 0.34 + angle * 1.65 + depth * 1.10);
    float pulseWaveB = 0.5 + 0.5 * sin(t * 0.76 + phaseB * 0.22 - angle * 2.20 + seedB * 3.10);
    float pulseWave = smoothstep(0.36, 0.86, pulseWaveA * 0.60 + pulseWaveB * 0.40);
    float circulationCycleA = 0.5 + 0.5 * sin(t * 0.68 + localPhase * 0.12 + angle * 1.10 + depth * 1.60);
    float circulationCycleB = 0.5 + 0.5 * cos(t * 0.52 + phaseB * 0.10 - angle * 0.72 + seedB * 1.80);
    float circulationCycle = smoothstep(0.30, 0.88, circulationCycleA * 0.54 + circulationCycleB * 0.46);
    float circulationGlobalPulse = 0.5 + 0.5 * sin(t * 0.92);
    float disruptionPulseA = 0.5 + 0.5 * sin(t * 0.86 + localPhase * 0.22 + angle * 2.90 + depth * 1.90);
    float disruptionPulseB = 0.5 + 0.5 * cos(t * 0.64 + phaseB * 0.20 - angle * 5.20 + seedB * 2.80);
    float disruptionPulse = smoothstep(0.42, 0.84, disruptionPulseA * 0.55 + disruptionPulseB * 0.45);
    float fragmentation = smoothstep(0.48, 0.90, 0.5 + 0.5 * sin(t * 0.72 + angle * 9.40 - depth * 3.80 + particleSeed * 3.60));
    float disruptionEdgePulse = smoothstep(0.50, 0.91, 0.5 + 0.5 * cos(t * 0.78 + angle * 11.40 + phaseB * 0.22));
    float disruptionGlobalPulse = smoothstep(0.22, 0.86, 0.5 + 0.5 * sin(t * 1.34 + 0.4));
    float pulseEdgeLift = mix(1.0, 1.32 + pulseWave * 0.30, pulse * edge);
    float circulationEdgeSettle = mix(1.0, 0.52, circulation * edge);
    float edgeSettle = mix(1.0, 0.18, focus) * circulationEdgeSettle * mix(1.0, 0.92, saturate(disruption + dissolutionState));
    float stateFocus = mix(1.0, 1.28, focus);
    float localBreath = (0.0065 * sin(uniforms.breathingTime * (0.29 + particleSeed * 0.11) + localPhase)
        + 0.0035 * sin(uniforms.breathingTime * (0.17 + seedB * 0.07) + phaseB))
        * uniforms.breathingAmount;
    float globalReference = uniforms.breathing * (0.18 + 0.24 * particleSeed + 0.16 * shellLayer);
    float edgeMembrane = edge * (0.0065 * sin(uniforms.breathingTime * (0.21 + seedB * 0.10) + phaseB + angle * 1.7) * uniforms.breathingAmount
        + uniforms.edgeBreathing * (0.28 + 0.34 * particleSeed));
    float2 innerFlow = float2(
        sin(t * (0.18 + seedB * 0.05) + localPhase + p.y * 5.2 + depth * 1.6),
        cos(t * (0.16 + particleSeed * 0.06) + phaseB - p.x * 4.6)
    );
    float innerFlowStrength = interior * centerMotionGate * (0.0012 + 0.0018 * seedB) * uniforms.coreStability;
    float tangentialDrift = edge * (0.0038 + 0.0028 * seedB)
        * sin(t * (0.20 + particleSeed * 0.08) + localPhase * 0.7 + depth * 2.8);
    float radialDrift = localBreath * centerMotionGate * (0.42 + edge * 0.72)
        + globalReference * (0.62 + centerMotionGate * 0.38)
        + edgeMembrane;
    float fieldTime = uniforms.flowTime;
    float flowSeedPhase = (saturate(uniforms.flowSeed) - 0.5) * 6.2831853;
    float flowPatternTime = fieldTime + flowSeedPhase * 0.24;
    float circulationFlowTime = fieldTime * 1.58;
    float midBand = 0.0;
    float2 globalAxis = cardinalDirection(uniforms.flowDirection);
    float2 globalSide = float2(-globalAxis.y, globalAxis.x);
    float globalWave = globalShapeWave(p, depth, flowPatternTime, globalAxis, globalSide);
    float localMorph = morphField(angle, depth, flowPatternTime * 0.72, float(uniforms.seed) * 0.0017 + particleSeed * 0.41 + flowSeedPhase * 0.13);
    float morph = globalWave * 0.74 + localMorph * 0.26;
    float edgeMorph = edge * edge * (0.022 + 0.056 * edge + 0.012 * particleSeed) * morph * edgeSettle * pulseEdgeLift * tuneFlowStructure;
    float surfaceMotion = smoothstep(0.24, 0.58, lengthP);
    float innerMorph = (interior * 0.20 * centerMotionGate + midBand * 0.88 * stateFocus) * (0.0100 + 0.0170 * seedB)
        * (globalWave * 0.78 + localMorph * 0.22)
        * tuneFlowStructure;
    float membraneRoll = edge * (0.010 + 0.018 * seedB)
        * sin(dot(p, globalAxis) * 4.2 + dot(p, globalSide) * 1.9 - flowPatternTime * 0.82 + phaseB + globalWave * 0.8)
        * edgeSettle * pulseEdgeLift * tuneFlowStructure;
    float2 directionWarp = coherentDirectionField(p, lengthP, depth, flowPatternTime, edge, interior, midBand, globalAxis, globalSide, globalWave);
    float2 localWarp = localNoiseField(p, depth, flowPatternTime, particleSeed, seedB, edge, interior, midBand, globalAxis, globalSide, globalWave);
    p += radial * radialDrift;
    p += radial * edgeMorph;
    p += tangent * tangentialDrift;
    p += tangent * membraneRoll;
    p += innerFlow * innerFlowStrength;
    p += innerFlow * innerMorph;
    p += directionWarp * (0.34 + surfaceMotion * 0.66) * mix(1.0, 1.10, focus * (interior + midBand)) * mix(1.0, 0.88, circulation) * tuneFlowStructure;
    p += localWarp * (0.20 + surfaceMotion * 0.80) * mix(1.0, 0.58, focus) * mix(1.0, 0.68, circulation) * tuneFlowStructure;
    float rim = smoothstep(0.46, 0.72, lengthP);
    float rimFeather = rim * rim;
    float rimWave = sin(dot(p, globalAxis) * 8.2 - dot(p, globalSide) * 3.4 - fieldTime * 1.08 + phaseB);
    float rimScatter = rimFeather * (0.018 + 0.026 * seedB) * (0.62 + 0.38 * abs(globalWave)) * edgeSettle * pulseEdgeLift;
    p += radial * rimScatter * (0.55 + 0.45 * rimWave);
    p += tangent * rimFeather * rimWave * (0.010 + 0.018 * particleSeed) * edgeSettle * pulseEdgeLift;
    float centerFollow = (midBand * 0.62 + edge * 0.10)
        * sin(dot(p, globalAxis) * 3.8 + dot(p, globalSide) * 2.6 - fieldTime * 0.74 + localPhase)
        * tuneFlowStructure;
    p += (globalAxis * centerFollow + globalSide * centerFollow * 0.45) * (0.006 + midBand * 0.014);

    float rotationTime = t * 0.76 * tuneRotationSpeed;
    float rotationBucket = floor(saturate(uniforms.rotationDirection) * 3.0 + 0.5);
    float spinDirection = rotationBucket < 1.5 ? -1.0 : 1.0;
    float bodySpinAngle = rotationTime * spinDirection * 3.0;
    bool rotatesVertically = rotationBucket > 0.5 && rotationBucket < 2.5;
    float3 bodySpinAngles = rotatesVertically
        ? float3(bodySpinAngle, 0.0, 0.0)
        : float3(0.0, bodySpinAngle, 0.0);
    float centerReliefGate = 1.0 - smoothstep(0.26, 0.62, lengthP);
    float centerDepthRelief = (globalWave * 0.78 + localMorph * 0.22) * centerReliefGate * 0.032 * tuneFlowStructure;
    float bodyDepth = depth * 0.58 + centerDepthRelief + globalWave * (0.018 + midBand * 0.052 + edge * 0.050) * tuneFlowStructure + centerFollow * 0.012;
    float3 shapeLocal = float3(p.x, p.y, bodyDepth);
    float activeInterior = interior * centerMotionGate;
    float3 materialFlow = materialFlowField(shapeLocal, flowPatternTime, particleSeed, seedB, edge, activeInterior, midBand, globalWave, globalAxis, globalSide);
    float3 cloudFlow = volumetricCloudFlowField(shapeLocal + materialFlow * 0.35, flowPatternTime, particleSeed, seedB, edge, activeInterior, midBand, globalWave, globalAxis, globalSide);
    materialFlow *= tuneFlowStructure;
    cloudFlow *= tuneFlowStructure;
    float3 lightFlowBody = shapeLocal;
    float3 flowDisplacement = materialFlow * (0.62 + activeInterior * 0.08 + midBand * 0.28)
        + cloudFlow * (1.22 + activeInterior * 0.14 + midBand * 0.50);
    float signedFlowRelief = dot(flowDisplacement, normalize(shapeLocal + float3(0.0001)));
    float waveRelief = max(0.0, globalWave) * (0.010 + edge * 0.026 + activeInterior * 0.012) * tuneFlowStructure;
    float dynamicProtrusion = smoothstep(0.002, 0.024, signedFlowRelief + waveRelief);
    float currentProtrusion = saturate(
        staticProtrusion * (0.62 + dynamicProtrusion * 0.38)
        + dynamicProtrusion * 0.72
    );
    float3 viewBody = shapeLocal + flowDisplacement;
    viewBody = rotateBody(viewBody, bodySpinAngles);
    float perspective = clamp(1.0 / (1.0 - viewBody.z * 0.30), 0.84, 1.20);
    p = viewBody.xy * perspective;
    float2 stableScreenPosition = p;
    float stableRadius = length(stableScreenPosition);
    float3 shellNormalView = normalize(rotateBody(normalize(shapeLocal), bodySpinAngles));
    float silhouetteGrazing = 1.0 - abs(shellNormalView.z);
    float base360Rim = smoothstep(0.34, 0.82, silhouetteGrazing);
    float shellSurfaceContinuity = saturate(max(
        base360Rim,
        max(edge * 0.72, smoothstep(0.34, 0.78, shellLayer) * 0.54)
    ));
    float2 surfaceFlowAxis = globalAxis;
    float2 surfaceFlowSide = float2(-surfaceFlowAxis.y, surfaceFlowAxis.x);
    float stretch = sin(fieldTime * 0.58 + globalWave * 0.65);
    float sail = cos(fieldTime * 0.46 + dot(p, surfaceFlowSide) * 2.8);
    float postSurfaceMotion = 0.42 + 0.58 * smoothstep(0.10, 0.58, length(p));
    p += surfaceFlowAxis * dot(p, surfaceFlowSide) * stretch * (0.030 + midBand * 0.020 + edge * 0.016) * postSurfaceMotion * tuneFlowStructure;
    p += surfaceFlowSide * dot(p, surfaceFlowAxis) * sail * (0.014 + midBand * 0.014 + edge * 0.010) * postSurfaceMotion * tuneFlowStructure;
    float sheetTravel = dot(p, surfaceFlowAxis);
    float sheetCross = dot(p, surfaceFlowSide);
    float turnWakePhase = fieldTime * 0.66 + globalWave * 0.32;
    float turnWakeA = sin(sheetTravel * 4.2 + sheetCross * 1.1 + viewBody.z * 2.0 - turnWakePhase);
    float turnWakeB = sin(sheetTravel * 2.1 - sheetCross * 2.6 + viewBody.z * 1.2 - turnWakePhase * 0.72 + 1.4);
    float turnWake = turnWakeA * 0.68 + turnWakeB * 0.22;
    float turnWakeCrest = smoothstep(0.18, 0.92, 0.5 + 0.5 * turnWake);
    float frontSurfaceGate = smoothstep(-0.34, 0.58, viewBody.z);
    float edgeWakeMute = 1.0 - smoothstep(0.62, 0.86, stableRadius);
    float frontSheetGate = 0.0;
    float frontSpreadGate = 0.0;
    float turnWakeGate = frontSurfaceGate
        * edgeWakeMute
        * (0.24 + frontSheetGate * 0.54 + frontSpreadGate * 0.58 + midBand * 0.22 + postSurfaceMotion * 0.22);
    float turnWakeEnergy = saturate((turnWakeCrest * 0.72 + abs(turnWake) * 0.18) * turnWakeGate);
    p += surfaceFlowAxis * turnWake * (0.004 + interior * 0.006 + midBand * 0.014 + frontSheetGate * 0.012 + frontSpreadGate * 0.016 + edge * 0.001) * turnWakeGate * mix(1.0, 1.10, focus) * mix(1.0, 1.10, pulse) * tuneFlowStructure;
    p += surfaceFlowSide * turnWakeB * (0.003 + interior * 0.004 + midBand * 0.010 + frontSheetGate * 0.008 + frontSpreadGate * 0.012 + edge * 0.001) * turnWakeGate * mix(1.0, 1.06, focus) * mix(1.0, 1.08, pulse) * tuneFlowStructure;
    float edgeFrayA = 0.5 + 0.5 * sin(angle * 7.2 + depth * 4.4 - fieldTime * 0.34 + particleSeed * 6.2831853);
    float edgeFrayB = 0.5 + 0.5 * cos(angle * 11.6 - depth * 3.6 + fieldTime * 0.26 + phaseB);
    float edgeFrayVariation = smoothstep(0.34, 0.78, edgeFrayA * 0.56 + edgeFrayB * 0.34 + seedB * 0.10);
    float edgeFrayField = base360Rim * mix(0.70, 1.0, edgeFrayVariation) * (0.82 + edge * 0.18);
    float2 edgeNormal = normalize(shellNormalView.xy + normalize(p + float2(0.001, 0.001)) * 0.35);
    float2 edgeTangent = float2(-edgeNormal.y, edgeNormal.x);
    float edgeFrayAmount = edgeFrayField * (0.006 + 0.016 * seedB) * (0.76 + 0.24 * abs(globalWave)) * edgeSettle * pulseEdgeLift * tuneEdgeFray * 0.42;
    p += edgeNormal * edgeFrayAmount;
    p += edgeTangent * edgeFrayField * sin(fieldTime * 0.41 + phaseB + angle * 2.0) * (0.001 + 0.004 * particleSeed) * edgeSettle * pulseEdgeLift * tuneEdgeFray;
    float screenCloudRoll = sin(dot(p, surfaceFlowAxis) * 3.2 + viewBody.z * 4.4 - fieldTime * 0.86 + globalWave);
    float screenCloudCurl = cos(dot(p, surfaceFlowSide) * 3.6 - viewBody.z * 5.0 + fieldTime * 0.72 + phaseB * 0.10);
    float screenCloudStrength = activeInterior * 0.006 + midBand * 0.018 * stateFocus + edge * 0.002 * edgeSettle;
    p += (surfaceFlowAxis * screenCloudCurl + surfaceFlowSide * screenCloudRoll) * screenCloudStrength * tuneFlowStructure;
    p += normalize(p + float2(0.001, 0.001)) * screenCloudRoll * (activeInterior * 0.003 + midBand * 0.012) * tuneFlowStructure;
    float visibleWakeGate = turnWakeGate
        * (0.46 + midBand * 0.42 + interior * 0.36 + frontSheetGate * 0.42 + frontSpreadGate * 0.88)
        * (1.0 - smoothstep(0.76, 0.98, stableRadius));
    p += (surfaceFlowAxis * turnWake + surfaceFlowSide * turnWakeB * 0.72)
        * (0.004 + interior * 0.010 + midBand * 0.014 + frontSheetGate * 0.014 + frontSpreadGate * 0.022 + edge * 0.001)
        * visibleWakeGate
        * mix(1.0, 1.20, pulse)
        * tuneFlowStructure;
    float focusGate = focus
        * (0.46 + interior * 0.34 + midBand * 0.54 + edge * 0.08)
        * (1.0 - smoothstep(0.78, 0.98, stableRadius));
    float focusWave = sin(sheetTravel * 3.8 - sheetCross * 0.85 + viewBody.z * 2.2 - fieldTime * 0.42 + globalWave);
    p += surfaceFlowAxis * focusWave * (0.010 + midBand * 0.026 + interior * 0.018) * focusGate;
    p -= normalize(p + float2(0.001, 0.001)) * (0.020 + midBand * 0.026 + interior * 0.016) * focusGate;
    float circulationLoopGate = circulation
        * (0.44 + interior * 0.42 + midBand * 0.54 + edge * 0.12)
        * (1.0 - smoothstep(0.86, 1.04, stableRadius));
    float circulationRing = sin(sheetTravel * 2.7 - sheetCross * 1.4 + viewBody.z * 2.2 - circulationFlowTime * 0.52);
    float circulationLayer = cos(sheetCross * 2.4 + sheetTravel * 1.1 + viewBody.z * 3.0 + circulationFlowTime * 0.42);
    float circulationLane = smoothstep(0.24, 0.90, 0.5 + 0.5 * (circulationRing * 0.62 + circulationLayer * 0.38));
    p += surfaceFlowSide
        * circulationRing
        * (0.014 + interior * 0.026 + midBand * 0.044 + frontSheetGate * 0.012)
        * circulationLoopGate;
    p += surfaceFlowAxis
        * circulationLayer
        * (0.010 + interior * 0.020 + midBand * 0.036 + frontSpreadGate * 0.009)
        * circulationLoopGate;
    p += normalize(p + float2(0.001, 0.001))
        * (circulationCycle - 0.5)
        * (0.007 + midBand * 0.016 + interior * 0.014)
        * circulationLoopGate;
    float disruptionDisruptionGate = disruption
        * frontSurfaceGate
        * (0.24 + interior * 0.36 + midBand * 0.86 + frontSheetGate * 0.36)
        * (1.0 - smoothstep(0.88, 1.06, stableRadius));
    float disruptionStall = disruptionPulse * (0.52 + fragmentation * 0.48);
    float disruptionShear = sin(sheetTravel * 5.2 - sheetCross * 2.1 + viewBody.z * 2.8 - fieldTime * 0.36 + phaseB * 0.10);
    p += surfaceFlowSide
        * disruptionShear
        * (0.009 + interior * 0.014 + midBand * 0.038 + frontSheetGate * 0.019)
        * disruptionDisruptionGate;
    p -= surfaceFlowAxis
        * disruptionStall
        * (0.007 + interior * 0.010 + midBand * 0.026)
        * disruptionDisruptionGate;
    p += normalize(p + float2(0.001, 0.001))
        * (fragmentation - 0.5)
        * (0.007 + interior * 0.008 + midBand * 0.022)
        * disruptionDisruptionGate;
    float disruptionEdgeGate = disruption
        * edge
        * smoothstep(0.48, 0.78, stableRadius)
        * (1.0 - smoothstep(0.86, 1.08, stableRadius))
        * disruptionEdgePulse;
    p += normalize(p + float2(0.001, 0.001)) * disruptionEdgeGate * (0.006 + 0.010 * seedB);
    p += surfaceFlowSide
        * disruptionEdgeGate
        * sin(fieldTime * 0.34 + angle * 2.7 + phaseB)
        * (0.003 + 0.006 * particleSeed);
    edgeFrayField = saturate(edgeFrayField + disruptionEdgeGate * 0.22);
    float pulseSurfaceGate = mix(0.48, 1.0, frontSurfaceGate);
    float pulseFlowGate = pulse
        * pulseSurfaceGate
        * (0.24 + interior * 0.42 + midBand * 0.58 + edge * 0.28)
        * (1.0 - smoothstep(0.84, 1.04, stableRadius));
    float pulseWaveSigned = pulseWave - 0.42;
    p += normalize(p + float2(0.001, 0.001))
        * pulseWaveSigned
        * (0.011 + interior * 0.021 + midBand * 0.029 + edge * 0.018)
        * pulseFlowGate;
    p += surfaceFlowAxis
        * pulseWaveSigned
        * (0.008 + interior * 0.011 + midBand * 0.021 + frontSpreadGate * 0.020)
        * pulseFlowGate;
    float pulseExpansion = pulse * (0.040 + pulseWave * 0.028 + midBand * 0.012 + edge * 0.014);
    float circulationHold = circulation * (0.042 + midBand * 0.010 + edge * 0.006 - circulationGlobalPulse * 0.010);
    float disruptionHold = disruption * (0.026 + disruptionGlobalPulse * 0.030);
    float placeholderScale = 1.0 - disruptionHold - dissolutionState * 0.008;
    p *= (1.0 - focus * 0.125 + pulseExpansion - circulationHold) * placeholderScale;
    float innerDissolutionZone = 1.0 - smoothstep(0.16, 0.38, lengthP);
    float middleDissolutionZone = smoothstep(0.18, 0.42, lengthP) * (1.0 - smoothstep(0.58, 0.82, lengthP));
    float edgeDissolutionZone = smoothstep(0.48, 0.76, lengthP);
    float outerDustZone = edgeDissolutionZone * smoothstep(0.56, 0.94, seedB);
    float dissolutionRadius = saturate(lengthP / 0.78);
    float dissolutionRingRelease = smoothstep(0.22 + dissolutionRadius * 0.42, 1.10 + dissolutionRadius * 0.56, dissolutionElapsed);
    float dissolutionLocalFade = dissolutionState * smoothstep(1.02 + dissolutionRadius * 0.88, 1.78 + dissolutionRadius * 1.08, dissolutionElapsed);
    float2 dissolutionOutward = normalize(p + float2(0.001, 0.001));
    float2 dissolutionRandom = normalize(float2(
        cos(particleSeed * 6.2831853 + seedB * 2.7),
        sin(seedB * 6.2831853 - particleSeed * 2.1)
    ) + float2(0.001, 0.001));
    float flowSignature = sin(sheetTravel * 3.4 - sheetCross * 2.1 + viewBody.z * 2.6 + phaseB * 0.16);
    float2 dissolutionFlowDirection = normalize(surfaceFlowAxis * (0.72 + flowSignature * 0.18)
        + surfaceFlowSide * (0.18 * sin(angle * 2.4 + depth * 1.8 + seedB * 2.0)));
    float2 dissolutionDirection = normalize(dissolutionOutward * 0.68 + dissolutionFlowDirection * 0.24 + dissolutionRandom * 0.08);
    float dissolutionBreakPattern = smoothstep(0.48, 0.88, 0.5 + 0.5 * sin(sheetTravel * 5.6 - sheetCross * 2.4 + viewBody.z * 3.2 + phaseB * 0.24));
    float dissolutionBreakAmount = dissolutionState * dissolutionDisconnect * dissolutionBreakPattern * (0.10 + middleDissolutionZone * 0.50 + edgeDissolutionZone * 0.24);
    float centerRelease = innerDissolutionZone * dissolutionRingRelease;
    float midSlide = middleDissolutionZone * (dissolutionRingRelease * 0.36 + dissolutionDisperse * 0.64);
    float edgeRelease = edgeDissolutionZone * (dissolutionRingRelease * 0.30 + dissolutionDisperse * 0.58 + dissolutionFade * 0.12);
    float dustRelease = outerDustZone * (dissolutionRingRelease * 0.18 + dissolutionDisperse * 0.22 + dissolutionFade * 0.60);
    p -= dissolutionOutward * dissolutionState * dissolutionContract * (0.046 * innerDissolutionZone + 0.030 * middleDissolutionZone + 0.012 * edgeDissolutionZone);
    p += dissolutionDirection * dissolutionState * (centerRelease * 0.105 + midSlide * (0.205 + 0.045 * dissolutionBreakPattern) + edgeRelease * 0.285);
    p += dissolutionOutward * dissolutionState * (centerRelease * 0.040 + midSlide * 0.085 + edgeRelease * 0.215 + dustRelease * 0.105);
    p += tangent * dissolutionState * dissolutionRingRelease * (0.018 + 0.018 * seedB) * sin(angle * 2.0 + phaseB + dissolutionElapsed * 0.36);
    p += dissolutionRandom * dissolutionState * dustRelease * 0.060;
    p += surfaceFlowSide * dissolutionState * dissolutionBreakAmount * sin(phaseB + dissolutionElapsed * 0.42) * 0.022;
    float2 mouseDelta = p - uniforms.mousePosition;
    float mouseDistance = length(mouseDelta);
    float2 mouseRadial = mouseDelta / max(mouseDistance, 0.001);
    float2 mouseTangent = float2(-mouseRadial.y, mouseRadial.x);
    float mouseBodyResponse = saturate(0.68 + interior * 0.30 + midBand * 0.20 + edge * 0.12);
    float interactionScale = mix(1.0, 0.72, focus) * mix(1.0, 0.90, instabilityPlaceholder);
    float radialMouseField = (1.0 - smoothstep(0.04, 1.28, mouseDistance)) * uniforms.mouseInfluence * mouseBodyResponse * interactionScale;
    float swirlMouseField = (1.0 - smoothstep(0.02, 0.78, mouseDistance)) * uniforms.mouseInfluence * mouseBodyResponse * interactionScale;
    float mouseSwirl = clamp(dot(uniforms.mouseVelocity, mouseTangent) * 0.18, -1.0, 1.0);
    p += mouseRadial * radialMouseField * 0.046;
    p += mouseTangent * swirlMouseField * mouseSwirl * 0.026;
    float screenEdge = smoothstep(0.34, 0.66, length(p));
    float edgeDustA = 0.5 + 0.5 * sin(angle * 17.0 + depth * 6.4 + particleSeed * 9.7 - fieldTime * 0.20);
    float edgeDustB = 0.5 + 0.5 * cos(angle * 23.0 - depth * 5.1 + seedB * 8.3 + fieldTime * 0.18);
    float2 screenNormal = normalize(p + float2(0.001, 0.001));
    float2 rimScatterNormal = normalize(shellNormalView.xy + screenNormal * 0.24 + float2(0.001, 0.001));
    float2 rimScatterTangent = float2(-rimScatterNormal.y, rimScatterNormal.x);
    float edgeDustVariation = smoothstep(0.28, 0.84, edgeDustA * 0.48 + edgeDustB * 0.36 + seedB * 0.16);
    float edgeDustField = base360Rim
        * mix(0.70, 1.0, edgeDustVariation)
        * (0.72 + screenEdge * 0.18 + edge * 0.10);
    edgeDustField *= edgeSettle * pulseEdgeLift * tuneEdgeDust;
    float edgeScatterSeed = hash11(particleSeed * 173.0 + seedB * 47.0 + 5.3);
    float farScatterMask = smoothstep(0.75, 0.92, edgeScatterSeed);
    float nearScatterDistance = mix(0.008, 0.018, seedB);
    float farScatterDistance = farScatterMask * mix(0.007, 0.017, hash11(seedB * 229.0 + particleSeed * 61.0));
    float edgeScatterDistance = min(0.035, nearScatterDistance + farScatterDistance);
    p += rimScatterNormal * edgeDustField * edgeScatterDistance;
    p += rimScatterTangent * edgeDustField * sin(angle * 3.4 + phaseB + fieldTime * 0.28)
        * mix(0.002, 0.007, particleSeed)
        * mix(0.72, 1.0, farScatterMask);
    edgeFrayField = saturate(edgeFrayField * 0.26 * tuneEdgeFray + dissolutionBreakAmount * 0.42 + dissolutionState * dustRelease * 0.24);

    float aspect = uniforms.resolution.x / max(uniforms.resolution.y, 1.0);
    p *= tuneGlobalScale;
    float2 clip = float2(p.x / aspect, p.y);

    ParticleVertexOut out;
    out.position = float4(clip, 0.0, 1.0);
    float independentFlowAngle = fieldTime * 2.48 + 0.73 + flowSeedPhase;
    float3 flowSpace = rotateBody(rotateY(lightFlowBody, independentFlowAngle), float3(0.08, -0.05, 0.03));
    float viewDepth = clamp(viewBody.z * 1.55, -1.0, 1.0);
    float animatedTravel = dot(flowSpace.xy, surfaceFlowAxis);
    float animatedCross = dot(flowSpace.xy, surfaceFlowSide);
    float cloudTravel = dot(flowSpace.xy, normalize(surfaceFlowAxis * 0.78 + surfaceFlowSide * 0.22));
    float cloudCross = dot(flowSpace.xy, normalize(surfaceFlowSide * 0.82 - surfaceFlowAxis * 0.18));
    float cloudPatchA = smoothstep(0.38, 0.84, 0.5 + 0.5 * sin(cloudTravel * 3.8 + flowSpace.z * 5.4 - fieldTime * 0.86 + morph * 0.72 + flowSeedPhase * 0.77));
    float cloudPatchB = smoothstep(0.42, 0.88, 0.5 + 0.5 * cos(cloudCross * 4.6 - cloudTravel * 1.4 + flowSpace.z * 4.2 + fieldTime * 0.72 + phaseB * 0.12 - flowSeedPhase * 1.11));
    float cloudPocket = 1.0 - smoothstep(0.48, 0.82, 0.5 + 0.5 * sin(cloudCross * 3.0 + cloudTravel * 2.0 - flowSpace.z * 4.9 - fieldTime * 0.48 + globalWave + flowSeedPhase * 0.53));
    float cloudDensity = saturate((cloudPatchA * 0.58 + cloudPatchB * 0.42)
        * (0.44 + interior * 0.56 + midBand * 0.46 + edge * 0.12)
        * (0.62 + cloudPocket * 0.38));
    float flowSurfaceGate = saturate(0.34 + interior * 0.28 + edge * 0.38);
    float structureAngle = atan2(flowSpace.y, flowSpace.x);
    float sectionA = 0.5 + 0.5 * sin(structureAngle * 2.4 + flowSpace.z * 3.2 - fieldTime * 0.24 + morph);
    float sectionB = 0.5 + 0.5 * cos(animatedTravel * 2.1 - animatedCross * 1.7 + flowSpace.z * 3.8 + fieldTime * 0.30);
    float sectionC = 0.5 + 0.5 * sin(animatedCross * 2.7 + flowSpace.z * 2.8 - fieldTime * 0.40 + phaseB * 0.08);
    float denseSection = smoothstep(0.46, 0.84, sectionA * 0.36 + sectionB * 0.30 + cloudDensity * 0.50);
    float sparseCavity = smoothstep(0.62, 0.94, (1.0 - sectionC) * 0.46 + (1.0 - cloudDensity) * 0.38)
        * (interior * 0.20 + midBand * 0.16);
    float baseShapeRidge = smoothstep(0.76, 0.94, ridge) * staticProtrusion;
    float protrusionCrest = smoothstep(0.56, 0.84, currentProtrusion);
    float ridgeLinePhaseA = animatedCross * 5.0
        + animatedTravel * 1.15
        + flowSpace.z * 3.4
        - fieldTime * 0.22
        + ridgeSeedPhase;
    float ridgeLinePhaseB = animatedTravel * 4.6
        - animatedCross * 0.82
        - flowSpace.z * 3.0
        + fieldTime * 0.16
        - ridgeSeedPhase * 0.73;
    float ridgeLineA = 1.0 - smoothstep(0.035, 0.14, abs(sin(ridgeLinePhaseA)));
    float ridgeLineB = 1.0 - smoothstep(0.030, 0.12, abs(sin(ridgeLinePhaseB)));
    float ridgeLine = max(ridgeLineA, ridgeLineB * 0.62);
    float ridgeRegion = smoothstep(0.48, 0.80, 0.5 + 0.5 * sin(
        structureAngle * 1.55
        + animatedTravel * 0.72
        + flowSpace.z * 1.45
        + ridgeSeedPhase * 0.54
    ));
    float ridgeEndPattern = 0.5 + 0.5 * sin(
        animatedTravel * 1.7
        - animatedCross * 0.55
        + flowSpace.z * 1.2
        - fieldTime * 0.10
        + ridgeSeedPhase * 0.68
    );
    float ridgeEndFade = smoothstep(0.28, 0.68, ridgeEndPattern);
    float spineSurfaceGate = flowSurfaceGate * (0.24 + interior * 0.30 + edge * 0.46);
    float dynamicRidgeCandidate = saturate(
        ridgeLine
        * ridgeRegion
        * ridgeEndFade
        * spineSurfaceGate
        * protrusionCrest
    );
    float dynamicRidge = dynamicRidgeCandidate;
    float ridgeFlow = dynamicRidge * (0.78 + 0.22 * (0.5 + 0.5 * sin(
        animatedTravel * 7.4
        + flowSpace.z * 3.8
        - fieldTime * 0.58
        + ridgeSeedPhase * 0.42
    )));
    float structuralSpine = saturate(
        baseShapeRidge * 0.14
        + dynamicRidge * 0.92
    );
    float densityFlow = smoothstep(0.42, 0.91, 0.5 + 0.5 * sin(animatedTravel * 7.1 - animatedCross * 2.5 + flowSpace.z * 3.6 - fieldTime * 0.78 + globalWave));
    float densitySheet = 0.5 + 0.5 * cos(animatedCross * 4.2 - animatedTravel * 1.1 + flowSpace.z * 3.2 + fieldTime * 0.48 + globalWave * 0.7);
    float dynamicDensity = saturate(densityFlow * 0.20
        + smoothstep(0.40, 0.92, densitySheet) * 0.20
        + cloudDensity * 0.60
        + denseSection * 0.24
        + edgeFrayField * 0.12
        + edgeDustField * 0.08
        + turnWakeEnergy * 0.16
        - sparseCavity * 0.070);
    float ionThreadA = smoothstep(0.66, 0.98, 0.5 + 0.5 * sin(animatedTravel * 8.2 + animatedCross * 1.7 + flowSpace.z * 4.4 - fieldTime * 1.06 + morph));
    float ionThreadB = smoothstep(0.70, 0.99, 0.5 + 0.5 * cos(animatedCross * 7.4 - animatedTravel * 2.2 + flowSpace.z * 5.8 + fieldTime * 0.74 + globalWave));
    float ionCluster = saturate(ionThreadA * 0.10 + ionThreadB * 0.08 + cloudDensity * 0.36 + structuralSpine * 0.38)
        * flowSurfaceGate
        * (0.30 + edge * 0.14 + structuralSpine * 0.28);
    float layerDensity = saturate(dynamicDensity * (0.18 + interior * 0.30 + midBand * 0.50 + edge * 0.08)
        + ridgeFlow * 0.10
        + ionCluster * 0.22
        + cloudDensity * 0.22
        + denseSection * 0.22
        + structuralSpine * 0.20
        - sparseCavity * 0.080);
    float localRidge = saturate(
        baseShapeRidge * 0.12
        + structuralSpine * 0.66
        + ridgeFlow * 0.34
        + layerDensity * protrusionCrest * ridgeLine * 0.05
        + ionCluster * protrusionCrest * ridgeLine * 0.04
    );
    float viewScreenRadius = length(stableScreenPosition);
    float frontDepthGate = smoothstep(-0.36, 0.14, viewDepth);
    float visibleCloudDensity = cloudDensity;
    float bodyEnvelope = saturate(0.42
        + smoothstep(0.88, 0.24, viewScreenRadius) * 0.32
        + midBand * 0.18
        + edge * 0.18
        + edgeFrayField * 0.06
        + edgeDustField * 0.04
        + visibleCloudDensity * 0.10);
    float visibleLayerDensity = layerDensity;
    float visibleLocalRidge = localRidge * ridgeVisibility;
    float visibleDenseSection = denseSection;
    float visibleSparseCavity = sparseCavity
        * (1.0 - shellSurfaceContinuity * 0.92)
        * 0.68;
    float visibleIonCluster = ionCluster;
    float visibleStructuralSpine = structuralSpine * ridgeVisibility;
    float visibleRidgeFlow = ridgeFlow * ridgeVisibility;
    float focusRidgeGate = focus * frontDepthGate * (0.30 + midBand * 0.70 + interior * 0.22);
    visibleLayerDensity = saturate(visibleLayerDensity * mix(1.0, 0.84, focus) + visibleDenseSection * 0.13 * focusRidgeGate);
    visibleLocalRidge = saturate(visibleLocalRidge + (visibleStructuralSpine * 0.10 + visibleRidgeFlow * 0.16) * focusRidgeGate);
    float circulationRidgeGate = circulation
        * frontDepthGate
        * (0.24 + midBand * 0.72 + interior * 0.42 + edge * 0.04)
        * (0.34 + circulationCycle * 0.34 + circulationLane * 0.32);
    visibleLayerDensity = saturate(visibleLayerDensity * mix(1.0, 0.92, circulation) + visibleDenseSection * 0.16 * circulationRidgeGate);
    visibleLocalRidge = saturate(visibleLocalRidge + (visibleStructuralSpine * 0.10 + visibleRidgeFlow * 0.20 + ridgeFlow * 0.08) * circulationRidgeGate);
    float pulseRidgeGate = pulse
        * frontDepthGate
        * (0.24 + midBand * 0.54 + interior * 0.28 + edge * 0.18)
        * (0.42 + pulseWave * 0.58);
    visibleLayerDensity = saturate(visibleLayerDensity + visibleDenseSection * 0.065 * pulseRidgeGate);
    visibleLocalRidge = saturate(visibleLocalRidge + (visibleStructuralSpine * 0.06 + visibleRidgeFlow * 0.12 + ridgeFlow * 0.05) * pulseRidgeGate);
    float disruptionBreakGate = disruption
        * frontDepthGate
        * (0.30 + midBand * 0.82 + interior * 0.24 + edge * 0.30)
        * (0.40 + fragmentation * 0.46 + disruptionPulse * 0.30);
    float disruptionDarkGap = disruption
        * smoothstep(0.42, 0.90, 0.5 + 0.5 * sin(animatedTravel * 6.8 - animatedCross * 3.6 + flowSpace.z * 4.2 - fieldTime * 0.80 + phaseB * 0.18));
    visibleLayerDensity = saturate(visibleLayerDensity * mix(1.0, 0.62, disruptionBreakGate) + visibleDenseSection * 0.075 * disruptionBreakGate);
    visibleLocalRidge = saturate(visibleLocalRidge * mix(1.0, 0.42, disruptionDarkGap * disruptionBreakGate) + visibleRidgeFlow * 0.14 * disruptionBreakGate);
    visibleStructuralSpine *= mix(1.0, 0.60, disruptionDarkGap * disruption);
    visibleIonCluster *= mix(1.0, 0.76, disruptionPulse * disruption);
    float dissolutionDim = dissolutionLocalFade;
    float dissolutionStructureLoss = saturate(dissolutionBreakAmount + dissolutionState * dissolutionDisperse * (middleDissolutionZone * 0.38 + edgeDissolutionZone * 0.30));
    visibleLayerDensity = saturate(visibleLayerDensity * mix(1.0, 0.54, dissolutionStructureLoss) + visibleDenseSection * 0.026 * dissolutionBreakAmount);
    visibleLocalRidge = saturate(visibleLocalRidge * mix(1.0, 0.40, dissolutionStructureLoss));
    visibleStructuralSpine *= mix(1.0, 0.34, dissolutionStructureLoss);
    visibleIonCluster *= mix(1.0, 0.48, dissolutionStructureLoss);
    visibleCloudDensity *= mix(1.0, 0.68, dissolutionDim);
    visibleDenseSection *= mix(1.0, 0.64, dissolutionDim);
    float3 surfaceNormal = normalize(float3(viewBody.xy * 0.92, viewBody.z * 1.12 + viewDepth * 0.22));
    float3 keyDirection = normalize(float3(-0.48, 0.36, 0.80));
    float3 fillDirection = normalize(float3(0.42, -0.18, 0.68));
    float rollingLight = smoothstep(-0.24, 0.66, dot(surfaceNormal, keyDirection));
    float fillLight = smoothstep(-0.18, 0.62, dot(surfaceNormal, fillDirection));
    float structuralSurfaceLight = saturate(0.46
        + rollingLight * 0.20
        + fillLight * 0.12
        + base360Rim * 0.035
        - visibleSparseCavity * 0.08);
    float surfaceLight = saturate(0.50 + (structuralSurfaceLight - 0.50) * tuneSurfaceLightContrast);
    surfaceLight = saturate(surfaceLight * mix(1.0, 0.82, disruption * (0.30 + disruptionPulse * 0.52))
        - disruptionDarkGap * (0.08 + frontDepthGate * 0.11));
    surfaceLight = saturate(surfaceLight * mix(1.0, 0.42, dissolutionDim)
        + dissolutionState * dissolutionContract * frontDepthGate * 0.040
        - dissolutionBreakAmount * 0.040);
    float ridgeAggregation = saturate(visibleLocalRidge * tuneRidgeStrength);
    float ionPresence = saturate(visibleIonCluster * 0.82 + ridgeAggregation * 0.30 + visibleLayerDensity * 0.24);
    float flowDensityBase = saturate(visibleLayerDensity * 0.62
        + visibleDenseSection * 0.12
        + visibleStructuralSpine * 0.08
        + visibleIonCluster * 0.16
        + turnWakeEnergy * 0.12);
    float flowDensityGain = saturate(flowDensityBase * tuneFlowBrightness);
    float flowBrightnessMask = saturate((flowDensityBase * 0.72
        + visibleRidgeFlow * 0.18
        + visibleCloudDensity * 0.22) * tuneFlowBrightness);
    float shellContinuity = saturate(max(
        base360Rim * (0.72 + edge * 0.28),
        shellSurfaceContinuity * 0.62
    ));
    float baseStructuralDensity = saturate(bodyEnvelope * 0.24
        + ridge * ridgeVisibility * 0.10
        + base360Rim * 0.10
        + shellContinuity * 0.085
        - visibleSparseCavity * 0.055);
    float baseDepthGate = smoothstep(-0.48, 0.46, viewDepth);
    float frontSizeLift = baseDepthGate * 0.34
        + smoothstep(0.72, 0.10, viewScreenRadius) * 0.08;
    float stableSizeRidge = saturate(ridge * ridgeVisibility * 0.58
        + smoothstep(0.30, 0.78, viewScreenRadius) * 0.16
        + baseDepthGate * 0.14
        + shellContinuity * 0.16
        + hash11(particleSeed * 73.0 + seedB * 19.0) * 0.10);
    float stableSparsePresence = saturate((1.0 - stableSizeRidge) * 0.18
        + smoothstep(0.78, 1.02, viewScreenRadius) * 0.14);
    float sizeJitter = mix(0.92, 1.10, hash11(particleSeed * 137.0 + seedB * 41.0));
    float sizeScatter = mix(-0.12, 0.24, hash11(particleSeed * 311.0 + phaseB * 0.17))
        * 0.42;
    float backAggregationMute = mix(0.68, 1.0, baseDepthGate);
    float structureScale = mix(0.88, 1.12, stableSizeRidge);
    structureScale *= mix(1.0, 0.88, stableSparsePresence);
    float pointBase = (mix(1.82, 4.82, stableSizeRidge)
        + ridge * ridgeVisibility * 0.84 * backAggregationMute
        + stableSizeRidge * 1.18
        + edge * 0.14 * edgeSettle
        + hash11(seedB * 67.0 + particleSeed * 23.0) * 0.18
        + frontSizeLift
        + sizeScatter) * structureScale * mix(1.0, 0.74, stableSparsePresence) * mix(1.0, 0.84, focus * edge) * mix(1.0, 0.94, circulation * edge) * mix(1.0, 1.06, pulse * edge) * mix(1.0, 0.96, instabilityPlaceholder * edge);
    float depthSize = mix(0.94, 1.20, smoothstep(-0.65, 0.75, viewDepth));
    float frontParticleLift = smoothstep(-0.26, 0.42, viewDepth);
    float backParticleMute = 1.0 - smoothstep(-0.72, -0.02, viewDepth);
    float ridgeSizeLift = saturate(stableSizeRidge * 0.86 + ridge * ridgeVisibility * 0.18);
    float visualSizeGate = saturate(max(frontParticleLift * 0.82, ridgeSizeLift * 0.96));
    float pointCeiling = mix(3.20, 10.80, visualSizeGate) + stableSizeRidge * 1.45;
    float depthVisibilitySize = mix(0.42, 1.34, frontParticleLift) * mix(1.0, 0.58, backParticleMute);
    depthVisibilitySize = max(depthVisibilitySize, shellContinuity * 0.72);
    float layeredPointSize = pointBase * sizeJitter * depthSize * depthVisibilitySize
        + ridgeSizeLift * (0.84 + frontParticleLift * 0.78);
    float dissolutionPointScale = mix(1.0, 0.56 + dustRelease * 0.16, dissolutionDim);
    dissolutionPointScale *= mix(1.0, 0.84, dissolutionState * dissolutionBreakAmount);
    float flowPointSizeCeiling = 1.42 + max(0.0, tuneFlowBrightness - 1.0) * 0.26;
    float flowPointSizeGain = mix(1.0, flowPointSizeCeiling, flowBrightnessMask);
    float rimPointSizeGain = mix(1.0, 1.18, base360Rim);
    float ridgePointSizeCeiling = 1.24 + max(0.0, tuneRidgeStrength - 1.0) * 0.20;
    float ridgePointSizeGain = mix(1.0, ridgePointSizeCeiling, ridgeAggregation);
    out.pointSize = clamp(layeredPointSize, 1.70 + frontSizeLift * 0.24, pointCeiling + ridgeSizeLift * 1.12) * 1.24 * flowPointSizeGain * ridgePointSizeGain * rimPointSizeGain * dissolutionPointScale * tunePointSize;
    out.ridge = saturate(visibleLocalRidge * min(tuneRidgeStrength, 1.0));
    out.depth = viewDepth;
    out.shimmer = ionPresence;
    float dynamicFlow = saturate(visibleRidgeFlow * 0.20 + visibleLayerDensity * 0.48 + visibleIonCluster * 0.58 + visibleCloudDensity * 0.30 + visibleStructuralSpine * 0.66 + edgeFrayField * 0.08 + edgeDustField * 0.08 + turnWakeEnergy * 0.48);
    out.flow = dynamicFlow;
    out.density = saturate(baseStructuralDensity + flowDensityGain + ridgeAggregation * 0.38);
    out.frontness = saturate(smoothstep(-0.50, 0.24, viewDepth) * 0.86);
    out.surfaceLight = surfaceLight;
    out.surfaceWake = turnWakeEnergy;
    out.focus = focus;
    out.pulse = pulse;
    out.pulseWave = pulseWave;
    out.circulation = circulation;
    out.circulationCycle = circulationCycle;
    out.circulationLane = circulationLane;
    out.disruption = disruption;
    out.disruptionPulse = disruptionPulse;
    out.fragmentation = fragmentation;
    out.edgePresence = saturate(max(base360Rim, shellContinuity * 0.52));
    out.dissolutionState = dissolutionState;
    out.dissolutionFade = dissolutionFade;
    out.dissolutionLocalFade = dissolutionLocalFade;
    out.dissolutionBreak = dissolutionBreakAmount;
    out.dissolutionDust = dustRelease;
    out.brightness = tuneBrightness;
    out.alphaScale = tuneAlpha;
    out.baseColor = uniforms.baseColor;
    out.ridgeColor = uniforms.ridgeColor;
    out.dimColor = uniforms.dimColor;
    out.highlightColor = uniforms.highlightColor;
    out.colorAlphaScale = uniforms.colorAlphaScale;
    out.instabilityPlaceholder = instabilityPlaceholder;
    return out;
}

fragment half4 particleFragment(ParticleVertexOut in [[stage_in]],
                                float2 pointCoord [[point_coord]]) {
    float d = distance(pointCoord, float2(0.5, 0.5));
    float core = 1.0 - smoothstep(0.08, 0.28, d);
    float halo = 1.0 - smoothstep(0.14, 0.52, d);
    float depthLight = saturate(in.frontness);
    float frontLight = smoothstep(0.42, 0.88, in.frontness);
    float ridge = saturate(in.ridge);
    float density = saturate(in.density);
    float densityLight = smoothstep(0.10, 0.92, density);
    float surfaceLight = saturate(in.surfaceLight);
    float surfaceWake = saturate(in.surfaceWake);
    float focus = saturate(in.focus);
    float pulse = saturate(in.pulse);
    float pulseWave = saturate(in.pulseWave);
    float circulation = saturate(in.circulation);
    float circulationCycle = saturate(in.circulationCycle);
    float circulationLane = saturate(in.circulationLane);
    float disruption = saturate(in.disruption);
    float disruptionPulse = saturate(in.disruptionPulse);
    float fragmentation = saturate(in.fragmentation);
    float dissolutionState = saturate(in.dissolutionState);
    float dissolutionLocalFade = saturate(in.dissolutionLocalFade);
    float dissolutionBreak = saturate(in.dissolutionBreak);
    float dissolutionDust = saturate(in.dissolutionDust);
    float brightness = max(0.0, in.brightness);
    float alphaScale = max(0.0, in.alphaScale * in.colorAlphaScale);
    float ionPresence = saturate(in.shimmer);
    float instabilityPlaceholder = saturate(in.instabilityPlaceholder);
    float litSurface = smoothstep(0.34, 0.86, surfaceLight);
    float frontSurfaceContrast = mix(0.42, 1.18, litSurface);
    float backPresence = 1.0 - smoothstep(-0.54, 0.06, in.depth);
    float frontPresence = smoothstep(-0.22, 0.46, in.depth);
    float backMute = mix(0.34 + in.edgePresence * 0.24, 1.0, frontPresence);
    float sparseDim = 1.0 - smoothstep(0.18, 0.58, density);
    float particleFill = saturate(0.12 + densityLight * 0.18 + ridge * 0.075 + ionPresence * 0.10 + in.flow * 0.020);
    float litFront = frontLight * litSurface;
    float densityFront = densityLight * (litFront * 0.80 + depthLight * 0.035);
    float densityMist = densityLight * (backPresence * 0.075 + 0.032);
    float interiorBase = saturate(particleFill * 0.34 + densityLight * 0.10 + depthLight * (0.080 + litSurface * 0.36) + backPresence * 0.058);
    float ionRidge = litFront * saturate(ridge * 2.10 + densityLight * 0.14 + in.flow * 0.18);
    float ridgeGlow = saturate(ridge * 3.92 + in.flow * 0.22 + densityLight * 0.12)
        * (0.66 + litFront * 2.10 + backPresence * 0.09);
    float coverage = saturate(particleFill * 0.34
        + backPresence * 0.070
        + depthLight * (0.16 + litSurface * 0.62)
        + interiorBase * 0.68
        + densityFront * 1.28
        + densityMist * 0.42
        + ionRidge * (0.96 + ionPresence * 0.42)
        + ridgeGlow * (1.22 + ionPresence * 0.44)
        + surfaceWake * 0.14);
    coverage *= mix(0.76, frontSurfaceContrast, frontLight);
    float outerDim = saturate(max(
        smoothstep(0.42, 0.10, in.frontness) * (1.0 - ridge * 0.48),
        in.edgePresence * (0.64 + backPresence * 0.18) * (1.0 - ridge * 0.22)
    ));
    coverage *= mix(1.0, 0.50, focus * outerDim);
    float circulationRidgeLight = circulation * frontLight * saturate((circulationCycle * 0.48 + circulationLane * 0.52) * (ridge * 0.76 + in.flow * 0.58 + surfaceLight * 0.22));
    coverage *= mix(1.0, 1.38, circulationRidgeLight);
    coverage = saturate(coverage + circulationRidgeLight * 0.100);
    coverage *= mix(1.0, 0.72, circulation * outerDim * (1.0 - ridge * 0.52));
    float pulseRidgeLight = pulse * pulseWave * frontLight * saturate(ridge * 0.68 + in.flow * 0.40 + surfaceLight * 0.22);
    coverage *= mix(1.0, 1.16, pulseRidgeLight);
    coverage *= mix(1.0, 0.94, pulse * outerDim * (1.0 - ridge * 0.46));
    float disruptionRidgeShadow = disruption * frontLight * saturate((disruptionPulse * 0.52 + fragmentation * 0.58) * (ridge * 0.78 + in.flow * 0.36 + surfaceLight * 0.30));
    coverage *= mix(1.0, 0.50, disruptionRidgeShadow);
    coverage *= mix(1.0, 0.70, disruption * outerDim * (1.0 - ridge * 0.44));
    coverage = saturate(coverage + disruption * fragmentation * ridge * frontLight * 0.030);
    coverage *= mix(1.0, 0.66, dissolutionBreak);
    coverage *= mix(1.0, 0.24 + dissolutionDust * 0.16, dissolutionLocalFade);
    coverage = saturate(coverage * mix(0.72, 1.54, ionPresence) * mix(1.0, 0.70, sparseDim));
    coverage *= mix(1.0, 0.96, instabilityPlaceholder);
    float highlight = saturate(litFront * 0.38 + ionRidge * 2.08 + ridgeGlow * 3.18 + surfaceWake * 0.24);
    highlight = saturate(highlight + focus * (ridge * 0.13 + in.flow * 0.070) * frontLight);
    highlight = saturate(highlight + circulationRidgeLight * (0.24 + ridge * 0.22));
    highlight = saturate(highlight + pulseRidgeLight * (0.22 + ridge * 0.22));
    highlight *= mix(1.0, 0.58, disruptionRidgeShadow);
    highlight = saturate(highlight + disruption * fragmentation * frontLight * ridge * 0.060);
    highlight = saturate(highlight + ionPresence * frontLight * (0.16 + ridge * 0.26));
    highlight *= mix(1.0, 0.24, dissolutionLocalFade);
    highlight *= mix(1.0, 0.74, dissolutionBreak);
    float alpha = saturate(halo * coverage * 0.74 + core * coverage * 2.18) * backMute;
    alpha *= mix(1.0, 0.18 + dissolutionDust * 0.14, dissolutionLocalFade);
    alpha = saturate(alpha * alphaScale);
    half3 back = half3(in.dimColor.rgb);
    half3 frontBase = half3(in.baseColor.rgb);
    half3 ridgeTint = half3(in.ridgeColor.rgb);
    half3 wakeTint = mix(frontBase, ridgeTint, half(0.42));
    float compressedDepthLight = 0.16 + depthLight * 0.84;
    float surfaceTone = 0.38 + litSurface * 0.62;
    half3 dim = mix(back, frontBase, half(compressedDepthLight * surfaceTone));
    dim *= half(mix(1.0, 0.80, focus * outerDim));
    dim *= half(mix(1.0, 0.78, disruption * (0.34 + outerDim * 0.76)));
    dim *= half(mix(1.0, 0.34 + dissolutionDust * 0.10, dissolutionLocalFade));
    half3 bright = mix(half3(in.highlightColor.rgb), ridgeTint, half(saturate(ridge * 0.28 + in.flow * 0.16)));
    half3 color = mix(dim, bright, half(highlight));
    color = mix(color, half3(0.64, 0.66, 0.70), half(disruption * disruptionPulse * 0.22));
    color = mix(color, wakeTint, half(surfaceWake * (0.20 + frontLight * 0.80) * 0.12));
    color = mix(color, half3(0.52, 0.54, 0.58), half(dissolutionState * dissolutionBreak * 0.08));
    color *= half(brightness);
    return half4(color, half(alpha));
}
