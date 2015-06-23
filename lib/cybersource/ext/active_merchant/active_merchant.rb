module ActiveMerchant
  module Billing
    class CyberSourceGateway

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
