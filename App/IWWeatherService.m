#import "IWWeatherService.h"

#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

static NSString * const IWWeatherErrorDomain = @"com.rex.wizardsystem.weather";
static NSString *IWWeatherServiceDebugPath(NSString *name) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

#ifndef IW_WEATHER_DIAGNOSTICS
#define IW_WEATHER_DIAGNOSTICS 0
#endif

static void IWWeatherServiceLog(NSString *message) {
    if (!IW_WEATHER_DIAGNOSTICS && ![[NSFileManager defaultManager] fileExistsAtPath:IWWeatherServiceDebugPath(@"wizard-weather-debug")]) return;
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message ?: @""];
    NSString *path = IWWeatherServiceDebugPath(@"wizard-weather-service.log");
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

static NSError *IWWeatherMakeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:IWWeatherErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"天气数据无效"}];
}

static BOOL IWWeatherCoordinatesAreValid(double latitude, double longitude) {
    return isfinite(latitude) && isfinite(longitude) &&
           latitude >= -90.0 && latitude <= 90.0 &&
           longitude >= -180.0 && longitude <= 180.0;
}

static BOOL IWWeatherReadNumber(id rawValue, double minimum, double maximum,
                                BOOL requiresInteger, double *valueOut) {
    if (![rawValue isKindOfClass:[NSNumber class]]) return NO;
    NSNumber *number = (NSNumber *)rawValue;
    if (CFGetTypeID((__bridge CFTypeRef)number) == CFBooleanGetTypeID()) return NO;
    double value = [number doubleValue];
    if (!isfinite(value) || value < minimum || value > maximum) return NO;
    if (requiresInteger && floor(value) != value) return NO;
    if (valueOut) *valueOut = value;
    return YES;
}

static NSNumber *IWWeatherFirstArrayNumber(id rawArray, double minimum, double maximum,
                                           NSNumber *fallback) {
    if (![rawArray isKindOfClass:[NSArray class]]) return fallback;
    NSArray *array = (NSArray *)rawArray;
    if ([array count] == 0) return fallback;
    double value = 0.0;
    if (!IWWeatherReadNumber([array objectAtIndex:0], minimum, maximum, NO, &value)) return fallback;
    return [NSNumber numberWithDouble:value];
}

