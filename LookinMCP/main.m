#import <Cocoa/Cocoa.h>
#import "LookinMCPServer.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        LookinMCPServer *server = [[LookinMCPServer alloc] init];
        return [server run];
    }
}
