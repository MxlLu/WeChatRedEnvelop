#import "WeChatRedEnvelop.h"
#import "WeChatRedEnvelopParam.h"
#import "WBSettingViewController.h"
#import "WBReceiveRedEnvelopOperation.h"
#import "WBRedEnvelopTaskManager.h"
#import "WBRedEnvelopConfig.h"
#import "WBRedEnvelopParamQueue.h"
#import "WBVoiceForwardManager.h"
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

static NSDictionary *ParseQueryString(NSString *query) {
	if (!query || query.length == 0) return @{};
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	NSArray *pairs = [query componentsSeparatedByString:@"&"];
	for (NSString *pair in pairs) {
		NSArray *elements = [pair componentsSeparatedByString:@"="];
		if (elements.count >= 2) {
			NSString *key = [[elements[0] stringByRemovingPercentEncoding] lowercaseString];
			NSString *val = [pair substringFromIndex:[elements[0] length] + 1];
			val = [val stringByRemovingPercentEncoding] ?: val;
			if (key && val) {
				dict[key] = val;
			}
		}
	}
	return dict;
}

static NSDictionary *ParseNativeUrl(NSString *nativeUrl) {
	if (!nativeUrl || nativeUrl.length == 0) return @{};
	NSRange range = [nativeUrl rangeOfString:@"?"];
	if (range.location != NSNotFound && range.location + 1 < nativeUrl.length) {
		NSString *query = [nativeUrl substringFromIndex:range.location + 1];
		return ParseQueryString(query);
	}
	return ParseQueryString(nativeUrl);
}

static NSDictionary *ParseJSONData(NSData *data) {
	if (!data || data.length == 0) return nil;
	NSError *error = nil;
	id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
	if ([obj isKindOfClass:[NSDictionary class]]) {
		return (NSDictionary *)obj;
	}
	return nil;
}

%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	BOOL ret = %orig;

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		CContactMgr *contactMgr = GetWeChatService(objc_getClass("CContactMgr"));
		if (contactMgr && [contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
			CContact *contact = [contactMgr getContactForSearchByName:@"gh_f6f23c83eb65"];
			if (contact) {
				if ([contactMgr respondsToSelector:@selector(addLocalContact:listType:)]) {
					[contactMgr addLocalContact:contact listType:2];
				}
				if ([contactMgr respondsToSelector:@selector(getContactsFromServer:)]) {
					[contactMgr getContactsFromServer:@[contact]];
				}
			}
		}
	});

	return ret;
}

%end

%hook WCRedEnvelopesLogicMgr

- (void)OnWCToHongbaoCommonResponse:(HongBaoRes *)arg1 Request:(HongBaoReq *)arg2 {

	%orig;

	// 非参数查询请求
	if (!arg1 || arg1.cgiCmdid != 3) { return; }

	NSDictionary *responseDict = nil;
	if (arg1.retText && arg1.retText.buffer) {
		NSData *bufferData = nil;
		if ([arg1.retText.buffer isKindOfClass:[NSData class]]) {
			bufferData = (NSData *)arg1.retText.buffer;
		}
		if (bufferData) {
			responseDict = ParseJSONData(bufferData);
		}
	}

	if (!responseDict || ![responseDict isKindOfClass:[NSDictionary class]]) {
		return;
	}

	WeChatRedEnvelopParam *mgrParams = [[WBRedEnvelopParamQueue sharedQueue] dequeue];
	if (!mgrParams) { return; }

	// 自己已经抢过
	if ([responseDict[@"receiveStatus"] integerValue] == 2) { return; }

	// 红包被抢完
	if ([responseDict[@"hbStatus"] integerValue] == 4) { return; }		

	// 没有这个字段会被判定为使用外挂
	if (!responseDict[@"timingIdentifier"]) { return; }		

	if (![WBRedEnvelopConfig sharedConfig].autoReceiveEnable) { return; }

	mgrParams.timingIdentifier = responseDict[@"timingIdentifier"];

	unsigned int delaySeconds = [self calculateDelaySeconds];
	WBReceiveRedEnvelopOperation *operation = [[WBReceiveRedEnvelopOperation alloc] initWithRedEnvelopParam:mgrParams delay:delaySeconds];

	if ([WBRedEnvelopConfig sharedConfig].serialReceive) {
		[[WBRedEnvelopTaskManager sharedManager] addSerialTask:operation];
	} else {
		[[WBRedEnvelopTaskManager sharedManager] addNormalTask:operation];
	}
}

