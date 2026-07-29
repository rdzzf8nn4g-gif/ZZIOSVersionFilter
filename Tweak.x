#import <UIKit/UIKit.h>

// ====== 消除 ARC 警告，声明转字典方法 ======
@interface NSObject (ZZNativeDataConvert)
- (id)modelToDictionary;
- (id)mj_keyValues;
- (id)yy_modelToJSONObject;
- (id)responseString;
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
- (void)requestGetSupplementaryInfoWith:(id)req success:(void(^)(id response))success failure:(void(^)(id error))failure;
@end

// B2C 接口
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
- (BOOL)custom_matchResponse:(id)response target:(NSString *)target sample:(NSMutableString *)sampleStr;
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
                                                                       message:@"请输入想筛选的iOS版本\n(已开启四路API齐发与全能解码引擎)" 
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
    
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在四路并发拉取" 
                                                                          message:@"后台正在强力破解编码并拆解详情，请稍候..." 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSLock *lock = [[NSLock alloc] init];
    
    // 强引用代理对象
    NSMutableArray *retainedProxies = [NSMutableArray array];
    
    __block int matchCount = 0;
    __block int reqSuccessCount = 0;
    NSMutableString *sampleResponseStr = [[NSMutableString alloc] init];
    
    // 目标文本标准化
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
        
        // ====== 请求通用处理 Block ======
        void (^handleResponse)(id) = ^(id response) {
            [lock lock]; reqSuccessCount++; [lock unlock];
            
            BOOL isMatch = [self custom_matchResponse:response target:target sample:sampleResponseStr];
            if (isMatch) {
                [lock lock];
                if (![matchedInfoIds containsObject:infoId]) {
                    [matchedInfoIds addObject:infoId];
                    matchCount++;
                }
                [lock unlock];
            }
            dispatch_group_leave(group);
        };
        
        void (^handleFailure)(id) = ^(id error) {
            dispatch_group_leave(group);
        };
        
        // ====== 路线 1 & 2：C2C 接口 ======
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
        
        // ====== 路线 3 & 4：B2C 接口 ======
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
    
    // 5. 等待所有并发网络请求完成
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [loadingAlert dismissViewControllerAnimated:YES completion:^{
            
            [retainedProxies removeAllObjects];
            
            if (matchCount > 0) {
                NSMutableArray *filteredInfos = [NSMutableArray array];
                for (id item in infos) {
                    NSString *infoId = [weakSelf custom_extractInfoId:item];
                    if (infoId && [matchedInfoIds containsObject:infoId]) {
                        [filteredInfos addObject:item];
                    }
                }
                
                [weakSelf.firstPageResponseData setValue:filteredInfos forKey:@"infos"];
                
                if ([weakSelf respondsToSelector:NSSelectorFromString(@"reloadListingGoodsWithRespModel:")]) {
                    #pragma clang diagnostic push
                    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [weakSelf performSelector:NSSelectorFromString(@"reloadListingGoodsWithRespModel:") withObject:weakSelf.firstPageResponseData];
                    #pragma clang diagnostic pop
                } else {
                    [weakSelf custom_reloadCollectionView];
                }
                
                NSString *resultMsg = [NSString stringWithFormat:@"接口全通返回: %d 次\n筛选匹配命中: %d 个", reqSuccessCount, matchCount];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"完美" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:successAlert animated:YES completion:nil];
                
            } else {
                NSString *resultMsg = [NSString stringWithFormat:@"接口全通返回: %d 次\n匹配命中: 0 个\n\n【服务器最终解密采样】:\n%@", reqSuccessCount, sampleResponseStr.length > 0 ? sampleResponseStr : @"解析为空"];
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"未能筛到相关商品" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

// ====== 终极降维打击：全能解码引擎 ======
%new
- (BOOL)custom_matchResponse:(id)response target:(NSString *)target sample:(NSMutableString *)sampleStr {
    if (!response) return NO;
    
    NSString *rawStr = nil;
    @try {
        id dict = nil;
        if ([response respondsToSelector:@selector(modelToDictionary)]) {
            dict = [response performSelector:@selector(modelToDictionary)];
        }
        if (!dict && [response respondsToSelector:@selector(mj_keyValues)]) {
            dict = [response performSelector:@selector(mj_keyValues)];
        }
        if (!dict && [response respondsToSelector:@selector(yy_modelToJSONObject)]) {
            dict = [response performSelector:@selector(yy_modelToJSONObject)];
        }
        
        // 提取文本描述
        if (dict) {
            rawStr = [dict description];
        } else if ([response respondsToSelector:@selector(responseString)]) {
            rawStr = [response performSelector:@selector(responseString)];
        } else {
            rawStr = [response description];
        }
        
        if (!rawStr || rawStr.length == 0) return NO;

        // ====== 核心：强力解除 Unicode 和 URL 编码的伪装 ======
        // 1. 将 \Uxxxx (例如 \U53cd\U9988) 转换为真实汉字
        NSString *unicodeDecoded = [NSString stringWithCString:[rawStr cStringUsingEncoding:NSUTF8StringEncoding] encoding:NSNonLossyASCIIStringEncoding];
        if (unicodeDecoded) {
            rawStr = unicodeDecoded;
        }
        
        // 2. 将 %xx (例如 %E8%8B%B9) URL 编码转换为真实汉字/符号
        NSString *urlDecoded = [rawStr stringByRemovingPercentEncoding];
        if (urlDecoded) {
            rawStr = urlDecoded;
        }

        // 保存一条解密最完善的样本用于弹窗诊断
        if (sampleStr && sampleStr.length == 0 && rawStr.length > 0) {
            [sampleStr appendString:(rawStr.length > 500 ? [rawStr substringToIndex:500] : rawStr)];
        }
        
        // ====== 全量暴力比对 ======
        NSString *cleanStr = [[rawStr lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
        if ([cleanStr containsString:target]) {
            return YES;
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
