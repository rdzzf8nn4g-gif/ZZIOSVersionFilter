#import <UIKit/UIKit.h>

// ====== 消除 ARC 警告，声明转字典方法 ======
@interface NSObject (ZZModelToJSON)
- (id)mj_keyValues;
- (NSString *)mj_JSONString;
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

@interface ZZListingResponseModel : NSObject
@property (retain, nonatomic) NSMutableArray *infos;
@end

// ====== 2. 声明列表控制器 ======
@interface ZZListingAprilViewController : UIViewController
@property (retain, nonatomic) NSArray *dataArray;
@property (retain, nonatomic) ZZListingResponseModel *firstPageResponseData;
- (void)loadData;
- (void)reloadListingGoodsWithRespModel:(id)arg;

// 自定义方法声明
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_filterWithVersion:(NSString *)version;
- (NSString *)custom_extractInfoId:(id)obj;
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
                                                                       message:@"请输入想筛选的iOS版本\n(将提取底层原生 JSON 进行暴力检索)" 
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
    
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在静默拉取与分析" 
                                                                          message:@"正在将详情数据降维至 JSON 纯文本进行暴力检索..." 
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
    __block NSString *sampleResponseStr = @""; // 捕获服务器第一条返回数据，用于诊断
    
    // 清理输入的目标版本号 (转全小写 + 去空格)
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
        
        Class ProxyClass = NSClassFromString(@"ZZInfoDetailProxy");
        if (ProxyClass) {
            dispatch_group_enter(group);
            id proxy = [[ProxyClass alloc] init];
            [retainedProxies addObject:proxy]; // 保活
            
            if ([proxy respondsToSelector:@selector(requestInfoDetailDatas:success:failure:)]) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [proxy requestInfoDetailDatas:reqModel success:^(id response) {
                    [lock lock];
                    reqSuccessCount++;
                    [lock unlock];
                    
                    // ====== 核心：暴力提取原生 JSON 字符串 ======
                    NSString *rawJsonStr = @"";
                    @try {
                        // 1. 如果它是网络请求对象 (YTKRequest)，直接拿 responseString
                        if ([response respondsToSelector:NSSelectorFromString(@"responseString")]) {
                            rawJsonStr = [response valueForKey:@"responseString"];
                        } 
                        // 2. 如果拿不到 string，拿 JSON 对象自己序列化
                        else if ([response respondsToSelector:NSSelectorFromString(@"responseJSONObject")]) {
                            id jsonObj = [response valueForKey:@"responseJSONObject"];
                            if (jsonObj) {
                                NSData *d = [NSJSONSerialization dataWithJSONObject:jsonObj options:0 error:nil];
                                if (d) rawJsonStr = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
                            }
                        }
                        // 3. 如果 response 就是模型本身，利用它的转 JSON 功能
                        else if ([response respondsToSelector:NSSelectorFromString(@"mj_JSONString")]) {
                            rawJsonStr = [response performSelector:NSSelectorFromString(@"mj_JSONString")];
                        }
                        // 4. 终极兜底，强制转换为文本
                        if (!rawJsonStr || rawJsonStr.length == 0) {
                            rawJsonStr = [NSString stringWithFormat:@"%@", response];
                        }
                    } @catch (NSException *e) {}
                    
                    // 记录第一条返回数据，方便弹窗诊断
                    [lock lock];
                    if (sampleResponseStr.length == 0 && rawJsonStr.length > 0) {
                        sampleResponseStr = rawJsonStr.length > 500 ? [rawJsonStr substringToIndex:500] : rawJsonStr;
                    }
                    [lock unlock];
                    
                    // 执行终极暴力匹配
                    if (rawJsonStr.length > 0) {
                        NSString *cleanJson = [[rawJsonStr lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
                        if ([cleanJson containsString:target]) {
                            [lock lock];
                            [matchedInfoIds addObject:infoId];
                            matchCount++;
                            [lock unlock];
                        }
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
                
                NSString *resultMsg = [NSString stringWithFormat:@"请求发出: %lu 个\n成功返回: %d 个\n失败: %d 个\n匹配命中: %d 个", (unsigned long)infos.count, reqSuccessCount, reqFailCount, matchCount];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"完美" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:successAlert animated:YES completion:nil];
                
            } else {
                // 如果是 0 个匹配，直接把服务器返回的数据打印在弹窗上，用于终极诊断！
                NSString *resultMsg = [NSString stringWithFormat:@"请求返回: %d个\n匹配命中: 0个\n\n【服务器底层返回截取】:\n%@", reqSuccessCount, sampleResponseStr.length > 0 ? sampleResponseStr : @"无数据返回(参数被拦截)"];
                
                // 因为文本可能较多，我们需要一个能显示的弹窗
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"筛选结果为空" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
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
