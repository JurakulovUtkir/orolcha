// MediaBridge — «Hozir chalinmoqda» ma'lumotini MediaRemote'dan o'qiydi.
// macOS 15.4+ da MediaRemote faqat Apple imzolagan jarayonlarga javob beradi,
// shuning uchun bu kutubxona /usr/bin/perl ichida yuklanadi (media-bridge.pl).
// Chiqish: stdout'ga har qatorda bitta JSON. Kirish: stdin'dan buyruqlar
// (toggle | play | pause | next | prev | seek <soniya> | refresh).

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>
#include <unistd.h>

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetBoolFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetPIDFn)(dispatch_queue_t, void (^)(int));
typedef void (*MRGetClientFn)(dispatch_queue_t, void (^)(id));
typedef CFStringRef (*MRClientStrFn)(id);
typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef Boolean (*MRSendCommandFn)(int, CFDictionaryRef);
typedef void (*MRSetElapsedFn)(double);

static void *mr;
static MRGetInfoFn getInfo;
static MRGetBoolFn getIsPlaying;
static MRGetPIDFn getPID;
static MRGetClientFn getClient;
static MRClientStrFn clientBundle;
static MRClientStrFn clientParentBundle;
static MRRegisterFn registerNotifs;
static MRSendCommandFn sendCommand;
static MRSetElapsedFn setElapsed;

static uint64_t lastArtHash = 0;
static uint64_t generation = 0;
static NSMutableString *inputBuffer;

static NSString *constant(const char *name) {
  CFStringRef *p = (CFStringRef *)dlsym(mr, name);
  if (p && *p) return (__bridge NSString *)*p;
  return [NSString stringWithUTF8String:name];
}

static void emit(NSDictionary *obj) {
  NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
  if (!d) return;
  fwrite(d.bytes, 1, d.length, stdout);
  fputc('\n', stdout);
  fflush(stdout);
}

static uint64_t artHash(NSData *data) {
  const uint8_t *b = data.bytes;
  NSUInteger n = data.length;
  uint64_t h = 1469598103934665603ULL ^ (uint64_t)n;
  NSUInteger step = n > 8192 ? n / 4096 : 1;
  for (NSUInteger i = 0; i < n; i += step) {
    h ^= b[i];
    h *= 1099511628211ULL;
  }
  return h;
}

static void putString(NSMutableDictionary *out, NSDictionary *info, NSString *key, NSString *as) {
  id v = info[key];
  if ([v isKindOfClass:NSString.class] && [v length] > 0) out[as] = v;
}

static void putNumber(NSMutableDictionary *out, NSDictionary *info, NSString *key, NSString *as) {
  id v = info[key];
  if ([v isKindOfClass:NSNumber.class] && isfinite([v doubleValue])) out[as] = v;
}

static void fetchNow(void) {
  dispatch_queue_t q = dispatch_get_main_queue();
  getInfo(q, ^(CFDictionaryRef cfInfo) {
    NSDictionary *info = cfInfo ? [(__bridge NSDictionary *)cfInfo copy] : nil;
    getIsPlaying(q, ^(Boolean playing) {
      getPID(q, ^(int pid) {
        void (^finish)(NSString *, NSString *) = ^(NSString *bundle, NSString *parent) {
          NSMutableDictionary *out = [NSMutableDictionary dictionary];
          out[@"type"] = @"info";
          out[@"playing"] = @(playing ? YES : NO);
          out[@"pid"] = @(pid);
          if (bundle.length) out[@"bundle"] = bundle;
          if (parent.length) out[@"parentBundle"] = parent;
          if (info.count) {
            putString(out, info, constant("kMRMediaRemoteNowPlayingInfoTitle"), @"title");
            putString(out, info, constant("kMRMediaRemoteNowPlayingInfoArtist"), @"artist");
            putString(out, info, constant("kMRMediaRemoteNowPlayingInfoAlbum"), @"album");
            putNumber(out, info, constant("kMRMediaRemoteNowPlayingInfoDuration"), @"duration");
            putNumber(out, info, constant("kMRMediaRemoteNowPlayingInfoElapsedTime"), @"elapsed");
            putNumber(out, info, constant("kMRMediaRemoteNowPlayingInfoPlaybackRate"), @"rate");
            id ts = info[constant("kMRMediaRemoteNowPlayingInfoTimestamp")];
            if ([ts isKindOfClass:NSDate.class]) out[@"timestamp"] = @([ts timeIntervalSince1970]);
            id art = info[constant("kMRMediaRemoteNowPlayingInfoArtworkData")];
            if ([art isKindOfClass:NSData.class] && [art length] > 0) {
              uint64_t h = artHash(art);
              if (h != lastArtHash) {
                lastArtHash = h;
                out[@"artwork"] = [art base64EncodedStringWithOptions:0];
              } else {
                out[@"artworkSame"] = @YES;
              }
            } else {
              lastArtHash = 0;
            }
          }
          emit(out);
        };
        if (getClient && clientBundle) {
          getClient(q, ^(id client) {
            NSString *b = client ? (__bridge NSString *)clientBundle(client) : nil;
            NSString *p = (client && clientParentBundle) ? (__bridge NSString *)clientParentBundle(client) : nil;
            finish(b, p);
          });
        } else {
          finish(nil, nil);
        }
      });
    });
  });
}

