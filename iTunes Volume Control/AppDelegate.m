//
//  AppDelegate.m
//  iTunes Volume Control
//
//  Created by Andrea Alberti on 25.12.12.
//  Copyright (c) 2012 Andrea Alberti. All rights reserved.
//

#import "AppDelegate.h"
#import <IOKit/hidsystem/ev_keymap.h>

@implementation AppDelegate

@synthesize AppleRemoteConnected=_AppleRemoteConnected;
@synthesize StartAtLogin=_StartAtLogin;
@synthesize Tapping=_Tapping;
@synthesize UseAppleCMDModifier=_UseAppleCMDModifier;

bool previousKeyIsRepeat=false;
bool keyIsRepeat;
bool _UseAppleCMDModifier;
NSTimer* timer;

CGEventRef event_tap_callback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon)
{
    NSEvent * sysEvent;
    
    // No event we care for? return ASAP
    if (type != NX_SYSDEFINED) return event;
    
    sysEvent = [NSEvent eventWithCGEvent:event];
    // No need to test event type, we know it is NSSystemDefined, becuase that is the same as NX_SYSDEFINED
    if ([sysEvent subtype] != 8) return event;
    
    int keyFlags = ([sysEvent data1] & 0x0000FFFF);
    int keyCode = (([sysEvent data1] & 0xFFFF0000) >> 16);
    int keyState = (((keyFlags & 0xFF00) >> 8)) == 0xA;
    CGEventFlags keyModifier = [sysEvent modifierFlags]|0xFFFF;
    keyIsRepeat = (keyFlags & 0x1);
    
    CGEventFlags mask=(_UseAppleCMDModifier ? NX_COMMANDMASK:0)|0xFFFF;
    
    switch( keyCode )
	{
		case NX_KEYTYPE_SOUND_UP:
        case NX_KEYTYPE_SOUND_DOWN:
            if( keyModifier==mask )
            {
                if( keyState == 1 )
                {
                    if( keyCode == NX_KEYTYPE_SOUND_UP )
                    {
                        if (!keyIsRepeat||!previousKeyIsRepeat)
                            [[NSNotificationCenter defaultCenter] postNotificationName:@"IncreaseITunesVolume" object:NULL];
                    }
                    else
                    {
                        if (!keyIsRepeat||!previousKeyIsRepeat)
                            [[NSNotificationCenter defaultCenter] postNotificationName:@"DecreaseITunesVolume" object:NULL];
                    }
                }
                else
                {
                    [timer invalidate];
                    timer=nil;
                }
                previousKeyIsRepeat=keyIsRepeat;
                return NULL;
            }
            break;
    }
    
    return event;
}

- (bool) StartAtLogin
{
    NSURL *appURL=[NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
    
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    
    bool found=false;
    
	if (loginItems) {
        UInt32 seedValue;
        //Retrieve the list of Login Items and cast them to a NSArray so that it will be easier to iterate.
        NSArray  *loginItemsArray = (__bridge NSArray *)LSSharedFileListCopySnapshot(loginItems, &seedValue);
        
        for(int i=0; i<[loginItemsArray count]; i++)
        {
            LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)[loginItemsArray objectAtIndex:i];
            //Resolve the item with URL
            CFURLRef URL = NULL;
            if (LSSharedFileListItemResolve(itemRef, 0, &URL, NULL) == noErr) {
                if ( CFEqual(URL, (__bridge CFTypeRef)(appURL)) ) // found it
                {
                    found=true;
                }
                CFRelease(URL);
            }
            if (itemRef) {
                CFRelease(itemRef);
            }
            
            if(found)break;
        }
        
        CFRelease(loginItems);
    }
    
    return found;
}

- (void)setStartAtLogin:(bool)enabled savePreferences:(bool)savePreferences
{
    NSMenuItem* menuItem=[statusMenu itemWithTag:4];
    [menuItem setState:enabled];
    
    if(savePreferences)
    {
        NSURL *appURL=[NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
        
        LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
        
        if (loginItems) {
            if(enabled)
            {
                // Insert the item at the bottom of Login Items list.
                LSSharedFileListItemRef loginItemRef = LSSharedFileListInsertItemURL(loginItems,
                                                                                     kLSSharedFileListItemLast,
                                                                                     NULL,
                                                                                     NULL,
                                                                                     (__bridge CFURLRef)appURL,
                                                                                     NULL,
                                                                                     NULL);
                if (loginItemRef) {
                    CFRelease(loginItemRef);
                }
            }
            else
            {
                UInt32 seedValue;
                //Retrieve the list of Login Items and cast them to a NSArray so that it will be easier to iterate.
                NSArray  *loginItemsArray = (__bridge NSArray *)LSSharedFileListCopySnapshot(loginItems, &seedValue);
                for(int i=0; i<[loginItemsArray count]; i++)
                {
                    LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)[loginItemsArray objectAtIndex:i];
                    //Resolve the item with URL
                    CFURLRef URL = NULL;
                    if (LSSharedFileListItemResolve(itemRef, 0, &URL, NULL) == noErr) {
                        if ( CFEqual(URL, (__bridge CFTypeRef)(appURL)) ) // found it
                        {
                            LSSharedFileListItemRemove(loginItems,itemRef);
                        }
                        CFRelease(URL);
                    }
                    if (itemRef) {
                        CFRelease(itemRef);
                    }
                }
                
            }
            CFRelease(loginItems);
        }
    }
}

