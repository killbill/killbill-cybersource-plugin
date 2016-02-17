module ActiveMerchant
  module Billing
    class CyberSourceGateway

      # Add support for CreditCard objects
      def build_credit_request(money, creditcard_or_reference, options)
        xml = Builder::XmlMarkup.new :indent => 2

        setup_address_hash(options)

        add_payment_method_or_subscription(xml, money, creditcard_or_reference, options)
        add_credit_service(xml)

        xml.target!
      end

      # See https://github.com/killbill/killbill-cybersource-plugin/issues/4
      def commit(request, options)
        request = build_request(request, options)
        begin
          raw_response = ssl_post(test? ? self.test_url : self.live_url, request)
        rescue ResponseError => e
          raw_response = e.response.body
        end
        response = parse(raw_response)

        success = response[:decision] == 'ACCEPT'
        message = @@response_codes[('r' + response[:reasonCode]).to_sym] rescue response[:message]
        authorization = success ? [options[:order_id], response[:requestID], response[:requestToken]].compact.join(";") : nil

        Response.new(success, message, response,
                     :test => test?,
                     :authorization => authorization,
                     :avs_result => {:code => response[:avsCode]},
                     :cvv_result => response[:cvCode]
        )
      end
    end
  end
end
