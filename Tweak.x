#import <UIKit/UIKit.h>

// ====== 1. 声明转转的网络请求类 ======
@interface ZZInfoDetailRequestModel : NSObject
@property (copy, nonatomic) NSString *infoID;
@property (nonatomic) unsigned long long from;
@property (copy, nonatomic) NSString *pageType;
@end

@interface ZZInfoDetailProxy : NSObject
- (void)requestInfoDetailDatas:(id)a0 success:(void(^)(id response))a1 failure:(void(^)(id error))a2;
@end

// ====== 2. 声明列表控制器 ======
@interface ZZListingAprilViewController : UIViewController
@property (retain, nonatomic) NSArray *dataArray;
- (void)loadData;

// 自定义方法声明
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_fetchDetailAndFilterWithVersion:(NSString *)version;
- (BOOL)custom_safeMatchObject:(id)obj target:(NSString *)target;
- (NSString *)custom_extractInfoId:(id)obj;
- (void)custom_pruneArray:(NSMutableArray *)array matchedIds:(NSSet *)matchedIds removedCount:(int *)removedCount;
- (void)custom_reloadCollectionView;
@end


%hook ZZListingAprilViewController

- (void)viewDidLoad {
    %orig;
    
    // 注入双指长按手势
    UILongPressGestureRecognizer *twoFingerLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(custom_twoFingerLongPress:)];
    twoFingerLongPress.numberOfTouchesRequired = 2; // 双指
    twoFingerLongPress.minimumPressDuration = 1.0;  // 长按 1 秒
    [self.view addGestureRecognizer:twoFingerLongPress];
}