- (void)stopTimer
{
    [timer invalidate];
    timer=nil;
}

- (void)rampVolumeUp:(NSTimer*)theTimer
{
    [self changeVol:2];
}

- (void)rampVolumeDown:(NSTimer*)theTimer
{
    [self changeVol:-2];
}

- (void)createEventTap
{
    CGEventMask eventMask = (/*(1 << kCGEventKeyDown) | (1 << kCGEventKeyUp) |*/CGEventMaskBit(NX_SYSDEFINED));
    eventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                                eventMask, event_tap_callback, NULL); // Create an event tap. We are interested in SYS key presses.
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0); // Create a run loop source.
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes); // Add to the current run loop.
}

- (void) appleRemoteInit
{
    remote = [[AppleRemote alloc] init];
    [remote setDelegate:self];
}

- (void)playPauseITunes:(NSNotification *)aNotification
{
    // check if iTunes is running (Q1)
    if ([iTunes isRunning])
    {
        [iTunes playpause];
    }
}

- (void)nextTrackITunes:(NSNotification *)aNotification
{
    if ([iTunes isRunning])
    {
        [iTunes nextTrack];
    }
}

- (void)previousTrackITunes:(NSNotification *)aNotification
{
    if ([iTunes isRunning])
    {
        [iTunes previousTrack];
    }
}

- (void)increaseITunesVolume:(NSNotification *)aNotification
{
    if( keyIsRepeat&&!previousKeyIsRepeat )
        timer=[NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(rampVolumeUp:) userInfo:nil repeats:YES];
    else
    {
        // [self stopTimer];
        [self changeVol:+2];
    }
}

- (void)decreaseITunesVolume:(NSNotification *)aNotification
{
    if( keyIsRepeat&&!previousKeyIsRepeat )
        timer=[NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(rampVolumeDown:) userInfo:nil repeats:YES];
    else
    {
        // [self stopTimer];
        [self changeVol:-2];
    }
}

- (void) appleRemoteButton: (AppleRemoteEventIdentifier)buttonIdentifier pressedDown: (BOOL) pressedDown clickCount: (unsigned int) count {
    switch (buttonIdentifier)
    {
        case kRemoteButtonVolume_Plus_Hold:
            if(timer==nil)
                timer=[NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(rampVolumeUp:) userInfo:nil repeats:YES];
            else
                [self stopTimer];
            break;
        case kRemoteButtonVolume_Plus:
            [[NSNotificationCenter defaultCenter] postNotificationName:@"IncreaseITunesVolume" object:NULL];
            break;
            
        case kRemoteButtonVolume_Minus_Hold:
            if(timer==nil)
                timer=[NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(rampVolumeDown:) userInfo:nil repeats:YES];
            else
                [self stopTimer];
            break;
        case kRemoteButtonVolume_Minus:
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DecreaseITunesVolume" object:NULL];
            break;
            
        case k2009RemoteButtonFullscreen:
            break;
            
        case k2009RemoteButtonPlay:
        case kRemoteButtonPlay:
            [[NSNotificationCenter defaultCenter] postNotificationName:@"PlayPauseITunes" object:NULL];
            break;
            
        case kRemoteButtonLeft_Hold:
        case kRemoteButtonLeft:
            [[NSNotificationCenter defaultCenter] postNotificationName:@"PreviousTrackITunes" object:NULL];
            break;
            
        case kRemoteButtonRight_Hold:
        case kRemoteButtonRight:
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NextTrackITunes" object:NULL];
            break;
            
        case kRemoteButtonMenu_Hold:
        case kRemoteButtonMenu:
            break;
            
        case kRemoteButtonPlay_Sleep:
            break;
            
        default:
            break;
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    // [statusItem setTitle:@"iTunes Volume Control"];
    [statusItem setMenu:statusMenu];
    [statusItem setHighlightMode:YES];
    
    statusImageOn = [NSImage imageNamed:@"statusbar-item-on.png"];
    statusImageOff = [NSImage imageNamed:@"statusbar-item-off.png"];
    
    [statusItem setImage:statusImageOn];
    
    iTunes = [SBApplication applicationWithBundleIdentifier:@"com.apple.iTunes"];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(increaseITunesVolume:) name:@"IncreaseITunesVolume" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(decreaseITunesVolume:) name:@"DecreaseITunesVolume" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playPauseITunes:) name:@"PlayPauseITunes" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nextTrackITunes:) name:@"NextTrackITunes" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(previousTrackITunes:) name:@"PreviousTrackITunes" object:nil];
    
    [self createEventTap];
    
    [self appleRemoteInit];
    
    [self initializePreferences];
    
    [self setStartAtLogin:[self StartAtLogin] savePreferences:false];
}

