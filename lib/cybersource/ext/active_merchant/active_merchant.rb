module ActiveMerchant
  module Billing

    KB_PLUGIN_VERSION = Gem.loaded_specs['killbill-cybersource'].version.version rescue nil

    class CyberSourceGateway
      # The payload definitions: https://ics2wstest.ic3.com/commerce/1.x/transactionProcessor/CyberSourceTransaction_1.109.xsd

      def self.x_request_id
        # See KillbillMDCInsertingServletFilter
        org::slf4j::MDC::get('req.requestId') rescue nil
      end

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
        else
          xml.tag! 'ccAuthService', {'run' => 'true'} do
            # Let CyberSource figure it out otherwise (internet is the default unless tokens are used)
            xml.tag!("commerceIndicator", options[:commerce_indicator]) unless options[:commerce_indicator].blank?
            add_reconciliation_id(xml, options)
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
              xml.tag!("commerceIndicator", options[:commerce_indicator] || (is_android_pay(payment_method, options) || is_google_pay(payment_method, options)) ? 'internet' : 'vbv')
              xml.tag!("xid", payment_method.payment_cryptogram)
              add_reconciliation_id(xml, options)
            end
          when :master
            xml.tag! 'ucaf' do
              xml.tag!("authenticationData", payment_method.payment_cryptogram)
              xml.tag!("collectionIndicator", "2")
            end
            xml.tag! 'ccAuthService', {'run' => 'true'} do
              xml.tag!("commerceIndicator", options[:commerce_indicator] || "spa")
              add_reconciliation_id(xml, options)
            end
          when :american_express
            cryptogram = Base64.decode64(payment_method.payment_cryptogram)
            xml.tag! 'ccAuthService', {'run' => 'true'} do
              xml.tag!("cavv", Base64.encode64(cryptogram[0...20]))
              xml.tag!("commerceIndicator", options[:commerce_indicator] || "aesk")
              if cryptogram.size == 40
                xml.tag!("xid", Base64.encode64(cryptogram[20...40]))
              end
              add_reconciliation_id(xml, options)
            end
          when :discover
            xml.tag! 'ccAuthService', {'run' => 'true'} do
              xml.tag!("cavv", payment_method.payment_cryptogram)
              xml.tag!("commerceIndicator", options[:commerce_indicator] || "dipb")
              add_reconciliation_id(xml, options)
            end
        end
      end

      def build_capture_request(money, authorization, options)
        order_id, request_id, request_token = authorization.split(";")
        options[:order_id] = order_id

        xml = Builder::XmlMarkup.new :indent => 2
        add_purchase_data(xml, money, true, options)
        add_capture_service(xml, request_id, request_token, options)
        add_business_rules_data(xml, authorization, options)
        xml.target!
      end

      def add_capture_service(xml, request_id, request_token, options = {})
        xml.tag! 'ccCaptureService', {'run' => 'true'} do
          xml.tag! 'authRequestID', request_id
          add_reconciliation_id(xml, options) # the order is important
          xml.tag! 'authRequestToken', request_token
        end
      end

      def build_refund_request(money, identification, options)
        order_id, request_id, request_token = identification.split(";")
        options[:order_id] = order_id

        xml = Builder::XmlMarkup.new :indent => 2
        add_purchase_data(xml, money, true, options)
        add_credit_service(xml, request_id, request_token, options)

        xml.target!
      end

      def add_credit_service(xml, request_id = nil, request_token = nil, options = {})
        xml.tag! 'ccCreditService', {'run' => 'true'} do
          xml.tag! 'captureRequestID', request_id if request_id
          add_reconciliation_id(xml, options)
          xml.tag! 'captureRequestToken', request_token if request_token
        end
      end

      # Changes:
      #  * http://apps.cybersource.com/library/documentation/dev_guides/Android_Pay_SO_API/html/wwhelp/wwhimpl/js/html/wwhelp.htm#href=ch_soAPI.html
      #  * add paymentSolution tag to support Android Pay
      def add_payment_solution(xml, payment_method, options)
        if is_android_pay(payment_method, options)
          xml.tag!('paymentSolution', '006')
        elsif is_google_pay(payment_method, options)
          xml.tag!('paymentSolution', '012')
        else
          xml.tag!('paymentSolution', '001')
        end
      end

      def is_android_pay(payment_method, options)
        (payment_method.respond_to?(:source) && payment_method.source == :android_pay) || options[:source] == 'androidpay'
      end

      def is_google_pay(payment_method, options)
        (payment_method.respond_to?(:source) && payment_method.source == :google_pay) || options[:source] == 'googlepay'
      end

      # Changes:
      #  * Enable business rules for Apple Pay
      #  * Set paymentNetworkToken and paymentSolution if needed (a bit of a hack to do it here, but it avoids having to override too much code)
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

          add_payment_solution(xml, payment_method, options)
        end
      end

      def commit(request, options)
        request = build_request(request, options)
        begin
          raw_response = ssl_post(test? ? self.test_url : self.live_url, request, build_headers(options))
        rescue ResponseError => e
          if !e.response.nil? && e.response.code.to_i == 500 && !e.response.body.blank?
            # See https://github.com/killbill/killbill-cybersource-plugin/issues/4
            raw_response = e.response.body
          else
            # Don't swallow other 5xx errors like proxy timeouts - these should most likely be UNKNOWN
            raise e
          end
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
        response[:reconciliation_id] = options[:reconciliation_id] if options[:reconciliation_id].present?

        success = response[:decision] == 'ACCEPT'
        authorization = success ? [options[:order_id], response['subscriptionID'] || response[:requestID], response[:requestToken]].compact.join(';') : nil

        message = nil
        if response[:reasonCode].blank? && (response[:faultcode] == 'wsse:FailedCheck' || response[:faultcode] == 'wsse:InvalidSecurity' || response[:faultcode] == 'soap:Client' || response[:faultcode] == 'c:ServerError')
          message = {:exception_message => response[:message], :payment_plugin_status => :CANCELED}.to_json
        end
        message ||= @@response_codes[('r' + response[:reasonCode].to_s).to_sym] || response[:message]

        Response.new(success, message, response,
                     :test => test?,
                     :authorization => authorization,
                     :avs_result => {:code => response['avsCode']},
                     :cvv_result => response['cvCode'])
      end

      def self.user_agent
        @@ua ||= JSON.dump({
                               :bindings_version => KB_PLUGIN_VERSION,
                               :lang => 'ruby',
                               :lang_version => "#{RUBY_VERSION} p#{RUBY_PATCHLEVEL} (#{RUBY_RELEASE_DATE})",
                               :platform => RUBY_PLATFORM,
                               :publisher => 'killbill'
                           })
      end

      def build_headers(options)
        options[:x_request_id] ||= self.class.x_request_id
        options[:content_type] ||= 'text/xml'

        headers = {}
        headers['Content-Type'] = options[:content_type]
        headers['User-Agent'] = self.class.user_agent
        headers['X-Request-Id'] = options[:x_request_id] unless options[:x_request_id].blank?
        headers
      end

      def add_merchant_data(xml, options)
        xml.tag! 'merchantID', @options[:login]
        xml.tag! 'merchantReferenceCode', options[:order_id]
        xml.tag! 'clientLibrary' ,'Kill Bill'
        xml.tag! 'clientLibraryVersion', KB_PLUGIN_VERSION
        xml.tag! 'clientEnvironment' , RUBY_PLATFORM
        add_invoice_header(xml, options) # Merchant soft descriptor
      end

      def add_invoice_header(xml, options)
        merchant_descriptor = options[:merchant_descriptor]
        if merchant_descriptor.present? &&
           merchant_descriptor.is_a?(Hash) &&
           !merchant_descriptor['card_type'].nil? &&
           !merchant_descriptor['transaction_type'].nil?
          name    = merchant_descriptor['name']
          contact = merchant_descriptor['contact']
          if merchant_descriptor['card_type'].to_s == 'american_express'
            unless merchant_descriptor['transaction_type'] == :AUTHORIZE # Amex only supports capture and refund
              xml.tag! 'invoiceHeader' do
                xml.tag! 'amexDataTAA1', format_string(name, 40)
                xml.tag! 'amexDataTAA2', format_string(contact, 40)
              end
            end
          else
            xml.tag! 'invoiceHeader' do
              xml.tag! 'merchantDescriptor', format_name(name)
              xml.tag! 'merchantDescriptorContact', format_contact(contact)
            end
          end
        end
      end

      def add_reconciliation_id(xml, options)
        return unless options[:reconciliation_id].present?
        xml.tag! 'reconciliationID', options[:reconciliation_id]
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

      def format_string(str, max_length)
        return '' if str.nil?
        str.first(max_length)
      end

      def format_contact(contact)
        contact ||= ''
        contact = contact.gsub(/\D/, '').ljust(10, '0')
        [contact[0..2],contact[3..5],contact[6..9]].join('-')
      end

      def format_name(name)
        name ||= ''
        if name.index('*') != nil
          subnames = name.split('*')
          name = subnames[0].ljust(12)[0..11] + '*' + subnames[1]
        end
        name.ljust(22)[0..21]
      end
    end
  end
end