static NSString *IWWeatherOptionalString(id rawValue, NSUInteger maximumLength) {
    if (![rawValue isKindOfClass:[NSString class]]) return @"";
    NSString *value = (NSString *)rawValue;
    if ([value length] > maximumLength ||
        [value rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound) return @"";
    return value;
}

static NSDictionary *IWWeatherSnapshotFromJSONData(NSData *data, double latitude, double longitude,
                                                     NSError **errorOut) {
    if (errorOut) *errorOut = nil;
    if (!IWWeatherCoordinatesAreValid(latitude, longitude)) {
        if (errorOut) *errorOut = IWWeatherMakeError(1, @"天气坐标无效");
        return nil;
    }
    if (![data isKindOfClass:[NSData class]] || [data length] == 0) {
        if (errorOut) *errorOut = IWWeatherMakeError(3, @"天气数据无效");
        return nil;
    }

    NSError *jsonError = nil;
    id rootValue = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (jsonError) {
        if (errorOut) *errorOut = jsonError;
        return nil;
    }
    if (![rootValue isKindOfClass:[NSDictionary class]]) {
        if (errorOut) *errorOut = IWWeatherMakeError(3, @"天气数据格式无效");
        return nil;
    }

    NSDictionary *root = (NSDictionary *)rootValue;
    id currentValue = [root objectForKey:@"current_weather"];
    if (![currentValue isKindOfClass:[NSDictionary class]]) {
        if (errorOut) *errorOut = IWWeatherMakeError(3, @"天气当前数据缺失");
        return nil;
    }
    NSDictionary *current = (NSDictionary *)currentValue;

    double temperatureValue = 0.0;
    double codeValue = 0.0;
    if (!IWWeatherReadNumber([current objectForKey:@"temperature"], -100.0, 70.0, NO, &temperatureValue) ||
        !IWWeatherReadNumber([current objectForKey:@"weathercode"], 0.0, 99.0, YES, &codeValue)) {
        if (errorOut) *errorOut = IWWeatherMakeError(3, @"天气必要字段无效");
        return nil;
    }

    NSNumber *temperature = [NSNumber numberWithDouble:temperatureValue];
    id dailyValue = [root objectForKey:@"daily"];
    NSDictionary *daily = [dailyValue isKindOfClass:[NSDictionary class]] ? (NSDictionary *)dailyValue : nil;
    NSNumber *high = IWWeatherFirstArrayNumber([daily objectForKey:@"temperature_2m_max"], -100.0, 70.0, temperature);
    NSNumber *low = IWWeatherFirstArrayNumber([daily objectForKey:@"temperature_2m_min"], -100.0, 70.0, temperature);
    NSNumber *rain = IWWeatherFirstArrayNumber([daily objectForKey:@"precipitation_probability_max"], 0.0, 100.0, @0);

    double isDayValue = 1.0;
    if (!IWWeatherReadNumber([current objectForKey:@"is_day"], 0.0, 1.0, YES, &isDayValue)) isDayValue = 1.0;

    return @{
        @"temperature": temperature,
        @"high": high,
        @"low": low,
        @"precipitationProbability": rain,
        @"code": [NSNumber numberWithDouble:codeValue],
        @"isDay": [NSNumber numberWithDouble:isDayValue],
        @"observedAt": IWWeatherOptionalString([current objectForKey:@"time"], 64),
        @"fetchedAt": [NSDate date],
        @"timezone": IWWeatherOptionalString([root objectForKey:@"timezone"], 128),
        @"latitude": [NSNumber numberWithDouble:latitude],
        @"longitude": [NSNumber numberWithDouble:longitude],
        @"provider": @"Open-Meteo"
    };
}

@implementation IWWeatherService

- (void)fetchWeatherForLatitude:(double)latitude
                     longitude:(double)longitude
                     completion:(IWWeatherCompletion)completion {
    if (!IWWeatherCoordinatesAreValid(latitude, longitude)) {
        if (completion) completion(nil, IWWeatherMakeError(1, @"天气坐标无效"));
        return;
    }
    // Open-Meteo is used only as the replaceable evaluation provider.  A
    // commercial Wizard release must point this adapter at a licensed
    // customer endpoint or Wizard Cloud without changing the UI contract.
    NSString *urlText = [NSString stringWithFormat:
        @"https://api.open-meteo.com/v1/forecast?latitude=%.5f&longitude=%.5f&current_weather=true&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days=1",
        latitude, longitude];
    NSURL *url = [NSURL URLWithString:urlText];
    IWWeatherServiceLog([NSString stringWithFormat:@"request %.3f %.3f", latitude, longitude]);
    if (!url) {
        if (completion) completion(nil, IWWeatherMakeError(1, @"天气地址无效"));
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:12.0];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"WizardLegacy/0.1 weather-evaluation" forHTTPHeaderField:@"User-Agent"];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = 12.0;
    configuration.timeoutIntervalForResource = 18.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        IWWeatherServiceLog([NSString stringWithFormat:@"response status=%ld bytes=%lu error=%@", (long)http.statusCode, (unsigned long)[data length], error.localizedDescription ?: @""]);
        if (error) {
            if (completion) completion(nil, error);
            [session finishTasksAndInvalidate];
            return;
        }
        if (http.statusCode != 200 || !data || [data length] == 0 || [data length] > 65536) {
            NSString *message = http ? [NSString stringWithFormat:@"天气服务返回 %ld", (long)http.statusCode] : @"天气数据无效";
            if (completion) completion(nil, IWWeatherMakeError(2, message));
            [session finishTasksAndInvalidate];
            return;
        }
        NSError *parseError = nil;
        NSDictionary *snapshot = IWWeatherSnapshotFromJSONData(data, latitude, longitude, &parseError);
        if (completion) completion(snapshot, parseError);
        [session finishTasksAndInvalidate];
    }];
    [task resume];
}

@end
