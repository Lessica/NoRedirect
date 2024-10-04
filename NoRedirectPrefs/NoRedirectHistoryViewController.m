#import <Foundation/Foundation.h>
#import <MobileCoreServices/LSApplicationProxy.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

#import "LSApplicationProxy+AltList.h"
#import "NoRedirectAppSpecificViewController.h"
#import "NoRedirectHistoryViewController.h"
#import "NoRedirectRecord.h"

@interface PSSpecifier (Private)
@property(nonatomic, retain) NSArray *values;
@end

@implementation NoRedirectHistoryViewController {
    UIBarButtonItem *_clearButton;
    PSSpecifier *_emptySpecifier;
    PSSpecifier *_statisticSpecifier;
}

- (BOOL)shouldShowSubtitles {
    return YES;
}

- (PSCellType)cellTypeForApplicationCells {
    return PSLinkListCell;
}

- (Class)detailControllerClassForSpecifierOfApplicationProxy:(LSApplicationProxy *)applicationProxy {
    return [NoRedirectAppSpecificViewController class];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    if (specifier == _statisticSpecifier) {
        [UIView transitionWithView:self.view
                          duration:0.25
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{
                          [self reloadSpecifiers];
                        }
                        completion:nil];
    }
}

+ (NSDateFormatter *)mediumDateFormatter {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      formatter = [[NSDateFormatter alloc] init];
      formatter.dateStyle = NSDateFormatterMediumStyle;
      formatter.timeStyle = NSDateFormatterNoStyle;
    });
    return formatter;
}

- (PSSpecifier *)emptySpecifier {
    if (!_emptySpecifier) {
        _emptySpecifier = [PSSpecifier preferenceSpecifierNamed:@""
                                                         target:nil
                                                            set:nil
                                                            get:nil
                                                         detail:nil
                                                           cell:PSGroupCell
                                                           edit:nil];
    }
    return _emptySpecifier;
}

- (PSSpecifier *)statisticSpecifier {
    if (!_statisticSpecifier) {
        PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:@""
                                                                target:self
                                                                   set:@selector(setPreferenceValue:specifier:)
                                                                   get:@selector(readPreferenceValue:)
                                                                detail:nil
                                                                  cell:PSSegmentCell
                                                                  edit:nil];

        [specifier setIdentifier:@"StatisticsType"];
        [specifier setProperty:@"StatisticsType" forKey:@"key"];
        [specifier setProperty:@"com.82flex.noredirectprefs" forKey:@"defaults"];
        [specifier setProperty:@YES forKey:@"enabled"];

        specifier.values = @[ @0, @1 ];
        specifier.titleDictionary = @{
            @0 :
                NSLocalizedStringFromTableInBundle(@"By Date", @"History", [NSBundle bundleForClass:[self class]], nil),
            @1 : NSLocalizedStringFromTableInBundle(@"By Application", @"History",
                                                    [NSBundle bundleForClass:[self class]], nil),
        };

        [specifier setProperty:@0 forKey:@"default"];

        _statisticSpecifier = specifier;
    }
    return _statisticSpecifier;
}

- (NSInteger)selectedStatisticsType {
    return [[self readPreferenceValue:[self statisticSpecifier]] integerValue];
}

