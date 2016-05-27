module Killbill #:nodoc:
  module Cybersource #:nodoc:
    # See http://apps.cybersource.com/library/documentation/dev_guides/Reporting_Developers_Guide/reporting_dg.pdf
    class CyberSourceOnDemand

      # For convenience, re-use the ActiveMerchant connection code, as the configuration is global currently
      # (see https://github.com/killbill/killbill-plugin-framework-ruby/issues/47)
      include ActiveMerchant::PostsData

      def initialize(config, logger)
        @config = config
        @logger = logger

        configure_connection
      end

      def single_transaction_report(merchant_reference_code, target_date)
        params = {
            :merchantID => @config[:merchantID],
            :merchantReferenceNumber => merchant_reference_code,
            :targetDate => target_date,
            :type => 'transaction',
            :subtype => 'transactionDetail',
            :versionNumber => '1.7',
        }

        headers = {
            # Don't use symbols or it will confuse Net/HTTP
            'Authorization' => 'Basic ' + Base64.encode64("#{@config[:username]}:#{@config[:password]}").chomp
        }

        data = URI.encode_www_form(params)

        @logger.info "Retrieving report for merchant_reference_code='#{merchant_reference_code}', target_date='#{target_date}', merchant_id='#{@config[:merchantID]}'"

        # Will raise ResponseError if the response code is > 300
        CyberSourceOnDemandTransactionReport.new(ssl_post(endpoint, data, headers), @logger)
      end

      def check_for_duplicates?
        @config[:check_for_duplicates] == true
      end

      private

      def endpoint
        @config[:test] == false ? live_url : test_url
      end

      def live_url
        @config[:live_url] || 'https://ebc.cybersource.com/ebc/Query'
      end

      def test_url
        @config[:test_url] || 'https://ebctest.cybersource.com/ebctest/Query'
      end

      def configure_connection
        if @config[:log_file]
          self.wiredump_device = File.open(@config[:log_file], 'w')
        else
          log_method = @config[:quiet] ? :debug : :info
          self.wiredump_device = ::Killbill::Plugin::ActiveMerchant::Utils::KBWiredumpDevice.new(@logger, log_method)
        end
        self.wiredump_device.sync = true

        self.open_timeout = @config[:open_timeout] unless @config[:open_timeout].nil?
        self.read_timeout = @config[:read_timeout] unless @config[:read_timeout].nil?
        self.retry_safe = @config[:retry_safe] unless @config[:retry_safe].nil?
        self.ssl_strict = @config[:ssl_strict] unless @config[:ssl_strict].nil?
        self.ssl_version = @config[:ssl_version] unless @config[:ssl_version].nil?
        self.max_retries = @config[:max_retries] unless @config[:max_retries].nil?
        self.proxy_address = @config[:proxy_address] unless @config[:proxy_address].nil?
        self.proxy_port = @config[:proxy_port] unless @config[:proxy_port].nil?
      end

      class CyberSourceOnDemandTransactionReport

        attr_reader :response

        def initialize(xml_report, logger)
          @logger = logger
          @hash_report = parse_xml(xml_report)
          parse
        end

        def success?
          @response.success?
        end

        def empty?
          @response.params['merchantReferenceCode'].nil?
        end

        private

        def parse
          report = parse_report
          request = parse_request(report)
          payment_data = !request.nil? ? request['PaymentData'] : nil
          profile = !request.nil? && !request['ProfileList'].nil? ? request['ProfileList']['Profile'] : nil

          test = parse_test(report)
          success, message = parse_success_message(request)
          merchant_reference_code = extract(request, 'MerchantReferenceNumber')
          request_id = extract(request, 'RequestID') || extract(payment_data, 'PaymentRequestID')
          request_token = nil

          # ActiveMerchant specific
          authorization = "#{merchant_reference_code};#{request_id};#{request_token}"

          # See CybersourceResponse
          params = {
              'merchantReferenceCode' => merchant_reference_code,
              'requestID' => request_id,
              'decision' => extract(profile, 'ProfileDecision'),
              'reasonCode' => nil,
              'requestToken' => request_token,
              'currency' => extract(payment_data, 'CurrencyCode'),
              'amount' => extract(payment_data, 'Amount'),
              'authorizationCode' => extract(payment_data, 'AuthorizationCode'),
              'avsCode' => extract(payment_data, 'AVSResultMapped'),
              'avsCodeRaw' => extract(payment_data, 'AVSResult'),
              'cvCode' => nil,
              'authorizedDateTime' => nil,
              'processorResponse' => nil,
              'reconciliationID' => extract(request, 'TransactionReferenceNumber'),
              'subscriptionID' => extract(request, 'SubscriptionID')
          }

          @response = ::ActiveMerchant::Billing::Response.new(success,
                                                              message,
                                                              params,
                                                              :test => test,
                                                              :authorization => authorization,
                                                              :avs_result => {:code => params['avsCode']},
                                                              :cvv_result => params['cvCode'])
        end

        def parse_report
          !@hash_report.nil? ? @hash_report['Report'] : nil
        end

        def parse_test(report)
          !report.nil? && !report['xmlns'].nil? && report['xmlns'].starts_with?('https://ebctest.cybersource.com')
        end

        def parse_request(report)
          # Assume the report contains a single request
          !report.nil? && !report['Requests'].nil? ? report['Requests']['Request'] : nil
        end

        # Note: for now, we only look at the response from CyberSource.
        # It would be nice to take into account the processor response too.
        def parse_success_message(request)
          success = false
          msg = nil
          return [success, msg] if request.nil? || request['ApplicationReplies'].nil? || request['ApplicationReplies']['ApplicationReply'].nil? || request['ApplicationReplies']['ApplicationReply'].empty?

          application_replies = request['ApplicationReplies']['ApplicationReply'].is_a?(Hash) ? [request['ApplicationReplies']['ApplicationReply']] : request['ApplicationReplies']['ApplicationReply']

          success = true
          application_replies.each do |application_reply|
            success &&= (application_reply['RCode'].to_s == '1')
            # Last message by convention
            msg = application_reply['RMsg']
          end
          [success, msg]
        end

        def extract(hash, key)
          !hash.nil? ? hash[key] : nil
        end

        def parse_xml(body)
          # Thanks ActiveSupport!
          Hash.from_xml(body)
        rescue # Parser error - request failed
          @logger.warn "Error checking for duplicate payment, CyberSource response: #{!body.nil? && body.respond_to?(:message) ? body.message : body}"
          nil
        end
      end
    end
  end
end
