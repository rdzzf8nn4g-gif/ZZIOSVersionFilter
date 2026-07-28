#import <UIKit/UIKit.h>

// ====== 消除 ARC 警告 ======
@interface NSObject (ZZModelToJSON)
- (id)mj_keyValues;
@end

// ====== 1. 声明转转的网络请求类 ======
@interface ZZInfoDetailRequestModel : NSObject
@property (copy, nonatomic) NSString *infoID;
@property (nonatomic) unsigned long long from;
@property (copy, nonatomic) NSString *pageType;
@end

// 闲置商品接口
@interface ZZInfoDetailProxy : NSObject
- (void)requestInfoDetailDatas:(id)req success:(void(^)(id response))success failure:(void(^)(id error))failure;
@end

// 验机精品接口
@interface ZZGoodsDetailProxy : NSObject
- (void)requestGoodsDetailDateWithRequestModel:(id)req success:(void(^)(id response))success failure:(void(^)(id error))failure;
@end

@interface ZZListingResponseModel : NSObject
@property (retain, nonatomic) NSMutableArray *infos;
@end

// ====== 2. 声明列表控制器 ======
@interface ZZListingAprilViewController : UIViewController
@property (retain, nonatomic) NSArray *dataArray;
@property (retain, nonatomic) ZZListingResponseModel *firstPageResponseData;
- (void)loadData;

// 自定义方法声明
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_filterWithVersion:(NSString *)version;
- (NSString *)custom_extractInfoId:(id)obj;
- (void)custom_extractAllStringsFrom:(id)obj into:(NSMutableString *)dump visited:(NSMutableSet *)visited depth:(int)depth;
- (void)custom_reloadCollectionView;
@end


%hook ZZListingAprilViewController

- (void)viewDidLoad {
    %orig;
    
    // 注入双指长按手势
    UILongPressGestureRecognizer *twoFingerLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(custom_twoFingerLongPress:)];
    twoFingerLongPress.numberOfTouchesRequired = 2;
    twoFingerLongPress.minimumPressDuration = 1.0;
    [self.view addGestureRecognizer:twoFingerLongPress];
}

