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

        # Remove namespace when unnecessary (ActiveMerchant and our original code expect it that way)
        response.keys.each do |k|
          _, actual_key = k.to_s.split('_', 2)
          if !actual_key.nil? && !response.has_key?(actual_key)
            response[actual_key] = response[k]
            response.delete(k)
          end
        end

        success = response[:decision] == 'ACCEPT'
        authorization = success ? [options[:order_id], response[:requestID], response[:requestToken]].compact.join(';') : nil

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

      def parse_element(reply, node)
        if node.has_elements?
          node.elements.each { |e| parse_element(reply, e) }
        else
          # The original ActiveMerchant implementation clobbers top level fields with values from the children
          # Instead, always namespace the keys for children (cleanup is needed afterwards, see above)
          is_top_level = node.parent.name == 'replyMessage' || node.parent.name == 'Fault'
          key = node.name.to_sym
          unless is_top_level
            parent = node.parent.name + (node.parent.attributes['id'] ? '_' + node.parent.attributes['id'] : '')
            key = (parent + '_' + node.name).to_sym
          end
          reply[key] = node.text
        end
        return reply
      end
    end
  end
end