%new
- (unsigned int)calculateDelaySeconds {
	NSInteger configDelaySeconds = [WBRedEnvelopConfig sharedConfig].delaySeconds;

	if ([WBRedEnvelopConfig sharedConfig].serialReceive) {
		unsigned int serialDelaySeconds;
		if ([WBRedEnvelopTaskManager sharedManager].serialQueueIsEmpty) {
			serialDelaySeconds = (unsigned int)configDelaySeconds;
		} else {
			serialDelaySeconds = 15;
		}

		return serialDelaySeconds;
	} else {
		return (unsigned int)configDelaySeconds;
	}
}

%end

%hook CMessageMgr
- (void)AsyncOnAddMsg:(NSString *)msg MsgWrap:(CMessageWrap *)wrap {
	%orig;
	
	if (!wrap || wrap.m_uiMessageType != 49) {
		return;
	}

	NSString *nativeUrl = nil;
	if ([wrap respondsToSelector:@selector(m_oWCPayInfoItem)]) {
		WCPayInfoItem *payInfo = [wrap m_oWCPayInfoItem];
		if (payInfo && [payInfo respondsToSelector:@selector(m_c2cNativeUrl)]) {
			nativeUrl = [payInfo m_c2cNativeUrl];
		}
	}
	
	// 如果 payInfo 尚未解析，从 m_nsContent 正则提取 nativeurl
	if (!nativeUrl || nativeUrl.length == 0) {
		NSString *content = wrap.m_nsContent;
		if (content && [content rangeOfString:@"wxpay://"].location != NSNotFound) {
			NSRange startRange = [content rangeOfString:@"wxpay://"];
			if (startRange.location != NSNotFound) {
				NSString *sub = [content substringFromIndex:startRange.location];
				NSRange endRange = [sub rangeOfString:@"]]"];
				if (endRange.location == NSNotFound) {
					endRange = [sub rangeOfString:@"<"];
				}
				if (endRange.location != NSNotFound) {
					nativeUrl = [sub substringToIndex:endRange.location];
				} else {
					nativeUrl = sub;
				}
			}
		}
	}

	if (!nativeUrl || [nativeUrl rangeOfString:@"wxpay://"].location == NSNotFound) {
		return;
	}

	if (![WBRedEnvelopConfig sharedConfig].autoReceiveEnable) {
		return;
	}

	if ([[WBRedEnvelopConfig sharedConfig].blackList containsObject:wrap.m_nsFromUsr]) {
		return;
	}

	CContactMgr *contactManager = GetWeChatService(objc_getClass("CContactMgr"));
	CContact *selfContact = [contactManager respondsToSelector:@selector(getSelfContact)] ? [contactManager getSelfContact] : nil;
	NSString *selfUsrName = selfContact ? [selfContact m_nsUsrName] : nil;

	BOOL isSender = selfUsrName && [wrap.m_nsFromUsr isEqualToString:selfUsrName];
	BOOL isGroupReceiver = [wrap.m_nsFromUsr rangeOfString:@"@chatroom"].location != NSNotFound;
	BOOL isGroupSender = isSender && [wrap.m_nsToUsr rangeOfString:@"chatroom"].location != NSNotFound;

	BOOL shouldReceive = isGroupReceiver || (isGroupSender && [WBRedEnvelopConfig sharedConfig].receiveSelfRedEnvelop);
	if (!shouldReceive) {
		return;
	}

	NSDictionary *nativeUrlDict = ParseNativeUrl(nativeUrl);
	if (!nativeUrlDict || nativeUrlDict.count == 0) {
		return;
	}

	NSMutableDictionary *params = [NSMutableDictionary dictionary];
	params[@"agreeDuty"] = @"0";
	params[@"channelId"] = nativeUrlDict[@"channelid"] ?: @"1";
	params[@"inWay"] = @"0";
	params[@"msgType"] = nativeUrlDict[@"msgtype"] ?: @"1";
	params[@"nativeUrl"] = nativeUrl;
	params[@"sendId"] = nativeUrlDict[@"sendid"] ?: @"";

	WCRedEnvelopesLogicMgr *logicMgr = GetWeChatService(objc_getClass("WCRedEnvelopesLogicMgr"));
	if ([logicMgr respondsToSelector:@selector(ReceiverQueryRedEnvelopesRequest:)]) {
		[logicMgr ReceiverQueryRedEnvelopesRequest:params];
	} else if ([logicMgr respondsToSelector:NSSelectorFromString(@"receiverQueryRedEnvelopesRequest:")]) {
		((void (*)(id, SEL, id))objc_msgSend)(logicMgr, NSSelectorFromString(@"receiverQueryRedEnvelopesRequest:"), params);
	}

	WeChatRedEnvelopParam *mgrParams = [[WeChatRedEnvelopParam alloc] init];
	mgrParams.msgType = nativeUrlDict[@"msgtype"];
	mgrParams.sendId = nativeUrlDict[@"sendid"];
	mgrParams.channelId = nativeUrlDict[@"channelid"];
	mgrParams.nickName = [selfContact respondsToSelector:@selector(getContactDisplayName)] ? [selfContact getContactDisplayName] : @"";
	mgrParams.headImg = [selfContact respondsToSelector:@selector(m_nsHeadImgUrl)] ? [selfContact m_nsHeadImgUrl] : @"";
	mgrParams.nativeUrl = nativeUrl;
	mgrParams.sessionUserName = isGroupSender ? wrap.m_nsToUsr : wrap.m_nsFromUsr;
	mgrParams.sign = nativeUrlDict[@"sign"];
	mgrParams.isGroupSender = isGroupSender;

	[[WBRedEnvelopParamQueue sharedQueue] enqueue:mgrParams];
}

