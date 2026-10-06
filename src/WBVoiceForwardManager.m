//
//  WBVoiceForwardManager.m
//  WeChatRedEnvelop
//
//  Created for Secondary Development.
//

#import "WBVoiceForwardManager.h"
#import "WeChatRedEnvelop.h"
#import <objc/objc-runtime.h>

static id GetWeChatService(Class serviceClass) {
    if (objc_getClass("MMContext")) {
        MMContext *context = [objc_getClass("MMContext") activeUserContext];
        if (context && [context respondsToSelector:@selector(getService:)]) {
            id service = [context getService:serviceClass];
            if (service) return service;
        }
        if ([objc_getClass("MMContext") respondsToSelector:@selector(currentContext)]) {
            id current = [objc_getClass("MMContext") performSelector:@selector(currentContext)];
            if (current && [current respondsToSelector:@selector(getService:)]) {
                id service = [current performSelector:@selector(getService:) withObject:serviceClass];
                if (service) return service;
            }
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

@interface WBVoiceForwardManager () <MultiSelectContactsViewControllerDelegate>

@property (nonatomic, strong) CMessageWrap *selectedMessageWrap;
@property (nonatomic, strong) id selectedFavItem;
@property (nonatomic, weak) UIViewController *presentingViewController;

@end

@implementation WBVoiceForwardManager

+ (instancetype)sharedManager {
    static WBVoiceForwardManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[WBVoiceForwardManager alloc] init];
    });
    return manager;
}

- (void)forwardVoiceMessage:(CMessageWrap *)msgWrap fromViewController:(UIViewController *)vc {
    if (!msgWrap) {
        return;
    }
    self.selectedMessageWrap = msgWrap;
    self.selectedFavItem = nil;
    self.presentingViewController = vc;

    [self presentContactPickerFromVC:vc];
}

- (void)forwardFavAudioItem:(id)favItem fromViewController:(UIViewController *)vc {
    if (!favItem) {
        return;
    }
    self.selectedFavItem = favItem;
    self.selectedMessageWrap = nil;
    self.presentingViewController = vc;

    [self presentContactPickerFromVC:vc];
}

- (void)presentContactPickerFromVC:(UIViewController *)vc {
    MultiSelectContactsViewController *contactsVC = [[objc_getClass("MultiSelectContactsViewController") alloc] init];
    contactsVC.m_scene = 5; // 支持好友与群聊
    contactsVC.m_delegate = self;

    if ([contactsVC respondsToSelector:@selector(loadViewIfNeeded)]) {
        [contactsVC loadViewIfNeeded];
    }

    MMUINavigationController *navigationController = [[objc_getClass("MMUINavigationController") alloc] initWithRootViewController:contactsVC];
    navigationController.modalPresentationStyle = UIModalPresentationFullScreen;

    if (vc) {
        [vc presentViewController:navigationController animated:YES completion:nil];
    } else {
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        UIViewController *rootVC = keyWindow.rootViewController;
        while (rootVC.presentedViewController) {
            rootVC = rootVC.presentedViewController;
        }
        [rootVC presentViewController:navigationController animated:YES completion:nil];
    }
}

#pragma mark - FavItem Extractor

