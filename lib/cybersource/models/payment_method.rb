module Killbill #:nodoc:
  module Cybersource #:nodoc:
    class CybersourcePaymentMethod < ::Killbill::Plugin::ActiveMerchant::ActiveRecord::PaymentMethod

      self.table_name = 'cybersource_payment_methods'

      def self.from_response(kb_account_id, kb_payment_method_id, cc_or_token, response, options, extra_params = {})
        super(kb_account_id,
              kb_payment_method_id,
              cc_or_token,
              response,
              options,
              {
              }.merge!(extra_params),
              ::Killbill::Cybersource::CybersourcePaymentMethod)
      end

      def external_payment_method_id
        token
      end
    end
  end
end
