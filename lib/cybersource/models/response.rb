module Killbill #:nodoc:
  module Cybersource #:nodoc:
    class CybersourceResponse < ::Killbill::Plugin::ActiveMerchant::ActiveRecord::Response

      self.table_name = 'cybersource_responses'

      has_one :cybersource_transaction

      def self.from_response(api_call, kb_payment_id, response, extra_params = {})
        super(api_call,
              kb_payment_id,
              response,
              {
                  :params_merchant_reference_code => extract(response, 'merchantReferenceCode'),
                  :params_request_id              => extract(response, 'requestID'),
                  :params_decision                => extract(response, 'decision'),
                  :params_reason_code             => extract(response, 'reasonCode'),
                  :params_request_token           => extract(response, 'requestToken'),
                  :params_currency                => extract(response, 'currency'),
                  :params_amount                  => extract(response, 'amount'),
                  :params_authorization_code      => extract(response, 'authorizationCode'),
                  :params_avs_code                => extract(response, 'avsCode'),
                  :params_avs_code_raw            => extract(response, 'avsCodeRaw'),
                  :params_cv_code                 => extract(response, 'cvCode'),
                  :params_authorized_date_time    => extract(response, 'authorizedDateTime'),
                  :params_processor_response      => extract(response, 'processorResponse'),
                  :params_reconciliation_id       => extract(response, 'reconciliationID'),
                  :params_subscription_id         => extract(response, 'subscriptionID'),
              }.merge!(extra_params),
              ::Killbill::Cybersource::CybersourceResponse)
      end
    end
  end
end
