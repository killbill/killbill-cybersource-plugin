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

      # Add support for commerceIndicator override
      def add_auth_service(xml, payment_method, options)
        if network_tokenization?(payment_method)
          add_network_tokenization(xml, payment_method, options)
          add_payment_solution(xml, payment_method, options)
        else
          xml.tag! 'ccAuthService', {'run' => 'true'} do
            # Let CyberSource figure it out otherwise (internet is the default unless tokens are used)
            xml.tag!("commerceIndicator", options[:commerce_indicator]) unless options[:commerce_indicator].blank?
          end
        end
      end

      # Changes:
      #  * Add support for commerceIndicator override
      #  * Don't set paymentNetworkToken (needs to be set after businessRules)
      #  * Fix typo (expected brand for MasterCard is master)
      def add_network_tokenization(xml, payment_method, options)
        return unless network_tokenization?(payment_method)

        case card_brand(payment_method).to_sym
          when :visa
            xml.tag! 'ccAuthService', {'run' => 'true'} do
              xml.tag!("cavv", payment_method.payment_cryptogram)
              xml.tag!("commerceIndicator", options[:commerce_indicator] || "vbv")
              xml.tag!("xid", payment_method.payment_cryptogram)
            end
          when :master
            xml.tag! 'ucaf' do
              xml.tag!("authenticationData", payment_method.payment_cryptogram)
              xml.tag!("collectionIndicator", "2")
            end
            xml.tag! 'ccAuthService', {'run' => 'true'} do
              xml.tag!("commerceIndicator", options[:commerce_indicator] || "spa")
            end
          when :american_express
            cryptogram = Base64.decode64(payment_method.payment_cryptogram)
            xml.tag! 'ccAuthService', {'run' => 'true'} do
              xml.tag!("cavv", Base64.encode64(cryptogram[0...20]))
              xml.tag!("commerceIndicator", options[:commerce_indicator] || "aesk")
              xml.tag!("xid", Base64.encode64(cryptogram[20...40]))
            end
        end
      end

      # Changes:
      #  * http://apps.cybersource.com/library/documentation/dev_guides/Android_Pay_SO_API/html/wwhelp/wwhimpl/js/html/wwhelp.htm#href=ch_soAPI.html
      #  * add paymentSolution tag to support Android Pay
      def add_payment_solution(xml, payment_method, options)
        xml.tag!("paymentSolution", "006") if options[:source] == "androidpay"
      end

      # Changes:
      #  * Enable business rules for Apple Pay
      #  * Set paymentNetworkToken if needed (a bit of a hack to do it here, but it avoids having to override too much code)
      def add_business_rules_data(xml, payment_method, options)
        prioritized_options = [options, @options]

        xml.tag! 'businessRules' do
          xml.tag!('ignoreAVSResult', 'true') if extract_option(prioritized_options, :ignore_avs)
          xml.tag!('ignoreCVResult', 'true') if extract_option(prioritized_options, :ignore_cvv)
        end

        if network_tokenization?(payment_method)
          xml.tag! 'paymentNetworkToken' do
            xml.tag!('transactionType', "1")
          end
        end
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
