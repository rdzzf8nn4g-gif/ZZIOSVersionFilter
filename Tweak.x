#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ====== 全局变量与锁 ======
static BOOL globalIsSearching = NO;
static NSString *globalSearchTarget = nil;
static NSMutableSet *globalMatchedInfoIds = nil;
static NSMutableSet *globalTargetInfoIds = nil;
static NSLock *globalLock = nil;

// ====== 终极 C 语言级内存溯源爬虫（绝对防截断、防闪退） ======
static BOOL ZZDeepTextSearch(id obj, NSString *target, NSMutableSet *visited, int depth, NSMutableString *sampleStr) {
    if (!obj || depth > 12) return NO;
    if ([obj isKindOfClass:[NSNull class]]) return NO;
    
    NSValue *ptr = [NSValue valueWithNonretainedObject:obj];
    if ([visited containsObject:ptr]) return NO;
    [visited addObject:ptr];
    
    if ([obj isKindOfClass:[NSString class]]) {
        NSString *rawStr = (NSString *)obj;
        if ([rawStr containsString:@"<ZZ"] || [rawStr containsString:@"ZZCommonFeed"]) return NO;
        
        // 强制解除各类乱码编码
        NSString *unicodeDecoded = [NSString stringWithCString:[rawStr cStringUsingEncoding:NSUTF8StringEncoding] encoding:NSNonLossyASCIIStringEncoding];
        if (unicodeDecoded) rawStr = unicodeDecoded;
        NSString *urlDecoded = [rawStr stringByRemovingPercentEncoding];
        if (urlDecoded) rawStr = urlDecoded;
        
        if (sampleStr && sampleStr.length < 300 && rawStr.length > 1 && ![rawStr hasPrefix:@"http"]) {
            [sampleStr appendFormat:@"[%@] ", rawStr];
        }
        
        NSString *cleanStr = [[rawStr lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
        if ([cleanStr containsString:target]) return YES;
        return NO;
    }
    
    if ([obj isKindOfClass:[NSAttributedString class]]) return ZZDeepTextSearch([(NSAttributedString *)obj string], target, visited, depth+1, sampleStr);
    if ([obj isKindOfClass:[NSNumber class]]) return ZZDeepTextSearch([(NSNumber *)obj stringValue], target, visited, depth+1, sampleStr);
    
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) {
            if (ZZDeepTextSearch(item, target, visited, depth+1, sampleStr)) return YES;
        }
        return NO;
    }
    
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id val in [(NSDictionary *)obj allValues]) {
            if (ZZDeepTextSearch(val, target, visited, depth+1, sampleStr)) return YES;
        }
        return NO;
    }
    
    NSString *className = NSStringFromClass([obj class]);
    if ([className hasPrefix:@"ZZ"] || [className hasPrefix:@"SimpleCheck"]) {
        Class currentClass = [obj class];
        while (currentClass && currentClass != [NSObject class]) {
            unsigned int outCount, i;
            objc_property_t *properties = class_copyPropertyList(currentClass, &outCount);
            if (properties) {
                for (i = 0; i < outCount; i++) {
                    const char *propName = property_getName(properties[i]);
                    if (propName) {
                        NSString *propertyName = [NSString stringWithUTF8String:propName];
                        @try {
                            id val = [obj valueForKey:propertyName];
                            if (val && ZZDeepTextSearch(val, target, visited, depth+1, sampleStr)) {
                                free(properties);
                                return YES;
                            }
                        } @catch (...) {}
                    }
                }
                free(properties);
            }
            currentClass = class_getSuperclass(currentClass);
        }
    }
    return NO;
}

// ====== 1. 声明底层网络拦截与请求类 ======
@interface ZZNetworkAgent : NSObject
- (void)handleRequestResult:(id)a0 responseObject:(id)a1 error:(id)a2;
@end

@interface ZZInfoDetailProxy : NSObject
- (void)requestInfoDetailDatas:(id)req success:(void(^)(id response))success failure:(void(^)(id error))failure;
@end

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
- (void)reloadListingGoodsWithRespModel:(id)arg;

- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_filterWithVersion:(NSString *)version;
- (void)custom_collectProductsFrom:(id)obj into:(NSMutableDictionary *)dict;
- (NSString *)custom_extractInfoId:(id)obj;
- (void)custom_pruneZZFLEXArray:(NSMutableArray *)array matchedIds:(NSSet *)matchedIds kept:(int *)kept removed:(int *)removed;
- (void)custom_reloadCollectionView;
@end

// ====== 终极杀招：全局底层网卡截胡（解决 YYModel 截断问题） ======
%hook ZZNetworkAgent

- (void)handleRequestResult:(id)request responseObject:(id)response error:(id)error {
    if (globalIsSearching && response && globalSearchTarget && globalTargetInfoIds && globalLock) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @try {
                NSMutableSet *visited = [NSMutableSet set];
                // 使用 C 爬虫暴力拆解网络返回的原始对象，防止任何属性被隐藏！
                if (ZZDeepTextSearch(response, globalSearchTarget, visited, 0, nil)) {
                    // 如果发现目标版本号，再查一下这个数据包属于哪台手机
                    for (NSString *infoId in globalTargetInfoIds) {
                        NSMutableSet *idVisited = [NSMutableSet set];
                        if (ZZDeepTextSearch(response, infoId, idVisited, 0, nil)) {
                            [globalLock lock];
                            [globalMatchedInfoIds addObject:infoId];
                            [globalLock unlock];
                            break;
                        }
                    }
                }
            } @catch(...) {}
        });
    }
    %orig;
}

%end

// ====== 主逻辑控制器 ======
%hook ZZListingAprilViewController

- (void)viewDidLoad {
    %orig;
    UILongPressGestureRecognizer *twoFingerLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(custom_twoFingerLongPress:)];
    twoFingerLongPress.numberOfTouchesRequired = 2;
    twoFingerLongPress.minimumPressDuration = 1.0;
    [self.view addGestureRecognizer:twoFingerLongPress];
    
    if (!globalLock) globalLock = [[NSLock alloc] init];
}