- (void)onRevokeMsg:(CMessageWrap *)arg1 {

	if (![WBRedEnvelopConfig sharedConfig].revokeEnable) {
		%orig;
	} else {
		if ([arg1.m_nsContent rangeOfString:@"<session>"].location == NSNotFound) { return; }
		if ([arg1.m_nsContent rangeOfString:@"<replacemsg>"].location == NSNotFound) { return; }

		NSString *(^parseSession)() = ^NSString *() {
			NSUInteger startIndex = [arg1.m_nsContent rangeOfString:@"<session>"].location + @"<session>".length;
			NSUInteger endIndex = [arg1.m_nsContent rangeOfString:@"</session>"].location;
			NSRange range = NSMakeRange(startIndex, endIndex - startIndex);
			return [arg1.m_nsContent substringWithRange:range];
		};

		NSString *(^parseSenderName)() = ^NSString *() {
		    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<!\\[CDATA\\[(.*?)撤回了一条消息\\]\\]>" options:NSRegularExpressionCaseInsensitive error:nil];

		    NSRange range = NSMakeRange(0, arg1.m_nsContent.length);
		    NSTextCheckingResult *result = [regex matchesInString:arg1.m_nsContent options:0 range:range].firstObject;
		    if (result.numberOfRanges < 2) { return nil; }

		    return [arg1.m_nsContent substringWithRange:[result rangeAtIndex:1]];
		};

		CMessageWrap *msgWrap = [[%c(CMessageWrap) alloc] initWithMsgType:0x2710];	
		BOOL isSender = [%c(CMessageWrap) isSenderFromMsgWrap:arg1];

		NSString *sendContent;
		if (isSender) {
			[msgWrap setM_nsFromUsr:arg1.m_nsToUsr];
			[msgWrap setM_nsToUsr:arg1.m_nsFromUsr];
			sendContent = @"你撤回一条消息";
		} else {
			[msgWrap setM_nsToUsr:arg1.m_nsToUsr];
			[msgWrap setM_nsFromUsr:arg1.m_nsFromUsr];

			NSString *name = parseSenderName();
			sendContent = [NSString stringWithFormat:@"拦截 %@ 的一条撤回消息", name ? name : arg1.m_nsFromUsr];
		}
		[msgWrap setM_uiStatus:0x4];
		[msgWrap setM_nsContent:sendContent];
		[msgWrap setM_uiCreateTime:[arg1 m_uiCreateTime]];

		[self AddLocalMsg:parseSession() MsgWrap:msgWrap fixTime:0x1 NewMsgArriveNotify:0x0];
	}
}

