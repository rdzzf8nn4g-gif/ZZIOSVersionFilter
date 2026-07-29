#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ====== 全局网络拦截变量 ======
static BOOL globalIsSearching = NO;
static NSString *globalSearchTarget = nil;
static NSMutableSet *globalMatchedInfoIds = nil;
static NSMutableSet *globalTargetInfoIds = nil;

// ====== 1. 声明转转的网络代理类 ======
@interface ZZNetworkAgent : NSObject
- (void)handleRequestResult:(id)a0 responseObject:(id)a1 error:(id)a2;
@end

@interface ZZInfoDetailRequestModel : NSObject
@property (copy, nonatomic) NSString *infoID;
@property (nonatomic) unsigned long long from;
@property (copy, nonatomic) NSString *pageType;
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

// 自定义方法
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_filterWithVersion:(NSString *)version;
- (NSString *)custom_extractInfoId:(id)obj;
- (BOOL)custom_deepTextSearch:(id)obj target:(NSString *)target visited:(NSMutableSet *)visited depth:(int)depth;
- (void)custom_pruneZZFLEXArray:(NSMutableArray *)array matchedIds:(NSSet *)matchedIds kept:(int *)kept removed:(int *)removed;
- (void)custom_reloadCollectionView;
@end

// ====== 终极杀招：全局网络 JSON 拦截器 ======
%hook ZZNetworkAgent

