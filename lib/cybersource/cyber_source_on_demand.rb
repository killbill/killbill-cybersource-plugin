module Killbill #:nodoc:
  module Cybersource #:nodoc:
    class CyberSourceOnDemand

      @@live_url = 'https://ebc.cybersource.com/ebc/Query'
      @@test_url = 'https://ebctest.cybersource.com/ebctest/Query'

      def initialize(gateway, logger)
        @gateway = gateway
        @logger  = logger
      end

      def single_transaction_report(merchant_reference_code, target_date)
        params = {
            :merchantID              => @gateway.config[:merchantID],
            :merchantReferenceNumber => merchant_reference_code,
            :targetDate              => target_date,
            :type                    => 'transaction',
            :subtype                 => 'transactionDetail',
            :versionNumber           => '1.7',
        }

        headers = {
            # Don't use symbols or it will confuse Net/HTTP
            'Authorization' => 'Basic ' + Base64.encode64("#{@gateway.config[:username]}:#{@gateway.config[:password]}").chomp
        }

        data     = URI.encode_www_form(params)
        endpoint = @gateway.test? ? @@test_url : @@live_url

        # Will raise ResponseError if the response code is > 300
        parse(@gateway.ssl_post(endpoint, data, headers))
      end

      private

      def parse(body)
        # Thanks ActiveSupport!
        Hash.from_xml(body)
      rescue # Parser error - request failed
        @logger.warn "Error checking for duplicate payment, CyberSource response: #{body}"
        nil
      end
    end
  end
end
