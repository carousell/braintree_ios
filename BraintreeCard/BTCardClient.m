#import "BTErrors.h"
#import "BTTokenizationParser.h"
#import "BTTokenizationService.h"
#import "BTCardClient.h"
#import "BTTokenizedCard_Internal.h"
#import "BTHTTP.h"
#import "BTJSON.h"
#import "BTClientMetadata.h"
#import "BTAPIClient_Internal.h"
#import "BTCard_Internal.h"

NSString *const BTCardClientErrorDomain = @"com.braintreepayments.BTCardClientErrorDomain";

@interface BTCardClient ()
@property (nonatomic, strong, readwrite) BTAPIClient *apiClient;
@end

@implementation BTCardClient

+ (void)load {
    if (self == [BTCardClient class]) {
        [[BTTokenizationService sharedService] registerType:@"Card" withTokenizationBlock:^(BTAPIClient *apiClient, NSDictionary *options, void (^completionBlock)(id<BTTokenized> tokenization, NSError *error)) {
            BTCardClient *client = [[BTCardClient alloc] initWithAPIClient:apiClient];
            BTCard *card = [[BTCard alloc] initWithParameters:options];
            [client tokenizeCard:card completion:completionBlock];
        }];

        [[BTTokenizationParser sharedParser] registerType:@"Card" withParsingBlock:^id<BTTokenized> _Nullable(BTJSON * _Nonnull creditCard) {
            return [BTTokenizedCard cardWithJSON:creditCard];
        }];
    }
}

- (instancetype)initWithAPIClient:(BTAPIClient *)apiClient {
    if (self = [super init]) {
        self.apiClient = apiClient;
    }
    return self;
}

- (instancetype)init {
    return nil;
}

- (void)tokenizeCard:(BTCard *)card
          completion:(void (^)(BTTokenizedCard *tokenizedCard, NSError *error))completionBlock {
    NSMutableDictionary *parameters = [NSMutableDictionary new];
    parameters[@"credit_card"] = card.parameters;
    parameters[@"_meta"] = @{
                             @"source" : self.apiClient.metadata.sourceString,
                             @"integration" : self.apiClient.metadata.integrationString,
                             @"sessionId" : self.apiClient.metadata.sessionId,
                             };
    
    [self.apiClient POST:@"v1/payment_methods/credit_cards"
              parameters:parameters
              completion:^(BTJSON *body, __unused NSHTTPURLResponse *response, NSError *error) {
                  if (error != nil) {

                      // Check if the error is a card validation error, and provide add'l error info
                      // about the validation errors in the userInfo
                      NSHTTPURLResponse *response = error.userInfo[BTHTTPURLResponseKey];
                      if (response.statusCode == 422) {
                          BTJSON *jsonResponse = error.userInfo[BTHTTPJSONResponseBodyKey];
                          NSDictionary *userInfo = jsonResponse.asDictionary ? @{ BTCustomerInputBraintreeValidationErrorsKey : jsonResponse.asDictionary } : @{};
                          NSError *validationError = [NSError errorWithDomain:BTCardClientErrorDomain
                                                                         code:BTErrorCustomerInputInvalid
                                                                     userInfo:userInfo];
                          completionBlock(nil, validationError);
                      } else {
                          completionBlock(nil, error);
                      }

                      return;
                  }

                  BTJSON *creditCard = body[@"creditCards"][0];
                  if (creditCard.isError) {
                      completionBlock(nil, creditCard.asError);
                  } else {
                      completionBlock([BTTokenizedCard cardWithJSON:creditCard], nil);
                  }
              }];
}

@end