- (void)handleRequestResult:(id)request responseObject:(id)response error:(id)error {
    // 只要处于搜索状态，拦截所有经过的原生网络响应
    if (globalIsSearching && response && globalSearchTarget && globalTargetInfoIds) {
        @try {
            NSString *jsonStr = nil;
            // 提取最原始的 JSON
            if ([response isKindOfClass:[NSDictionary class]] || [response isKindOfClass:[NSArray class]]) {
                NSData *data = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
                if (data) jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            } else {
                jsonStr = [response description];
            }
            
            // 解码 Unicode (解决 \u56fd 等乱码)
            if (jsonStr) {
                NSString *unicodeDecoded = [NSString stringWithCString:[jsonStr cStringUsingEncoding:NSUTF8StringEncoding] encoding:NSNonLossyASCIIStringEncoding];
                if (unicodeDecoded) jsonStr = unicodeDecoded;
                
                NSString *cleanStr = [[jsonStr lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
                
                // 如果这段原始 JSON 里包含了 15.4！
                if ([cleanStr containsString:globalSearchTarget]) {
                    // 判断这份 JSON 属于哪个商品
                    for (NSString *infoId in globalTargetInfoIds) {
                        if ([jsonStr containsString:infoId]) {
                            [globalMatchedInfoIds addObject:infoId];
                        }
                    }
                }
            }
        } @catch(...) {}
    }
    %orig; // 保证不影响 App 正常运行
}

%end


%hook ZZListingAprilViewController

- (void)viewDidLoad {
    %orig;
    UILongPressGestureRecognizer *twoFingerLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(custom_twoFingerLongPress:)];
    twoFingerLongPress.numberOfTouchesRequired = 2;
    twoFingerLongPress.minimumPressDuration = 1.0;
    [self.view addGestureRecognizer:twoFingerLongPress];
}

%new
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"系统版本全局拦截" 
                                                                       message:@"请输入想筛选的iOS版本\n(已挂载底层网卡 JSON 拦截器)" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.placeholder = @"输入版本号 (如: 15.4、16)";
            textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
            textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        
        __weak typeof(self) weakSelf = self;
        UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"开始轰炸" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
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
    if (!self.firstPageResponseData || ![self.firstPageResponseData respondsToSelector:NSSelectorFromString(@"infos")]) {
        return;
    }
    
    // 确保读取的是完整的 infos 列表（你往下划的所有商品都在这里）
    NSArray *infos = [self.firstPageResponseData valueForKey:@"infos"];
    if (!infos || infos.count == 0) return;
    
    // 初始化全局网络拦截器参数
    globalIsSearching = YES;
    globalSearchTarget = [[version lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    globalMatchedInfoIds = [NSMutableSet set];
    globalTargetInfoIds = [NSMutableSet set];
    
    NSMutableDictionary *allProducts = [NSMutableDictionary dictionary];
    for (id item in infos) {
        NSString *infoId = [self custom_extractInfoId:item];
        if (infoId && infoId.length > 4) {
            allProducts[infoId] = item;
            [globalTargetInfoIds addObject:infoId];
        }
    }
    
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在网络层拦截验机参数" 
                                                                          message:[NSString stringWithFormat:@"已锁定 %lu 个商品，正在跨接口抓取未修改的 JSON...", (unsigned long)allProducts.count]
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    dispatch_group_t group = dispatch_group_create();
    NSLock *lock = [[NSLock alloc] init];
    NSMutableArray *retainedProxies = [NSMutableArray array];
    
    __block int netReqCount = 0;
    
    for (NSString *infoId in allProducts.allKeys) {
        id item = allProducts[infoId];
        
        // 1. 本地内存搜索兜底
        NSMutableSet *visited = [NSMutableSet set];
        if ([self custom_deepTextSearch:item target:globalSearchTarget visited:visited depth:0]) {
            [globalMatchedInfoIds addObject:infoId];
            continue;
        }
        
        // 2. 发起安全网络请求，诱导转转服务器返回数据，触发全局拦截器
        void (^handleResponse)(id) = ^(id response) {
            [lock lock]; netReqCount++; [lock unlock];
            dispatch_group_leave(group);
        };
        void (^handleFailure)(id) = ^(id error) {
            dispatch_group_leave(group);
        };
        
        // 发送给 C2C 接口
        Class ProxyClassC2C = NSClassFromString(@"ZZInfoDetailProxy");
        Class ReqModelClassC2C = NSClassFromString(@"ZZInfoDetailRequestModel");
        if (ProxyClassC2C && ReqModelClassC2C) {
            id reqC2C = [[ReqModelClassC2C alloc] init];
            @try { [reqC2C setValue:infoId forKey:@"infoID"]; } @catch(...) {}
            @try { [reqC2C setValue:@(1) forKey:@"from"]; } @catch(...) {}
            @try { [reqC2C setValue:@"1" forKey:@"pageType"]; } @catch(...) {}
            
            id proxyC2C = [[ProxyClassC2C alloc] init];
            [retainedProxies addObject:proxyC2C];
            if ([proxyC2C respondsToSelector:@selector(requestInfoDetailDatas:success:failure:)]) {
                dispatch_group_enter(group);
                [proxyC2C requestInfoDetailDatas:reqC2C success:handleResponse failure:handleFailure];
            }
        }
        
        // 发送给 B2C 验机接口
        Class ProxyClassB2C = NSClassFromString(@"ZZGoodsDetailProxy");
        Class ReqModelClassB2C = NSClassFromString(@"ZZGoodsDetailRequestModel");
        if (ProxyClassB2C) {
            id reqB2C = nil;
            if (ReqModelClassB2C) {
                reqB2C = [[ReqModelClassB2C alloc] init];
                @try { [reqB2C setValue:infoId forKey:@"goodsId"]; } @catch(...) {}
            } else {
                reqB2C = [[ReqModelClassC2C alloc] init]; // 兜底
                @try { [reqB2C setValue:infoId forKey:@"infoID"]; } @catch(...) {}
            }
            @try { [reqB2C setValue:@(1) forKey:@"from"]; } @catch(...) {}
            
            id proxyB2C = [[ProxyClassB2C alloc] init];
            [retainedProxies addObject:proxyB2C];
            if ([proxyB2C respondsToSelector:@selector(requestGoodsDetailDateWithRequestModel:success:failure:)]) {
                dispatch_group_enter(group);
                [proxyB2C requestGoodsDetailDateWithRequestModel:reqB2C success:handleResponse failure:handleFailure];
            }
        }
    }
    
    __weak typeof(self) weakSelf = self;
    
    // 3. 执行结果清算
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        globalIsSearching = NO; // 关闭全局拦截器
        [loadingAlert dismissViewControllerAnimated:YES completion:^{
            [retainedProxies removeAllObjects];
            
            if (globalMatchedInfoIds.count > 0) {
                int kept = 0, removed = 0;
                
                // 修剪屏幕显示池
                NSMutableArray *mutDataArray = [weakSelf.dataArray mutableCopy];
                [weakSelf custom_pruneZZFLEXArray:mutDataArray matchedIds:globalMatchedInfoIds kept:&kept removed:&removed];
                weakSelf.dataArray = mutDataArray;
                
                // 修剪商品数据源池
                NSMutableArray *filteredInfos = [NSMutableArray array];
                for (id item in infos) {
                    NSString *iId = [weakSelf custom_extractInfoId:item];
                    if (iId && [globalMatchedInfoIds containsObject:iId]) {
                        [filteredInfos addObject:item];
                    }
                }
                [weakSelf.firstPageResponseData setValue:filteredInfos forKey:@"infos"];
                
                [weakSelf custom_reloadCollectionView];
                
                NSString *resultMsg = [NSString stringWithFormat:@"总计扫描商品: %lu 个\n全接口触发次数: %d 次\n\n拦截命中: %lu 个\n成功剔除 %d 个无关商品！", (unsigned long)allProducts.count, netReqCount, (unsigned long)globalMatchedInfoIds.count, removed];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"太棒了" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:successAlert animated:YES completion:nil];
                
            } else {
                NSString *resultMsg = [NSString stringWithFormat:@"总计扫描商品: %lu 个\n诱发接口返回: %d 次\n网卡 JSON 拦截匹配: 0 个\n\n※ 请继续向下加载更多商品后，再次筛选！", (unsigned long)allProducts.count, netReqCount];
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"当前列表无匹配项" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"好的，我往下多划一点" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

// ====== 安全文本爬虫 ======
%new
- (BOOL)custom_deepTextSearch:(id)obj target:(NSString *)target visited:(NSMutableSet *)visited depth:(int)depth {
    if (!obj || depth > 8) return NO;
    NSValue *ptr = [NSValue valueWithNonretainedObject:obj];
    if ([visited containsObject:ptr]) return NO;
    [visited addObject:ptr];
    
    if ([obj isKindOfClass:[NSString class]]) {
        NSString *rawStr = (NSString *)obj;
        if ([rawStr containsString:@"<ZZ"] || [rawStr containsString:@"ZZCommonFeed"]) return NO;
        NSString *cleanStr = [[rawStr lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
        if ([cleanStr containsString:target]) return YES;
        return NO;
    }
    if ([obj isKindOfClass:[NSAttributedString class]]) {
        NSString *rawStr = [(NSAttributedString *)obj string];
        if (rawStr) return [self custom_deepTextSearch:rawStr target:target visited:visited depth:depth+1];
        return NO;
    }
    if ([obj isKindOfClass:[NSNumber class]]) return [self custom_deepTextSearch:[(NSNumber *)obj stringValue] target:target visited:visited depth:depth+1];
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) if ([self custom_deepTextSearch:item target:target visited:visited depth:depth+1]) return YES;
        return NO;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id val in [(NSDictionary *)obj allValues]) if ([self custom_deepTextSearch:val target:target visited:visited depth:depth+1]) return YES;
        return NO;
    }
    return NO;
}

// ====== 原地修剪 UI 列表 ======
%new
- (void)custom_pruneZZFLEXArray:(NSMutableArray *)array matchedIds:(NSSet *)matchedIds kept:(int *)kept removed:(int *)removed {
    for (NSInteger i = array.count - 1; i >= 0; i--) {
        id item = array[i];
        if ([item respondsToSelector:NSSelectorFromString(@"itemsArray")]) {
            @try {
                id items = [item valueForKey:@"itemsArray"];
                if ([items isKindOfClass:[NSMutableArray class]]) [self custom_pruneZZFLEXArray:items matchedIds:matchedIds kept:kept removed:removed];
                else if ([items isKindOfClass:[NSArray class]]) {
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
