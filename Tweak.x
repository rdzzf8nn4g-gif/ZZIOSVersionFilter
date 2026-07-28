#import <UIKit/UIKit.h>

// ====== 1. 声明转转官方和第三方的数据转换方法，消除 ARC 警告 ======
@interface NSObject (ZZNativeDataConvert)
- (id)modelToDictionary; // 转转官方自带的模型转字典神器
- (id)mj_keyValues;
- (id)yy_modelToJSONObject;
- (id)responseString;
- (id)responseJSONObject;
@end

// ====== 2. 声明网络请求模型与代理 ======
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

// ====== 3. 声明列表控制器 ======
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
- (BOOL)custom_matchResponse:(id)response target:(NSString *)target;
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
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"系统版本官方解析检索" 
                                                                       message:@"请输入想筛选的iOS版本\n(已调用转转官方modelToDictionary引擎)" 
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
    // 1. 直击转转底层商品数据源
    if (!self.firstPageResponseData || ![self.firstPageResponseData respondsToSelector:NSSelectorFromString(@"infos")]) {
        return;
    }
    
    NSArray *infos = [self.firstPageResponseData valueForKey:@"infos"];
    if (!infos || infos.count == 0) return;
    
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在静默并发拉取" 
                                                                          message:@"后台已启动官方引擎解析详情，请稍候..." 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSLock *lock = [[NSLock alloc] init];
    
    // 强引用代理对象，防止 ARC 提前销毁
    NSMutableArray *retainedProxies = [NSMutableArray array];
    
    __block int matchCount = 0;
    __block int reqSuccessCount = 0;
    __block int reqFailCount = 0;
    __block NSString *sampleStr = @""; // 取第一条数据用于诊断
    
    // 清理输入的目标版本号 (转全小写 + 去空格)
    NSString *target = [[version lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    Class ReqModelClass = NSClassFromString(@"ZZInfoDetailRequestModel");
    
    for (id item in infos) {
        NSString *infoId = [self custom_extractInfoId:item];
        if (!infoId || infoId.length < 4) continue;
        
        // 构造请求体
        id reqModel = [[ReqModelClass alloc] init];
        [reqModel setValue:infoId forKey:@"infoID"];
        [reqModel setValue:@(1) forKey:@"from"];
        [reqModel setValue:@"1" forKey:@"pageType"];
        
        // ====== 路线 1：C2C 个人商品接口 ======
        Class ProxyClassC2C = NSClassFromString(@"ZZInfoDetailProxy");
        if (ProxyClassC2C) {
            dispatch_group_enter(group);
            id proxyC2C = [[ProxyClassC2C alloc] init];
            [retainedProxies addObject:proxyC2C];
            
            if ([proxyC2C respondsToSelector:@selector(requestInfoDetailDatas:success:failure:)]) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [proxyC2C requestInfoDetailDatas:reqModel success:^(id response) {
                    [lock lock]; reqSuccessCount++; [lock unlock];
                    
                    if ([self custom_matchResponse:response target:target]) {
                        [lock lock];
                        if (![matchedInfoIds containsObject:infoId]) {
                            [matchedInfoIds addObject:infoId];
                            matchCount++;
                        }
                        [lock unlock];
                    } else if (sampleStr.length == 0) {
                        // 留底做诊断
                        [lock lock]; sampleStr = [[response description] substringToIndex:MIN(500, [response description].length)]; [lock unlock];
                    }
                    dispatch_group_leave(group);
                } failure:^(id error) {
                    [lock lock]; reqFailCount++; [lock unlock];
                    dispatch_group_leave(group);
                }];
                #pragma clang diagnostic pop
            } else {
                dispatch_group_leave(group);
            }
        }
        
        // ====== 路线 2：B2C 验机精品接口 ======
        Class ProxyClassB2C = NSClassFromString(@"ZZGoodsDetailProxy");
        if (ProxyClassB2C) {
            dispatch_group_enter(group);
            id proxyB2C = [[ProxyClassB2C alloc] init];
            [retainedProxies addObject:proxyB2C];
            
            if ([proxyB2C respondsToSelector:@selector(requestGoodsDetailDateWithRequestModel:success:failure:)]) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [proxyB2C requestGoodsDetailDateWithRequestModel:reqModel success:^(id response) {
                    [lock lock]; reqSuccessCount++; [lock unlock];
                    
                    if ([self custom_matchResponse:response target:target]) {
                        [lock lock];
                        if (![matchedInfoIds containsObject:infoId]) {
                            [matchedInfoIds addObject:infoId];
                            matchCount++;
                        }
                        [lock unlock];
                    }
                    dispatch_group_leave(group);
                } failure:^(id error) {
                    [lock lock]; reqFailCount++; [lock unlock];
                    dispatch_group_leave(group);
                }];
                #pragma clang diagnostic pop
            } else {
                dispatch_group_leave(group);
            }
        }
    }
    
    __weak typeof(self) weakSelf = self;
    
    // 5. 等待所有并发网络请求完成
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
                
                // 修复：在这里使用了 reqFailCount，消除编译警告
                NSString *resultMsg = [NSString stringWithFormat:@"请求成功: %d 个\n请求失败: %d 个\n匹配命中: %d 个", reqSuccessCount, reqFailCount, matchCount];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"完美" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:successAlert animated:YES completion:nil];
                
            } else {
                // 修复：在这里使用了 reqFailCount，消除编译警告
                NSString *resultMsg = [NSString stringWithFormat:@"请求成功: %d 个\n请求失败: %d 个\n匹配命中: 0 个\n\n【服务器首条数据采样】:\n%@", reqSuccessCount, reqFailCount, sampleStr.length > 0 ? sampleStr : @"获取为空"];
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"未能筛到相关商品" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

// ====== 终极降维打击：利用官方方法转 JSON 纯文本进行搜索 ======
%new
- (BOOL)custom_matchResponse:(id)response target:(NSString *)target {
    if (!response) return NO;
    
    NSString *rawJsonStr = nil;
    @try {
        id dict = nil;
        // 1. 转转官方自带的模型转字典神器（最安全，最完整）
        if ([response respondsToSelector:@selector(modelToDictionary)]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            dict = [response performSelector:@selector(modelToDictionary)];
            #pragma clang diagnostic pop
        }
        // 2. 如果是网络框架请求体本身，拿 responseString
        else if ([response respondsToSelector:@selector(responseString)]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            rawJsonStr = [response performSelector:@selector(responseString)];
            #pragma clang diagnostic pop
        }
        // 3. 第三方兜底转换
        else if ([response respondsToSelector:@selector(mj_keyValues)]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            dict = [response performSelector:@selector(mj_keyValues)];
            #pragma clang diagnostic pop
        }
        
        // 字典转纯文本 JSON
        if (dict && [dict isKindOfClass:[NSDictionary class]]) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
            if (jsonData) {
                rawJsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            }
        }
        
        // 终极匹配
        if (rawJsonStr && rawJsonStr.length > 0) {
            NSString *cleanJson = [[rawJsonStr lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
            if ([cleanJson containsString:target]) {
                return YES;
            }
        }
    } @catch (NSException *e) {}
    
    return NO;
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
