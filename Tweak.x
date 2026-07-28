#import <UIKit/UIKit.h>

// ====== 消除 ARC 警告，声明转字典方法 ======
@interface NSObject (ZZModelToJSON)
- (id)mj_keyValues;
- (id)yy_modelToJSONObject;
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

// 自定义方法声明
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_filterWithVersion:(NSString *)version;
- (NSString *)custom_extractInfoId:(id)obj;
- (BOOL)custom_searchAnyTextInObject:(id)obj target:(NSString *)target;
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
                                                                       message:@"请输入想筛选的iOS版本\n(将双路API齐发，并使用JSON全量降维解析)" 
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
                                                                          message:@"正在将详情数据降维至 JSON 并全量检索..." 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSLock *lock = [[NSLock alloc] init];
    
    // 强引用代理对象，防止 ARC 提前销毁
    NSMutableArray *retainedProxies = [NSMutableArray array];
    
    __block int matchCount = 0;
    
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
                    if ([self custom_searchAnyTextInObject:response target:target]) {
                        [lock lock];
                        if (![matchedInfoIds containsObject:infoId]) {
                            [matchedInfoIds addObject:infoId];
                            matchCount++;
                        }
                        [lock unlock];
                    }
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
                    if ([self custom_searchAnyTextInObject:response target:target]) {
                        [lock lock];
                        if (![matchedInfoIds containsObject:infoId]) {
                            [matchedInfoIds addObject:infoId];
                            matchCount++;
                        }
                        [lock unlock];
                    }
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
                
                NSString *resultMsg = [NSString stringWithFormat:@"共处理商品: %lu 个\n双路网络命中: %d 个", (unsigned long)infos.count, matchCount];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"完美" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:successAlert animated:YES completion:nil];
                
            } else {
                NSString *resultMsg = [NSString stringWithFormat:@"处理商品: %lu 个\n\n所有详情数据经JSON深度透视后\n均未发现该系统版本，请加载更多后重试。", (unsigned long)infos.count];
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"未能筛到相关商品" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

// ====== 核弹级全量解析引擎 (字典转JSON字符串进行无死角检索) ======
%new
- (BOOL)custom_searchAnyTextInObject:(id)obj target:(NSString *)target {
    if (!obj) return NO;
    @try {
        NSDictionary *dict = nil;
        // 把模型压成字典
        if ([obj isKindOfClass:[NSDictionary class]]) {
            dict = obj;
        } else if ([obj respondsToSelector:@selector(mj_keyValues)]) {
            dict = [obj mj_keyValues];
        } else if ([obj respondsToSelector:@selector(yy_modelToJSONObject)]) {
            dict = [obj yy_modelToJSONObject];
        }
        
        // 压扁成 JSON 纯文本进行搜索
        if (dict && [dict isKindOfClass:[NSDictionary class]]) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
            if (jsonData) {
                NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                if (jsonString) {
                    NSString *cleanStr = [[jsonString lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
                    if ([cleanStr containsString:target]) {
                        return YES;
                    }
                }
            }
        }
        
        // 降级兜底：某些时候压扁失败，手动遍历高概率字段
        NSArray *keys = @[@"paramValue", @"title", @"desc", @"content", @"sellerDescription", @"extendJson"];
        for (NSString *key in keys) {
            if ([obj respondsToSelector:NSSelectorFromString(key)]) {
                id val = [obj valueForKey:key];
                if ([val isKindOfClass:[NSString class]]) {
                    NSString *cleanVal = [[(NSString *)val lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
                    if ([cleanVal containsString:target]) return YES;
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
