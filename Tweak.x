#import <AVFoundation/AVFoundation.h>
#import <notify.h>

// PleaseDontStopTheMusic
//
// Goal: let a second app play audio without pausing the music you already have
// going, and keep your music app's lock-screen / Control Center "Now Playing"
// controls.
//
// Default rule: when other audio is already playing, the "intruder" app is
// forced to MixWithOthers so it joins the music as a *secondary* source. The
// music app stays primary and keeps its Now-Playing controls.
//
// Special case — TikTok Live PiP: TikTok Live uses a sample-buffer Picture-in-
// Picture renderer that only advances video frames while its audio session is
// the *primary* (hardware-clock) source. Forcing it to mix makes it secondary,
// which freezes the PiP video. So for TikTok we flip the roles: TikTok keeps a
// primary session (PiP video plays) and we tell the music app, over a Darwin
// notification, to make ITS OWN session secondary (MixWithOthers) so it keeps
// playing instead of being interrupted. The signal is sent as TikTok launches /
// comes to the foreground, before TikTok's audio seizes the session, so the
// music is already mixing and never pauses. When you return to the music app it
// reclaims the primary session and its Now-Playing controls.

static BOOL gIsVideoApp     = NO;   // TikTok: stays primary, drives the role-flip
static BOOL gForcedMusicMix = NO;   // this music app went secondary for TikTok
static BOOL gReclaiming     = NO;   // music app reclaiming primary (skip auto-mix)
static BOOL gSessionActive  = NO;   // tracks setActive: state

static NSString *const kBegin = @"com.pdstm.pip.begin";

static BOOL PDSTMShouldMix(AVAudioSession *s) {
    if (gIsVideoApp)     return NO;    // TikTok stays primary so its PiP clock runs
    if (gReclaiming)     return NO;    // explicit reclaim of primary
    if (gForcedMusicMix) return YES;   // music app keeping itself secondary
    return s.isOtherAudioPlaying;      // default: mix the intruder
}

static void PDSTMPost(NSString *name) { notify_post(name.UTF8String); }

// Music side: TikTok wants the primary session — make ours secondary so we keep
// playing instead of being interrupted.
static void PDSTMGoSecondary(void) {
    if (gIsVideoApp) return;
    AVAudioSession *s = [AVAudioSession sharedInstance];
    NSString *cat = s.category;
    BOOL playbackish = [cat isEqualToString:AVAudioSessionCategoryPlayback]
                    || [cat isEqualToString:AVAudioSessionCategoryPlayAndRecord];
    if (!gSessionActive || !playbackish) return;
    gForcedMusicMix = YES;
    if (s.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers) return; // already mixing
    [s setCategory:cat mode:s.mode
           options:(s.categoryOptions | AVAudioSessionCategoryOptionMixWithOthers) error:nil];
    [s setActive:YES error:nil];
}

// Music side: user came back to the music app — reclaim the primary session and
// the Now-Playing controls.
static void PDSTMReclaimPrimary(void) {
    if (gIsVideoApp || !gForcedMusicMix) return;
    gForcedMusicMix = NO;
    AVAudioSession *s = [AVAudioSession sharedInstance];
    gReclaiming = YES;
    [s setCategory:s.category mode:s.mode
           options:(s.categoryOptions & ~AVAudioSessionCategoryOptionMixWithOthers) error:nil];
    [s setActive:YES error:nil];
    gReclaiming = NO;
}

static void PDSTMDarwinCallback(CFNotificationCenterRef c, void *obs, CFStringRef name,
                                const void *obj, CFDictionaryRef info) {
    if ([(__bridge NSString *)name isEqualToString:kBegin]) PDSTMGoSecondary();
}

%hook AVAudioSession

- (BOOL)setCategory:(NSString *)category error:(NSError **)outError {
    if (PDSTMShouldMix(self)) {
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient])
            return %orig(AVAudioSessionCategoryAmbient, outError);
        if ([category isEqualToString:AVAudioSessionCategoryPlayback])
            return [self setCategory:category mode:AVAudioSessionModeDefault
                             options:AVAudioSessionCategoryOptionMixWithOthers error:outError];
    }
    return %orig;
}

- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    if (PDSTMShouldMix(self)) {
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) category = AVAudioSessionCategoryAmbient;
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    return %orig(category, mode, options, outError);
}

- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode routeSharingPolicy:(AVAudioSessionRouteSharingPolicy)policy options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    if (PDSTMShouldMix(self)) {
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) category = AVAudioSessionCategoryAmbient;
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    return %orig(category, mode, policy, options, outError);
}

- (BOOL)setCategory:(NSString *)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    if (PDSTMShouldMix(self)) {
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) category = AVAudioSessionCategoryAmbient;
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    return %orig(category, options, outError);
}

- (BOOL)setActive:(BOOL)active error:(NSError **)outError {
    gSessionActive = active;
    if (gIsVideoApp && active && self.isOtherAudioPlaying) PDSTMPost(kBegin);
    if (active && PDSTMShouldMix(self)
        && !(self.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers)) {
        NSString *cat = self.category;
        if ([cat isEqualToString:AVAudioSessionCategorySoloAmbient]) cat = AVAudioSessionCategoryAmbient;
        [self setCategory:cat mode:self.mode
                  options:self.categoryOptions | AVAudioSessionCategoryOptionMixWithOthers error:nil];
    }
    return %orig;
}

- (BOOL)setActive:(BOOL)active withOptions:(AVAudioSessionSetActiveOptions)options error:(NSError **)outError {
    gSessionActive = active;
    if (gIsVideoApp && active && self.isOtherAudioPlaying) PDSTMPost(kBegin);
    if (active && PDSTMShouldMix(self)
        && !(self.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers)) {
        NSString *cat = self.category;
        if ([cat isEqualToString:AVAudioSessionCategorySoloAmbient]) cat = AVAudioSessionCategoryAmbient;
        [self setCategory:cat mode:self.mode
                  options:self.categoryOptions | AVAudioSessionCategoryOptionMixWithOthers error:nil];
    }
    return %orig;
}

%end

%ctor {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"?";
    NSArray *video = @[ @"com.zhiliaoapp.musically",       // TikTok
                        @"com.zhiliaoapp.musically.go",
                        @"com.ss.iphone.ugc.Ame" ];        // TikTok (other region)
    gIsVideoApp = [video containsObject:bid];

    CFNotificationCenterRef dc = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(dc, NULL, PDSTMDarwinCallback,
        (__bridge CFStringRef)kBegin, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    if (gIsVideoApp) {
        // Tell the music app to go secondary as TikTok comes to the foreground,
        // before TikTok's Live audio seizes the primary session.
        [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationDidBecomeActiveNotification"
            object:nil queue:nil usingBlock:^(NSNotification *n) { PDSTMPost(kBegin); }];
        [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationWillEnterForegroundNotification"
            object:nil queue:nil usingBlock:^(NSNotification *n) { PDSTMPost(kBegin); }];
        PDSTMPost(kBegin);
    } else {
        // Music app: reclaim the primary session (and Now-Playing controls) when
        // the user returns to it.
        [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationDidBecomeActiveNotification"
            object:nil queue:nil usingBlock:^(NSNotification *n) { PDSTMReclaimPrimary(); }];
    }

    NSLog(@"[PleaseDontStopTheMusic] loaded (bundle=%@ video=%d)", bid, gIsVideoApp);
}
