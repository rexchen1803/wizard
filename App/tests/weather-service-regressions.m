#import <Foundation/Foundation.h>

#import "../IWWeatherService.m"

static NSUInteger IWWeatherTestCount = 0;
static NSUInteger IWWeatherFailureCount = 0;

static void IWWeatherCheck(BOOL condition, NSString *name) {
    IWWeatherTestCount += 1;
    if (!condition) {
        IWWeatherFailureCount += 1;
        fprintf(stderr, "FAIL: %s\n", [name UTF8String]);
    }
}

static NSData *IWWeatherJSONData(id object) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object
                                                   options:NSJSONWritingFragmentsAllowed
                                                     error:&error];
    IWWeatherCheck(data != nil && error == nil, @"Fixture serializes as JSON");
    return data;
}

static NSDictionary *IWWeatherParseFixture(id object, NSError **errorOut) {
    return IWWeatherSnapshotFromJSONData(IWWeatherJSONData(object), 51.5, -0.1, errorOut);
}

static NSMutableDictionary *IWWeatherValidRoot(void) {
    NSMutableDictionary *current = [@{
            @"temperature": @18.5,
            @"weathercode": @2,
            @"is_day": @1,
            @"time": @"2026-11-10T12:00"
        } mutableCopy];
    NSMutableDictionary *daily = [@{
            @"temperature_2m_max": @[@20.5],
            @"temperature_2m_min": @[@10.25],
            @"precipitation_probability_max": @[@35]
        } mutableCopy];
    return [@{
        @"current_weather": current,
        @"daily": daily,
        @"timezone": @"Europe/London"
    } mutableCopy];
}

static BOOL IWWeatherHasErrorForObject(id object) {
    NSError *error = nil;
    NSDictionary *snapshot = IWWeatherParseFixture(object, &error);
    return snapshot == nil && error != nil;
}

static void IWWeatherTestValidSnapshot(void) {
    NSError *error = nil;
    NSDictionary *snapshot = IWWeatherParseFixture(IWWeatherValidRoot(), &error);
    IWWeatherCheck(snapshot != nil && error == nil, @"Valid Open-Meteo snapshot parses");
    IWWeatherCheck([snapshot[@"temperature"] isEqualToNumber:@18.5], @"Current temperature is numeric");
    IWWeatherCheck([snapshot[@"high"] isEqualToNumber:@20.5], @"Daily high is preserved");
    IWWeatherCheck([snapshot[@"low"] isEqualToNumber:@10.25], @"Daily low is preserved");
    IWWeatherCheck([snapshot[@"precipitationProbability"] isEqualToNumber:@35], @"Precipitation probability is preserved");
    IWWeatherCheck([snapshot[@"code"] isEqualToNumber:@2] && [snapshot[@"isDay"] isEqualToNumber:@1], @"Code and day flag are numeric");
    IWWeatherCheck([snapshot[@"observedAt"] isEqualToString:@"2026-11-10T12:00"], @"Observation time is preserved");
    IWWeatherCheck([snapshot[@"timezone"] isEqualToString:@"Europe/London"], @"Timezone is preserved");
    IWWeatherCheck([snapshot[@"latitude"] isEqualToNumber:@51.5] && [snapshot[@"longitude"] isEqualToNumber:@-0.1], @"Validated coordinates are returned");
    IWWeatherCheck([snapshot[@"fetchedAt"] isKindOfClass:[NSDate class]] && [snapshot[@"provider"] isEqualToString:@"Open-Meteo"], @"Fetch metadata remains present");
}

