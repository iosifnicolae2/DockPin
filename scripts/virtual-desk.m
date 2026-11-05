// Builds the user's desk out of virtual displays, for pointer and drag tests on a Mac without those monitors
// (a VM, a laptop on the road): PHL | Odyssey | LG in a row, the MacBook below the Odyssey, the Odyssey main.
// Any other display (a VM's own screen) mirrors the Odyssey, so it shows what happens there.
// The displays last as long as this runs; DockPin counts them only with
// `defaults write io.bringes.DockPin includeVirtualDisplays -bool YES`.
// Build and run: clang -fobjc-arc -framework Foundation -framework CoreGraphics scripts/virtual-desk.m -o /tmp/virtual-desk && /tmp/virtual-desk
// Uses CoreGraphics' CGVirtualDisplay (private, macOS 11+), as display tools such as BetterDisplay do.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface CGVirtualDisplayDescriptor : NSObject
@property (retain) dispatch_queue_t queue;
@property (retain) NSString *name;
@property unsigned int maxPixelsHigh, maxPixelsWide, serialNum, productID, vendorID;
@property CGSize sizeInMillimeters;
@property (copy) void (^terminationHandler)(id, id);
@end
@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)rate;
@end
@interface CGVirtualDisplaySettings : NSObject
@property (retain) NSArray *modes;
@property unsigned int hiDPI;
@end
@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@property (readonly) CGDirectDisplayID displayID;
@end

typedef struct { const char *name; int x, y, w, h; unsigned int serial; } Screen;

int main(void) {
    @autoreleasepool {
        // The user's real arrangement (T-001): PHL left, Odyssey main and center, LG right, MacBook below.
        Screen desk[] = {
            {"Odyssey G5", 0, 0, 1920, 1080, 0xD0C0001},
            {"PHL 241V8", -1920, 0, 1920, 1080, 0xD0C0002},
            {"LG ULTRAGEAR", 1920, 0, 1920, 1080, 0xD0C0003},
            {"MacBook", 97, 1080, 1728, 1117, 0xD0C0004},
        };
        int count = sizeof desk / sizeof *desk;
        NSMutableArray *keep = [NSMutableArray array];
        CGDirectDisplayID ids[4];
        for (int i = 0; i < count; i++) {
            CGVirtualDisplayDescriptor *d = [CGVirtualDisplayDescriptor new];
            d.queue = dispatch_get_main_queue();
            d.name = @(desk[i].name);
            d.maxPixelsWide = desk[i].w;
            d.maxPixelsHigh = desk[i].h;
            d.sizeInMillimeters = CGSizeMake(desk[i].w * 0.27, desk[i].h * 0.27);
            d.vendorID = 0xD0C;
            d.productID = 0x1000 + i;
            d.serialNum = desk[i].serial;
            d.terminationHandler = ^(id a, id b) { fprintf(stderr, "virtual display ended\n"); };
            CGVirtualDisplay *display = [[CGVirtualDisplay alloc] initWithDescriptor:d];
            CGVirtualDisplaySettings *s = [CGVirtualDisplaySettings new];
            s.hiDPI = 0;
            s.modes = @[[[CGVirtualDisplayMode alloc] initWithWidth:desk[i].w height:desk[i].h refreshRate:60]];
            if (!display || ![display applySettings:s]) { fprintf(stderr, "could not make %s\n", desk[i].name); return 1; }
            [keep addObject:display];
            ids[i] = display.displayID;
        }
        [NSThread sleepForTimeInterval:2];  // let the window server bring them up

        CGDirectDisplayID all[16];
        uint32_t n = 0;
        CGGetOnlineDisplayList(16, all, &n);
        CGDisplayConfigRef config;
        CGBeginDisplayConfiguration(&config);
        for (uint32_t j = 0; j < n; j++) {
            BOOL ours = NO;
            for (int i = 0; i < count; i++) ours |= all[j] == ids[i];
            if (!ours) CGConfigureDisplayMirrorOfDisplay(config, all[j], ids[0]);
        }
        for (int i = 0; i < count; i++) CGConfigureDisplayOrigin(config, ids[i], desk[i].x, desk[i].y);
        CGError err = CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
        if (err) { fprintf(stderr, "arranging failed: %d\n", err); return 1; }
        [NSThread sleepForTimeInterval:1];
        for (int i = 0; i < count; i++) {
            CGRect b = CGDisplayBounds(ids[i]);
            printf("%s id %u at (%.0f, %.0f) %.0fx%.0f%s\n", desk[i].name, ids[i], b.origin.x, b.origin.y, b.size.width, b.size.height,
                   CGDisplayIsMain(ids[i]) ? " main" : "");
        }
        printf("ready\n");
        fflush(stdout);
        dispatch_main();
    }
}
