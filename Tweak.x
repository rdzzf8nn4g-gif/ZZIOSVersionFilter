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

@interface ZZListingResponseModel : NSObject
@property (retain, nonatomic) NSMutableArray *infos;
@end

// ====== 2. 声明列表控制器 ======
@interface ZZListingAprilViewController : UIViewController
@property (retain, nonatomic) NSArray *dataArray;
@property (retain, nonatomic) ZZListingResponseModel *firstPageResponseData;
- (void)loadData;
- (void)real_reloadData:(id)arg;
- (void)reloadListingGoodsWithRespModel:(id)arg;

// 自定义方法声明
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_filterWithVersion:(NSString *)version;
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
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"系统版本核弹级检索" 
                                                                       message:@"请输入想筛选的iOS版本\n(已挂载溯源内存爬虫，防闪退且无死角)" 
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
    if (!self.firstPageResponseData || ![self.firstPageResponseData respondsToSelector:NSSelectorFromString(@"infos")]) {
        return;
    }
    
    NSArray *infos = [self.firstPageResponseData valueForKey:@"infos"];
    if (!infos || infos.count == 0) return;
    
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在核弹级搜索" 
                                                                          message:@"后台已开启多路 API 与内存溯源爬虫，请稍候..." 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSLock *lock = [[NSLock alloc] init];
    
    // 保活代理，防止请求提早销毁
    NSMutableArray *retainedProxies = [NSMutableArray array];
    
    __block int localMatchCount = 0;
    __block int netMatchCount = 0;
    __block int netReqCount = 0;
    NSMutableString *sampleResponseStr = [[NSMutableString alloc] init];
    
    // 目标文本标准化：全小写 + 去空格
    NSString *target = [[version lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    Class ReqModelClass = NSClassFromString(@"ZZInfoDetailRequestModel");
    
    for (id item in infos) {
        NSString *infoId = [self custom_extractInfoId:item];
        if (!infoId || infoId.length < 4) continue;
        
        // ====== 第一道防线：本地列表缓存全属性溯源扫描 ======
        NSMutableSet *visited = [NSMutableSet set];
        if ([self custom_deepTextSearch:item target:target visited:visited depth:0 sample:sampleResponseStr]) {
            [matchedInfoIds addObject:infoId];
            localMatchCount++;
            continue; // 本地找到了就跳过网络请求，提速！
        }
        
        // ====== 第二道防线：四路网络并发兜底 ======
        id reqModel = [[ReqModelClass alloc] init];
        [reqModel setValue:infoId forKey:@"infoID"];
        [reqModel setValue:@(1) forKey:@"from"];
        [reqModel setValue:@"1" forKey:@"pageType"];
        
        void (^handleResponse)(id) = ^(id response) {
            [lock lock]; netReqCount++; [lock unlock];
            
            NSMutableSet *netVisited = [NSMutableSet set];
            BOOL isMatch = [self custom_deepTextSearch:response target:target visited:netVisited depth:0 sample:sampleResponseStr];
            
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
        
        // 路线 1 & 2：C2C 接口
        Class ProxyClassC2C = NSClassFromString(@"ZZInfoDetailProxy");
        if (ProxyClassC2C) {
            id proxyC2C = [[ProxyClassC2C alloc] init];
            [retainedProxies addObject:proxyC2C];
            if ([proxyC2C respondsToSelector:@selector(requestInfoDetailDatas:success:failure:)]) {
                dispatch_group_enter(group);
                [proxyC2C requestInfoDetailDatas:reqModel success:handleResponse failure:handleFailure];
            }
            if ([proxyC2C respondsToSelector:@selector(requestGetSupplementaryInfoWith:success:failure:)]) {
                dispatch_group_enter(group);
                [proxyC2C requestGetSupplementaryInfoWith:reqModel success:handleResponse failure:handleFailure];
            }
        }
        
        // 路线 3 & 4：B2C 接口
        Class ProxyClassB2C = NSClassFromString(@"ZZGoodsDetailProxy");
        if (ProxyClassB2C) {
            id proxyB2C = [[ProxyClassB2C alloc] init];
            [retainedProxies addObject:proxyB2C];
            if ([proxyB2C respondsToSelector:@selector(requestGoodsDetailDateWithRequestModel:success:failure:)]) {
                dispatch_group_enter(group);
                [proxyB2C requestGoodsDetailDateWithRequestModel:reqModel success:handleResponse failure:handleFailure];
            }
            if ([proxyB2C respondsToSelector:@selector(requestGoodsDetailExtraDateWithRequestModel:success:failure:)]) {
                dispatch_group_enter(group);
                [proxyB2C requestGoodsDetailExtraDateWithRequestModel:reqModel success:handleResponse failure:handleFailure];
            }
        }
    }
    
    __weak typeof(self) weakSelf = self;
    
    // 5. 等待所有请求完成
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [loadingAlert dismissViewControllerAnimated:YES completion:^{
            [retainedProxies removeAllObjects];
            
            if (matchedInfoIds.count > 0) {
                // 原地剔除无用商品
                int kept = 0, removed = 0;
                NSMutableArray *mutDataArray = [weakSelf.dataArray mutableCopy];
                [weakSelf custom_pruneZZFLEXArray:mutDataArray matchedIds:matchedInfoIds kept:&kept removed:&removed];
                weakSelf.dataArray = mutDataArray;
                
                // 重组 infos
                NSMutableArray *filteredInfos = [NSMutableArray array];
                for (id item in infos) {
                    NSString *infoId = [weakSelf custom_extractInfoId:item];
                    if (infoId && [matchedInfoIds containsObject:infoId]) {
                        [filteredInfos addObject:item];
                    }
                }
                [weakSelf.firstPageResponseData setValue:filteredInfos forKey:@"infos"];
                
                // 强制刷新
                [weakSelf custom_reloadCollectionView];
                
                NSString *resultMsg = [NSString stringWithFormat:@"本地精准命中: %d 个\n网络挖掘命中: %d 个\n\n已为您剔除 %d 个无关商品！", localMatchCount, netMatchCount, removed];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"完美" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:successAlert animated:YES completion:nil];
                
            } else {
                NSString *resultMsg = [NSString stringWithFormat:@"本地全量检索完毕\n网络接口辅助排查 (%d 次)\n匹配命中: 0 个\n\n【爬虫深入采样】:\n%@", netReqCount, sampleResponseStr.length > 0 ? sampleResponseStr : @"空"];
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"未能筛到相关商品" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

// ====== 终极核武器：带溯源机制的无限安全爬虫 ======
%new
- (BOOL)custom_deepTextSearch:(id)obj target:(NSString *)target visited:(NSMutableSet *)visited depth:(int)depth sample:(NSMutableString *)sampleStr {
    // 深度限制 10，完全规避递归死循环闪退
    if (!obj || depth > 10) return NO;
    
    // 防环形引用指针检测
    NSValue *ptr = [NSValue valueWithNonretainedObject:obj];
    if ([visited containsObject:ptr]) return NO;
    [visited addObject:ptr];
    
    // 1. 如果它是字符串，我们挖到底了！
    if ([obj isKindOfClass:[NSString class]]) {
        NSString *rawStr = (NSString *)obj;
        
        // 尝试解除 URL 和 Unicode 编码
        NSString *unicodeDecoded = [NSString stringWithCString:[rawStr cStringUsingEncoding:NSUTF8StringEncoding] encoding:NSNonLossyASCIIStringEncoding];
        if (unicodeDecoded) rawStr = unicodeDecoded;
        
        NSString *urlDecoded = [rawStr stringByRemovingPercentEncoding];
        if (urlDecoded) rawStr = urlDecoded;
        
        // 采集有效汉字或数字展示
        if (sampleStr && sampleStr.length < 600 && rawStr.length > 0 && ![rawStr hasPrefix:@"http"]) {
            [sampleStr appendFormat:@"[%@] ", rawStr];
        }
        
        NSString *cleanStr = [[rawStr lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
        if ([cleanStr containsString:target]) return YES;
        
        return NO;
    }
    
    // 2. 富文本解析
    if ([obj isKindOfClass:[NSAttributedString class]]) {
        NSString *rawStr = [(NSAttributedString *)obj string];
        if (rawStr) return [self custom_deepTextSearch:rawStr target:target visited:visited depth:depth+1 sample:sampleStr];
        return NO;
    }
    
    // 3. 数字解析
    if ([obj isKindOfClass:[NSNumber class]]) {
        return [self custom_deepTextSearch:[(NSNumber *)obj stringValue] target:target visited:visited depth:depth+1 sample:sampleStr];
    }
    
    // 4. 数组拆解
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) {
            if ([self custom_deepTextSearch:item target:target visited:visited depth:depth+1 sample:sampleStr]) return YES;
        }
        return NO;
    }
    
    // 5. 字典拆解
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id val in [(NSDictionary *)obj allValues]) {
            if ([self custom_deepTextSearch:val target:target visited:visited depth:depth+1 sample:sampleStr]) return YES;
        }
        return NO;
    }
    
    // 6. ====== 破壁之战：强制溯源父类的一切隐藏属性 ======
    NSString *className = NSStringFromClass([obj class]);
    if ([className hasPrefix:@"ZZ"] || [className hasPrefix:@"SimpleCheck"]) {
        Class currentClass = [obj class];
        
        // 循环直到根类 NSObject，把继承链上所有的属性全部刮下来！
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
            // 溯源：移到父类
            currentClass = class_getSuperclass(currentClass);
        }
    }
    
    return NO;
}

// ====== 原地修剪 ZZFLEX 列表 ======
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