%new
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"系统版本深层检索" 
                                                                       message:@"请输入想筛选的iOS版本\n(已修复闪退，启用网络强驻留并发模式)" 
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
    NSArray *currentData = self.dataArray;
    if (!currentData || currentData.count == 0) {
        UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"提示" message:@"列表暂无数据，请向下滑动加载或刷新后再试" preferredStyle:UIAlertControllerStyleAlert];
        [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:emptyAlert animated:YES completion:nil];
        return;
    }
    
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在静默拉取..." 
                                                                          message:@"后台正在并发安全拉取详情，请稍候..." 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSLock *lock = [[NSLock alloc] init];
    
    // ====== 核心修复1：强引用网络代理，防止请求被提前销毁 ======
    NSMutableArray *retainedProxies = [NSMutableArray array];
    
    __block int localMatchCount = 0;
    __block int netMatchCount = 0;
    __block int netFailCount = 0;
    __block int totalScanned = 0;
    
    // 目标处理 (去空格 + 全小写)
    NSString *target = [[version lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    // 递归提取屏幕上存在的所有商品 ID
    NSMutableArray *allNodes = [NSMutableArray arrayWithObject:currentData];
    NSMutableSet *allIdsToFetch = [NSMutableSet set];
    
    while (allNodes.count > 0) {
        id node = allNodes.firstObject;
        [allNodes removeObjectAtIndex:0];
        
        if ([node isKindOfClass:[NSArray class]]) {
            [allNodes addObjectsFromArray:(NSArray *)node];
        } else {
            // 尝试找 itemsArray (ZZFLEX 的 Section 结构)
            @try {
                if ([node respondsToSelector:NSSelectorFromString(@"itemsArray")]) {
                    id items = [node valueForKey:@"itemsArray"];
                    if ([items isKindOfClass:[NSArray class]]) {
                        [allNodes addObjectsFromArray:(NSArray *)items];
                    }
                }
            } @catch(...) {}
            
            // 提取真正的商品 ID
            NSString *infoId = [self custom_extractInfoId:node];
            if (infoId && infoId.length > 5) {
                [allIdsToFetch addObject:infoId];
                totalScanned++;
                
                // 本地安全匹配 (极速)
                if ([self custom_safeMatchObject:node target:target]) {
                    [matchedInfoIds addObject:infoId];
                    localMatchCount++;
                }
            }
        }
    }
    
    // 遍历没有在本地搜到的 ID，发起网络请求
    for (NSString *infoId in allIdsToFetch) {
        if ([matchedInfoIds containsObject:infoId]) continue; // 本地命中的不再发请求
        
        dispatch_group_enter(group);
        
        ZZInfoDetailRequestModel *reqModel = [[NSClassFromString(@"ZZInfoDetailRequestModel") alloc] init];
        [reqModel setValue:infoId forKey:@"infoID"]; // 注意：头文件里大写的 ID
        [reqModel setValue:@(1) forKey:@"from"];
        [reqModel setValue:@"1" forKey:@"pageType"];
        
        id proxy = [[NSClassFromString(@"ZZInfoDetailProxy") alloc] init];
        if (proxy) {
            [retainedProxies addObject:proxy]; // 必须强引用！
        }
        
        if ([proxy respondsToSelector:NSSelectorFromString(@"requestInfoDetailDatas:success:failure:")]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [proxy requestInfoDetailDatas:reqModel success:^(id response) {
                // 网络详情返回后，进行安全匹配
                if ([self custom_safeMatchObject:response target:target]) {
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
    }
    
    __weak typeof(self) weakSelf = self;
    
    // 等待所有网络请求完成
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [loadingAlert dismissViewControllerAnimated:YES completion:^{
            
            // ====== 核心修复2：原地修剪内存树 ======
            int removedCount = 0;
            NSMutableArray *mutDataArray = [weakSelf.dataArray mutableCopy];
            [weakSelf custom_pruneArray:mutDataArray matchedIds:matchedInfoIds removedCount:&removedCount];
            weakSelf.dataArray = mutDataArray;
            
            // 强制刷新屏幕视图
            [weakSelf custom_reloadCollectionView];
            
            // 释放网络代理对象
            [retainedProxies removeAllObjects];
            
            if (matchedInfoIds.count > 0) {
                NSString *resultMsg = [NSString stringWithFormat:@"扫描总数: %d\n本地匹配: %d 个\n详情拉取: %d 个\n网络失败: %d 个\n已剔除不符商品: %d 个", totalScanned, localMatchCount, netMatchCount, netFailCount, removedCount];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"完美" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:successAlert animated:YES completion:nil];
            } else {
                NSString *resultMsg = [NSString stringWithFormat:@"扫描总数: %d\n网络失败: %d 个\n\n已深层验证所有商品及详情参数，均未发现该版本！请下滑加载更多后重试。", totalScanned, netFailCount];
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"未找到相关商品" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

// ====== 动态树形修剪器 (原地把不包含该版本的商品干掉) ======
%new
- (void)custom_pruneArray:(NSMutableArray *)array matchedIds:(NSSet *)matchedIds removedCount:(int *)removedCount {
    for (NSInteger i = array.count - 1; i >= 0; i--) {
        id item = array[i];
        
        // 1. 如果它是 Section 分组，向下钻取它的 itemsArray
        if ([item respondsToSelector:NSSelectorFromString(@"itemsArray")]) {
            @try {
                id items = [item valueForKey:@"itemsArray"];
                if ([items isKindOfClass:[NSMutableArray class]]) {
                    [self custom_pruneArray:items matchedIds:matchedIds removedCount:removedCount];
                } else if ([items isKindOfClass:[NSArray class]]) {
                    // 转成可变数组后修剪
                    NSMutableArray *mutItems = [(NSArray *)items mutableCopy];
                    [self custom_pruneArray:mutItems matchedIds:matchedIds removedCount:removedCount];
                    [item setValue:mutItems forKey:@"itemsArray"];
                }
            } @catch(...) {}
            continue;
        }
        
        // 2. 如果是嵌套数组，继续钻取
        if ([item isKindOfClass:[NSMutableArray class]]) {
            [self custom_pruneArray:item matchedIds:matchedIds removedCount:removedCount];
            continue;
        }
        
        // 3. 叶子节点：它是商品！提取它的 infoId
        NSString *infoId = [self custom_extractInfoId:item];
        if (infoId && infoId.length > 5) {
            // 如果这个商品不在我们匹配成功的列表里，彻底从内存中抹除！
            if (![matchedIds containsObject:infoId]) {
                [array removeObjectAtIndex:i];
                (*removedCount)++;
            }
        }
    }
}

// ====== 纯净安全匹配器 (绝不触发死循环闪退) ======
%new
- (BOOL)custom_safeMatchObject:(id)obj target:(NSString *)target {
    if (!obj) return NO;
    
    @try {
        // 1. 直奔主题：提取详情里的 param 数组（最精确的验机参数所在位置）
        if ([obj respondsToSelector:NSSelectorFromString(@"param")]) {
            id paramArr = [obj valueForKey:@"param"];
            if ([paramArr isKindOfClass:[NSArray class]]) {
                for (id pItem in (NSArray *)paramArr) {
                    if ([pItem respondsToSelector:NSSelectorFromString(@"paramValue")]) {
                        id pVal = [pItem valueForKey:@"paramValue"];
                        if ([pVal isKindOfClass:[NSString class]]) {
                            NSString *cleanVal = [[(NSString *)pVal lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
                            if ([cleanVal containsString:target]) return YES;
                        }
                    }
                }
            }
        }
        
        // 2. 检查可能包含文案的安全属性 (不进行任何对象遍历，绝对防闪退)
        NSArray *safeKeys = @[@"title", @"desc", @"content", @"sellerDescription", 
                              @"extendJson", @"userInfoLabelText", @"userCateLabelDesc", 
                              @"priceDesc", @"subTitle", @"detail"];
        for (NSString *key in safeKeys) {
            if ([obj respondsToSelector:NSSelectorFromString(key)]) {
                id val = [obj valueForKey:key];
                if ([val isKindOfClass:[NSString class]]) {
                    NSString *cleanVal = [[(NSString *)val lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
                    if ([cleanVal containsString:target]) return YES;
                } else if ([val isKindOfClass:[NSAttributedString class]]) {
                    // 支持富文本解析
                    NSString *rawStr = [(NSAttributedString *)val string];
                    if (rawStr) {
                        NSString *cleanVal = [[rawStr lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
                        if ([cleanVal containsString:target]) return YES;
                    }
                }
            }
        }
        
        // 3. 安全解析嵌套的内部模型壳子
        NSArray *wrapperKeys = @[@"dataModel", @"feedModel"];
        for (NSString *key in wrapperKeys) {
            if ([obj respondsToSelector:NSSelectorFromString(key)]) {
                id innerObj = [obj valueForKey:key];
                if (innerObj && innerObj != obj) {
                    if ([self custom_safeMatchObject:innerObj target:target]) return YES;
                }
            }
        }
    } @catch (...) {}
    
    return NO;
}

// ====== 智能商品 ID 提取器 ======
%new
- (NSString *)custom_extractInfoId:(id)obj {
    if (!obj) return nil;
    @try {
        if ([obj respondsToSelector:NSSelectorFromString(@"infoId")]) {
            id val = [obj valueForKey:@"infoId"];
            if ([val isKindOfClass:[NSString class]]) return val;
            if ([val isKindOfClass:[NSNumber class]]) return [(NSNumber *)val stringValue];
        }
        if ([obj respondsToSelector:NSSelectorFromString(@"infoID")]) {
            id val = [obj valueForKey:@"infoID"];
            if ([val isKindOfClass:[NSString class]]) return val;
            if ([val isKindOfClass:[NSNumber class]]) return [(NSNumber *)val stringValue];
        }
        // 如果外面包了一层大壳子，直接钻进去拿
        NSArray *wrappers = @[@"dataModel", @"feedModel", @"itemModel", @"searchResult"];
        for (NSString *key in wrappers) {
            if ([obj respondsToSelector:NSSelectorFromString(key)]) {
                id inner = [obj valueForKey:key];
                if (inner && inner != obj) return [self custom_extractInfoId:inner];
            }
        }
    } @catch(...) {}
    return nil;
}

// 暴力刷新视图
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
