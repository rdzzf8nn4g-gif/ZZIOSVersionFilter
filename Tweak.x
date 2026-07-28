#import <UIKit/UIKit.h>

// ====== 1. 声明转转真实的网络请求类 ======
@interface ZZInfoDetailRequestModel : NSObject
@property (copy, nonatomic) NSString *infoID;
@property (nonatomic) unsigned long long from;
@property (copy, nonatomic) NSString *pageType;
@end

@interface ZZGoodsDetailProxy : NSObject
- (void)requestGoodsDetailDateWithRequestModel:(id)a0 success:(void(^)(id response))a1 failure:(void(^)(id error))a2;
@end

@interface ZZListingResponseModel : NSObject
@property (retain, nonatomic) NSMutableArray *infos;
@end

// ====== 2. 声明列表控制器 ======
@interface ZZListingAprilViewController : UIViewController
@property (retain, nonatomic) NSArray *dataArray;
@property (retain, nonatomic) ZZListingResponseModel *firstPageResponseData;
@property (retain, nonatomic) ZZListingResponseModel *lastPageResponseData;

- (void)loadData;
- (void)reloadListingGoodsWithRespModel:(id)arg;

// 我们的自定义方法
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_fetchDetailAndFilterWithVersion:(NSString *)version;
- (void)custom_findInfoIdsInObject:(id)obj intoSet:(NSMutableSet *)set visited:(NSMutableSet *)visited;
- (void)custom_reloadCollectionView;
@end


%hook ZZListingAprilViewController

- (void)viewDidLoad {
    %orig;
    
    // 注入双指长按手势
    UILongPressGestureRecognizer *twoFingerLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(custom_twoFingerLongPress:)];
    twoFingerLongPress.numberOfTouchesRequired = 2; // 需要双指
    twoFingerLongPress.minimumPressDuration = 1.0;  // 长按 1 秒
    [self.view addGestureRecognizer:twoFingerLongPress];
}

%new
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"系统版本深度检索" 
                                                                       message:@"请输入想筛选的iOS版本\n(将在后台静默拉取详情页参数)" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.placeholder = @"输入版本号 (如: 15.4、16)";
            textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
            textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        
        __weak typeof(self) weakSelf = self;
        UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"开始筛选" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSString *versionText = alert.textFields.firstObject.text;
            if (versionText.length > 0) {
                [weakSelf custom_fetchDetailAndFilterWithVersion:versionText];
            }
        }];
        
        UIAlertAction *resetAction = [UIAlertAction actionWithTitle:@"重置列表" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            if ([weakSelf respondsToSelector:@selector(loadData)]) {
                [weakSelf performSelector:@selector(loadData)];
            }
        }];
        
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
        
        [alert addAction:confirmAction];
        [alert addAction:resetAction];
        [alert addAction:cancelAction];
        
        [self presentViewController:alert animated:YES completion:nil];
    }
}

