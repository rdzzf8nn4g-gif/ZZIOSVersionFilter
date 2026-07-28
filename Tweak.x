#import <UIKit/UIKit.h>
#import <objc/runtime.h> // 必须引入 Runtime

// ====== 消除 ARC 警告 ======
@interface NSObject (ZZModelToJSON)
- (id)mj_keyValues;
@end

// ====== 声明控制器 ======
@interface ZZListingAprilViewController : UIViewController
@property (retain, nonatomic) NSArray *dataArray;
- (void)loadData;

// 自定义方法声明
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_filterLocallyWithVersion:(NSString *)version;
- (void)custom_pruneArray:(NSMutableArray *)array target:(NSString *)target kept:(int *)kept removed:(int *)removed;
- (BOOL)custom_deepSearch:(id)obj target:(NSString *)target visited:(NSMutableSet *)visited depth:(int)depth;
- (NSString *)custom_extractInfoId:(id)obj;
- (void)custom_reloadCollectionView;
@end


%hook ZZListingAprilViewController

- (void)viewDidLoad {
    %orig;
    
    // 注入双指长按手势
    UILongPressGestureRecognizer *twoFingerLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(custom_twoFingerLongPress:)];
    twoFingerLongPress.numberOfTouchesRequired = 2; // 需要双指
    twoFingerLongPress.minimumPressDuration = 1.0;  // 长按 1 秒
    [self.view addGestureRecognizer:twoFingerLongPress];
}

