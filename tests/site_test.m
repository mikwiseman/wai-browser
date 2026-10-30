#import "../shared/WAISite.h"
int main(int argc, char **argv) { @autoreleasepool {
  if (argc != 2) return 2;
  NSString *path = @(argv[1]);
  NSDictionary *cases = @{@" https://WWW.TBANK.RU/account?a=1 ": @"tbank.ru",
    @"ticket.rzd.ru": @"rzd.ru", @"www.example.co.uk": @"example.co.uk",
    @"alice.github.io": @"alice.github.io", @"https://пример.рф/": @"xn--e1afmkfd.xn--p1ai",
    @"www.city.kawasaki.jp": @"city.kawasaki.jp", @"rzd.ru.": @"rzd.ru"};
  for (NSString *input in cases) {
    if (![WAISiteFromInput(input,path) isEqual:cases[input]]) {
      NSLog(@"FAIL input %@, got %@",input,WAISiteFromInput(input,path)); return 1;
    }
  }
  for (NSString *input in @[@"ru", @"co.uk", @"github.io", @"*.ru", @"https://a@b.ru", @"file:///tmp/foo", @"127.0.0.1", @"[::1]", @"a..ru", @"bad site.ru", @"https://rzd.ru:wrong"]) {
    if (WAISiteFromInput(input,path)) { NSLog(@"FAIL accepted %@",input); return 1; }
  }
  if (!WAIHostMatches(@"STATIC.TBANK.RU.",@[@"tbank.ru"]) || WAIHostMatches(@"tbank.ru.evil.com",@[@"tbank.ru"]) || WAIHostMatches(@"eviltbank.ru",@[@"tbank.ru"])) return 1;
  NSArray *merged = WAIMergeSites(@[@"keep.ru", @"custom.ru"], @[@"keep.ru", @"removed.ru"], @[@"keep.ru", @"new.ru", @"api.removed.ru"]);
  if (![merged isEqual:@[@"custom.ru", @"keep.ru", @"new.ru"]]) return 1;
  if ([WAIMergeSites(@[], @[@"removed.ru"], @[@"removed.ru", @"api.removed.ru"]) count]) return 1;
  if ([WAIMergeSites(@[], @[@"api.removed.ru"], @[@"removed.ru"]) count]) return 1;
  if (![WAIMergeSites(@[@"custom.ru", @"old.ru"], @[@"old.ru"], @[@"new.ru"]) isEqual:@[@"custom.ru", @"new.ru"]]) return 1;
  puts("25 site parsing, scope and migration checks passed");
} }
