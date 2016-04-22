module ActiveMerchant
  module Billing

    KB_PLUGIN_VERSION = Gem.loaded_specs['killbill-cybersource'].version.version rescue nil

    class CyberSourceGateway

      def initialize(options = {})
        super

        # Add missing response codes
        @@response_codes[:r104] = 'The merchant reference code for this authorization request matches the merchant reference code of another authorization request that you sent within the past 15 minutes.'
        @@response_codes[:r110] = 'Only a partial amount was approved'
      end

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
        authorization = success ? [options[:order_id], response[:requestID], response[:requestToken]].compact.join(";") : nil

        message = nil
        if response[:reasonCode].blank? && (response[:faultcode] == 'wsse:FailedCheck' || response[:faultcode] == 'wsse:InvalidSecurity' || response[:faultcode] == 'soap:Client' || response[:faultcode] == 'c:ServerError')
          message = {:exception_message => response[:message], :payment_plugin_status => :CANCELED}.to_json
        end
        message ||= @@response_codes[('r' + response[:reasonCode].to_s).to_sym] || response[:message]

        Response.new(success, message, response,
                     :test => test?,
                     :authorization => authorization,
                     :avs_result => {:code => response[:avsCode]},
                     :cvv_result => response[:cvCode]
        )
      end

      def add_merchant_data(xml, options)
        xml.tag! 'merchantID', @options[:login]
        xml.tag! 'merchantReferenceCode', options[:order_id]
        xml.tag! 'clientLibrary' ,'Kill Bill'
        xml.tag! 'clientLibraryVersion', KB_PLUGIN_VERSION
        xml.tag! 'clientEnvironment' , RUBY_PLATFORM
      end
    end
  end
end