- (NSData *)extractVoiceDataFromFavItem:(id)favItem outDuration:(NSUInteger *)outDuration outFormat:(NSUInteger *)outFormat {
    if (!favItem) return nil;

    NSUInteger duration = 1;
    NSUInteger format = 0;
    NSData *voiceData = nil;

    NSArray *dataList = nil;
    if ([favItem respondsToSelector:@selector(dataList)]) {
        dataList = [favItem performSelector:@selector(dataList)];
    } else {
        @try {
            dataList = [favItem valueForKey:@"dataList"];
        } @catch (NSException *e) {}
    }

    id targetField = nil;
    if (dataList && [dataList isKindOfClass:[NSArray class]]) {
        for (id field in dataList) {
            unsigned int dataType = 0;
            @try {
                dataType = [[field valueForKey:@"dataType"] unsignedIntValue];
            } @catch (NSException *e) {}
            if (dataType == 3 || dataType == 0) { // 3: voice
                targetField = field;
                break;
            }
        }
        if (!targetField && dataList.count > 0) {
            targetField = dataList.firstObject;
        }
    }

    if (targetField) {
        @try {
            duration = [[targetField valueForKey:@"duration"] unsignedIntValue];
        } @catch (NSException *e) {}

        NSString *dataPath = nil;
        @try {
            dataPath = [targetField valueForKey:@"dataPath"];
        } @catch (NSException *e) {}

        if (!dataPath || dataPath.length == 0) {
            @try {
                dataPath = [targetField valueForKey:@"m_dataPath"];
            } @catch (NSException *e) {}
        }

        if (dataPath && [[NSFileManager defaultManager] fileExistsAtPath:dataPath]) {
            voiceData = [NSData dataWithContentsOfFile:dataPath];
        }

        if (!voiceData) {
            // 尝试通过 FavRecordLogic 获取沙盒音频路径
            if (objc_getClass("FavRecordLogic") && [objc_getClass("FavRecordLogic") respondsToSelector:@selector(getRecordDataPath:)]) {
                NSString *path = [objc_getClass("FavRecordLogic") performSelector:@selector(getRecordDataPath:) withObject:targetField];
                if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
                    voiceData = [NSData dataWithContentsOfFile:path];
                }
            }
        }
    }

    if (duration == 0) {
        duration = 1;
    }

    if (outDuration) *outDuration = duration;
    if (outFormat) *outFormat = format;

    return voiceData;
}

#pragma mark - Single Send (For in-chat)

- (BOOL)sendFavAudioItem:(id)favItem toUser:(NSString *)toUser {
    if (!favItem || toUser.length == 0) return NO;

    NSUInteger duration = 1;
    NSUInteger format = 0;
    NSData *voiceData = [self extractVoiceDataFromFavItem:favItem outDuration:&duration outFormat:&format];

    if (!voiceData || voiceData.length == 0) {
        return NO;
    }

    return [self sendVoiceData:voiceData duration:duration format:format toUser:toUser];
}

#pragma mark - MultiSelectContactsViewControllerDelegate

- (void)onMultiSelectContactReturn:(NSArray *)contacts {
    if (contacts.count == 0 || (!self.selectedMessageWrap && !self.selectedFavItem)) {
        [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
        self.selectedMessageWrap = nil;
        self.selectedFavItem = nil;
        return;
    }

    NSData *voiceData = nil;
    NSUInteger voiceTime = 1;
    NSUInteger voiceFormat = 0;
    NSString *sourceTypeDesc = @"语音";

    if (self.selectedMessageWrap) {
        CMessageWrap *srcMsg = self.selectedMessageWrap;
        voiceTime = srcMsg.m_uiVoiceTime;
        voiceFormat = srcMsg.m_uiVoiceFormat;

        // 若时长为 0，尝试从 XML content 中提取 voicelength (毫秒或秒)
        if (voiceTime == 0 && srcMsg.m_nsContent.length > 0) {
            NSRange lenRange = [srcMsg.m_nsContent rangeOfString:@"voicelength=\""];
            if (lenRange.location != NSNotFound) {
                NSString *sub = [srcMsg.m_nsContent substringFromIndex:lenRange.location + lenRange.length];
                NSRange endRange = [sub rangeOfString:@"\""];
                if (endRange.location != NSNotFound) {
                    NSString *lenStr = [sub substringToIndex:endRange.location];
                    NSInteger parsedMs = [lenStr integerValue];
                    voiceTime = parsedMs > 1000 ? (parsedMs / 1000) : parsedMs;
                }
            }
        }
        if (voiceTime == 0) voiceTime = 1;

        // 获取音频数据
        voiceData = srcMsg.m_dtVoice;
        if (!voiceData || voiceData.length == 0) {
            NSString *voicePath = nil;
            if ([objc_getClass("CMessageWrap") respondsToSelector:@selector(getVoicePathByMessageWrap:)]) {
                voicePath = [objc_getClass("CMessageWrap") getVoicePathByMessageWrap:srcMsg];
            }
            if ((!voicePath || ![[NSFileManager defaultManager] fileExistsAtPath:voicePath]) && srcMsg.m_nsFilePath.length > 0) {
                voicePath = srcMsg.m_nsFilePath;
            }
            if (voicePath && [[NSFileManager defaultManager] fileExistsAtPath:voicePath]) {
                voiceData = [NSData dataWithContentsOfFile:voicePath];
            }
        }
    } else if (self.selectedFavItem) {
        sourceTypeDesc = @"收藏语音";
        voiceData = [self extractVoiceDataFromFavItem:self.selectedFavItem outDuration:&voiceTime outFormat:&voiceFormat];
    }

    NSUInteger successCount = 0;
    for (CContact *contact in contacts) {
        NSString *toUser = contact.m_nsUsrName;
        if (toUser.length == 0) continue;

        if ([self sendVoiceData:voiceData duration:voiceTime format:voiceFormat toUser:toUser]) {
            successCount++;
        }
    }

    self.selectedMessageWrap = nil;
    self.selectedFavItem = nil;

    [self.presentingViewController dismissViewControllerAnimated:YES completion:^{
        if (successCount > 0) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@转发", sourceTypeDesc] 
                                                                           message:[NSString stringWithFormat:@"已成功转发到 %lu 个会话", (unsigned long)successCount] 
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            
            UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
            UIViewController *rootVC = keyWindow.rootViewController;
            while (rootVC.presentedViewController) {
                rootVC = rootVC.presentedViewController;
            }
            [rootVC presentViewController:alert animated:YES completion:nil];
        }
    }];
}