static void scheduleFetch(void) {
  uint64_t g = ++generation;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
    if (g == generation) fetchNow();
  });
}

static void handleLine(NSString *line) {
  NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
  NSString *cmd = parts.firstObject;
  if (!sendCommand) return;
  if ([cmd isEqualToString:@"toggle"]) sendCommand(2, NULL);
  else if ([cmd isEqualToString:@"play"]) sendCommand(0, NULL);
  else if ([cmd isEqualToString:@"pause"]) sendCommand(1, NULL);
  else if ([cmd isEqualToString:@"next"]) sendCommand(4, NULL);
  else if ([cmd isEqualToString:@"prev"]) sendCommand(5, NULL);
  else if ([cmd isEqualToString:@"seek"] && parts.count > 1 && setElapsed) setElapsed(parts[1].doubleValue);
  else if ([cmd isEqualToString:@"refresh"]) scheduleFetch();
  if (![cmd isEqualToString:@"refresh"]) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ scheduleFetch(); });
  }
}

static void startStdin(void) {
  inputBuffer = [NSMutableString string];
  dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, dispatch_get_main_queue());
  dispatch_source_set_event_handler(src, ^{
    char buf[1024];
    ssize_t n = read(STDIN_FILENO, buf, sizeof(buf));
    if (n <= 0) exit(0); // ilova yopildi — ko'prik ham to'xtaydi
    NSString *chunk = [[NSString alloc] initWithBytes:buf length:(NSUInteger)n encoding:NSUTF8StringEncoding];
    if (!chunk) return;
    [inputBuffer appendString:chunk];
    NSRange r;
    while ((r = [inputBuffer rangeOfString:@"\n"]).location != NSNotFound) {
      NSString *line = [[inputBuffer substringToIndex:r.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
      [inputBuffer deleteCharactersInRange:NSMakeRange(0, r.location + 1)];
      if (line.length) handleLine(line);
    }
  });
  dispatch_resume(src);
  static dispatch_source_t keep;
  keep = src;
}

// perl DynaLoader XSUB sifatida chaqiradi; argumentlar ishlatilmaydi.
void orolcha_run(void *interp, void *cv) {
  @autoreleasepool {
    mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!mr) {
      emit(@{@"type": @"error", @"message": @"MediaRemote yuklanmadi"});
      exit(2);
    }
    getInfo = (MRGetInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
    getIsPlaying = (MRGetBoolFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    getPID = (MRGetPIDFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationPID");
    getClient = (MRGetClientFn)dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
    clientBundle = (MRClientStrFn)dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
    clientParentBundle = (MRClientStrFn)dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");
    registerNotifs = (MRRegisterFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
    sendCommand = (MRSendCommandFn)dlsym(mr, "MRMediaRemoteSendCommand");
    setElapsed = (MRSetElapsedFn)dlsym(mr, "MRMediaRemoteSetElapsedTime");
    if (!getInfo || !getIsPlaying || !getPID || !registerNotifs) {
      emit(@{@"type": @"error", @"message": @"MediaRemote funksiyalari topilmadi"});
      exit(3);
    }

    registerNotifs(dispatch_get_main_queue());
    const char *names[] = {
      "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
      "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
      "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
      "kMRMediaRemoteNowPlayingApplicationClientStateDidChange",
    };
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
      [NSNotificationCenter.defaultCenter addObserverForName:constant(names[i])
                                                      object:nil
                                                       queue:NSOperationQueue.mainQueue
                                                  usingBlock:^(NSNotification *n) { scheduleFetch(); }];
    }

    startStdin();
    // Ba'zi pleyerlar xabar yubormay qoladi — sekin "yurak urishi".
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), 15 * NSEC_PER_SEC, 2 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{ scheduleFetch(); });
    dispatch_resume(timer);

    emit(@{@"type": @"ready"});
    scheduleFetch();
    CFRunLoopRun();
  }
}
