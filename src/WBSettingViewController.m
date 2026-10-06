//
//  WBSettingViewController.m
//  WeChatRedEnvelop
//
//  Created by 杨志超 on 2017/2/22.
//  Copyright © 2017年 swiftyper. All rights reserved.
//

#import "WBSettingViewController.h"
#import "WeChatRedEnvelop.h"
#import "WBRedEnvelopConfig.h"
#import <objc/runtime.h>
#import <objc/message.h>

static NSString * const kTargetOfficialAccountID = @"gh_f6f23c83eb65";

@interface WBSettingViewController () <MultiSelectContactsViewControllerDelegate>

@property (nonatomic, strong) WCTableViewManager *tableViewMgr;

@end

@implementation WBSettingViewController

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        _tableViewMgr = [[objc_getClass("WCTableViewManager") alloc] initWithFrame:[UIScreen mainScreen].bounds style:UITableViewStyleGrouped];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self initTitle];
    [self reloadTableData];
    

    MMTableView *tableView = [self.tableViewMgr getTableView];
    if (@available(iOS 11, *)) {
        tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    }
    [self.view addSubview:tableView];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
    [self stopLoading];
}

- (void)initTitle {
    self.title = @"微信小助手";
}

- (void)reloadTableData {
    [self.tableViewMgr clearAllSection];
    
    [self addBasicSettingSection];
    [self addSupportSection];
    [self addAdvanceSettingSection];    
    
    MMTableView *tableView = [self.tableViewMgr getTableView];
    [tableView reloadData];
}

#pragma mark - BasicSetting

- (void)addBasicSettingSection {
    WCTableViewSectionManager *sectionInfo = [objc_getClass("WCTableViewSectionManager") sectionInfoDefaut];
    
    [sectionInfo addCell:[self createAutoReceiveRedEnvelopCell]];
    [sectionInfo addCell:[self createDelaySettingCell]];
    
    [self.tableViewMgr addSection:sectionInfo];
}

- (WCTableViewCellManager *)createAutoReceiveRedEnvelopCell {
    return [objc_getClass("WCTableViewCellManager") switchCellForSel:@selector(switchRedEnvelop:) target:self title:@"自动抢红包" on:[WBRedEnvelopConfig sharedConfig].autoReceiveEnable];
}

- (WCTableViewNormalCellManager *)createDelaySettingCell {
    NSInteger delaySeconds = [WBRedEnvelopConfig sharedConfig].delaySeconds;
    NSString *delayString = delaySeconds == 0 ? @"不延迟" : [NSString stringWithFormat:@"%ld 秒", (long)delaySeconds];
    
    WCTableViewNormalCellManager *cellInfo = nil;
    if ([WBRedEnvelopConfig sharedConfig].autoReceiveEnable) {
        cellInfo = [objc_getClass("WCTableViewNormalCellManager") normalCellForSel:@selector(settingDelay) target:self title:@"延迟抢红包" rightValue:delayString accessoryType:1];
    } else {
        cellInfo = [objc_getClass("WCTableViewNormalCellManager") normalCellForTitle:@"延迟抢红包" rightValue: @"抢红包已关闭"];
    }
    return cellInfo;
}

- (void)switchRedEnvelop:(UISwitch *)envelopSwitch {
    [WBRedEnvelopConfig sharedConfig].autoReceiveEnable = envelopSwitch.on;
    
    [self reloadTableData];
}

- (void)settingDelay {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"延迟抢红包(秒)" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"延迟时长";
        textField.keyboardType = UIKeyboardTypeNumberPad;
        if ([WBRedEnvelopConfig sharedConfig].delaySeconds > 0) {
            textField.text = [NSString stringWithFormat:@"%ld", (long)[WBRedEnvelopConfig sharedConfig].delaySeconds];
        }
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UITextField *textField = alert.textFields.firstObject;
        NSInteger delaySeconds = [textField.text integerValue];
        [WBRedEnvelopConfig sharedConfig].delaySeconds = delaySeconds;
        [self reloadTableData];
    }];
    
    [alert addAction:cancelAction];
    [alert addAction:confirmAction];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - ProSetting
- (void)addAdvanceSettingSection {
    WCTableViewSectionManager *sectionInfo = [objc_getClass("WCTableViewSectionManager") sectionInfoHeader:@"高级功能"];
    
    [sectionInfo addCell:[self createReceiveSelfRedEnvelopCell]];
    [sectionInfo addCell:[self createQueueCell]];
    [sectionInfo addCell:[self createAbortRemokeMessageCell]];
    [sectionInfo addCell:[self createVoiceForwardCell]];
    [sectionInfo addCell:[self createFavVoiceForwardCell]];
    [sectionInfo addCell:[self createBlackListCell]];
    
    [self.tableViewMgr addSection:sectionInfo];
}

