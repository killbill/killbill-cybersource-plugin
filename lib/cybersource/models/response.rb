module Killbill #:nodoc:
  module Cybersource #:nodoc:
    class CybersourceResponse < ::Killbill::Plugin::ActiveMerchant::ActiveRecord::Response

      self.table_name = 'cybersource_responses'

      has_one :cybersource_transaction

      def self.from_response(api_call, kb_account_id, kb_payment_id, kb_payment_transaction_id, transaction_type, payment_processor_account_id, kb_tenant_id, response, extra_params = {}, model = ::Killbill::Cybersource::CybersourceResponse)
        super(api_call,
              kb_account_id,
              kb_payment_id,
              kb_payment_transaction_id,
              transaction_type,
              payment_processor_account_id,
              kb_tenant_id,
              response,
              cybersource_response_params(response).merge!(extra_params),
              model)
      end

      def self.cybersource_response_params(response)
        {
            :params_merchant_reference_code => extract(response, 'merchantReferenceCode'),
            :params_request_id => extract(response, 'requestID'),
            :params_decision => extract(response, 'decision'),
            :params_reason_code => extract(response, 'reasonCode'),
            :params_request_token => extract(response, 'requestToken'),
            :params_currency => extract(response, 'currency'),
            :params_amount => extract(response, 'amount'),
            :params_authorization_code => extract(response, 'authorizationCode'),
            :params_avs_code => extract(response, 'avsCode'),
            :params_avs_code_raw => extract(response, 'avsCodeRaw'),
            :params_cv_code => extract(response, 'cvCode'),
            :params_authorized_date_time => extract(response, 'authorizedDateTime'),
            :params_processor_response => extract(response, 'processorResponse'),
            :params_reconciliation_id => extract(response, 'reconciliationID'),
            :params_subscription_id => extract(response, 'subscriptionID'),
        }
      end

      def update_and_create_transaction(gw_response)
        updated_attributes = {
            :message => gw_response.message,
            :authorization => gw_response.authorization,
            :fraud_review => gw_response.fraud_review?,
            :test => gw_response.test?,
            :avs_result_code => gw_response.avs_result.kind_of?(::ActiveMerchant::Billing::AVSResult) ? gw_response.avs_result.code : gw_response.avs_result['code'],
            :avs_result_message => gw_response.avs_result.kind_of?(::ActiveMerchant::Billing::AVSResult) ? gw_response.avs_result.message : gw_response.avs_result['message'],
            :avs_result_street_match => gw_response.avs_result.kind_of?(::ActiveMerchant::Billing::AVSResult) ? gw_response.avs_result.street_match : gw_response.avs_result['street_match'],
            :avs_result_postal_match => gw_response.avs_result.kind_of?(::ActiveMerchant::Billing::AVSResult) ? gw_response.avs_result.postal_match : gw_response.avs_result['postal_match'],
            :cvv_result_code => gw_response.cvv_result.kind_of?(::ActiveMerchant::Billing::CVVResult) ? gw_response.cvv_result.code : gw_response.cvv_result['code'],
            :cvv_result_message => gw_response.cvv_result.kind_of?(::ActiveMerchant::Billing::CVVResult) ? gw_response.cvv_result.message : gw_response.cvv_result['message'],
            :success => gw_response.success?,
            :updated_at => Time.now.utc
        }.merge(CybersourceResponse.cybersource_response_params(gw_response))

        # Keep original values as much as possible
        updated_attributes.delete_if { |k, v| v.blank? }

        # Update the response row
        update!(updated_attributes)

        # Create the transaction row if needed (cannot have been created before or the state wouldn't have been UNDEFINED)
        if gw_response.success?
          amount = gw_response.params['amount']
          currency = gw_response.params['currency']
          amount_in_cents = amount.nil? ? nil : ::Monetize.from_numeric(amount.to_f, currency).cents.to_i
          build_cybersource_transaction(:kb_account_id => kb_account_id,
                                        :kb_tenant_id => kb_tenant_id,
                                        :amount_in_cents => amount_in_cents,
                                        :currency => currency,
                                        :api_call => api_call,
                                        :kb_payment_id => kb_payment_id,
                                        :kb_payment_transaction_id => kb_payment_transaction_id,
                                        :transaction_type => transaction_type,
                                        :payment_processor_account_id => payment_processor_account_id,
                                        :txn_id => txn_id,
                                        :created_at => updated_at,
                                        :updated_at => updated_at).save!
        end
      end

      def first_reference_id
        params_request_id
      end

      def second_reference_id
        params_reconciliation_id
      end

      def gateway_error_code
        params_reason_code
      end

      def to_transaction_info_plugin(transaction=nil)
        t_info_plugin = super(transaction)

        t_info_plugin.properties << create_plugin_property('cybersourceResponseId', id)

        t_info_plugin
      end
    end
  end
end
