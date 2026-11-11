#import <Foundation/Foundation.h>

typedef void (^IWWeatherCompletion)(NSDictionary *snapshot, NSError *error);

@interface IWWeatherService : NSObject
- (void)fetchWeatherForLatitude:(double)latitude
                     longitude:(double)longitude
                     completion:(IWWeatherCompletion)completion;
@end
