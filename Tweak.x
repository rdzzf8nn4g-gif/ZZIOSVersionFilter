#import <UIKit/UIKit.h>
#import <objc/runtime.h> // 引入 Objective-C 运行时机制

// ====== 1. 声明转转的网络请求类 ======
@interface ZZInfoDetailRequestModel : NSObject
@property (copy, nonatomic) NSString *infoID;
@property (nonatomic) unsigned long long from;
@property (copy, nonatomic) NSString *pageType;
@end

@interface ZZGoodsDetailProxy : NSObject
- (void)requestGoodsDetailDateWithRequestModel:(id)a0 success:(void(^)(id response))a1 failure:(void(^)(id error))a2;
@end

@interface ZZInfoDetailProxy : NSObject
- (void)requestInfoDetailDatas:(id)a0 success:(void(^)(id response))a1 failure:(void(^)(id error))a2;
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

// 自定义方法
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_fetchDetailAndFilterWithVersion:(NSString *)version;
- (void)custom_findInfoIdsInObject:(id)obj intoSet:(NSMutableSet *)set visited:(NSMutableSet *)visited;
- (BOOL)custom_safeDeepSearch:(id)obj target:(NSString *)target visited:(NSMutableSet *)visited depth:(int)depth;
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
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"系统版本运行时检索" 
                                                                       message:@"请输入想筛选的iOS版本\n(将使用 Runtime 级深度透视与双路 API 并发)" 
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
    // 1. 递归提取所有 infoId
    NSMutableSet *infoIds = [NSMutableSet set];
    NSMutableSet *visited = [NSMutableSet set];
    
    [self custom_findInfoIdsInObject:self.firstPageResponseData intoSet:infoIds visited:visited];
    [self custom_findInfoIdsInObject:self.lastPageResponseData intoSet:infoIds visited:visited];
    [self custom_findInfoIdsInObject:self.dataArray intoSet:infoIds visited:visited];
    
    if (infoIds.count == 0) {
        UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"提取失败" message:@"未能在页面内识别到任何商品 ID" preferredStyle:UIAlertControllerStyleAlert];
        [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:emptyAlert animated:YES completion:nil];
        return;
    }
    
    // 2. 弹出处理中提示
    NSString *loadingMsg = [NSString stringWithFormat:@"已识别 %lu 个商品\n后台正在双路 API 并发拉取并进行 Runtime 透视...", (unsigned long)infoIds.count];
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"静默执行中" 
                                                                          message:loadingMsg 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSLock *lock = [[NSLock alloc] init];
    
    __block int netMatchCount = 0;
    __block int netFailCount = 0;
    __block NSString *sampleServerResponse = @""; // 截获服务器原始数据
    
    // 版本号处理 (去空格 + 全小写)
    NSString *target = [[version lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    // 3. 遍历发请求
    for (NSString *infoId in infoIds) {
        ZZInfoDetailRequestModel *reqModel = [[NSClassFromString(@"ZZInfoDetailRequestModel") alloc] init];
        [reqModel setValue:infoId forKey:@"infoID"];
        [reqModel setValue:@(1) forKey:@"from"];
        [reqModel setValue:@"1" forKey:@"pageType"];
        
        // 路线A：ZZGoodsDetailProxy (针对验机精品)
        dispatch_group_enter(group);
        id proxyA = [[NSClassFromString(@"ZZGoodsDetailProxy") alloc] init];
        if ([proxyA respondsToSelector:NSSelectorFromString(@"requestGoodsDetailDateWithRequestModel:success:failure:")]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [proxyA requestGoodsDetailDateWithRequestModel:reqModel success:^(id response) {
                // 抓取第一个请求的服务器返回样本用于调试
                if (sampleServerResponse.length == 0 && response) {
                    @try {
                        NSString *dump = [NSString stringWithFormat:@"%@", response];
                        [lock lock];
                        sampleServerResponse = dump.length > 300 ? [dump substringToIndex:300] : dump;
                        [lock unlock];
                    } @catch(...) {}
                }
                
                // Runtime 极深透视
                NSMutableSet *scanVisited = [NSMutableSet set];
                if ([self custom_safeDeepSearch:response target:target visited:scanVisited depth:0]) {
                    [lock lock];
                    [matchedInfoIds addObject:infoId];
                    netMatchCount++;
                    [lock unlock];
                }
                dispatch_group_leave(group);
            } failure:^(id error) {
                [lock lock]; netFailCount++; [lock unlock];
                dispatch_group_leave(group);
            }];
            #pragma clang diagnostic pop
        } else {
            dispatch_group_leave(group);
        }
        
        // 路线B：ZZInfoDetailProxy (针对个人C2C)
        dispatch_group_enter(group);
        id proxyB = [[NSClassFromString(@"ZZInfoDetailProxy") alloc] init];
        if ([proxyB respondsToSelector:NSSelectorFromString(@"requestInfoDetailDatas:success:failure:")]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [proxyB requestInfoDetailDatas:reqModel success:^(id response) {
                NSMutableSet *scanVisited = [NSMutableSet set];
                if ([self custom_safeDeepSearch:response target:target visited:scanVisited depth:0]) {
                    [lock lock];
                    [matchedInfoIds addObject:infoId];
                    netMatchCount++;
                    [lock unlock];
                }
                dispatch_group_leave(group);
            } failure:^(id error) {
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
            
            // 数据源替换方法
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
                            
                            if (iId && [matchedInfoIds containsObject:iId]) {
                                [filtered addObject:item];
                            }
                        }
                        [respData setValue:filtered forKey:@"infos"];
                    }
                } @catch(NSException *e){}
            };
            
            filterResponseData(weakSelf.firstPageResponseData);
            filterResponseData(weakSelf.lastPageResponseData);
            
            if (matchedInfoIds.count > 0) {
                if ([weakSelf respondsToSelector:NSSelectorFromString(@"reloadListingGoodsWithRespModel:")]) {
                    #pragma clang diagnostic push
                    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
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
                // 如果是 0 个匹配，直接把服务器返回的数据打印在弹窗上，用于究极诊断！
                NSString *resultMsg = [NSString stringWithFormat:@"扫描商品: %lu个\n匹配: 0个\n失败: %d个\n\n【服务器返回截取】:\n%@", (unsigned long)infoIds.count, netFailCount, sampleServerResponse.length > 0 ? sampleServerResponse : @"无数据返回(可能被拦截)"];
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"筛选结果为空" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

// ====== Runtime 级全属性终极提取器 (绝对防闪退) ======
%new
- (BOOL)custom_safeDeepSearch:(id)obj target:(NSString *)target visited:(NSMutableSet *)visited depth:(int)depth {
    if (!obj || depth > 5) return NO; // 限制深度为 5，杜绝爆栈
    
    // 防循环引用验证
    NSValue *ptr = [NSValue valueWithNonretainedObject:obj];
    if ([visited containsObject:ptr]) return NO;
    [visited addObject:ptr];
    
    // 字符串直接匹配
    if ([obj isKindOfClass:[NSString class]]) {
        NSString *cleanStr = [[(NSString *)obj lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
        if ([cleanStr containsString:target]) return YES;
        return NO;
    }
    
    // 数字类型
    if ([obj isKindOfClass:[NSNumber class]]) {
        return [[(NSNumber *)obj stringValue] containsString:target];
    }
    
    // 数组类型
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) {
            if ([self custom_safeDeepSearch:item target:target visited:visited depth:depth+1]) return YES;
        }
        return NO;
    }
    
    // 字典类型
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id key in (NSDictionary *)obj) {
            if ([self custom_safeDeepSearch:[(NSDictionary *)obj objectForKey:key] target:target visited:visited depth:depth+1]) return YES;
        }
        return NO;
    }
    
    // ====== Objective-C Runtime 动态遍历自定义对象的一切属性 ======
    unsigned int outCount, i;
    objc_property_t *properties = class_copyPropertyList([obj class], &outCount);
    if (properties) {
        for (i = 0; i < outCount; i++) {
            objc_property_t property = properties[i];
            const char *propName = property_getName(property);
            if(propName) {
                NSString *propertyName = [NSString stringWithUTF8String:propName];
                @try {
                    id val = [obj valueForKey:propertyName];
                    if (val) {
                        if ([self custom_safeDeepSearch:val target:target visited:visited depth:depth+1]) {
                            free(properties);
                            return YES;
                        }
                    }
                } @catch (NSException *e) {}
            }
        }
        free(properties);
    }
    
    return NO;
}

// ====== 万能 ID 提取剥洋葱法 ======
%new
- (void)custom_findInfoIdsInObject:(id)obj intoSet:(NSMutableSet *)set visited:(NSMutableSet *)visited {
    if (!obj || [visited containsObject:[NSValue valueWithNonretainedObject:obj]]) return;
    [visited addObject:[NSValue valueWithNonretainedObject:obj]];
    
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) [self custom_findInfoIdsInObject:item intoSet:set visited:visited];
        return;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id key in (NSDictionary *)obj) [self custom_findInfoIdsInObject:[(NSDictionary *)obj objectForKey:key] intoSet:set visited:visited];
        return;
    }
    
    @try {
        NSString *iId = nil;
        if ([obj respondsToSelector:NSSelectorFromString(@"infoId")]) iId = [[obj valueForKey:@"infoId"] description];
        else if ([obj respondsToSelector:NSSelectorFromString(@"infoID")]) iId = [[obj valueForKey:@"infoID"] description];
        
        if (iId.length > 8 && [iId longLongValue] > 0) [set addObject:iId];
    } @catch(NSException *e){}
    
    NSArray *keys = @[@"infos", @"viewItems", @"searchResult", @"dataModel", @"feedModel", @"itemModel"];
    for (NSString *key in keys) {
        @try {
            if ([obj respondsToSelector:NSSelectorFromString(key)]) {
                id val = [obj valueForKey:key];
                if (val) [self custom_findInfoIdsInObject:val intoSet:set visited:visited];
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
