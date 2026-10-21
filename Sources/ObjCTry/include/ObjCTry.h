#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs a block and catches any Objective-C exception it raises.
///
/// Swift can't catch Objective-C exceptions, and AVAudioEngine raises them instead of throwing errors.
///
/// - Parameter block: The code to run.
/// - Returns: The exception that the block raised, or `nil` if it didn't raise one.
NSException *_Nullable objcTry(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