%new
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"列表版本秒切系统" 
                                                                       message:@"请输入想筛选的iOS版本\n(已搭载富文本及底层变量强力解析引擎)" 
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
                [weakSelf custom_filterLocallyWithVersion:versionText];
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
- (void)custom_filterLocallyWithVersion:(NSString *)version {
    if (!self.dataArray || self.dataArray.count == 0) {
        UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"提示" message:@"当前列表无数据，请向下滑动加载或刷新后再试" preferredStyle:UIAlertControllerStyleAlert];
        [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:emptyAlert animated:YES completion:nil];
        return;
    }
    
    // 将输入的版本号转换为标准格式：无空格、全小写 (比如 " iOS  15.4" 会变成 "ios15.4")
    NSString *target = [[version lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    int keptCount = 0;
    int removedCount = 0;
    
    // ====== 核心：ZZFLEX 内存原地切割 ======
    // 转转的 dataArray 通常装着 SectionModel，里面有 itemsArray (它是 NSMutableArray)
    if ([self.dataArray isKindOfClass:[NSMutableArray class]]) {
        [self custom_pruneArray:(NSMutableArray *)self.dataArray target:target kept:&keptCount removed:&removedCount];
    } else {
        for (id section in self.dataArray) {
            // 找出转转可能用来存放商品元素的数组属性
            NSArray *keys = @[@"itemsArray", @"dataArray", @"items", @"viewModels", @"cellModels"];
            for (NSString *key in keys) {
                @try {
                    id val = [section valueForKey:key];
                    if ([val isKindOfClass:[NSMutableArray class]]) {
                        // 如果找到了商品数组，执行清理裁剪
                        [self custom_pruneArray:val target:target kept:&keptCount removed:&removedCount];
                    }
                } @catch(NSException *e){}
            }
        }
    }
    
    // 直接刷新视图
    [self custom_reloadCollectionView];
    
    // 弹窗反馈结果
    NSString *resultMsg = [NSString stringWithFormat:@"成功保留: %d 个\n剔除无关商品: %d 个", keptCount, removedCount];
    if (keptCount > 0) {
        UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
        [successAlert addAction:[UIAlertAction actionWithTitle:@"完美" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:successAlert animated:YES completion:nil];
    } else {
        UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"未能筛到相关商品" 
                                                                            message:@"已动用底层富文本引擎扫描屏幕上的所有数据，均未发现该版本！\n\n如果确认该版本存在，请检查输入是否正确；若未加载出来，请下拉加载更多。" 
                                                                     preferredStyle:UIAlertControllerStyleAlert];
        [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:emptyAlert animated:YES completion:nil];
    }
}

// ====== 动态数组修剪器（原地剔除不符合要求的数据） ======
%new
- (void)custom_pruneArray:(NSMutableArray *)array target:(NSString *)target kept:(int *)kept removed:(int *)removed {
    // 必须倒序遍历，否则删除元素会导致数组越界崩溃
    for (NSInteger i = array.count - 1; i >= 0; i--) {
        id item = array[i];
        
        // 判断这个元素是不是“商品”（有 ID 的才是商品，没有的可能是顶部横幅广告）
        NSString *infoId = [self custom_extractInfoId:item];
        
        if (infoId && infoId.length > 5) {
            // 这是一个商品！开始底层扫描
            NSMutableSet *visited = [NSMutableSet set];
            if ([self custom_deepSearch:item target:target visited:visited depth:0]) {
                (*kept)++; // 匹配成功，保留！
            } else {
                [array removeObjectAtIndex:i]; // 没匹配到，彻底从内存中抹除！
                (*removed)++;
            }
        } else if ([item isKindOfClass:[NSMutableArray class]]) {
            // 如果遇到嵌套数组，继续钻进去修剪
            [self custom_pruneArray:item target:target kept:kept removed:removed];
        }
    }
}

// ====== 终极底层属性扫描引擎（杜绝漏网之鱼） ======
%new
- (BOOL)custom_deepSearch:(id)obj target:(NSString *)target visited:(NSMutableSet *)visited depth:(int)depth {
    if (!obj || depth > 5) return NO; // 限制深度，防止死循环导致 App 卡死
    
    // 防环形引用锁
    NSValue *ptr = [NSValue valueWithNonretainedObject:obj];
    if ([visited containsObject:ptr]) return NO;
    [visited addObject:ptr];
    
    // 1. 突破点一：处理最常见的 NSString
    if ([obj isKindOfClass:[NSString class]]) {
        NSString *clean = [[(NSString *)obj lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
        return [clean containsString:target];
    }
    
    // 2. 突破点二：处理富文本 NSAttributedString (转转列表的标签经常用这个渲染)
    if ([obj isKindOfClass:[NSAttributedString class]]) {
        NSString *rawStr = [(NSAttributedString *)obj string];
        if (rawStr) {
            NSString *clean = [[rawStr lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
            return [clean containsString:target];
        }
        return NO;
    }
    
    // 3. 处理 Number
    if ([obj isKindOfClass:[NSNumber class]]) {
        return [[(NSNumber *)obj stringValue] containsString:target];
    }
    
    // 4. 处理数组
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) {
            if ([self custom_deepSearch:item target:target visited:visited depth:depth+1]) return YES;
        }
        return NO;
    }
    
    // 5. 处理字典
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id val in [(NSDictionary *)obj allValues]) {
            if ([self custom_deepSearch:val target:target visited:visited depth:depth+1]) return YES;
        }
        return NO;
    }
    
    // 6. 突破点三：Objective-C Runtime 强行读取底层实例变量（突破 Swift 私有变量限制）
    unsigned int ivarCount = 0;
    Ivar *ivars = class_copyIvarList([obj class], &ivarCount);
    if (ivars) {
        for (unsigned int i = 0; i < ivarCount; i++) {
            Ivar ivar = ivars[i];
            const char *typeEncoding = ivar_getTypeEncoding(ivar);
            // 只有对象类型 ('@') 才能读取，否则会导致 EXC_BAD_ACCESS 闪退
            if (typeEncoding && typeEncoding[0] == '@') {
                @try {
                    id val = object_getIvar(obj, ivar);
                    if (val && [self custom_deepSearch:val target:target visited:visited depth:depth+1]) {
                        free(ivars);
                        return YES;
                    }
                } @catch(...) {} // 绝对防崩溃
            }
        }
        free(ivars);
    }
    
    // 7. 兜底方案：尝试转为 JSON
    @try {
        if ([obj respondsToSelector:NSSelectorFromString(@"mj_keyValues")]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id dict = [obj performSelector:NSSelectorFromString(@"mj_keyValues")];
            #pragma clang diagnostic pop
            if ([dict isKindOfClass:[NSDictionary class]]) {
                NSString *desc = [[dict description] lowercaseString];
                desc = [desc stringByReplacingOccurrencesOfString:@" " withString:@""];
                if ([desc containsString:target]) return YES;
            }
        }
    } @catch(...) {}
    
    return NO;
}

// ====== 万能 ID 提取器 ======
%new
- (NSString *)custom_extractInfoId:(id)obj {
    if (!obj) return nil;
    @try {
        id val = nil;
        if ([obj respondsToSelector:NSSelectorFromString(@"infoId")]) val = [obj valueForKey:@"infoId"];
        else if ([obj respondsToSelector:NSSelectorFromString(@"infoID")]) val = [obj valueForKey:@"infoID"];
        else if ([obj isKindOfClass:[NSDictionary class]]) val = [(NSDictionary *)obj objectForKey:@"infoId"];

        if ([val isKindOfClass:[NSString class]]) return val;
        if ([val isKindOfClass:[NSNumber class]]) return [(NSNumber *)val stringValue];
    } @catch(...) {}

    // 如果外面包了一层大壳子，直接钻进去拿
    NSArray *wrappers = @[@"dataModel", @"feedModel", @"itemModel", @"searchResult"];
    for (NSString *key in wrappers) {
        @try {
            id val = [obj valueForKey:key];
            if (val && val != obj) {
                NSString *inner = [self custom_extractInfoId:val];
                if (inner) return inner;
            }
        } @catch(...) {}
    }
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
