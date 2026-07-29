#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ====== 1. 声明转转的网络请求类 ======
@interface ZZInfoDetailRequestModel : NSObject
@property (copy, nonatomic) NSString *infoID;
@property (nonatomic) unsigned long long from;
@property (copy, nonatomic) NSString *pageType;
@end

// C2C 与 B2C 接口
@interface ZZInfoDetailProxy : NSObject
- (void)requestInfoDetailDatas:(id)req success:(void(^)(id response))success failure:(void(^)(id error))failure;
- (void)requestGetSupplementaryInfoWith:(id)req success:(void(^)(id response))success failure:(void(^)(id error))failure;
@end

@interface ZZGoodsDetailProxy : NSObject
- (void)requestGoodsDetailDateWithRequestModel:(id)req success:(void(^)(id response))success failure:(void(^)(id error))failure;
- (void)requestGoodsDetailExtraDateWithRequestModel:(id)req success:(void(^)(id response))success failure:(void(^)(id error))failure;
@end

// ====== 2. 声明列表控制器 ======
@interface ZZListingAprilViewController : UIViewController
@property (retain, nonatomic) NSArray *dataArray;
- (void)loadData;

// 自定义方法声明
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_filterWithVersion:(NSString *)version;
- (void)custom_collectProductsFrom:(id)obj into:(NSMutableDictionary *)dict;
- (NSString *)custom_extractInfoId:(id)obj;
- (BOOL)custom_deepTextSearch:(id)obj target:(NSString *)target visited:(NSMutableSet *)visited depth:(int)depth sample:(NSMutableString *)sampleStr;
- (void)custom_pruneZZFLEXArray:(NSMutableArray *)array matchedIds:(NSSet *)matchedIds kept:(int *)kept removed:(int *)removed;
- (void)custom_reloadCollectionView;
@end

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
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"全局系统版本检索" 
                                                                       message:@"请输入想筛选的iOS版本\n(已修复分页漏洞，将扫描你划过的所有商品)" 
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
    if (!self.dataArray || self.dataArray.count == 0) {
        return;
    }
    
    // ====== 核心修复：直接从屏幕数据源中提取所有已加载的商品 ======
    NSMutableDictionary *allProducts = [NSMutableDictionary dictionary];
    [self custom_collectProductsFrom:self.dataArray into:allProducts];
    
    if (allProducts.count == 0) {
        UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"提示" message:@"当前列表未能识别到商品，请刷新重试" preferredStyle:UIAlertControllerStyleAlert];
        [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:emptyAlert animated:YES completion:nil];
        return;
    }
    
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在全局深度扫描" 
                                                                          message:[NSString stringWithFormat:@"已锁定 %lu 个商品，正在进行本地与网络深度挖掘...", (unsigned long)allProducts.count]
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSLock *lock = [[NSLock alloc] init];
    
    NSMutableArray *retainedProxies = [NSMutableArray array];
    
    __block int localMatchCount = 0;
    __block int netMatchCount = 0;
    __block int netReqCount = 0;
    NSMutableString *sampleResponseStr = [[NSMutableString alloc] init];
    
    NSString *target = [[version lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    Class ReqModelClass = NSClassFromString(@"ZZInfoDetailRequestModel");
    
    for (NSString *infoId in allProducts.allKeys) {
        id item = allProducts[infoId];
        
        // ====== 第一步：本地深度搜索 (完美解决列表有却搜不到的问题) ======
        NSMutableSet *visited = [NSMutableSet set];
        if ([self custom_deepTextSearch:item target:target visited:visited depth:0 sample:sampleResponseStr]) {
            [matchedInfoIds addObject:infoId];
            localMatchCount++;
            continue; // 本地命中了就不发请求了，加速！
        }
        
        // ====== 第二步：网络请求查详情页 (解决详情里有但列表没写的问题) ======
        id reqModel = [[ReqModelClass alloc] init];
        [reqModel setValue:infoId forKey:@"infoID"];
        [reqModel setValue:@(1) forKey:@"from"];
        [reqModel setValue:@"1" forKey:@"pageType"];
        
        void (^handleResponse)(id) = ^(id response) {
            [lock lock]; netReqCount++; [lock unlock];
            
            NSMutableSet *netVisited = [NSMutableSet set];
            BOOL isMatch = [self custom_deepTextSearch:response target:target visited:netVisited depth:0 sample:nil];
            
            if (isMatch) {
                [lock lock];
                if (![matchedInfoIds containsObject:infoId]) {
                    [matchedInfoIds addObject:infoId];
                    netMatchCount++;
                }
                [lock unlock];
            }
            dispatch_group_leave(group);
        };
        
        void (^handleFailure)(id) = ^(id error) {
            dispatch_group_leave(group);
        };
        
        Class ProxyClassC2C = NSClassFromString(@"ZZInfoDetailProxy");
        if (ProxyClassC2C) {
            id proxyC2C = [[ProxyClassC2C alloc] init];
            [retainedProxies addObject:proxyC2C];
            if ([proxyC2C respondsToSelector:@selector(requestInfoDetailDatas:success:failure:)]) {
                dispatch_group_enter(group);
                [proxyC2C requestInfoDetailDatas:reqModel success:handleResponse failure:handleFailure];
            }
        }
        
        Class ProxyClassB2C = NSClassFromString(@"ZZGoodsDetailProxy");
        if (ProxyClassB2C) {
            id proxyB2C = [[ProxyClassB2C alloc] init];
            [retainedProxies addObject:proxyB2C];
            if ([proxyB2C respondsToSelector:@selector(requestGoodsDetailDateWithRequestModel:success:failure:)]) {
                dispatch_group_enter(group);
                [proxyB2C requestGoodsDetailDateWithRequestModel:reqModel success:handleResponse failure:handleFailure];
            }
        }
    }
    
    __weak typeof(self) weakSelf = self;
    
    // 等待所有任务完成
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [loadingAlert dismissViewControllerAnimated:YES completion:^{
            [retainedProxies removeAllObjects];
            
            if (matchedInfoIds.count > 0) {
                int kept = 0, removed = 0;
                NSMutableArray *mutDataArray = [weakSelf.dataArray mutableCopy];
                [weakSelf custom_pruneZZFLEXArray:mutDataArray matchedIds:matchedInfoIds kept:&kept removed:&removed];
                weakSelf.dataArray = mutDataArray;
                
                [weakSelf custom_reloadCollectionView];
                
                NSString *resultMsg = [NSString stringWithFormat:@"总计处理商品: %lu 个\n本地精准命中: %d 个\n详情挖掘命中: %d 个\n\n已为您剔除 %d 个无关商品！", (unsigned long)allProducts.count, localMatchCount, netMatchCount, removed];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"太棒了" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:successAlert animated:YES completion:nil];
                
            } else {
                NSString *resultMsg = [NSString stringWithFormat:@"总计处理商品: %lu 个\n网络深入排查: %d 次\n\n依然未找到匹配项。\n为证明爬虫运行正常，截取第一台设备属性：\n%@\n\n※ 请继续向下滑动加载更多，再重试！", (unsigned long)allProducts.count, netReqCount, sampleResponseStr.length > 0 ? sampleResponseStr : @"空"];
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"当前列表无匹配项" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"好的，我往下多划一点" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

// ====== 递归提取列表中的所有商品 ======
%new
- (void)custom_collectProductsFrom:(id)obj into:(NSMutableDictionary *)dict {
    if (!obj) return;
    
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) {
            [self custom_collectProductsFrom:item into:dict];
        }
        return;
    }
    
    if ([obj respondsToSelector:NSSelectorFromString(@"itemsArray")]) {
        @try {
            id items = [obj valueForKey:@"itemsArray"];
            [self custom_collectProductsFrom:items into:dict];
        } @catch(...) {}
        return;
    }
    
    id realData = obj;
    if ([obj respondsToSelector:NSSelectorFromString(@"dataModel")]) {
        id inner = [obj valueForKey:@"dataModel"];
        if (inner) realData = inner;
    }
    
    NSString *infoId = [self custom_extractInfoId:realData];
    if (infoId && infoId.length > 4) {
        dict[infoId] = realData;
    }
}

// ====== 无限安全的底层文字爬虫 ======
%new
- (BOOL)custom_deepTextSearch:(id)obj target:(NSString *)target visited:(NSMutableSet *)visited depth:(int)depth sample:(NSMutableString *)sampleStr {
    if (!obj || depth > 10) return NO;
    
    NSValue *ptr = [NSValue valueWithNonretainedObject:obj];
    if ([visited containsObject:ptr]) return NO;
    [visited addObject:ptr];
    
    if ([obj isKindOfClass:[NSString class]]) {
        NSString *rawStr = (NSString *)obj;
        
        if ([rawStr containsString:@"<ZZ"] || [rawStr containsString:@"ZZCommonFeed"]) return NO;
        
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
    
    if ([obj isKindOfClass:[NSAttributedString class]]) {
        NSString *rawStr = [(NSAttributedString *)obj string];
        if (rawStr) return [self custom_deepTextSearch:rawStr target:target visited:visited depth:depth+1 sample:sampleStr];
        return NO;
    }
    
    if ([obj isKindOfClass:[NSNumber class]]) {
        return [self custom_deepTextSearch:[(NSNumber *)obj stringValue] target:target visited:visited depth:depth+1 sample:sampleStr];
    }
    
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) {
            if ([self custom_deepTextSearch:item target:target visited:visited depth:depth+1 sample:sampleStr]) return YES;
        }
        return NO;
    }
    
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id val in [(NSDictionary *)obj allValues]) {
            if ([self custom_deepTextSearch:val target:target visited:visited depth:depth+1 sample:sampleStr]) return YES;
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
                            if (val) {
                                if ([self custom_deepTextSearch:val target:target visited:visited depth:depth+1 sample:sampleStr]) {
                                    free(properties);
                                    return YES;
                                }
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
            if ([matchedIds containsObject:infoId]) {
                (*kept)++;
            } else {
                [array removeObjectAtIndex:i];
                (*removed)++;
            }
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