#pragma mark - Core Voice Sender

- (BOOL)sendVoiceData:(NSData *)voiceData duration:(NSUInteger)duration format:(NSUInteger)format toUser:(NSString *)toUser {
    if (toUser.length == 0) return NO;

    CContactMgr *contactMgr = GetWeChatService(objc_getClass("CContactMgr"));
    CContact *selfContact = [contactMgr getSelfContact];
    NSString *selfUserName = selfContact ? selfContact.m_nsUsrName : @"";

    CMessageWrap *newVoiceWrap = [[objc_getClass("CMessageWrap") alloc] initWithMsgType:34];
    [newVoiceWrap setM_uiMessageType:34];
    [newVoiceWrap setM_nsFromUsr:selfUserName];
    [newVoiceWrap setM_nsToUsr:toUser];
    [newVoiceWrap setM_uiVoiceTime:duration];
    [newVoiceWrap setM_uiVoiceFormat:format];
    [newVoiceWrap setM_uiCreateTime:(NSUInteger)[[NSDate date] timeIntervalSince1970]];
    [newVoiceWrap setM_uiStatus:1];

    if (voiceData) {
        [newVoiceWrap setM_dtVoice:voiceData];
    }

    // 写入本地沙盒音频目录（供底层音频上传与回放组件读取）
    if (voiceData && [objc_getClass("CMessageWrap") respondsToSelector:@selector(getVoicePathByMessageWrap:)]) {
        NSString *targetVoicePath = [objc_getClass("CMessageWrap") getVoicePathByMessageWrap:newVoiceWrap];
        if (targetVoicePath.length > 0) {
            NSString *dir = [targetVoicePath stringByDeletingLastPathComponent];
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            [voiceData writeToFile:targetVoicePath atomically:YES];
        }
    }

    AudioSender *audioSender = GetWeChatService(objc_getClass("AudioSender"));
    CMessageMgr *msgMgr = GetWeChatService(objc_getClass("CMessageMgr"));

    BOOL sent = NO;
    if (audioSender && [audioSender respondsToSelector:@selector(ResendVoiceMsg:MsgWrap:)]) {
        [audioSender ResendVoiceMsg:toUser MsgWrap:newVoiceWrap];
        sent = YES;
    } else if (audioSender && [audioSender respondsToSelector:@selector(SendAudioMsg:MsgWrap:)]) {
        [audioSender SendAudioMsg:toUser MsgWrap:newVoiceWrap];
        sent = YES;
    } else if (msgMgr && [msgMgr respondsToSelector:@selector(AddMsg:MsgWrap:)]) {
        [msgMgr AddMsg:toUser MsgWrap:newVoiceWrap];
        sent = YES;
    }

    return sent;
}

@end