- (PSSpecifier *)createEmptySpecifier {
    PSSpecifier *specifier = [PSSpecifier
        preferenceSpecifierNamed:NSLocalizedStringFromTableInBundle(@"No history", @"History",
                                                                    [NSBundle bundleForClass:[self class]], nil)
                          target:nil
                             set:nil
                             get:nil
                          detail:nil
                            cell:PSGroupCell
                            edit:nil];
    return specifier;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray<PSSpecifier *> *specifiers = [NSMutableArray array];

        NSInteger declinedCount = 0;
        NSInteger totalCount = 0;
        PSSpecifier *lastGroupSpecifier = nil;

        NSInteger selectedStatisticsType = [self selectedStatisticsType];
        if (selectedStatisticsType == 0) {
            NSString *dateString = nil;
            NSMutableDictionary<NSString *, LSApplicationProxy *> *cachedProxies = [NSMutableDictionary dictionary];
            NSArray<NoRedirectRecord *> *records = [NoRedirectRecord allRecords];
            for (NoRedirectRecord *record in records) {
                if (!record.source || !record.target) {
                    continue;
                }

                LSApplicationProxy *srcProxy = cachedProxies[record.source];
                if (!srcProxy) {
                    srcProxy = [LSApplicationProxy applicationProxyForIdentifier:record.source];
                    if (srcProxy) {
                        cachedProxies[record.source] = srcProxy;
                    }
                }
                if (!srcProxy || srcProxy.atl_isHidden || !srcProxy.atl_nameToDisplay) {
                    continue;
                }

                LSApplicationProxy *targetProxy = cachedProxies[record.target];
                if (!targetProxy) {
                    targetProxy = [LSApplicationProxy applicationProxyForIdentifier:record.target];
                    if (targetProxy) {
                        cachedProxies[record.target] = targetProxy;
                    }
                }
                if (!targetProxy || targetProxy.atl_isHidden || !targetProxy.atl_nameToDisplay) {
                    continue;
                }

                PSSpecifier *specifier = [self createSpecifierForApplicationProxy:srcProxy];
                if (!specifier) {
                    continue;
                }

                specifier.name =
                    [NSString stringWithFormat:@"%@  ❯  %@", srcProxy.atl_nameToDisplay, targetProxy.atl_nameToDisplay];

                [specifier setProperty:record forKey:@"associatedRecord"];
                [specifier setProperty:srcProxy.atl_nameToDisplay forKey:@"applicationName"];

                NSString *newDateString =
                    [[NoRedirectHistoryViewController mediumDateFormatter] stringFromDate:record.createdAt];
                if (![dateString isEqualToString:newDateString]) {
                    dateString = newDateString;

                    PSSpecifier *dateSpecifier = [PSSpecifier preferenceSpecifierNamed:dateString
                                                                                target:nil
                                                                                   set:nil
                                                                                   get:nil
                                                                                detail:nil
                                                                                  cell:PSGroupCell
                                                                                  edit:nil];

                    [specifiers addObject:dateSpecifier];

                    lastGroupSpecifier = dateSpecifier;
                }

                specifier.identifier = [NSString stringWithFormat:@"%@-%@-%.0f", record.source, record.target,
                                                                  record.createdAt.timeIntervalSince1970];

                [specifiers addObject:specifier];

                if (record.declined) {
                    declinedCount++;
                }

                totalCount++;
            }
        } else if (selectedStatisticsType == 1) {
            NSMutableDictionary<NSString *, LSApplicationProxy *> *cachedProxies = [NSMutableDictionary dictionary];
            NSMutableDictionary<NSString *, NSNumber *> *requestsCountMapping = [NSMutableDictionary dictionary];
            NSArray<NoRedirectRecord *> *records = [NoRedirectRecord allRecords];
            for (NoRedirectRecord *record in records) {
                if (!record.source || !record.target) {
                    continue;
                }

                LSApplicationProxy *srcProxy = cachedProxies[record.source];
                if (!srcProxy) {
                    srcProxy = [LSApplicationProxy applicationProxyForIdentifier:record.source];
                    if (srcProxy) {
                        cachedProxies[record.source] = srcProxy;
                    }
                }
                if (!srcProxy || srcProxy.atl_isHidden || !srcProxy.atl_nameToDisplay) {
                    continue;
                }

                LSApplicationProxy *targetProxy = cachedProxies[record.target];
                if (!targetProxy) {
                    targetProxy = [LSApplicationProxy applicationProxyForIdentifier:record.target];
                    if (targetProxy) {
                        cachedProxies[record.target] = targetProxy;
                    }
                }
                if (!targetProxy || targetProxy.atl_isHidden || !targetProxy.atl_nameToDisplay) {
                    continue;
                }

                NSInteger previousCount = [requestsCountMapping[record.source] integerValue];
                requestsCountMapping[record.source] = @(previousCount + 1);

                if (record.declined) {
                    declinedCount++;
                }

                totalCount++;
            }

            NSMutableArray<LSApplicationProxy *> *requestsProxies = [NSMutableArray array];
            for (NSString *appId in requestsCountMapping) {
                LSApplicationProxy *proxy = cachedProxies[appId];
                [requestsProxies addObject:proxy];
            }
            [requestsProxies
                sortUsingComparator:^NSComparisonResult(LSApplicationProxy *obj1, LSApplicationProxy *obj2) {
                  NSComparisonResult countResult =
                      [requestsCountMapping[obj2.bundleIdentifier] compare:requestsCountMapping[obj1.bundleIdentifier]];
                  if (countResult != NSOrderedSame) {
                      return countResult;
                  }
                  return [obj1.atl_nameToDisplay localizedStandardCompare:obj2.atl_nameToDisplay];
                }];

            NSMutableArray<PSSpecifier *> *groupedSpecifiers = [NSMutableArray array];
            for (LSApplicationProxy *proxy in requestsProxies) {
                PSSpecifier *specifier = [self createSpecifierForApplicationProxy:proxy];
                if (!specifier) {
                    continue;
                }

                [specifier setProperty:requestsCountMapping[proxy.bundleIdentifier] forKey:@"associatedCount"];
                [specifier setProperty:proxy.atl_nameToDisplay forKey:@"applicationName"];
                [groupedSpecifiers addObject:specifier];
            }

            if (groupedSpecifiers.count > 0) {
                PSSpecifier *emptySpecifier = [PSSpecifier preferenceSpecifierNamed:@""
                                                                             target:nil
                                                                                set:nil
                                                                                get:nil
                                                                             detail:nil
                                                                               cell:PSGroupCell
                                                                               edit:nil];

                lastGroupSpecifier = emptySpecifier;

                [specifiers addObject:emptySpecifier];
            }

            [specifiers addObjectsFromArray:groupedSpecifiers];
        }

        if (specifiers.count == 0) {
            PSSpecifier *emptySpecifier = [self createEmptySpecifier];
            [specifiers addObject:emptySpecifier];
        } else {
            [specifiers insertObjects:@[ [self emptySpecifier], [self statisticSpecifier] ]
                            atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]];

            [lastGroupSpecifier setProperty:[self statisticContentWithDeclinedCount:declinedCount totalCount:totalCount]
                                     forKey:@"footerText"];
        }

        _specifiers = specifiers;
    }
    return _specifiers;
}

