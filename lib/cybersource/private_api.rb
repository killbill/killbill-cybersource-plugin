module Killbill #:nodoc:
  module Cybersource #:nodoc:
    class PrivatePaymentPlugin < ::Killbill::Plugin::ActiveMerchant::PrivatePaymentPlugin
      def initialize(session = {})
        super(:cybersource,
              ::Killbill::Cybersource::CybersourcePaymentMethod,
              ::Killbill::Cybersource::CybersourceTransaction,
              ::Killbill::Cybersource::CybersourceResponse,
              session)
      end
    end
  end
end