%new
- (void)custom_fetchDetailAndFilterWithVersion:(NSString *)version {
    // 1. 深度递归提取当前屏幕上所有的商品 ID (infoId)
    NSMutableSet *infoIds = [NSMutableSet set];
    NSMutableSet *visited = [NSMutableSet set];
    
    [self custom_findInfoIdsInObject:self.firstPageResponseData intoSet:infoIds visited:visited];
    [self custom_findInfoIdsInObject:self.lastPageResponseData intoSet:infoIds visited:visited];
    [self custom_findInfoIdsInObject:self.dataArray intoSet:infoIds visited:visited];
    
    if (infoIds.count == 0) {
        UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"提取失败" message:@"未能在当前页面识别到任何商品，请向下滑动加载或刷新后再试。" preferredStyle:UIAlertControllerStyleAlert];
        [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:emptyAlert animated:YES completion:nil];
        return;
    }
    
    // 2. 告诉用户提取到了多少个，准备开始网络请求
    NSString *loadingMsg = [NSString stringWithFormat:@"已识别到 %lu 个商品\n正在后台并发拉取详情数据，请稍候...", (unsigned long)infoIds.count];
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在静默拉取" 
                                                                          message:loadingMsg 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSLock *lock = [[NSLock alloc] init];
    
    __block int netMatchCount = 0;
    __block int netFailCount = 0;
    
    // 目标版本号标准化处理 (去空格 + 全小写)
    NSString *target = [[version lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    // 3. 遍历所有的 infoId 发起真实的详情页网络请求
    for (NSString *infoId in infoIds) {
        dispatch_group_enter(group);
        
        ZZInfoDetailRequestModel *reqModel = [[NSClassFromString(@"ZZInfoDetailRequestModel") alloc] init];
        [reqModel setValue:infoId forKey:@"infoID"];
        [reqModel setValue:@(1) forKey:@"from"];
        [reqModel setValue:@"1" forKey:@"pageType"];
        
        id proxy = [[NSClassFromString(@"ZZGoodsDetailProxy") alloc] init];
        if ([proxy respondsToSelector:NSSelectorFromString(@"requestGoodsDetailDateWithRequestModel:success:failure:")]) {
            
            // 发起请求
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [proxy requestGoodsDetailDateWithRequestModel:reqModel success:^(id response) {
                BOOL isMatch = NO;
                @try {
                    // 安全提取详情页的 param 数组 (ZZGoodsDetailParamModel)
                    NSArray *params = [response valueForKey:@"param"];
                    if ([params isKindOfClass:[NSArray class]]) {
                        for (id pItem in params) {
                            NSString *pVal = [[pItem valueForKey:@"paramValue"] description];
                            if (pVal) {
                                NSString *cleanVal = [[pVal lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
                                if ([cleanVal containsString:target]) {
                                    isMatch = YES;
                                    break;
                                }
                            }
                        }
                    }
                    // 兜底：检查详情里的 title 和 content
                    if (!isMatch) {
                        NSString *title = [[response valueForKey:@"title"] description];
                        NSString *content = [[response valueForKey:@"content"] description];
                        NSString *sellerDesc = [[response valueForKey:@"sellerDescription"] description];
                        
                        if (title && [[[title lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""] containsString:target]) isMatch = YES;
                        if (content && [[[content lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""] containsString:target]) isMatch = YES;
                        if (sellerDesc && [[[sellerDesc lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""] containsString:target]) isMatch = YES;
                    }
                } @catch(NSException *e){}
                
                if (isMatch) {
                    [lock lock];
                    [matchedInfoIds addObject:infoId];
                    netMatchCount++;
                    [lock unlock];
                }
                dispatch_group_leave(group);
                
            } failure:^(id error) {
                [lock lock];
                netFailCount++;
                [lock unlock];
                dispatch_group_leave(group);
            }];
            #pragma clang diagnostic pop
            
        } else {
            dispatch_group_leave(group);
        }
    }
    
    __weak typeof(self) weakSelf = self;
    
    // 4. 所有请求结束后更新列表
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [loadingAlert dismissViewControllerAnimated:YES completion:^{
            
            // 过滤数组的内联函数，把没命中的商品从列表中剔除
            void (^filterResponseData)(id) = ^(id respData) {
                if (!respData) return;
                @try {
                    NSMutableArray *infos = [respData valueForKey:@"infos"];
                    if ([infos isKindOfClass:[NSArray class]]) {
                        NSMutableArray *filtered = [NSMutableArray array];
                        for (id item in infos) {
                            NSString *iId = nil;
                            if ([item respondsToSelector:NSSelectorFromString(@"infoId")]) iId = [[item valueForKey:@"infoId"] description];
                            else if ([item respondsToSelector:NSSelectorFromString(@"infoID")]) iId = [[item valueForKey:@"infoID"] description];
                            
                            // 只要该商品被命中，就保留它
                            if (iId && [matchedInfoIds containsObject:iId]) {
                                [filtered addObject:item];
                            }
                        }
                        [respData setValue:filtered forKey:@"infos"];
                    }
                } @catch(NSException *e){}
            };
            
            // 过滤第一页和可能存在的下一页数据
            filterResponseData(weakSelf.firstPageResponseData);
            filterResponseData(weakSelf.lastPageResponseData);
            
            // ====== 核心：通知转转框架重绘 UI ======
            if (matchedInfoIds.count > 0) {
                if ([weakSelf respondsToSelector:NSSelectorFromString(@"reloadListingGoodsWithRespModel:")]) {
                    #pragma clang diagnostic push
                    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    // 重新把过滤后的第一页数据喂给框架
                    [weakSelf performSelector:NSSelectorFromString(@"reloadListingGoodsWithRespModel:") withObject:weakSelf.firstPageResponseData];
                    #pragma clang diagnostic pop
                } else {
                    [weakSelf custom_reloadCollectionView];
                }
                
                NSString *resultMsg = [NSString stringWithFormat:@"共扫描商品: %lu 个\n成功匹配到: %d 个\n网络拉取失败: %d 个", (unsigned long)infoIds.count, netMatchCount, netFailCount];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"完美" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:successAlert animated:YES completion:nil];
                
            } else {
                NSString *resultMsg = [NSString stringWithFormat:@"共扫描商品: %lu 个\n匹配到系统版本: 0 个\n网络拉取失败: %d 个\n\n如果拉取失败较多，可能是网络拥堵。请下拉加载更多后重试。", (unsigned long)infoIds.count, netFailCount];
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"筛选结果为空" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

// ====== 万能 ID 提取器 (通过深度遍历剥洋葱，解决嵌套太深找不到 ID 的问题) ======
%new
- (void)custom_findInfoIdsInObject:(id)obj intoSet:(NSMutableSet *)set visited:(NSMutableSet *)visited {
    if (!obj || [visited containsObject:[NSValue valueWithNonretainedObject:obj]]) return;
    [visited addObject:[NSValue valueWithNonretainedObject:obj]];
    
    // 如果是数组
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) {
            [self custom_findInfoIdsInObject:item intoSet:set visited:visited];
        }
        return;
    }
    
    // 如果是字典
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id key in (NSDictionary *)obj) {
            [self custom_findInfoIdsInObject:[(NSDictionary *)obj objectForKey:key] intoSet:set visited:visited];
        }
        return;
    }
    
    // 尝试提取 infoId
    @try {
        NSString *iId = nil;
        if ([obj respondsToSelector:NSSelectorFromString(@"infoId")]) {
            iId = [[obj valueForKey:@"infoId"] description];
        } else if ([obj respondsToSelector:NSSelectorFromString(@"infoID")]) {
            iId = [[obj valueForKey:@"infoID"] description];
        }
        
        // 过滤掉误判的短字符串，转转的 infoId 一般是一长串数字
        if (iId.length > 8 && [iId longLongValue] > 0) {
            [set addObject:iId];
        }
    } @catch(NSException *e){}
    
    // 如果没提取到，继续往底层壳子钻
    NSArray *keys = @[@"infos", @"viewItems", @"searchResult", @"dataModel", @"feedModel", @"itemModel"];
    for (NSString *key in keys) {
        @try {
            if ([obj respondsToSelector:NSSelectorFromString(key)]) {
                id val = [obj valueForKey:key];
                if (val) {
                    [self custom_findInfoIdsInObject:val intoSet:set visited:visited];
                }
            }
        } @catch(NSException *e){}
    }
}

// 暴力刷新视图兜底方法
%new
- (void)custom_reloadCollectionView {
    NSMutableArray *queue = [NSMutableArray arrayWithObject:self.view];
    while (queue.count > 0) {
        UIView *currentView = queue.firstObject;
        [queue removeObjectAtIndex:0];
        
        if ([currentView isKindOfClass:[UICollectionView class]]) [(UICollectionView *)currentView reloadData];
        else if ([currentView isKindOfClass:[UITableView class]]) [(UITableView *)currentView reloadData];
        
        [queue addObjectsFromArray:currentView.subviews];
    }
}

%end
