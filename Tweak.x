#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ====== 消除 ARC 警告，声明辅助方法 ======
@interface NSObject (ZZNativeDataConvert)
- (id)mj_keyValues;
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
- (BOOL)custom_deepTextSearch:(id)obj target:(NSString *)target visited:(NSMutableSet *)visited depth:(int)depth sample:(NSMutableString *)sampleStr;
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
                                                                       message:@"请输入想筛选的iOS版本\n(已搭载 Runtime 无限剥层提取引擎)" 
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
                                                                          message:@"后台内存爬虫正在剥离全部属性，请稍候..." 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSLock *lock = [[NSLock alloc] init];
    
    NSMutableArray *retainedProxies = [NSMutableArray array];
    
    __block int matchCount = 0;
    __block int reqSuccessCount = 0;
    __block int reqFailCount = 0;
    NSMutableString *sampleResponseStr = [[NSMutableString alloc] init];
    
    // 目标文本标准化：全小写 + 去空格
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
        
        // 通用回调处理 (极深爬虫搜索)
        void (^handleResponse)(id) = ^(id response) {
            [lock lock]; reqSuccessCount++; [lock unlock];
            
            NSMutableSet *visited = [NSMutableSet set];
            BOOL isMatch = [self custom_deepTextSearch:response target:target visited:visited depth:0 sample:sampleResponseStr];
            
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
            [lock lock]; reqFailCount++; [lock unlock];
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
    
    // 5. 等待所有请求完成并处理视图
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
                
                NSString *resultMsg = [NSString stringWithFormat:@"接口返回: %d 次\n筛选匹配命中: %d 个", reqSuccessCount, matchCount];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"完美" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:successAlert animated:YES completion:nil];
                
            } else {
                // 将被爬虫提取出来的、纯粹的底层中文字符显示出来！
                NSString *resultMsg = [NSString stringWithFormat:@"接口返回: %d 次\n匹配: 0 个\n\n【爬虫底层文字采样】:\n%@", reqSuccessCount, sampleResponseStr.length > 0 ? sampleResponseStr : @"空"];
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"未能筛到相关商品" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

// ====== 终极核武器：Runtime 内存爬虫，无视一切数组封装，直接剥出纯文本 ======
%new
- (BOOL)custom_deepTextSearch:(id)obj target:(NSString *)target visited:(NSMutableSet *)visited depth:(int)depth sample:(NSMutableString *)sampleStr {
    if (!obj || depth > 8) return NO; // 允许挖取 8 层深度
    
    // 防循环引用死循环
    NSValue *ptr = [NSValue valueWithNonretainedObject:obj];
    if ([visited containsObject:ptr]) return NO;
    [visited addObject:ptr];
    
    // 1. 如果它是字符串，我们终于挖到底了！
    if ([obj isKindOfClass:[NSString class]]) {
        // 解除 unicode/url 乱码伪装
        NSString *rawStr = (NSString *)obj;
        NSString *unicodeDecoded = [NSString stringWithCString:[rawStr cStringUsingEncoding:NSUTF8StringEncoding] encoding:NSNonLossyASCIIStringEncoding];
        if (unicodeDecoded) rawStr = unicodeDecoded;
        
        NSString *urlDecoded = [rawStr stringByRemovingPercentEncoding];
        if (urlDecoded) rawStr = urlDecoded;
        
        // ====== 记录样本数据 ======
        // 遇到中文字符或数字，收集起来打印在弹窗上，这是用来证明我们挖到了什么！
        if (sampleStr && sampleStr.length < 800 && rawStr.length > 0) {
            [sampleStr appendFormat:@"[%@] ", rawStr];
        }
        
        // ====== 终极匹配 ======
        NSString *cleanStr = [[rawStr lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
        if ([cleanStr containsString:target]) return YES;
        
        return NO;
    }
    
    // 2. 如果是富文本
    if ([obj isKindOfClass:[NSAttributedString class]]) {
        NSString *rawStr = [(NSAttributedString *)obj string];
        if (rawStr) return [self custom_deepTextSearch:rawStr target:target visited:visited depth:depth+1 sample:sampleStr];
        return NO;
    }
    
    // 3. 数字类型
    if ([obj isKindOfClass:[NSNumber class]]) {
        return [self custom_deepTextSearch:[(NSNumber *)obj stringValue] target:target visited:visited depth:depth+1 sample:sampleStr];
    }
    
    // 4. 数组（比如 supplementaryArr、paramLabelsInfo），遍历里面装的神奇对象
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) {
            if ([self custom_deepTextSearch:item target:target visited:visited depth:depth+1 sample:sampleStr]) return YES;
        }
        return NO;
    }
    
    // 5. 字典类型
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id val in [(NSDictionary *)obj allValues]) {
            if ([self custom_deepTextSearch:val target:target visited:visited depth:depth+1 sample:sampleStr]) return YES;
        }
        return NO;
    }
    
    // 6. 自定义模型对象（比如 ZZGoodsDetailSupplementaryModel / ZZLabelInfoModel）
    NSString *className = NSStringFromClass([obj class]);
    if ([className hasPrefix:@"ZZ"] || [className hasPrefix:@"SimpleCheck"]) {
        unsigned int outCount, i;
        // 使用 Runtime 强行读取这个对象里声明的所有属性
        objc_property_t *properties = class_copyPropertyList([obj class], &outCount);
        if (properties) {
            for (i = 0; i < outCount; i++) {
                objc_property_t property = properties[i];
                const char *propName = property_getName(property);
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
                    } @catch (NSException *e) {}
                }
            }
            free(properties);
        }
        
        // 兜底：如果这个模型支持转字典，也挖一下字典
        @try {
            if ([obj respondsToSelector:@selector(mj_keyValues)]) {
                id dict = [obj performSelector:@selector(mj_keyValues)];
                if ([dict isKindOfClass:[NSDictionary class]]) {
                    if ([self custom_deepTextSearch:dict target:target visited:visited depth:depth+1 sample:sampleStr]) return YES;
                }
            }
        } @catch(...) {}
    }
    
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