- (WCTableViewCellManager *)createReceiveSelfRedEnvelopCell {
    return [objc_getClass("WCTableViewCellManager") switchCellForSel:@selector(settingReceiveSelfRedEnvelop:) target:self title:@"抢自己发的红包" on:[WBRedEnvelopConfig sharedConfig].receiveSelfRedEnvelop];
}

- (WCTableViewCellManager *)createQueueCell {
    return [objc_getClass("WCTableViewCellManager") switchCellForSel:@selector(settingReceiveByQueue:) target:self title:@"防止同时抢多个红包" on:[WBRedEnvelopConfig sharedConfig].serialReceive];
}

- (WCTableViewCellManager *)createVoiceForwardCell {
    return [objc_getClass("WCTableViewCellManager") switchCellForSel:@selector(settingVoiceForward:) target:self title:@"语音消息一键转发" on:[WBRedEnvelopConfig sharedConfig].voiceForwardEnable];
}

- (void)settingVoiceForward:(UISwitch *)voiceSwitch {
    [WBRedEnvelopConfig sharedConfig].voiceForwardEnable = voiceSwitch.on;
}

- (WCTableViewCellManager *)createFavVoiceForwardCell {
    return [objc_getClass("WCTableViewCellManager") switchCellForSel:@selector(settingFavVoiceForward:) target:self title:@"转发微信收藏语音" on:[WBRedEnvelopConfig sharedConfig].favVoiceForwardEnable];
}

- (void)settingFavVoiceForward:(UISwitch *)favSwitch {
    [WBRedEnvelopConfig sharedConfig].favVoiceForwardEnable = favSwitch.on;
}

- (WCTableViewCellManager *)createBlackListCell {
    
    if ([WBRedEnvelopConfig sharedConfig].blackList.count == 0) {
        return [objc_getClass("WCTableViewNormalCellManager") normalCellForSel:@selector(showBlackList) target:self title:@"群聊过滤" rightValue:@"已关闭" accessoryType:1];
    } else {
        NSString *blackListCountStr = [NSString stringWithFormat:@"已选 %lu 个群", (unsigned long)[WBRedEnvelopConfig sharedConfig].blackList.count];
        return [objc_getClass("WCTableViewNormalCellManager") normalCellForSel:@selector(showBlackList) target:self title:@"群聊过滤" rightValue:blackListCountStr accessoryType:1];
    }
    
}

- (WCTableViewSectionManager *)createAbortRemokeMessageCell {
    return [objc_getClass("WCTableViewCellManager") switchCellForSel:@selector(settingMessageRevoke:) target:self title:@"消息防撤回" on:[WBRedEnvelopConfig sharedConfig].revokeEnable];
}

- (void)settingReceiveSelfRedEnvelop:(UISwitch *)receiveSwitch {
    [WBRedEnvelopConfig sharedConfig].receiveSelfRedEnvelop = receiveSwitch.on;
}

- (void)settingReceiveByQueue:(UISwitch *)queueSwitch {
    [WBRedEnvelopConfig sharedConfig].serialReceive = queueSwitch.on;
}

- (void)showBlackList {
    MultiSelectContactsViewController *contactsViewController = [[objc_getClass("MultiSelectContactsViewController") alloc] init];
    contactsViewController.m_scene = 5;
    contactsViewController.m_delegate = self;

    // 强制触发 viewDidLoad 调用
    if ([contactsViewController respondsToSelector:@selector(loadViewIfNeeded)]) {
        [contactsViewController loadViewIfNeeded];
    } else {
        contactsViewController.view.alpha = 1.0;
    }

    CContactMgr *contactMgr = GetWeChatService(objc_getClass("CContactMgr"));
        
    ContactSelectView *selectView = (ContactSelectView *)[contactsViewController valueForKey:@"m_selectView"];
    for (NSString *contactName in [WBRedEnvelopConfig sharedConfig].blackList) {
        CContact *contact = [contactMgr getContactByName:contactName];
        [selectView addSelect:contact];
    }
    [contactsViewController updatePanelBtn];

    MMUINavigationController *navigationController = [[objc_getClass("MMUINavigationController") alloc] initWithRootViewController:contactsViewController];

    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)settingMessageRevoke:(UISwitch *)revokeSwitch {
    [WBRedEnvelopConfig sharedConfig].revokeEnable = revokeSwitch.on;
}

#pragma mark - Support
- (void)addSupportSection {
    WCTableViewSectionManager *sectionInfo = [objc_getClass("WCTableViewSectionManager") sectionInfoDefaut];
    
    [sectionInfo addCell:[self createWeChatPayingCell]];
    [sectionInfo addCell:[self createOfficalAccountCell]];
    
    [self.tableViewMgr addSection:sectionInfo];
}

