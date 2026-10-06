//
//  WBVoiceForwardManager.h
//  WeChatRedEnvelop
//
//  Created for Secondary Development.
//

#import <UIKit/UIKit.h>

@class CMessageWrap;

@interface WBVoiceForwardManager : NSObject

+ (instancetype)sharedManager;

- (void)forwardVoiceMessage:(CMessageWrap *)msgWrap fromViewController:(UIViewController *)vc;

- (void)forwardFavAudioItem:(id)favItem fromViewController:(UIViewController *)vc;

- (BOOL)sendFavAudioItem:(id)favItem toUser:(NSString *)toUser;

@end
