#import <UIKit/UIKit.h>

// ====== 消除 ARC 警告，声明转字典方法 ======
@interface NSObject (ZZNativeDataConvert)
- (id)modelToDictionary;
- (id)mj_keyValues;
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
- (BOOL)custom_matchResponse:(id)response target:(NSString *)target sample:(NSMutableString *)sampleStr;
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
                                                                       message:@"请输入想筛选的iOS版本\n(已搭载全属性降维解析引擎)" 
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
    
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在双路并发拉取" 
                                                                          message:@"后台正在强力拆解详情模型，请稍候..." 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSLock *lock = [[NSLock alloc] init];
    
    // 强引用代理对象，防止 ARC 提前销毁
    NSMutableArray *retainedProxies = [NSMutableArray array];
    
    __block int matchCount = 0;
    __block int reqSuccessCount = 0;
    NSMutableString *sampleResponseStr = [[NSMutableString alloc] init];
    
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
                    [lock lock]; 
                    reqSuccessCount++; 
                    
                    BOOL isMatch = [self custom_matchResponse:response target:target sample:(sampleResponseStr.length == 0 ? sampleResponseStr : nil)];
                    if (isMatch) {
                        if (![matchedInfoIds containsObject:infoId]) {
                            [matchedInfoIds addObject:infoId];
                            matchCount++;
                        }
                    }
                    [lock unlock];
                    dispatch_group_leave(group);
                } failure:^(id error) {
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
                    [lock lock]; 
                    reqSuccessCount++; 
                    
                    BOOL isMatch = [self custom_matchResponse:response target:target sample:(sampleResponseStr.length == 0 ? sampleResponseStr : nil)];
                    if (isMatch) {
                        if (![matchedInfoIds containsObject:infoId]) {
                            [matchedInfoIds addObject:infoId];
                            matchCount++;
                        }
                    }
                    [lock unlock];
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
                
                NSString *resultMsg = [NSString stringWithFormat:@"请求成功: %d 个\n匹配命中: %d 个", reqSuccessCount, matchCount];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"完美" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:successAlert animated:YES completion:nil];
                
            } else {
                NSString *resultMsg = [NSString stringWithFormat:@"请求成功: %d 个\n匹配命中: 0 个\n\n【服务器数据采样】:\n%@", reqSuccessCount, sampleResponseStr.length > 0 ? sampleResponseStr : @"解析为空"];
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"未能筛到相关商品" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

// ====== 终极降维打击：利用官方方法转字典 + Description 进行解析 ======
%new
- (BOOL)custom_matchResponse:(id)response target:(NSString *)target sample:(NSMutableString *)sampleStr {
    if (!response) return NO;
    
    NSString *rawStr = nil;
    @try {
        id dict = nil;
        // 1. mj_keyValues 会深度递归，把包含的所有子模型全部变成干净的字典！
        if ([response respondsToSelector:@selector(mj_keyValues)]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            dict = [response performSelector:@selector(mj_keyValues)];
            #pragma clang diagnostic pop
        }
        
        // 2. 转转官方方法兜底
        if (!dict && [response respondsToSelector:@selector(modelToDictionary)]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            dict = [response performSelector:@selector(modelToDictionary)];
            #pragma clang diagnostic pop
        }
        
        // 核心突破点：直接使用字典自带的 description，它会把里面所有的嵌套内容原封不动打印成文本！
        if (dict) {
            rawStr = [dict description];
        } else if ([response respondsToSelector:@selector(responseString)]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            rawStr = [response performSelector:@selector(responseString)];
            #pragma clang diagnostic pop
        } else {
            rawStr = [response description];
        }
        
        // 保存一条样本用于弹窗诊断
        if (sampleStr && rawStr.length > 0) {
            [sampleStr appendString:(rawStr.length > 500 ? [rawStr substringToIndex:500] : rawStr)];
        }
        
        // ====== 第一层匹配：全文检索 ======
        if (rawStr && rawStr.length > 0) {
            NSString *cleanStr = [[rawStr lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
            if ([cleanStr containsString:target]) {
                return YES;
            }
        }
        
        // ====== 第二层匹配：专门针对转转的验机详情模型 (对付 ZZGoodsDetailParamModel 等) ======
        NSArray *possibleKeys = @[@"title", @"content", @"sellerDescription", @"extendJson", @"param", @"extraData", @"operatingContent", @"serviceInfo", @"qualityDes", @"overview"];
        for (NSString *key in possibleKeys) {
            if ([response respondsToSelector:NSSelectorFromString(key)]) {
                id val = [response valueForKey:key];
                if (val) {
                    // 如果它是一个数组（比如验机报告各项参数），钻进去提取 paramValue
                    if ([val isKindOfClass:[NSArray class]]) {
                        for (id item in (NSArray *)val) {
                            if ([item respondsToSelector:NSSelectorFromString(@"paramValue")]) {
                                NSString *pVal = [[item valueForKey:@"paramValue"] description];
                                if (pVal && [[[pVal lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""] containsString:target]) {
                                    return YES;
                                }
                            }
                        }
                    }
                    
                    // 获取值的描述
                    NSString *valDesc = [[val description] lowercaseString];
                    valDesc = [valDesc stringByReplacingOccurrencesOfString:@" " withString:@""];
                    if ([valDesc containsString:target]) {
                        return YES;
                    }
                }
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