- (WCTableViewNormalCellManager *)createWeChatPayingCell {
    return [objc_getClass("WCTableViewNormalCellManager") normalCellForSel:@selector(payingToAuthor) target:self title:@"微信打赏" rightValue:@"支持作者开发" accessoryType:1];
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

- (WCTableViewNormalCellManager *)createOfficalAccountCell {
    CContactMgr *contactMgr = GetWeChatService(objc_getClass("CContactMgr"));

    NSString *rightValue = @"未关注";
    if ([contactMgr respondsToSelector:@selector(isInContactList:)] && [contactMgr isInContactList:kTargetOfficialAccountID]) {
        rightValue = @"已关注";
    } else {
        rightValue = @"未关注";
        if ([contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
            CContact *contact = [contactMgr getContactForSearchByName:kTargetOfficialAccountID];
            if (contact) {
                if ([contactMgr respondsToSelector:@selector(addLocalContact:listType:)]) {
                    [contactMgr addLocalContact:contact listType:2];
                }
                if ([contactMgr respondsToSelector:@selector(getContactsFromServer:)]) {
                    [contactMgr getContactsFromServer:@[contact]];
                }
            }
        }
    }

    return [objc_getClass("WCTableViewNormalCellManager") normalCellForSel:@selector(followMyOfficalAccount) target:self title:@"ly科技服务" rightValue:rightValue accessoryType:1];
}

- (void)payingToAuthor {
    ScanQRCodeLogicParams *logicParams = [[objc_getClass("ScanQRCodeLogicParams") alloc] initWithCodeType:31 fromScene:1];
    ScanQRCodeLogicController *scanQRCodeLogic = [[objc_getClass("ScanQRCodeLogicController") alloc] initWithViewController:self logicParams:logicParams];
    
    NewQRCodeScannerParams *scannerParams = [[objc_getClass("NewQRCodeScannerParams") alloc] initWithCodeType:31];
    NewQRCodeScanner *qrCodeScanner = [[objc_getClass("NewQRCodeScanner") alloc] initWithDelegate:scanQRCodeLogic scannerParams:scannerParams];

    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"com.swiftyper.wechatredenvelop" ofType:@"bundle"];
    if (!bundlePath || ![[NSFileManager defaultManager] fileExistsAtPath:bundlePath]) {
        bundlePath = @"/var/jb/Library/MobileSubstrate/DynamicLibraries/com.swiftyper.wechatredenvelop.bundle";
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:bundlePath]) {
        bundlePath = kBundlePath;
    }

    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    NSString *imagePath = [bundle pathForResource:@"IMG_0018" ofType:@"JPG"];
    UIImage *qrImage = [UIImage imageWithContentsOfFile:imagePath];

    NSLog(@"bundle: %@, imagePath: %@, qrImage: %@", bundle, imagePath, qrImage);

    if (qrImage) {
        [self startLoadingNonBlock];
        [qrCodeScanner scanOnePicture:qrImage];
    } else {
        NSLog(@"[WeChatRedEnvelop] 未能读取到赞赏码图片: %@", imagePath);
    }
}

- (void)followMyOfficalAccount {
    CContactMgr *contactMgr = GetWeChatService(objc_getClass("CContactMgr"));

    CContact *contact = nil;
    if ([contactMgr respondsToSelector:@selector(getContactByName:)]) {
        contact = [contactMgr getContactByName:kTargetOfficialAccountID];
    }
    if (!contact && [contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
        contact = [contactMgr getContactForSearchByName:kTargetOfficialAccountID];
    }

    if (contact) {
        ContactInfoViewController *contactViewController = [[objc_getClass("ContactInfoViewController") alloc] init];
        [contactViewController setM_contact:contact];

        [self.navigationController PushViewController:contactViewController animated:YES]; 
    } else {
        if ([contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
            CContact *newContact = [contactMgr getContactForSearchByName:kTargetOfficialAccountID];
            if (newContact) {
                if ([contactMgr respondsToSelector:@selector(addLocalContact:listType:)]) {
                    [contactMgr addLocalContact:newContact listType:2];
                }
                if ([contactMgr respondsToSelector:@selector(getContactsFromServer:)]) {
                    [contactMgr getContactsFromServer:@[newContact]];
                }
                ContactInfoViewController *contactViewController = [[objc_getClass("ContactInfoViewController") alloc] init];
                [contactViewController setM_contact:newContact];
                [self.navigationController PushViewController:contactViewController animated:YES];
            }
        }
    }
}

#pragma mark - MultiSelectContactsViewControllerDelegate

- (void)onMultiSelectContactReturn:(NSArray *)arg1 {
    NSMutableArray *blackList = [NSMutableArray new];
    for (CContact *contact in arg1) {
        NSString *contactName = contact.m_nsUsrName;
        if ([contactName length] > 0 && [contactName hasSuffix:@"@chatroom"]) {
            [blackList addObject:contactName];
        }
    }
    [WBRedEnvelopConfig sharedConfig].blackList = blackList;
    [self reloadTableData];
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