%new
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"系统版本黎明检索" 
                                                                       message:@"请输入想筛选的iOS版本\n(已挂载原生拦截与HTTP直穿引擎)" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.placeholder = @"输入版本号 (如: 15.4、16)";
            textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
            textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        
        __weak typeof(self) weakSelf = self;
        UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"执行筛选" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
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
    if (!self.dataArray || self.dataArray.count == 0) return;
    
    // 递归收集屏幕上划过的所有商品
    NSMutableDictionary *allProducts = [NSMutableDictionary dictionary];
    [self custom_collectProductsFrom:self.dataArray into:allProducts];
    if (allProducts.count == 0) return;
    
    // 初始化全局变量
    globalIsSearching = YES;
    globalSearchTarget = [[version lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    globalMatchedInfoIds = [NSMutableSet set];
    globalTargetInfoIds = [NSMutableSet set];
    
    for (NSString *infoId in allProducts.allKeys) {
        [globalTargetInfoIds addObject:infoId];
    }
    
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在执行三栖扫描" 
                                                                          message:[NSString stringWithFormat:@"锁定 %lu 台设备\n正在通过 本地+伪装网卡+官方API 并发掘地三尺...", (unsigned long)allProducts.count]
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableArray *retainedProxies = [NSMutableArray array];
    
    __block int localMatchCount = 0;
    __block int netReqCount = 0;
    __block int httpApiCount = 0;
    NSMutableString *sampleResponseStr = [[NSMutableString alloc] init];
    
    for (NSString *infoId in allProducts.allKeys) {
        id item = allProducts[infoId];
        
        // ====== 第一栖：本地极深内存扫描 ======
        NSMutableSet *visited = [NSMutableSet set];
        if (ZZDeepTextSearch(item, globalSearchTarget, visited, 0, sampleResponseStr)) {
            [globalLock lock];
            [globalMatchedInfoIds addObject:infoId];
            localMatchCount++;
            [globalLock unlock];
            continue; // 本地找到了就不发请求
        }
        
        // 获取商品的真实 ptype (核心修复！不传 ptype 就拿不到验机报告)
        id ptypeVal = nil;
        @try { ptypeVal = [item valueForKey:@"ptype"]; } @catch(...) {}
        if (!ptypeVal) { @try { ptypeVal = [item valueForKey:@"zc_page_type"]; } @catch(...) {} }
        if (!ptypeVal) ptypeVal = @(101); // 兜底：101 是验机手机专属类型
        
        // ====== 第二栖：原生接口伪装骗取 ======
        void (^handleResponse)(id) = ^(id response) {
            [globalLock lock]; netReqCount++; [globalLock unlock];
            dispatch_group_leave(group); // 数据已被 global ZZNetworkAgent 截胡处理
        };
        void (^handleFailure)(id) = ^(id error) {
            dispatch_group_leave(group);
        };
        
        Class ProxyClassB2C = NSClassFromString(@"ZZGoodsDetailProxy");
        Class ReqModelClassB2C = NSClassFromString(@"ZZGoodsDetailRequestModel");
        if (ProxyClassB2C) {
            id reqB2C = nil;
            if (ReqModelClassB2C) {
                reqB2C = [[ReqModelClassB2C alloc] init];
                @try { [reqB2C setValue:infoId forKey:@"goodsId"]; } @catch(...) {}
            } else {
                Class ReqModelClassC2C = NSClassFromString(@"ZZInfoDetailRequestModel");
                reqB2C = [[ReqModelClassC2C alloc] init];
                @try { [reqB2C setValue:infoId forKey:@"infoID"]; } @catch(...) {}
            }
            @try { [reqB2C setValue:@(1) forKey:@"from"]; } @catch(...) {}
            @try { [reqB2C setValue:ptypeVal forKey:@"ptype"]; } @catch(...) {} // 注入真实类型
            
            id proxyB2C = [[ProxyClassB2C alloc] init];
            [retainedProxies addObject:proxyB2C];
            if ([proxyB2C respondsToSelector:@selector(requestGoodsDetailDateWithRequestModel:success:failure:)]) {
                dispatch_group_enter(group);
                [proxyB2C requestGoodsDetailDateWithRequestModel:reqB2C success:handleResponse failure:handleFailure];
            }
        }
        
        // ====== 第三栖：直穿转转官方公开 API（完全绕过客户端限制） ======
        NSArray *openUrls = @[
            [NSString stringWithFormat:@"https://app.zhuanzhuan.com/zzopen/main/goodsDetail?infoId=%@", infoId],
            [NSString stringWithFormat:@"https://m.zhuanzhuan.com/openapi/zzapp/new-goods-detail/info?infoId=%@", infoId]
        ];
        
        for (NSString *urlStr in openUrls) {
            dispatch_group_enter(group);
            NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:urlStr] completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
                [globalLock lock]; httpApiCount++; [globalLock unlock];
                if (data) {
                    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (json) {
                        NSString *unicodeDecoded = [NSString stringWithCString:[json cStringUsingEncoding:NSUTF8StringEncoding] encoding:NSNonLossyASCIIStringEncoding];
                        if (unicodeDecoded) json = unicodeDecoded;
                        NSString *cleanJson = [[json lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
                        if ([cleanJson containsString:globalSearchTarget]) {
                            [globalLock lock];
                            [globalMatchedInfoIds addObject:infoId];
                            [globalLock unlock];
                        }
                    }
                }
                dispatch_group_leave(group);
            }];
            [task resume];
        }
    }
    
    __weak typeof(self) weakSelf = self;
    
    // 4. 执行结果清算
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        // 等待几百毫秒让所有截胡线程处理完毕
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            globalIsSearching = NO;
            [loadingAlert dismissViewControllerAnimated:YES completion:^{
                [retainedProxies removeAllObjects];
                
                if (globalMatchedInfoIds.count > 0) {
                    int kept = 0, removed = 0;
                    NSMutableArray *mutDataArray = [weakSelf.dataArray mutableCopy];
                    [weakSelf custom_pruneZZFLEXArray:mutDataArray matchedIds:globalMatchedInfoIds kept:&kept removed:&removed];
                    weakSelf.dataArray = mutDataArray;
                    
                    if (weakSelf.firstPageResponseData) {
                        NSArray *infos = [weakSelf.firstPageResponseData valueForKey:@"infos"];
                        NSMutableArray *filteredInfos = [NSMutableArray array];
                        for (id item in infos) {
                            NSString *iId = [weakSelf custom_extractInfoId:item];
                            if (iId && [globalMatchedInfoIds containsObject:iId]) {
                                [filteredInfos addObject:item];
                            }
                        }
                        [weakSelf.firstPageResponseData setValue:filteredInfos forKey:@"infos"];
                    }
                    
                    [weakSelf custom_reloadCollectionView];
                    
                    // 修复：在这里使用了 localMatchCount 消除编译警告
                    NSString *resultMsg = [NSString stringWithFormat:@"总计处理设备: %lu 台\n本地精准发现: %d 台\n原生网卡+公开API 发送请求: %d 次\n\n精准命中并保留设备: %lu 台！\n成功剔除 %d 台无关设备。", (unsigned long)allProducts.count, localMatchCount, (netReqCount + httpApiCount), (unsigned long)globalMatchedInfoIds.count, removed];
                    UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                    [successAlert addAction:[UIAlertAction actionWithTitle:@"太棒了" style:UIAlertActionStyleDefault handler:nil]];
                    [weakSelf presentViewController:successAlert animated:YES completion:nil];
                    
                } else {
                    // 修复：在这里使用了 localMatchCount 消除编译警告
                    NSString *resultMsg = [NSString stringWithFormat:@"已全维度检索设备: %lu 台\n本地扫描发现: %d 台\n网卡拦截与API穿透成功: %d 次\n\n最终匹配命中: 0 台\n\n【爬虫底层证明采样】:\n%@\n\n※ 请继续向下加载更多设备后，再次重试！", (unsigned long)allProducts.count, localMatchCount, (netReqCount + httpApiCount), sampleResponseStr.length > 0 ? sampleResponseStr : @"空"];
                    UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"当前列表无匹配项" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                    [emptyAlert addAction:[UIAlertAction actionWithTitle:@"好的，我多加载一点" style:UIAlertActionStyleCancel handler:nil]];
                    [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
                }
            }];
        });
    });
}

