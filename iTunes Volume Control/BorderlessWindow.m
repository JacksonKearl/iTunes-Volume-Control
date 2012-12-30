#import "BorderlessWindow.h"

@implementation BorderlessWindow

- (id) initWithContentRect: (NSRect) contentRect
                 styleMask: (unsigned long) aStyle
                   backing: (NSBackingStoreType) bufferingType
                     defer: (BOOL) flag
{
    if (![super initWithContentRect: contentRect styleMask: NSBorderlessWindowMask backing: bufferingType defer: flag]) return nil;
	[self setBackgroundColor: [NSColor clearColor]];
	[self setOpaque:NO];
    [self orderOut:nil];
    
    return self;
}

@end