- (NSString *)statisticContentWithDeclinedCount:(NSInteger)declinedCount totalCount:(NSInteger)totalCount {
    if (totalCount == 0) {
        return nil;
    }
    NSString *totalDescription = nil;
    if (totalCount == 1) {
        totalDescription =
            NSLocalizedStringFromTableInBundle(@"1 request", @"History", [NSBundle bundleForClass:[self class]], nil);
    } else {
        totalDescription =
            [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%ld requests", @"History",
                                                                          [NSBundle bundleForClass:[self class]], nil),
                                       (long)totalCount];
    }
    if (declinedCount > 0) {
        NSString *declinedDescription = nil;
        if (declinedCount == 1) {
            declinedDescription = NSLocalizedStringFromTableInBundle(@"1 request", @"History",
                                                                     [NSBundle bundleForClass:[self class]], nil);
        } else {
            declinedDescription = [NSString
                stringWithFormat:NSLocalizedStringFromTableInBundle(@"%ld requests", @"History",
                                                                    [NSBundle bundleForClass:[self class]], nil),
                                 (long)declinedCount];
        }
        return [NSString
            stringWithFormat:NSLocalizedStringFromTableInBundle(
                                 @"No Redirect has recognized %@ and declined %@ for you since the last boot.",
                                 @"History", [NSBundle bundleForClass:[self class]], nil),
                             totalDescription, declinedDescription];
    } else {
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(
                                              @"No Redirect has recognized %@ for you since the last boot.", @"History",
                                              [NSBundle bundleForClass:[self class]], nil),
                                          totalDescription];
    }
}

