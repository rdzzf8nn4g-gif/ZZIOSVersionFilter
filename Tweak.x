#import <UIKit/UIKit.h>

// ====== 消除 ARC 警告，声明转字典方法 ======
@interface NSObject (ZZNativeDataConvert)
- (id)yy_modelToJSONObject;
- (id)mj_keyValues;
- (id)modelToDictionary;
@end

// ====== 1. 声明转转的网络请求类 ======
@interface ZZInfoDetailRequestModel : NSObject
@property (copy, nonatomic) NSString *infoID;
@property (nonatomic) unsigned long long from;
@property (copy, nonatomic) NSString *pageType;
@end

// C2C 接口
@interface ZZInfoDetailProxy : NSObject
- (void)requestInfoDetailDatas:(id)req success:(void(^)(id response))success failure:(void(^)(id error))failure;
@end

// B2C 接口
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
- (void)real_reloadData:(id)arg;
- (void)reloadListingGoodsWithRespModel:(id)arg;

// 自定义方法声明
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_filterWithVersion:(NSString *)version;
- (NSString *)custom_extractInfoId:(id)obj;
- (NSString *)custom_forceStringify:(id)obj;
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
                                                                       message:@"请输入想筛选的iOS版本\n(已挂载 YYModel 降维压扁引擎)" 
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
                                                                          message:@"正在将底层对象通过 YYModel 强制降维..." 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    NSString *target = [[version lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSMutableString *sampleStr = [[NSMutableString alloc] init];
    
    int localMatchCount = 0;
    
    // ====== 1. 本地 UI 模型强行降维提取 (解决“列表有却搜不到”的问题) ======
    for (id item in infos) {
        NSString *infoId = [self custom_extractInfoId:item];
        if (!infoId || infoId.length < 4) continue;
        
        // 压扁对象为纯文本
        NSString *localStr = [self custom_forceStringify:item];
        
        // 采集一段文本用来弹窗看效果
        if (sampleStr.length < 600 && localStr.length > 0) {
            [sampleStr appendFormat:@"[%@] ", localStr];
        }
        
        if ([localStr containsString:target]) {
            [matchedInfoIds addObject:infoId];
            localMatchCount++;
        }
    }
    
    // ====== 2. 网络请求兜底 (如果本地标签没写全，去详情页抓) ======
    dispatch_group_t group = dispatch_group_create();
    NSLock *lock = [[NSLock alloc] init];
    NSMutableArray *retainedProxies = [NSMutableArray array];
    
    __block int netReqCount = 0;
    __block int netMatchCount = 0;
    
    Class ReqModelClass = NSClassFromString(@"ZZInfoDetailRequestModel");
    
    for (id item in infos) {
        NSString *infoId = [self custom_extractInfoId:item];
        if (!infoId || infoId.length < 4) continue;
        if ([matchedInfoIds containsObject:infoId]) continue; // 已经本地命中了就不发请求了
        
        id reqModel = [[ReqModelClass alloc] init];
        [reqModel setValue:infoId forKey:@"infoID"];
        [reqModel setValue:@(1) forKey:@"from"];
        [reqModel setValue:@"1" forKey:@"pageType"];
        
        // 路线 1: C2C
        Class ProxyClassC2C = NSClassFromString(@"ZZInfoDetailProxy");
        if (ProxyClassC2C) {
            id proxyC2C = [[ProxyClassC2C alloc] init];
            [retainedProxies addObject:proxyC2C];
            if ([proxyC2C respondsToSelector:@selector(requestInfoDetailDatas:success:failure:)]) {
                dispatch_group_enter(group);
                [proxyC2C requestInfoDetailDatas:reqModel success:^(id response) {
                    [lock lock]; netReqCount++; [lock unlock];
                    NSString *netStr = [self custom_forceStringify:response];
                    if ([netStr containsString:target]) {
                        [lock lock];
                        if (![matchedInfoIds containsObject:infoId]) {
                            [matchedInfoIds addObject:infoId];
                            netMatchCount++;
                        }
                        [lock unlock];
                    }
                    dispatch_group_leave(group);
                } failure:^(id error) { dispatch_group_leave(group); }];
            }
        }
        
        // 路线 2: B2C 验机
        Class ProxyClassB2C = NSClassFromString(@"ZZGoodsDetailProxy");
        if (ProxyClassB2C) {
            id proxyB2C = [[ProxyClassB2C alloc] init];
            [retainedProxies addObject:proxyB2C];
            if ([proxyB2C respondsToSelector:@selector(requestGoodsDetailDateWithRequestModel:success:failure:)]) {
                dispatch_group_enter(group);
                [proxyB2C requestGoodsDetailDateWithRequestModel:reqModel success:^(id response) {
                    [lock lock]; netReqCount++; [lock unlock];
                    NSString *netStr = [self custom_forceStringify:response];
                    if ([netStr containsString:target]) {
                        [lock lock];
                        if (![matchedInfoIds containsObject:infoId]) {
                            [matchedInfoIds addObject:infoId];
                            netMatchCount++;
                        }
                        [lock unlock];
                    }
                    dispatch_group_leave(group);
                } failure:^(id error) { dispatch_group_leave(group); }];
            }
        }
    }
    
    __weak typeof(self) weakSelf = self;
    
    // 3. 所有任务执行完毕，清理 ZZFLEX 列表
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [loadingAlert dismissViewControllerAnimated:YES completion:^{
            [retainedProxies removeAllObjects];
            
            if (matchedInfoIds.count > 0) {
                // 直接修剪屏幕驱动器 dataArray 里的无用商品
                int kept = 0, removed = 0;
                NSMutableArray *mutDataArray = [weakSelf.dataArray mutableCopy];
                [weakSelf custom_pruneZZFLEXArray:mutDataArray matchedIds:matchedInfoIds kept:&kept removed:&removed];
                weakSelf.dataArray = mutDataArray;
                
                // 强制重绘列表
                [weakSelf custom_reloadCollectionView];
                
                NSString *resultMsg = [NSString stringWithFormat:@"本地UI命中: %d 个\n网络详情命中: %d 个\n\n成功为您保留 %d 个匹配商品！", localMatchCount, netMatchCount, kept];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"完美" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:successAlert animated:YES completion:nil];
                
            } else {
                NSString *resultMsg = [NSString stringWithFormat:@"本地扫描完成，网络请求(%d次)\n均未命中!\n\n【强行压扁后的文字采样】:\n%@", netReqCount, sampleStr.length > 0 ? sampleStr : @"空"];
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"未能筛到相关商品" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

// ====== 终极杀招：把一切对象强行压扁为字符串 ======
%new
- (NSString *)custom_forceStringify:(id)obj {
    if (!obj) return @"";
    NSString *resultStr = @"";
    @try {
        id dict = nil;
        // 使用各大厂通用的 JSON 序列化方法，把对象的层层外壳剥掉变成字典
        if ([obj respondsToSelector:@selector(yy_modelToJSONObject)]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            dict = [obj performSelector:@selector(yy_modelToJSONObject)];
            #pragma clang diagnostic pop
        } else if ([obj respondsToSelector:@selector(mj_keyValues)]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            dict = [obj performSelector:@selector(mj_keyValues)];
            #pragma clang diagnostic pop
        } else if ([obj respondsToSelector:@selector(modelToDictionary)]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            dict = [obj performSelector:@selector(modelToDictionary)];
            #pragma clang diagnostic pop
        }
        
        if (dict) {
            resultStr = [dict description];
        } else {
            resultStr = [obj description];
        }
        
        // 特殊照顾：强行剥开转转列表用于显示小标签的 labelPosition
        if ([obj respondsToSelector:NSSelectorFromString(@"labelPosition")]) {
            id labelPos = [obj valueForKey:@"labelPosition"];
            if (labelPos) {
                if ([labelPos respondsToSelector:@selector(yy_modelToJSONObject)]) {
                    #pragma clang diagnostic push
                    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    resultStr = [resultStr stringByAppendingFormat:@" %@", [[labelPos performSelector:@selector(yy_modelToJSONObject)] description]];
                    #pragma clang diagnostic pop
                } else {
                    resultStr = [resultStr stringByAppendingFormat:@" %@", [labelPos description]];
                }
            }
        }
    } @catch(...) {}

    // 如果里面有 \Uxxxx 这种 Unicode 汉字乱码，强行翻译成正常的中文！
    NSString *unicodeDecoded = [NSString stringWithCString:[resultStr cStringUsingEncoding:NSUTF8StringEncoding] encoding:NSNonLossyASCIIStringEncoding];
    if (unicodeDecoded) resultStr = unicodeDecoded;
    
    // 如果里面有 %xx 这种 URL 编码，强行解开！
    NSString *urlDecoded = [resultStr stringByRemovingPercentEncoding];
    if (urlDecoded) resultStr = urlDecoded;

    // 转成小写，去掉一切空格，让 "15.4" 无所遁形
    return [[resultStr lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
}

// ====== 原地修剪 ZZFLEX 列表 ======
%new
- (void)custom_pruneZZFLEXArray:(NSMutableArray *)array matchedIds:(NSSet *)matchedIds kept:(int *)kept removed:(int *)removed {
    for (NSInteger i = array.count - 1; i >= 0; i--) {
        id item = array[i];
        
        // ZZFLEX 的 Section 分组
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
        
        // 普通嵌套数组
        if ([item isKindOfClass:[NSMutableArray class]]) {
            [self custom_pruneZZFLEXArray:item matchedIds:matchedIds kept:kept removed:removed];
            continue;
        }
        
        // 获取真正的模型数据
        id realData = item;
        if ([item respondsToSelector:NSSelectorFromString(@"dataModel")]) {
            id inner = [item valueForKey:@"dataModel"];
            if (inner) realData = inner;
        }
        
        NSString *infoId = [self custom_extractInfoId:realData];
        if (infoId && infoId.length > 4) {
            // 如果不在匹配成功的集合里，直接杀掉！
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
