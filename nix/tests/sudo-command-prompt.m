#import <Foundation/Foundation.h>

NSString *tid_look_command_prompt(int argc, char **argv);

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    @autoreleasepool {
        // argv[1] is the expected display text. The formatter ignores argv[0]
        // of the invocation it receives, just as it does inside sudo.
        NSString *expected = [@(argv[1]) stringByAppendingString:@"\n\n"];
        NSString *prompt = tid_look_command_prompt(argc - 1, argv + 1);
        // Upstream inserts left-to-right marks between arguments for display.
        NSString *text = [prompt stringByReplacingOccurrencesOfString:@"\u200e" withString:@""];
        if (![text isEqualToString:expected]) {
            fprintf(stderr, "expected <%s>, got <%s>\n", expected.UTF8String, text.UTF8String);
            return 1;
        }
        printf("prompt OK: %s\n", argv[1]);
    }
    return 0;
}