+ (NSDateFormatter *)shortDateTimeFormatter {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      formatter = [[NSDateFormatter alloc] init];
      formatter.dateStyle = NSDateFormatterShortStyle;
      formatter.timeStyle = NSDateFormatterShortStyle;
    });
    return formatter;
}

- (NSString *)_subtitleForSpecifier:(PSSpecifier *)specifier {
    NoRedirectRecord *record = [specifier propertyForKey:@"associatedRecord"];
    if (record) {
        if (record.declined) {
            return [NSString
                stringWithFormat:NSLocalizedStringFromTableInBundle(@"Declined on %@", @"History",
                                                                    [NSBundle bundleForClass:[self class]], nil),
                                 [[NoRedirectHistoryViewController shortDateTimeFormatter]
                                     stringFromDate:record.createdAt]];
        } else {
            return [NSString
                stringWithFormat:NSLocalizedStringFromTableInBundle(@"Redirected on %@", @"History",
                                                                    [NSBundle bundleForClass:[self class]], nil),
                                 [[NoRedirectHistoryViewController shortDateTimeFormatter]
                                     stringFromDate:record.createdAt]];
        }
    } else {
        NSInteger associatedCount = [[specifier propertyForKey:@"associatedCount"] integerValue];
        if (associatedCount == 0) {
            return nil;
        }
        if (associatedCount == 1) {
            return NSLocalizedStringFromTableInBundle(@"1 request", @"History", [NSBundle bundleForClass:[self class]],
                                                      nil);
        } else {
            return [NSString
                stringWithFormat:NSLocalizedStringFromTableInBundle(@"%ld requests", @"History",
                                                                    [NSBundle bundleForClass:[self class]], nil),
                                 (long)associatedCount];
        }
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title =
        NSLocalizedStringFromTableInBundle(@"Redirect History", @"Root", [NSBundle bundleForClass:self.class], nil);

    _clearButton = [[UIBarButtonItem alloc]
        initWithTitle:NSLocalizedStringFromTableInBundle(@"Clear", @"History", [NSBundle bundleForClass:self.class],
                                                         nil)
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(clearHistory)];

    self.navigationItem.rightBarButtonItem = _clearButton;
}

- (void)clearHistory {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:nil
                                            message:NSLocalizedStringFromTableInBundle(
                                                        @"Are you sure you want to clear the redirect history?",
                                                        @"History", [NSBundle bundleForClass:self.class], nil)
                                     preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(
                                                        @"Clear", @"History", [NSBundle bundleForClass:self.class], nil)
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
                                              [self realClearHistory];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(
                                                        @"Cancel", @"Root", [NSBundle bundleForClass:self.class], nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)realClearHistory {
    [NoRedirectRecord clearAllRecords];
    [self updateSpecifiers:[self specifiers] withSpecifiers:@[ [self createEmptySpecifier] ]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    NSString *appId = [specifier propertyForKey:@"applicationIdentifier"];
    if ([appId isEqualToString:@"com.apple.springboard"]) {
        NSString *appName = [specifier propertyForKey:@"applicationName"];
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:nil
                             message:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(
                                                                    @"Settings of “%@” cannot be modified.", @"History",
                                                                    [NSBundle bundleForClass:self.class], nil),
                                                                appName]
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(
                                                            @"OK", @"Root", [NSBundle bundleForClass:self.class], nil)
                                                  style:UIAlertActionStyleCancel
                                                handler:^(UIAlertAction *_Nonnull action) {
                                                  [tableView deselectRowAtIndexPath:indexPath animated:YES];
                                                }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

@end