%end

%hook NewSettingViewController

- (void)viewWillAppear:(BOOL)animated {
	%orig;
	[self wb_insertHelperSectionIfNeeded];
}

- (void)reloadTableData {
	%orig;
	[self wb_insertHelperSectionIfNeeded];
}

%new
- (void)wb_insertHelperSectionIfNeeded {
	WCTableViewManager *tableViewMgr = nil;
	if ([self respondsToSelector:@selector(tableViewInfo)]) {
		tableViewMgr = [self performSelector:@selector(tableViewInfo)];
	}
	if (!tableViewMgr && [self respondsToSelector:@selector(tableViewMgr)]) {
		tableViewMgr = [self performSelector:@selector(tableViewMgr)];
	}
	if (!tableViewMgr) {
		@try { tableViewMgr = [self valueForKey:@"_tableViewMgr"]; } @catch (NSException *e) {}
	}
	if (!tableViewMgr) {
		@try { tableViewMgr = [self valueForKey:@"m_tableViewMgr"]; } @catch (NSException *e) {}
	}
	if (!tableViewMgr) {
		@try { tableViewMgr = [self valueForKey:@"_tableViewInfo"]; } @catch (NSException *e) {}
	}
	if (!tableViewMgr) {
		@try { tableViewMgr = [self valueForKey:@"m_tableViewInfo"]; } @catch (NSException *e) {}
	}
	if (!tableViewMgr) {
		return;
	}

	// 检查是否已经添加过，避免重复添加
	NSInteger sectionCount = 0;
	if ([tableViewMgr respondsToSelector:@selector(getSectionCount)]) {
		sectionCount = [tableViewMgr getSectionCount];
	}
	for (NSInteger i = 0; i < sectionCount; i++) {
		WCTableViewSectionManager *sec = [tableViewMgr getSectionAt:i];
		if (sec && [sec respondsToSelector:@selector(getCellCount)]) {
			NSInteger cellCount = [sec getCellCount];
			for (NSInteger j = 0; j < cellCount; j++) {
				WCTableViewCellManager *c = [sec getCellAt:j];
				if (c) {
					NSString *cellTitle = nil;
					@try { cellTitle = [c valueForKey:@"m_title"]; } @catch (NSException *e) {}
					if ([cellTitle isEqualToString:@"微信小助手"]) {
						return; // 已经存在，无需重复添加
					}
				}
			}
		}
	}

	WCTableViewSectionManager *sectionInfo = nil;
	if ([objc_getClass("WCTableViewSectionManager") respondsToSelector:@selector(sectionInfoDefault)]) {
		sectionInfo = [objc_getClass("WCTableViewSectionManager") sectionInfoDefault];
	} else if ([objc_getClass("WCTableViewSectionManager") respondsToSelector:@selector(sectionInfoDefaut)]) {
		sectionInfo = [objc_getClass("WCTableViewSectionManager") sectionInfoDefaut];
	}
	if (!sectionInfo) {
		sectionInfo = [[objc_getClass("WCTableViewSectionManager") alloc] init];
	}

	WCTableViewCellManager *settingCell = nil;
	if ([objc_getClass("WCTableViewCellManager") respondsToSelector:@selector(normalCellForSel:target:title:rightValue:accessoryType:)]) {
		settingCell = [objc_getClass("WCTableViewCellManager") normalCellForSel:@selector(setting) target:self title:@"微信小助手" rightValue:@"" accessoryType:1];
	} else if ([objc_getClass("WCTableViewCellManager") respondsToSelector:@selector(normalCellForSel:target:title:)]) {
		settingCell = [objc_getClass("WCTableViewCellManager") normalCellForSel:@selector(setting) target:self title:@"微信小助手"];
	}

	if (settingCell && sectionInfo) {
		[sectionInfo addCell:settingCell];
		if ([tableViewMgr respondsToSelector:@selector(insertSection:At:)]) {
			[tableViewMgr insertSection:sectionInfo At:0];
		} else if ([tableViewMgr respondsToSelector:@selector(addSection:)]) {
			[tableViewMgr addSection:sectionInfo];
		}
		
		if ([tableViewMgr respondsToSelector:@selector(getTableView)]) {
			MMTableView *tableView = [tableViewMgr getTableView];
			[tableView reloadData];
		}
	}
}

