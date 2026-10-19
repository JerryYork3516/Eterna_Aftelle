// Foundation-only admission probe: no NSSound, CoreAudio, or device calls.
#include "proxy_registry.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        @try {
            if (argc != 3) RejectProxy(@"Expected asset root and registered filename");
            NSString *root = [NSString stringWithUTF8String:argv[1]];
            NSString *path = [root stringByAppendingPathComponent:[NSString stringWithUTF8String:argv[2]]];
            NSMutableDictionary *result = [RegisteredProxy(path, root) mutableCopy];
            [result removeObjectForKey:@"data"];
            NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
            fwrite(json.bytes, 1, json.length, stdout);
            fputc('\n', stdout);
            return 0;
        } @catch (NSException *error) {
            fprintf(stderr, "%s\n", error.reason.UTF8String);
            return 1;
        }
    }
}
