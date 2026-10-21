#import "ObjCTry.h"

NSException *objcTry(NS_NOESCAPE void (^block)(void)) {
  @try {
    block();
  } @catch (NSException *exception) {
    return exception;
  }
  return nil;
}
