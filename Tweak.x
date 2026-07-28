#import <UIKit/UIKit.h>

// ====== 声明第三方库方法，消除 ARC 警告 ======
@interface NSObject (ZZModelToJSON)
- (id)mj_keyValues;
- (id)yy_modelToJSONObject;
@end

// ====== 声明转转的网络与模型类 ======
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

@interface ZZListingAprilViewController : UIViewController
@property (retain, nonatomic) NSArray *dataArray;
@property (retain, nonatomic) ZZListingResponseModel *firstPageResponseData;
- (void)loadData;
- (void)real_reloadData:(id)arg;
- (void)reloadListingGoodsWithRespModel:(id)arg;

// 自定义方法声明
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_fetchDetailAndFilterWithVersion:(NSString *)version;
- (BOOL)custom_deepSearchObject:(id)obj target:(NSString *)target visited:(NSMutableSet *)visited depth:(int)depth;
- (NSString *)custom_extractInfoId:(id)obj;
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
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"系统版本终极筛选" 
                                                                       message:@"请输入想筛选的iOS版本\n(已攻破ZZFLEX引擎，直击底层数据)" 
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
    // 1. 突破 ZZFLEX：直取最纯粹的底层数据 infos，而不是经过封装的 dataArray
    NSArray *currentData = nil;
    if (self.firstPageResponseData && [self.firstPageResponseData respondsToSelector:@selector(infos)]) {
        currentData = [self.firstPageResponseData valueForKey:@"infos"];
    }
    if (!currentData || currentData.count == 0) {
        currentData = self.dataArray; // 兜底
    }
    
    if (!currentData || currentData.count == 0) {
        UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"提示" message:@"列表暂无数据，请向下滑动加载或刷新后再试" preferredStyle:UIAlertControllerStyleAlert];
        [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:emptyAlert animated:YES completion:nil];
        return;
    }
    
    // 弹出全局 Loading
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在静默拉取与分析..." 
                                                                          message:@"正在进行全量数据透视，请稍候..." 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSLock *lock = [[NSLock alloc] init];
    
    // 数据统计
    __block int localMatchCount = 0;
    __block int netMatchCount = 0;
    
    // 目标词标准化处理（去空格 + 全小写），比如 "15.4"
    NSString *target = [[version lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    for (id item in currentData) {
        // 智能剥壳器提取商品 ID
        NSString *infoId = [self custom_extractInfoId:item];
        if (!infoId || infoId.length == 0) {
            continue; 
        }

        // ====== 阶段一：本地全量透视匹配 ======
        NSMutableSet *visited = [NSMutableSet set];
        if ([self custom_deepSearchObject:item target:target visited:visited depth:0]) {
            [lock lock];
            [matchedInfoIds addObject:infoId];
            localMatchCount++;
            [lock unlock];
            continue; // 本地找到了，极速跳过网络请求！
        }

        // ====== 阶段二：本地没找到，发起并发详情请求 ======
        dispatch_group_enter(group);
        
        ZZInfoDetailRequestModel *reqModel = [[NSClassFromString(@"ZZInfoDetailRequestModel") alloc] init];
        reqModel.infoID = infoId;
        reqModel.from = 1; 
        reqModel.pageType = @"1";
        
        ZZGoodsDetailProxy *proxy = [[NSClassFromString(@"ZZGoodsDetailProxy") alloc] init];
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
            dispatch_group_leave(group);
        }];
    }
    
    __weak typeof(self) weakSelf = self;
    
    // 5. 所有并发的网络请求拉取完毕
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [loadingAlert dismissViewControllerAnimated:YES completion:^{
            
            // 按原始列表顺序重新组装
            NSMutableArray *sortedFilteredArray = [NSMutableArray array];
            for (id item in currentData) {
                NSString *infoId = [weakSelf custom_extractInfoId:item];
                // 只有被命中的保留，没 infoId 的（例如横幅广告）由于无法验证我们选择丢弃
                if (infoId && [matchedInfoIds containsObject:infoId]) {
                    [sortedFilteredArray addObject:item];
                }
            }
            
            if (sortedFilteredArray.count > 0) {
                // 彻底替换转转的底层数据源
                if (weakSelf.firstPageResponseData) {
                    @try {
                        [weakSelf.firstPageResponseData setValue:[sortedFilteredArray mutableCopy] forKey:@"infos"];
                    } @catch (NSException *e) {}
                }
                weakSelf.dataArray = [sortedFilteredArray copy];
                
                // 让转转的 ZZFLEX 引擎去重新计算 UI 和高度
                if ([weakSelf respondsToSelector:@selector(reloadListingGoodsWithRespModel:)]) {
                    [weakSelf performSelector:@selector(reloadListingGoodsWithRespModel:) withObject:weakSelf.firstPageResponseData];
                } else if ([weakSelf respondsToSelector:@selector(real_reloadData:)]) {
                    [weakSelf performSelector:@selector(real_reloadData:) withObject:nil];
                } else {
                    [weakSelf custom_reloadCollectionView]; 
                }
                
                NSString *resultMsg = [NSString stringWithFormat:@"本地直接秒筛: %d 条\n网络后台拉取: %d 条", localMatchCount, netMatchCount];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"完美" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:successAlert animated:YES completion:nil];
                
            } else {
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"未能筛到相关商品" 
                                                                                    message:@"已遍历本页所有列表标签及详情参数\n未发现该系统版本！请下拉加载下一页。"
                                                                             preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

// ====== 智能商品ID剥壳器 ======
%new
- (NSString *)custom_extractInfoId:(id)obj {
    if (!obj) return nil;
    @try {
        id val = nil;
        // 直接读取
        if ([obj respondsToSelector:@selector(infoId)]) val = [obj performSelector:@selector(infoId)];
        else if ([obj respondsToSelector:@selector(infoID)]) val = [obj performSelector:@selector(infoID)];
        else val = [obj valueForKey:@"infoId"];
        
        if ([val isKindOfClass:[NSString class]]) return val;
        if ([val isKindOfClass:[NSNumber class]]) return [(NSNumber *)val stringValue];
    } @catch(NSException *e) {}

    // 如果是 ZZFLEX 分组或封装对象，深入剥壳
    NSArray *wrappers = @[@"dataModel", @"feedModel"];
    for (NSString *key in wrappers) {
        @try {
            id wrapper = [obj valueForKey:key];
            if (wrapper && wrapper != obj) {
                NSString *innerId = [self custom_extractInfoId:wrapper];
                if (innerId) return innerId;
            }
        } @catch(NSException *e) {}
    }
    return nil;
}

// ====== 终极安全文本探测器 ======
%new
- (BOOL)custom_deepSearchObject:(id)obj target:(NSString *)target visited:(NSMutableSet *)visited depth:(int)depth {
    if (!obj || depth > 4) return NO;
    
    // 防循环引用死锁
    NSValue *ptr = [NSValue valueWithNonretainedObject:obj];
    if ([visited containsObject:ptr]) return NO;
    [visited addObject:ptr];

    // 1. 命中字符串！直接匹配
    if ([obj isKindOfClass:[NSString class]]) {
        NSString *cleanStr = [[(NSString *)obj lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
        if ([cleanStr containsString:target]) return YES;
        return NO;
    }

    // 2. 超级大杀器：利用自带的转字典方法，将其变成 JSON 文本后强制正则匹配！
    @try {
        id dict = nil;
        if ([obj respondsToSelector:@selector(mj_keyValues)]) {
            dict = [obj mj_keyValues];
        } else if ([obj respondsToSelector:@selector(yy_modelToJSONObject)]) {
            dict = [obj yy_modelToJSONObject];
        }
        if (dict) {
            NSString *dictStr = [[dict description] lowercaseString];
            NSString *cleanDictStr = [dictStr stringByReplacingOccurrencesOfString:@" " withString:@""];
            if ([cleanDictStr containsString:target]) return YES;
        }
    } @catch(NSException *e) {}

    // 3. 解析字典 (降级方案)
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id key in (NSDictionary *)obj) {
            if ([self custom_deepSearchObject:[(NSDictionary *)obj objectForKey:key] target:target visited:visited depth:depth+1]) return YES;
        }
        return NO;
    }

    // 4. 解析数组 (降级方案)
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) {
            if ([self custom_deepSearchObject:item target:target visited:visited depth:depth+1]) return YES;
        }
        return NO;
    }

    // 5. 自定义对象解析 (硬核探测转转常用埋点字段)
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
        if ([currentView isKindOfClass:[UICollectionView class]]) [(UICollectionView *)currentView reloadData];
        else if ([currentView isKindOfClass:[UITableView class]]) [(UITableView *)currentView reloadData];
        [queue addObjectsFromArray:currentView.subviews];
    }
}

%end
