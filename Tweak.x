#import <AVFoundation/AVFoundation.h>

static BOOL isInterruptive(NSString *cat) {
    return [cat isEqualToString:@"AVAudioSessionCategoryPlayback"]
        || [cat isEqualToString:@"AVAudioSessionCategorySoloAmbient"]
        || [cat isEqualToString:@"AVAudioSessionCategoryPlayAndRecord"]
        || [cat isEqualToString:@"AVAudioSessionCategoryRecord"];
}

%hook AVAudioSession

- (BOOL)setCategory:(NSString *)category error:(NSError **)outError {
    if (isInterruptive(category)) {
        return %orig(@"AVAudioSessionCategoryAmbient", outError);
    }
    return %orig;
}

- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    return %orig(category, mode, options | AVAudioSessionCategoryOptionMixWithOthers, outError);
}

- (BOOL)setCategory:(NSString *)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    return %orig(category, options | AVAudioSessionCategoryOptionMixWithOthers, outError);
}

- (BOOL)setActive:(BOOL)active error:(NSError **)outError {
    if (active) {
        NSString *cur = [self category];
        if (isInterruptive(cur)) {
            [self setCategory:@"AVAudioSessionCategoryAmbient"
                         mode:AVAudioSessionModeDefault
                      options:AVAudioSessionCategoryOptionMixWithOthers
                        error:nil];
        }
    }
    return %orig;
}

- (BOOL)setActive:(BOOL)active withOptions:(AVAudioSessionSetActiveOptions)options error:(NSError **)outError {
    if (active) {
        NSString *cur = [self category];
        if (isInterruptive(cur)) {
            [self setCategory:@"AVAudioSessionCategoryAmbient"
                         mode:AVAudioSessionModeDefault
                      options:AVAudioSessionCategoryOptionMixWithOthers
                        error:nil];
        }
    }
    return %orig;
}

%end

%ctor {
    NSLog(@"[AudioMix] loaded");
}
