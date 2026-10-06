//
//  WBReceiveRedEnvelopOperation.m
//  WeChatRedEnvelop
//
//  Created by wordbeyondyoung on 17/2/22.
//  Copyright © 2017年 swiftyper. All rights reserved.
//

#import "WBReceiveRedEnvelopOperation.h"
#import "WeChatRedEnvelopParam.h"
#import "WBRedEnvelopConfig.h"
#import "WeChatRedEnvelop.h"
#import <objc/runtime.h>
#import <objc/message.h>

@interface WBReceiveRedEnvelopOperation ()

@property (assign, nonatomic, getter=isExecuting) BOOL executing;
@property (assign, nonatomic, getter=isFinished) BOOL finished;

@property (strong, nonatomic) WeChatRedEnvelopParam *redEnvelopParam;
@property (assign, nonatomic) unsigned int delaySeconds;

@end

@implementation WBReceiveRedEnvelopOperation

@synthesize executing = _executing;
@synthesize finished = _finished;

- (instancetype)initWithRedEnvelopParam:(WeChatRedEnvelopParam *)param delay:(unsigned int)delaySeconds {
    if (self = [super init]) {
        _redEnvelopParam = param;
        _delaySeconds = delaySeconds;
    }
    return self;
}

- (void)start {
    if (self.isCancelled) {
        self.finished = YES;
        self.executing = NO;
        return;
    }
    
    [self main];
    
    self.executing = YES;
    self.finished = NO;
}

static id GetWeChatService(Class serviceClass) {
    if (objc_getClass("MMContext")) {
        MMContext *context = [objc_getClass("MMContext") activeUserContext];
        if (context && [context respondsToSelector:@selector(getService:)]) {
            id service = [context getService:serviceClass];
            if (service) return service;
        }
    }
    if (objc_getClass("MMServiceCenter")) {
        id center = [objc_getClass("MMServiceCenter") performSelector:@selector(defaultCenter)];
        if (center && [center respondsToSelector:@selector(getService:)]) {
            return [center performSelector:@selector(getService:) withObject:serviceClass];
        }
    }
    return nil;
}

- (void)main {
    sleep(self.delaySeconds);
    
    WCRedEnvelopesLogicMgr *logicMgr = GetWeChatService(objc_getClass("WCRedEnvelopesLogicMgr"));
    if ([logicMgr respondsToSelector:@selector(OpenRedEnvelopesRequest:)]) {
        [logicMgr OpenRedEnvelopesRequest:[self.redEnvelopParam toParams]];
    } else if ([logicMgr respondsToSelector:NSSelectorFromString(@"openRedEnvelopesRequest:")]) {
        [logicMgr performSelector:NSSelectorFromString(@"openRedEnvelopesRequest:") withObject:[self.redEnvelopParam toParams]];
    } else {
        NSLog(@"[WeChatRedEnvelop] 未找到 OpenRedEnvelopesRequest 接口");
    }
    
    self.finished = YES;
    self.executing = NO;
}

- (void)cancel {
    self.finished = YES;
    self.executing = NO;
}

- (void)setFinished:(BOOL)finished {
    [self willChangeValueForKey:@"isFinished"];
    _finished = finished;
    [self didChangeValueForKey:@"isFinished"];
}

- (void)setExecuting:(BOOL)executing {
    [self willChangeValueForKey:@"isExecuting"];
    _executing = executing;
    [self didChangeValueForKey:@"isExecuting"];
}

- (BOOL)isAsynchronous {
    return YES;
}

@end