static void IWWeatherTestMalformedRootsAndCurrent(void) {
    IWWeatherCheck(IWWeatherHasErrorForObject(@[]), @"Array root returns an error");
    IWWeatherCheck(IWWeatherHasErrorForObject([NSNull null]), @"Null root returns an error");
    IWWeatherCheck(IWWeatherHasErrorForObject(@"root"), @"String root returns an error");

    NSMutableDictionary *root = IWWeatherValidRoot();
    [root removeObjectForKey:@"current_weather"];
    IWWeatherCheck(IWWeatherHasErrorForObject(root), @"Missing current_weather returns an error");
    for (id current in @[[NSNull null], @[], @"current"]) {
        root = IWWeatherValidRoot();
        root[@"current_weather"] = current;
        IWWeatherCheck(IWWeatherHasErrorForObject(root), @"Wrong current_weather type returns an error");
    }

    NSArray *invalidTemperatures = @[[NSNull null], @"18.5", @[@18.5], @(YES), @71, @-101];
    for (id value in invalidTemperatures) {
        root = IWWeatherValidRoot();
        root[@"current_weather"][@"temperature"] = value;
        IWWeatherCheck(IWWeatherHasErrorForObject(root), @"Invalid current temperature returns an error");
    }

    NSArray *invalidCodes = @[[NSNull null], @"2", @[@2], @(YES), @1.5, @100];
    for (id value in invalidCodes) {
        root = IWWeatherValidRoot();
        root[@"current_weather"][@"weathercode"] = value;
        IWWeatherCheck(IWWeatherHasErrorForObject(root), @"Invalid weather code returns an error");
    }

    NSError *error = nil;
    NSDictionary *snapshot = IWWeatherSnapshotFromJSONData([@"not-json" dataUsingEncoding:NSUTF8StringEncoding], 51.5, -0.1, &error);
    IWWeatherCheck(snapshot == nil && error != nil, @"Malformed JSON returns an NSError");
    error = nil;
    snapshot = IWWeatherSnapshotFromJSONData(nil, 51.5, -0.1, &error);
    IWWeatherCheck(snapshot == nil && error != nil, @"Missing response data returns an NSError");
}

static void IWWeatherTestOptionalDailyFields(void) {
    NSArray *invalidDailyObjects = @[[NSNull null], @[], @"daily"];
    for (id daily in invalidDailyObjects) {
        NSMutableDictionary *root = IWWeatherValidRoot();
        root[@"daily"] = daily;
        NSError *error = nil;
        NSDictionary *snapshot = IWWeatherParseFixture(root, &error);
        IWWeatherCheck(snapshot != nil && error == nil, @"Malformed optional daily object does not fail the snapshot");
        IWWeatherCheck([snapshot[@"high"] isEqualToNumber:@18.5] &&
                       [snapshot[@"low"] isEqualToNumber:@18.5] &&
                       [snapshot[@"precipitationProbability"] isEqualToNumber:@0],
                       @"Malformed daily object uses safe fallbacks");
    }

    NSArray *invalidTemperatureValues = @[[NSNull null], @"20", @{}, @(YES), @71, @-101];
    NSUInteger temperatureFixtureIndex = 0;
    for (id value in invalidTemperatureValues) {
        NSMutableDictionary *root = IWWeatherValidRoot();
        root[@"daily"][@"temperature_2m_max"] = value;
        root[@"daily"][@"temperature_2m_min"] = @[value];
        NSError *error = nil;
        NSDictionary *snapshot = IWWeatherParseFixture(root, &error);
        IWWeatherCheck(snapshot != nil && error == nil, @"Malformed optional daily arrays do not throw");
        IWWeatherCheck([snapshot[@"high"] isEqualToNumber:@18.5] &&
                       [snapshot[@"low"] isEqualToNumber:@18.5] &&
                       [snapshot[@"precipitationProbability"] isEqualToNumber:@35],
                       [NSString stringWithFormat:@"Malformed daily temperature fixture %lu is normalized", (unsigned long)temperatureFixtureIndex]);
        temperatureFixtureIndex += 1;
    }

    NSMutableDictionary *nestedRoot = IWWeatherValidRoot();
    nestedRoot[@"daily"][@"temperature_2m_max"] = @[@[@20]];
    nestedRoot[@"daily"][@"temperature_2m_min"] = @[@[@10]];
    NSError *nestedError = nil;
    NSDictionary *nestedSnapshot = IWWeatherParseFixture(nestedRoot, &nestedError);
    IWWeatherCheck(nestedSnapshot != nil && nestedError == nil &&
                   [nestedSnapshot[@"high"] isEqualToNumber:@18.5] &&
                   [nestedSnapshot[@"low"] isEqualToNumber:@18.5],
                   @"Nested daily arrays are rejected and fall back safely");

    NSArray *invalidRainValues = @[[NSNull null], @"35", @{}, @[@35], @(YES), @101, @-1];
    for (id value in invalidRainValues) {
        NSMutableDictionary *root = IWWeatherValidRoot();
        root[@"daily"][@"precipitation_probability_max"] = @[value];
        NSError *error = nil;
        NSDictionary *snapshot = IWWeatherParseFixture(root, &error);
        IWWeatherCheck(snapshot != nil && error == nil &&
                       [snapshot[@"precipitationProbability"] isEqualToNumber:@0],
                       @"Invalid optional precipitation values use zero fallback");
    }

    NSMutableDictionary *root = IWWeatherValidRoot();
    root[@"daily"][@"temperature_2m_max"] = @[];
    root[@"daily"][@"temperature_2m_min"] = @[];
    root[@"daily"][@"precipitation_probability_max"] = @[];
    NSError *error = nil;
    NSDictionary *snapshot = IWWeatherParseFixture(root, &error);
    IWWeatherCheck(snapshot != nil && [snapshot[@"high"] isEqualToNumber:@18.5] &&
                   [snapshot[@"low"] isEqualToNumber:@18.5] &&
                   [snapshot[@"precipitationProbability"] isEqualToNumber:@0],
                   @"Empty daily arrays use safe fallbacks");
}