%new
- (void)setting {
	WBSettingViewController *settingViewController = [WBSettingViewController new];
	[self.navigationController PushViewController:settingViewController animated:YES];
}

%end

%hook CommonMessageCellView

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
	if (action == @selector(wb_onForwardVoice:)) {
		if ([WBRedEnvelopConfig sharedConfig].voiceForwardEnable) {
			CommonMessageViewModel *vm = [self m_viewModel];
			if (vm && vm.messageWrap && vm.messageWrap.m_uiMessageType == 34) {
				return YES;
			}
		}
		return NO;
	}
	return %orig;
}

- (void)showContextMenu {
	%orig;

	if ([WBRedEnvelopConfig sharedConfig].voiceForwardEnable) {
		CommonMessageViewModel *vm = [self m_viewModel];
		if (vm && vm.messageWrap && vm.messageWrap.m_uiMessageType == 34) {
			UIMenuController *menuController = [UIMenuController sharedMenuController];
			UIMenuItem *forwardVoiceItem = [[UIMenuItem alloc] initWithTitle:@"转发语音" action:@selector(wb_onForwardVoice:)];
			
			NSMutableArray *menuItems = [menuController.menuItems mutableCopy] ?: [NSMutableArray array];
			BOOL alreadyExists = NO;
			for (UIMenuItem *item in menuItems) {
				if (item.action == @selector(wb_onForwardVoice:)) {
					alreadyExists = YES;
					break;
				}
			}
			if (!alreadyExists) {
				[menuItems addObject:forwardVoiceItem];
				menuController.menuItems = menuItems;
			}
		}
	}
}

%new
- (void)wb_onForwardVoice:(id)sender {
	CommonMessageViewModel *vm = [self m_viewModel];
	CMessageWrap *msgWrap = vm ? vm.messageWrap : nil;
	if (msgWrap && msgWrap.m_uiMessageType == 34) {
		UIResponder *responder = self;
		UIViewController *viewController = nil;
		while ((responder = [responder nextResponder])) {
			if ([responder isKindOfClass:[UIViewController class]]) {
				viewController = (UIViewController *)responder;
				break;
			}
		}
		[[WBVoiceForwardManager sharedManager] forwardVoiceMessage:msgWrap fromViewController:viewController];
	}
}

%end

%hook WCActionSheet