%new
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"系统版本核弹级检索" 
                                                                       message:@"请输入想筛选的iOS版本\n(已搭载全域字符串粉碎机，无死角提取详情)" 
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
                [weakSelf custom_filterWithVersion:versionText];
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
- (void)custom_filterWithVersion:(NSString *)version {
    // 1. 直击底层列表数据
    if (!self.firstPageResponseData || ![self.firstPageResponseData respondsToSelector:NSSelectorFromString(@"infos")]) {
        return;
    }
    
    NSArray *infos = [self.firstPageResponseData valueForKey:@"infos"];
    if (!infos || infos.count == 0) return;
    
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"静默双路拉取中" 
                                                                          message:@"正在将详情层层粉碎为纯文本进行绝对匹配..." 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSLock *lock = [[NSLock alloc] init];
    
    // 必须强引用代理对象！防止 ARC 销毁网络请求
    NSMutableArray *retainedProxies = [NSMutableArray array];
    
    __block int matchCount = 0;
    
    // 目标文本标准化：全小写，去空格
    NSString *target = [[version lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    Class ReqModelClass = NSClassFromString(@"ZZInfoDetailRequestModel");
    
    for (id item in infos) {
        NSString *infoId = [self custom_extractInfoId:item];
        if (!infoId || infoId.length < 4) continue;
        
        // 构造请求体
        id reqModel = [[ReqModelClass alloc] init];
        [reqModel setValue:infoId forKey:@"infoID"]; // 大写的 infoID
        [reqModel setValue:@(1) forKey:@"from"];
        [reqModel setValue:@"1" forKey:@"pageType"];
        
        // ============================================
        // 路线 1：个人闲置接口 (ZZInfoDetailProxy)
        // ============================================
        Class ProxyClassC2C = NSClassFromString(@"ZZInfoDetailProxy");
        if (ProxyClassC2C) {
            dispatch_group_enter(group);
            id proxyC2C = [[ProxyClassC2C alloc] init];
            [retainedProxies addObject:proxyC2C];
            
            if ([proxyC2C respondsToSelector:@selector(requestInfoDetailDatas:success:failure:)]) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [proxyC2C requestInfoDetailDatas:reqModel success:^(id response) {
                    
                    // 【核心爆发点】将 response 对象彻底粉碎为一段纯文本
                    NSMutableString *textDump = [NSMutableString string];
                    NSMutableSet *visited = [NSMutableSet set];
                    [self custom_extractAllStringsFrom:response into:textDump visited:visited depth:0];
                    
                    NSString *cleanDump = [[textDump lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
                    
                    if ([cleanDump containsString:target]) {
                        [lock lock];
                        if (![matchedInfoIds containsObject:infoId]) {
                            [matchedInfoIds addObject:infoId];
                            matchCount++;
                        }
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
        
        // ============================================
        // 路线 2：验机精品接口 (ZZGoodsDetailProxy)
        // ============================================
        Class ProxyClassB2C = NSClassFromString(@"ZZGoodsDetailProxy");
        if (ProxyClassB2C) {
            dispatch_group_enter(group);
            id proxyB2C = [[ProxyClassB2C alloc] init];
            [retainedProxies addObject:proxyB2C];
            
            if ([proxyB2C respondsToSelector:@selector(requestGoodsDetailDateWithRequestModel:success:failure:)]) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [proxyB2C requestGoodsDetailDateWithRequestModel:reqModel success:^(id response) {
                    
                    // 【核心爆发点】将 response 对象彻底粉碎为一段纯文本
                    NSMutableString *textDump = [NSMutableString string];
                    NSMutableSet *visited = [NSMutableSet set];
                    [self custom_extractAllStringsFrom:response into:textDump visited:visited depth:0];
                    
                    NSString *cleanDump = [[textDump lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
                    
                    if ([cleanDump containsString:target]) {
                        [lock lock];
                        if (![matchedInfoIds containsObject:infoId]) {
                            [matchedInfoIds addObject:infoId];
                            matchCount++;
                        }
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
    }
    
    __weak typeof(self) weakSelf = self;
    
    // 5. 等待请求完成并更新 UI
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [loadingAlert dismissViewControllerAnimated:YES completion:^{
            
            [retainedProxies removeAllObjects];
            
            if (matchCount > 0) {
                // 有匹配项，重载列表
                NSMutableArray *filteredInfos = [NSMutableArray array];
                for (id item in infos) {
                    NSString *infoId = [weakSelf custom_extractInfoId:item];
                    if (infoId && [matchedInfoIds containsObject:infoId]) {
                        [filteredInfos addObject:item];
                    }
                }
                
                // 替换掉转转底层的数据源
                [weakSelf.firstPageResponseData setValue:filteredInfos forKey:@"infos"];
                
                // 强制 ZZFLEX 布局引擎重绘
                if ([weakSelf respondsToSelector:NSSelectorFromString(@"reloadListingGoodsWithRespModel:")]) {
                    #pragma clang diagnostic push
                    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [weakSelf performSelector:NSSelectorFromString(@"reloadListingGoodsWithRespModel:") withObject:weakSelf.firstPageResponseData];
                    #pragma clang diagnostic pop
                } else {
                    [weakSelf custom_reloadCollectionView]; // 兜底刷新
                }
                
                NSString *resultMsg = [NSString stringWithFormat:@"全页扫描并验证完毕\n成功匹配命中: %d 个！", matchCount];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"完美" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:successAlert animated:YES completion:nil];
                
            } else {
                NSString *resultMsg = [NSString stringWithFormat:@"已将当前列表所有详情数据\n粉碎为纯文本检索，\n依然匹配到 0 个商品！\n请向下滑动加载下一页后再试。"];
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"未能筛到相关商品" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

// ====== 核弹级武器：全域字符串粉碎机 ======
// 把任何对象（字典、数组、模型）里面所有的文字提取出来，组合成一条超长的巨型文本！
%new
- (void)custom_extractAllStringsFrom:(id)obj into:(NSMutableString *)dump visited:(NSMutableSet *)visited depth:(int)depth {
    if (!obj || depth > 6) return;
    
    // 防循环引用崩溃
    NSValue *ptr = [NSValue valueWithNonretainedObject:obj];
    if ([visited containsObject:ptr]) return;
    [visited addObject:ptr];
    
    if ([obj isKindOfClass:[NSString class]]) {
        [dump appendString:(NSString *)obj];
        [dump appendString:@"|"];
        return;
    }
    
    if ([obj isKindOfClass:[NSNumber class]]) {
        [dump appendString:[(NSNumber *)obj stringValue]];
        [dump appendString:@"|"];
        return;
    }
    
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) {
            [self custom_extractAllStringsFrom:item into:dump visited:visited depth:depth+1];
        }
        return;
    }
    
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id key in (NSDictionary *)obj) {
            [self custom_extractAllStringsFrom:[(NSDictionary *)obj objectForKey:key] into:dump visited:visited depth:depth+1];
        }
        return;
    }
    
    // 如果是自定义模型（商品详情 ZZGoodsDetailModel 或 ZZGoodsDetailParamModel 等）
    @try {
        if ([obj respondsToSelector:@selector(mj_keyValues)]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id dict = [obj performSelector:@selector(mj_keyValues)];
            #pragma clang diagnostic pop
            
            if (dict && [dict isKindOfClass:[NSDictionary class]]) {
                [self custom_extractAllStringsFrom:dict into:dump visited:visited depth:depth+1];
            }
        }
    } @catch(...) {}
    
    // 直接提取高概率存在的字段（双保险）
    NSArray *commonKeys = @[@"paramValue", @"title", @"desc", @"content", @"sellerDescription", @"extendJson"];
    for (NSString *key in commonKeys) {
        if ([obj respondsToSelector:NSSelectorFromString(key)]) {
            @try {
                id val = [obj valueForKey:key];
                if (val && [val isKindOfClass:[NSString class]]) {
                    [dump appendString:(NSString *)val];
                    [dump appendString:@"|"];
                }
            } @catch(...) {}
        }
    }
}

// ====== 智能提取商品 ID ======
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