static void IWWeatherTestOptionalMetadataAndCoordinates(void) {
    NSMutableDictionary *root = IWWeatherValidRoot();
    root[@"timezone"] = @{};
    root[@"current_weather"][@"time"] = @12;
    root[@"current_weather"][@"is_day"] = @"day";
    NSError *error = nil;
    NSDictionary *snapshot = IWWeatherParseFixture(root, &error);
    IWWeatherCheck(snapshot != nil && error == nil, @"Malformed optional metadata does not fail the snapshot");
    IWWeatherCheck([snapshot[@"timezone"] isEqualToString:@""] &&
                   [snapshot[@"observedAt"] isEqualToString:@""] &&
                   [snapshot[@"isDay"] isEqualToNumber:@1],
                   @"Malformed optional metadata uses safe defaults");

    IWWeatherCheck(IWWeatherCoordinatesAreValid(-90, -180) && IWWeatherCoordinatesAreValid(90, 180), @"Inclusive coordinate bounds are valid");
    IWWeatherCheck(!IWWeatherCoordinatesAreValid(90.01, 0) && !IWWeatherCoordinatesAreValid(0, -180.01), @"Out-of-range coordinates are rejected");
    IWWeatherCheck(!IWWeatherCoordinatesAreValid(NAN, 0) && !IWWeatherCoordinatesAreValid(0, INFINITY), @"Non-finite coordinates are rejected");
    double numericValue = 0.0;
    IWWeatherCheck(!IWWeatherReadNumber(@(NAN), -100, 70, NO, &numericValue) &&
                   !IWWeatherReadNumber(@(INFINITY), -100, 70, NO, &numericValue),
                   @"Non-finite weather numbers are rejected");
    error = nil;
    snapshot = IWWeatherSnapshotFromJSONData(IWWeatherJSONData(IWWeatherValidRoot()), NAN, 0, &error);
    IWWeatherCheck(snapshot == nil && error != nil, @"Invalid coordinates return an NSError without a request");

    __block BOOL completionCalled = NO;
    __block NSDictionary *invalidCoordinateSnapshot = nil;
    __block NSError *invalidCoordinateError = nil;
    [[IWWeatherService new] fetchWeatherForLatitude:91 longitude:0 completion:^(NSDictionary *result, NSError *fetchError) {
        completionCalled = YES;
        invalidCoordinateSnapshot = result;
        invalidCoordinateError = fetchError;
    }];
    IWWeatherCheck(completionCalled && invalidCoordinateSnapshot == nil && invalidCoordinateError != nil,
                   @"Public fetch API reports invalid coordinates before network access");
}

int main(void) {
    @autoreleasepool {
        IWWeatherTestValidSnapshot();
        IWWeatherTestMalformedRootsAndCurrent();
        IWWeatherTestOptionalDailyFields();
        IWWeatherTestOptionalMetadataAndCoordinates();
        fprintf(stdout, "weather-service regressions: %lu checks, %lu failures\n",
                (unsigned long)IWWeatherTestCount, (unsigned long)IWWeatherFailureCount);
        return IWWeatherFailureCount ? 1 : 0;
    }
}
