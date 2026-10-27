#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Returns a registrable domain, including private suffix boundaries (e.g. github.io).
FOUNDATION_EXPORT NSString * _Nullable WAISiteFromInput(NSString *input, NSString *suffixListPath);
FOUNDATION_EXPORT BOOL WAIHostMatches(NSString *host, NSArray<NSString *> *sites);
NS_ASSUME_NONNULL_END
