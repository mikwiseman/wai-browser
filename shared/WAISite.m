#import "WAISite.h"
#import <arpa/inet.h>
static NSString *ASCIIHost(NSString *host) {
  if(!host.length)return nil;
  NSString *value = [host canBeConvertedToEncoding:NSASCIIStringEncoding] ? host.lowercaseString : [NSURL URLWithString:[@"https://" stringByAppendingString:host]].host.lowercaseString;
  if ([value hasSuffix:@"."]) value = [value substringToIndex:value.length-1];
  return value;
}
NSString *WAISiteFromInput(NSString *input, NSString *path) {
  NSString *value = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (![value containsString:@"://"]) value = [@"https://" stringByAppendingString:value];
  NSURLComponents *url = [NSURLComponents componentsWithString:value];
  if (![@[@"https",@"http"] containsObject:url.scheme.lowercaseString] || url.user || url.password || !url.URL) return nil;
  NSString *host = ASCIIHost(url.URL.host);
  if (!host || host.length > 253) return nil;
  struct in_addr ip; if (inet_pton(AF_INET,host.UTF8String,&ip)==1) return nil;
  NSArray<NSString *> *labels = [host componentsSeparatedByString:@"."];
  NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789-"] invertedSet];
  for (NSString *label in labels) if (!label.length || label.length>63 || [label hasPrefix:@"-"] || [label hasSuffix:@"-"] || [label rangeOfCharacterFromSet:invalid].location!=NSNotFound) return nil;
  static NSString *loadedPath;
  static NSSet *rules;
  @synchronized(NSSet.class) {
    if (![loadedPath isEqual:path]) {
      NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
      if (!text) return nil;
      NSMutableSet *parsed = [NSMutableSet set];
      for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (!line.length || [line hasPrefix:@"//"]) continue;
        NSString *prefix = [line hasPrefix:@"!"] ? @"!" : ([line hasPrefix:@"*."] ? @"*." : @"");
        NSString *suffix = ASCIIHost([line substringFromIndex:prefix.length]);
        if (suffix) [parsed addObject:[prefix stringByAppendingString:suffix]];
      }
      rules = parsed; loadedPath = [path copy];
    }
  }
  NSUInteger suffixCount = 1;
  for (NSUInteger i=0; i<labels.count; ++i) {
    NSString *suffix = [[labels subarrayWithRange:NSMakeRange(i,labels.count-i)] componentsJoinedByString:@"."];
    if ([rules containsObject:[@"!" stringByAppendingString:suffix]]) { suffixCount=labels.count-i-1; break; }
    if ([rules containsObject:suffix]) suffixCount=MAX(suffixCount,labels.count-i);
    if (i>0 && [rules containsObject:[@"*." stringByAppendingString:suffix]]) suffixCount=MAX(suffixCount,labels.count-i+1);
  }
  if (labels.count<=suffixCount) return nil;
  return [[labels subarrayWithRange:NSMakeRange(labels.count-suffixCount-1,suffixCount+1)] componentsJoinedByString:@"."];
}
BOOL WAIHostMatches(NSString *host, NSArray<NSString *> *sites) {
  NSString *value = ASCIIHost(host);
  for (NSString *site in sites) if ([value isEqual:site] || [value hasSuffix:[@"." stringByAppendingString:site]]) return YES;
  return NO;
}
NSArray<NSString *> *WAIMergeSites(NSArray<NSString *> *selected, NSArray<NSString *> *previous, NSArray<NSString *> *updated) {
  NSMutableSet *removed = [NSMutableSet setWithArray:previous];
  [removed minusSet:[NSSet setWithArray:selected]];
  NSMutableSet *result = [NSMutableSet setWithArray:selected];
  [result minusSet:[NSSet setWithArray:previous]];
  for (NSString *site in updated) {
    BOOL excluded = NO;
    for (NSString *old in removed) {
      if (WAIHostMatches(site, @[old]) || WAIHostMatches(old, @[site])) { excluded = YES; break; }
    }
    if (!excluded) [result addObject:site];
  }
  return [result.allObjects sortedArrayUsingSelector:@selector(compare:)];
}