// ====== 递归提取列表中的所有商品 ======
%new
- (void)custom_collectProductsFrom:(id)obj into:(NSMutableDictionary *)dict {
    if (!obj) return;
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) [self custom_collectProductsFrom:item into:dict];
        return;
    }
    if ([obj respondsToSelector:NSSelectorFromString(@"itemsArray")]) {
        @try { id items = [obj valueForKey:@"itemsArray"]; [self custom_collectProductsFrom:items into:dict]; } @catch(...) {}
        return;
    }
    id realData = obj;
    if ([obj respondsToSelector:NSSelectorFromString(@"dataModel")]) {
        id inner = [obj valueForKey:@"dataModel"];
        if (inner) realData = inner;
    }
    NSString *infoId = [self custom_extractInfoId:realData];
    if (infoId && infoId.length > 4) dict[infoId] = realData;
}

// ====== 原地修剪 UI 列表 ======
%new
- (void)custom_pruneZZFLEXArray:(NSMutableArray *)array matchedIds:(NSSet *)matchedIds kept:(int *)kept removed:(int *)removed {
    for (NSInteger i = array.count - 1; i >= 0; i--) {
        id item = array[i];
        if ([item respondsToSelector:NSSelectorFromString(@"itemsArray")]) {
            @try {
                id items = [item valueForKey:@"itemsArray"];
                if ([items isKindOfClass:[NSMutableArray class]]) {
                    [self custom_pruneZZFLEXArray:items matchedIds:matchedIds kept:kept removed:removed];
                } else if ([items isKindOfClass:[NSArray class]]) {
                    NSMutableArray *mut = [items mutableCopy];
                    [self custom_pruneZZFLEXArray:mut matchedIds:matchedIds kept:kept removed:removed];
                    [item setValue:mut forKey:@"itemsArray"];
                }
            } @catch(...) {}
            continue;
        }
        if ([item isKindOfClass:[NSMutableArray class]]) {
            [self custom_pruneZZFLEXArray:item matchedIds:matchedIds kept:kept removed:removed];
            continue;
        }
        id realData = item;
        if ([item respondsToSelector:NSSelectorFromString(@"dataModel")]) {
            id inner = [item valueForKey:@"dataModel"];
            if (inner) realData = inner;
        }
        NSString *infoId = [self custom_extractInfoId:realData];
        if (infoId && infoId.length > 4) {
            if ([matchedIds containsObject:infoId]) (*kept)++;
            else { [array removeObjectAtIndex:i]; (*removed)++; }
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
