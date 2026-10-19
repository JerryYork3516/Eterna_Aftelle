#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>

static void RejectProxy(NSString *reason) {
    @throw [NSException exceptionWithName:@"Fixture" reason:reason userInfo:nil];
}

static uint32_t ProxyLE32(const uint8_t *p) {
    return p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint16_t ProxyLE16(const uint8_t *p) {
    return p[0] | ((uint16_t)p[1] << 8);
}

// The two local paths and complete file identities are fixed, not a caller-supplied allowlist.
static NSDictionary *RegisteredProxy(NSString *path, NSString *assetRoot) {
    NSString *name = path.lastPathComponent;
    BOOL host = [name isEqualToString:@"HOST_proxy.wav"];
    if (!host && ![name isEqualToString:@"REF_proxy.wav"]) RejectProxy(@"Unregistered filename");
    NSString *expectedPath = [assetRoot stringByAppendingPathComponent:name].stringByStandardizingPath;
    if (![path isAbsolutePath] || ![path isEqualToString:expectedPath] ||
        ![path.stringByResolvingSymlinksInPath isEqualToString:path]) RejectProxy(@"Unregistered path or symlink");
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if (![attributes[NSFileType] isEqual:NSFileTypeRegular] ||
        [attributes[NSFileSize] unsignedLongLongValue] > 720664) RejectProxy(@"Invalid file size/type");
    NSData *file = [NSData dataWithContentsOfFile:path];
    const uint8_t *p = file.bytes;
    if (file.length < 44 || memcmp(p, "RIFF", 4) || memcmp(p + 8, "WAVE", 4) ||
        ProxyLE32(p + 4) != file.length - 8) RejectProxy(@"Invalid RIFF");
    const uint8_t *pcm = NULL;
    size_t pcmBytes = 0, offset = 12;
    BOOL formatSeen = NO;
    while (offset + 8 <= file.length) {
        uint32_t length = ProxyLE32(p + offset + 4);
        size_t end = offset + 8 + (size_t)length;
        if (end > file.length) RejectProxy(@"Truncated chunk");
        const uint8_t *chunk = p + offset + 8;
        if (!memcmp(p + offset, "fmt ", 4)) {
            if (formatSeen || length != 16 || ProxyLE16(chunk) != 1 || ProxyLE16(chunk + 2) != 1 ||
                ProxyLE32(chunk + 4) != 24000 || ProxyLE32(chunk + 8) != 48000 ||
                ProxyLE16(chunk + 12) != 2 || ProxyLE16(chunk + 14) != 16) RejectProxy(@"PCM format mismatch");
            formatSeen = YES;
        } else if (!memcmp(p + offset, "data", 4)) {
            if (pcm) RejectProxy(@"Duplicate PCM chunk");
            pcm = chunk;
            pcmBytes = length;
        }
        offset = end + (length & 1);
    }
    NSUInteger frames = host ? 360310 : 264310;
    if (!formatSeen || !pcm || offset != file.length || pcmBytes != frames * 2) RejectProxy(@"Frame count mismatch");
    NSUInteger leadingFrames = host ? 96000 : 0;
    for (NSUInteger i = 0; i < leadingFrames * 2; i++) {
        if (pcm[i]) RejectProxy(@"Leading silence mismatch");
    }
    if (ProxyLE16(pcm + leadingFrames * 2) == 0) RejectProxy(@"Registered onset mismatch");
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(file.bytes, (CC_LONG)file.length, hash);
    NSMutableString *digest = [NSMutableString new];
    for (NSUInteger i = 0; i < sizeof(hash); i++) [digest appendFormat:@"%02x", hash[i]];
    NSString *expected = host ? @"4a0b85b6fa3d14f14510d3f041ff1c41ee9b0363962c28dca812ce0ae83a55e8"
                              : @"1c7081f8271251804e01234be8a0ff8344062d09c311592634cb8fdf6b992d0a";
    if (![digest isEqualToString:expected]) RejectProxy(@"Frozen speech SHA mismatch");
    return @{@"data": file, @"sha256": digest, @"profile": host ? @"HOST" : @"REF",
             @"frames": @(frames), @"duration": @(frames / 24000.0), @"leading_frames": @(leadingFrames)};
}