- (void)initializePreferences
{
    preferences = [NSUserDefaults standardUserDefaults];
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                          [NSNumber numberWithBool:false] ,@"TappingEnabled",
                          [NSNumber numberWithBool:false] ,@"AppleRemoteConnected",
                          [NSNumber numberWithBool:false] ,@"UseAppleCMDModifier",
                          nil ]; // terminate the list
    [preferences registerDefaults:dict];
        
    [self setAppleRemoteConnected:[preferences boolForKey:@"AppleRemoteConnected"]];
    [self setTapping:[preferences boolForKey:@"TappingEnabled"]];
    [self setUseAppleCMDModifier:[preferences boolForKey:@"UseAppleCMDModifier"]];
}

- (IBAction)toggleStartAtLogin:(id)sender
{
    [self setStartAtLogin:![self StartAtLogin] savePreferences:true];
}

- (void)setAppleRemoteConnected:(bool)enabled
{
    NSMenuItem* menuItem=[statusMenu itemWithTag:2];
    [menuItem setState:enabled];
    
    if(enabled && CGEventTapIsEnabled(eventTap))
        [remote startListening:self];
    else
        [remote stopListening:self];
    
    [preferences setBool:enabled forKey:@"AppleRemoteConnected"];
    [preferences synchronize];
    
    _AppleRemoteConnected=enabled;
}

- (IBAction)toggleAppleRemote:(id)sender
{
    [self setAppleRemoteConnected:![self AppleRemoteConnected]];
}

- (void) setUseAppleCMDModifier:(bool)enabled
{
    NSMenuItem* menuItem=[statusMenu itemWithTag:3];
    [menuItem setState:enabled];

    [preferences setBool:enabled forKey:@"UseAppleCMDModifier"];
    [preferences synchronize];
    
    _UseAppleCMDModifier=enabled;
}

- (IBAction)toggleUseAppleCMDModifier:(id)sender
{
    [self setUseAppleCMDModifier:![self UseAppleCMDModifier]];
}

- (void) setTapping:(bool)enabled
{
    NSMenuItem* menuItem=[statusMenu itemWithTag:1];
    [menuItem setState:enabled];
    
    CGEventTapEnable(eventTap, enabled);
    
    if(enabled)
    {
        [statusItem setImage:statusImageOn];
        if([self AppleRemoteConnected]) [remote startListening:self];
    }
    else
    {
        [statusItem setImage:statusImageOff];
        [remote stopListening:self];
    }
    
    [preferences setBool:CGEventTapIsEnabled(eventTap) forKey:@"TappingEnabled"];
    [preferences synchronize];
    
    _Tapping=enabled;
}

- (IBAction)toggleTapping:(id)sender
{
    [self setTapping:![self Tapping]];
}

- (IBAction)aboutPanel:(id)sender
{
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    [[NSApplication sharedApplication] orderFrontStandardAboutPanel:sender];
}

- (void) dealloc
{
    if(CFMachPortIsValid(eventTap)) {
        CFMachPortInvalidate(eventTap);
        CFRunLoopSourceInvalidate(runLoopSource);
        CFRelease(eventTap);
        CFRelease(runLoopSource);
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)changeVol:(int)vol
{
    // check if iTunes is running (Q1)
    if ([iTunes isRunning])
    {
        NSInteger volume = [iTunes soundVolume]+vol;
        if (volume<0) volume=0;
        if (volume>100) volume=100;
        
        [iTunes setSoundVolume:volume];
        
        // NSLog(@"The new volume is: %ld",[iTunes soundVolume]);
    }
}

@end
