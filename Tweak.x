#import <UIKit/UIKit.h>

// 1. 声明网络请求模型
@interface ZZInfoDetailRequestModel : NSObject
@property (copy, nonatomic) NSString *infoID;
@property (nonatomic) unsigned long long from;
@property (copy, nonatomic) NSString *pageType;
@end

// 2. 声明真实详情网络请求代理类
@interface ZZGoodsDetailProxy : NSObject
- (void)requestGoodsDetailDateWithRequestModel:(id)a0 success:(void(^)(id response))a1 failure:(void(^)(id error))a2;
@end

// 3. 声明另一个可能用到的网络请求代理类
@interface ZZInfoDetailProxy : NSObject
- (void)requestInfoDetailDatas:(id)a0 success:(void(^)(id response))a1 failure:(void(^)(id error))a2;
@end

// 4. 声明转转的列表控制器
@interface ZZListingAprilViewController : UIViewController
@property (retain, nonatomic) NSArray *dataArray;
- (void)loadData;
- (void)real_reloadData:(id)arg;

// 自定义注入的方法
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_fetchDetailAndFilterWithVersion:(NSString *)version;
- (BOOL)custom_deepSearchObject:(id)obj target:(NSString *)target visited:(NSMutableSet *)visited depth:(int)depth;
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
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"系统版本深层筛选" 
                                                                       message:@"请输入想筛选的iOS版本\n(将深度解析嵌套角标标签，并自动并发拉取详情)" 
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
    
    // 弹出全局 Loading
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在静默拉取与分析..." 
                                                                          message:@"正在进行对象深层递归解析，请稍候..." 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSLock *lock = [[NSLock alloc] init];
    
    // 数据统计（用于最后的结果弹窗，让你知道系统究竟做了什么）
    __block int localMatchCount = 0;
    __block int netMatchCount = 0;
    __block int netFailCount = 0;
    
    // 对输入的版本号进行标准化处理（去空格 + 全小写），比如 "15.4"
    NSString *target = [[version lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    for (id item in currentData) {
        NSString *infoId = nil;
        @try { 
            id val = [item valueForKey:@"infoId"];
            if ([val isKindOfClass:[NSNumber class]]) infoId = [(NSNumber *)val stringValue];
            else if ([val isKindOfClass:[NSString class]]) infoId = val;
        } @catch (NSException *e) {}
        
        if (!infoId || infoId.length == 0) continue;

        // ====== 阶段一：本地安全深度递归匹配 ======
        NSMutableSet *visited = [NSMutableSet set]; // 防止死循环
        if ([self custom_deepSearchObject:item target:target visited:visited depth:0]) {
            [lock lock];
            [matchedInfoIds addObject:infoId];
            localMatchCount++;
            [lock unlock];
            continue; // 本地找到了，就不浪费时间发起网络请求了
        }

        // ====== 阶段二：本地没找到，发起静默并发详情请求 ======
        dispatch_group_enter(group);
        
        ZZInfoDetailRequestModel *reqModel = [[NSClassFromString(@"ZZInfoDetailRequestModel") alloc] init];
        reqModel.infoID = infoId;
        reqModel.from = 1; 
        reqModel.pageType = @"1";
        
        // 尝试自动识别代理类
        id proxy = nil;
        if (NSClassFromString(@"ZZGoodsDetailProxy")) {
            proxy = [[NSClassFromString(@"ZZGoodsDetailProxy") alloc] init];
        } else if (NSClassFromString(@"ZZInfoDetailProxy")) {
            proxy = [[NSClassFromString(@"ZZInfoDetailProxy") alloc] init];
        }
        
        // 发起请求
        if ([proxy respondsToSelector:@selector(requestGoodsDetailDateWithRequestModel:success:failure:)]) {
            [proxy requestGoodsDetailDateWithRequestModel:reqModel success:^(id response) {
                NSMutableSet *netVisited = [NSMutableSet set];
                if ([self custom_deepSearchObject:response target:target visited:netVisited depth:0]) {
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
        } else if ([proxy respondsToSelector:@selector(requestInfoDetailDatas:success:failure:)]) {
            [proxy requestInfoDetailDatas:reqModel success:^(id response) {
                NSMutableSet *netVisited = [NSMutableSet set];
                if ([self custom_deepSearchObject:response target:target visited:netVisited depth:0]) {
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
        } else {
            // 没有可用的网络代理类，直接离开组
            dispatch_group_leave(group);
        }
    }
    
    __weak typeof(self) weakSelf = self;
    
    // 5. 等待所有并发的网络请求拉取完毕
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [loadingAlert dismissViewControllerAnimated:YES completion:^{
            
            NSMutableArray *sortedFilteredArray = [NSMutableArray array];
            for (id item in currentData) {
                NSString *infoId = nil;
                @try { 
                    id val = [item valueForKey:@"infoId"];
                    if ([val isKindOfClass:[NSNumber class]]) infoId = [(NSNumber *)val stringValue];
                    else if ([val isKindOfClass:[NSString class]]) infoId = val;
                } @catch (NSException *e) {}
                
                if (infoId && [matchedInfoIds containsObject:infoId]) {
                    [sortedFilteredArray addObject:item];
                }
            }
            
            if (sortedFilteredArray.count > 0) {
                // 替换数据源
                weakSelf.dataArray = [sortedFilteredArray copy];
                
                // 刷新 UI
                if ([weakSelf respondsToSelector:@selector(real_reloadData:)]) {
                    [weakSelf performSelector:@selector(real_reloadData:) withObject:nil];
                } else {
                    [weakSelf custom_reloadCollectionView]; 
                }
                
                // 给用户展示后台统计数据（方便排查问题）
                NSString *resultMsg = [NSString stringWithFormat:@"本地深层匹配: %d 条\n网络详情匹配: %d 条\n网络请求失败: %d 条", localMatchCount, netMatchCount, netFailCount];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:successAlert animated:YES completion:nil];
                
            } else {
                NSString *resultMsg = [NSString stringWithFormat:@"本地深层匹配: 0 条\n网络详情匹配: 0 条\n网络请求失败: %d 条\n\n请向下滑动加载下一页后再试。", netFailCount];
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"未能筛到相关商品" 
                                                                                    message:resultMsg
                                                                             preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

// ====== 绝对安全防闪退的深层穿透搜索引擎 ======
// 不依赖 JSON 转换，而是手工剥洋葱，保证绝对安全！
%new
- (BOOL)custom_deepSearchObject:(id)obj target:(NSString *)target visited:(NSMutableSet *)visited depth:(int)depth {
    // 设置最大挖掘深度为 4 层，防止复杂对象导致内存爆炸或死循环
    if (!obj || depth > 4) return NO;
    
    // 防循环引用验证
    NSValue *ptr = [NSValue valueWithNonretainedObject:obj];
    if ([visited containsObject:ptr]) return NO;
    [visited addObject:ptr];
    
    // 1. 如果剥到了字符串，直接比较！
    if ([obj isKindOfClass:[NSString class]]) {
        // 去空格 + 全小写 比如 "iOS 15.4" 会变成 "ios15.4"，"15.4" 会变成 "15.4" 完美匹配！
        NSString *cleanStr = [[(NSString *)obj lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
        if ([cleanStr containsString:target]) return YES;
        return NO;
    }
    
    // 2. 剥到数字
    if ([obj isKindOfClass:[NSNumber class]]) {
        return [[(NSNumber *)obj stringValue] containsString:target];
    }
    
    // 3. 剥开数组，遍历里面的元素
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) {
            if ([self custom_deepSearchObject:item target:target visited:visited depth:depth+1]) return YES;
        }
        return NO;
    }
    
    // 4. 剥开字典，遍历里面的值
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id key in (NSDictionary *)obj) {
            if ([self custom_deepSearchObject:[(NSDictionary *)obj objectForKey:key] target:target visited:visited depth:depth+1]) return YES;
        }
        return NO;
    }
    
    // 5. 剥开转转自定义模型（通过 KVC 提取最容易藏数据的这些字段继续往下剥）
    NSArray *keys = @[@"title", @"desc", @"content", @"extendJson", @"extend", 
                      @"paramValue", @"param", @"labelPosition", @"text", @"name", 
                      @"sellerDescription", @"titleAndContent", @"respData", @"data",
                      @"waterFeedAppearanceLabelsInfoViewModel", @"actInfo", 
                      @"priceDesc", @"userCateLabelDesc", @"subTitle", @"detail"];
    for (NSString *key in keys) {
        id val = nil;
        @try { val = [obj valueForKey:key]; } @catch(NSException *e) {}
        if (val) {
            if ([self custom_deepSearchObject:val target:target visited:visited depth:depth+1]) return YES;
        }
    }
    
    return NO;
}

// 暴力刷新视图兜底方法
%new
- (void)custom_reloadCollectionView {
    NSMutableArray *queue = [NSMutableArray arrayWithObject:self.view];
    while (queue.count > 0) {
        UIView *currentView = queue.firstObject;
        [queue removeObjectAtIndex:0];
        
        if ([currentView isKindOfClass:[UICollectionView class]]) {
            [(UICollectionView *)currentView reloadData];
        } else if ([currentView isKindOfClass:[UITableView class]]) {
            [(UITableView *)currentView reloadData];
        }
        
        [queue addObjectsFromArray:currentView.subviews];
    }
}

%end
