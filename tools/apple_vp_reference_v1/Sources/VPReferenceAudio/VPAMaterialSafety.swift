import AVFoundation
import VPReferenceCore

struct VPAMaterialSafety: Encodable {
    struct Channel: Encodable, Equatable {
        let index: Int
        let sampleCount: UInt32
        let peakAbsolute: Float
        let fullScaleSampleCount: UInt32
    }

    let channels: [Channel]

    static func inspect(_ buffer: AVAudioPCMBuffer) throws -> Self {
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        let stride = buffer.stride
        guard buffer.format.commonFormat == .pcmFormatFloat32, frameCount > 0,
            channelCount > 0, channelCount <= 32,
            stride == (buffer.format.isInterleaved ? channelCount : 1),
            UInt64(frameCount) * UInt64(channelCount) * 4 <= PCMSourceMaterial.maximumBytes,
            let data = buffer.floatChannelData
        else { throw EngineeringFailure(stage: .sourceMaterial, code: .materialSampleLayoutInvalid) }
        var channels: [Channel] = []
        channels.reserveCapacity(channelCount)
        for index in 0..<channelCount {
            var peak: Float = 0
            var fullScale: UInt32 = 0
            for frame in 0..<frameCount {
                let sample = data[index][frame * stride]
                guard sample.isFinite else {
                    throw EngineeringFailure(stage: .sourceMaterial, code: .materialNonFiniteSamples)
                }
                let magnitude = abs(sample)
                guard magnitude <= 1 else {
                    throw EngineeringFailure(stage: .sourceMaterial, code: .materialOutOfRangeSamples)
                }
                peak = max(peak, magnitude)
                if magnitude == 1 { fullScale += 1 }
            }
            channels.append(
                Channel(
                    index: index, sampleCount: buffer.frameLength, peakAbsolute: peak,
                    fullScaleSampleCount: fullScale))
        }
        return Self(channels: channels)
    }
}