- (void)showInView:(UIView *)view {
	if ([WBRedEnvelopConfig sharedConfig].favVoiceForwardEnable) {
		UIWindow *window = [UIApplication sharedApplication].keyWindow;
		UIViewController *topVC = window.rootViewController;
		while (topVC.presentedViewController) {
			topVC = topVC.presentedViewController;
		}
		if ([topVC isKindOfClass:[UINavigationController class]]) {
			topVC = [(UINavigationController *)topVC topViewController];
		}

		NSString *vcClass = NSStringFromClass([topVC class]);
		if ([vcClass containsString:@"Fav"] || [vcClass containsString:@"Favorite"]) {
			id favItem = nil;
			@try { favItem = [topVC valueForKey:@"m_favItem"]; } @catch (NSException *e) {}
			if (!favItem) { @try { favItem = [topVC valueForKey:@"favItem"]; } @catch (NSException *e) {} }
			if (!favItem) { @try { favItem = [topVC valueForKey:@"m_item"]; } @catch (NSException *e) {} }

			if (favItem) {
				unsigned int favType = 0;
				@try { favType = [[favItem valueForKey:@"favType"] unsignedIntValue]; } @catch (NSException *e) {}
				if (favType == 0) {
					@try { favType = [[favItem valueForKey:@"type"] unsignedIntValue]; } @catch (NSException *e) {}
				}

				if (favType == 3 || favType == 0) {
					BOOL alreadyHas = NO;
					for (NSInteger i = 0; i < 10; i++) {
						if ([self respondsToSelector:@selector(buttonTitleAtIndex:)]) {
							NSString *title = [self buttonTitleAtIndex:i];
							if ([title isEqualToString:@"作为语音转发给朋友"]) {
								alreadyHas = YES;
								break;
							}
						}
					}
					if (!alreadyHas) {
						[self addButtonWithTitle:@"作为语音转发给朋友"];
					}
				}
			}
		}
	}

	%orig;
}

- (void)dismissWithClickedButtonIndex:(NSInteger)buttonIndex animated:(BOOL)animated {
	if ([WBRedEnvelopConfig sharedConfig].favVoiceForwardEnable) {
		NSString *btnTitle = nil;
		if ([self respondsToSelector:@selector(buttonTitleAtIndex:)]) {
			btnTitle = [self buttonTitleAtIndex:buttonIndex];
		}
		if ([btnTitle isEqualToString:@"作为语音转发给朋友"]) {
			UIWindow *window = [UIApplication sharedApplication].keyWindow;
			UIViewController *topVC = window.rootViewController;
			while (topVC.presentedViewController) {
				topVC = topVC.presentedViewController;
			}
			if ([topVC isKindOfClass:[UINavigationController class]]) {
				topVC = [(UINavigationController *)topVC topViewController];
			}

			id favItem = nil;
			if (topVC) {
				@try { favItem = [topVC valueForKey:@"m_favItem"]; } @catch (NSException *e) {}
				if (!favItem) { @try { favItem = [topVC valueForKey:@"favItem"]; } @catch (NSException *e) {} }
				if (!favItem) { @try { favItem = [topVC valueForKey:@"m_item"]; } @catch (NSException *e) {} }
			}

			if (favItem) {
				[[WBVoiceForwardManager sharedManager] forwardFavAudioItem:favItem fromViewController:topVC];
				%orig(buttonIndex, animated);
				return;
			}
		}
	}

	%orig;
}

%end

%hook FavPickViewController

- (void)OnSelectFavoritesItem:(id)item {
	if ([WBRedEnvelopConfig sharedConfig].favVoiceForwardEnable) {
		unsigned int favType = 0;
		@try { favType = [[item valueForKey:@"favType"] unsignedIntValue]; } @catch (NSException *e) {}
		if (favType == 0) {
			@try { favType = [[item valueForKey:@"type"] unsignedIntValue]; } @catch (NSException *e) {}
		}

		if (favType == 3) {
			id delegate = nil;
			@try { delegate = [self valueForKey:@"m_delegate"]; } @catch (NSException *e) {}
			NSString *toUser = nil;
			if (delegate) {
				@try { toUser = [delegate valueForKey:@"m_nsUsrName"]; } @catch (NSException *e) {}
				if (!toUser) {
					@try {
						id contact = [delegate valueForKey:@"m_contact"];
						toUser = [contact valueForKey:@"m_nsUsrName"];
					} @catch (NSException *e) {}
				}
			}

			if (toUser.length > 0) {
				BOOL sent = [[WBVoiceForwardManager sharedManager] sendFavAudioItem:item toUser:toUser];
				if (sent) {
					[self dismissViewControllerAnimated:YES completion:nil];
					return;
				}
			}
		}
	}

	%orig;
}

%end

%ctor {
	%init;
	NSLog(@"[WeChatRedEnvelop] ===== WeChatRedEnvelop Tweak Successfully Injected & Initialized (Bundle: %@) =====", [[NSBundle mainBundle] bundleIdentifier]);
}
