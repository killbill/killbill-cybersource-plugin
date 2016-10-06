require 'spec_helper'

describe Killbill::Cybersource::PaymentPlugin do

  include ::Killbill::Plugin::ActiveMerchant::RSpec

  before(:each) do
    Dir.mktmpdir do |dir|
      file = File.new(File.join(dir, 'cybersource.yml'), 'w+')
      file.write(<<-eos)
:cybersource:
  :test: true
# As defined by spec_helper.rb
:database:
  :adapter: 'sqlite3'
  :database: 'test.db'
      eos
      file.close

      @plugin = build_plugin(::Killbill::Cybersource::PaymentPlugin, 'cybersource', File.dirname(file))

      # Start the plugin here - since the config file will be deleted
      @plugin.start_plugin
    end
  end

  let(:expected_successful_params) do
    {
        :params_merchant_reference_code => 'b0a6cf9aa07f1a8495f89c364bbd6a9a',
        :params_request_id => '2004333231260008401927',
        :params_decision => 'ACCEPT',
        :params_reason_code => '100',
        :params_request_token => 'Afvvj7Ke2Fmsbq0wHFE2sM6R4GAptYZ0jwPSA+R9PhkyhFTb0KRjoE4+ynthZrG6tMBwjAtT',
        :params_currency => 'USD',
        :params_amount => '1.00',
        :params_authorization_code => '123456',
        :params_avs_code => 'Y',
        :params_avs_code_raw => 'Y',
        :params_cv_code => 'M',
        :params_authorized_date_time => '2008-01-15T21:42:03Z',
        :params_processor_response => '00',
        :params_reconciliation_id => 'ABCDEF',
        :params_subscription_id => 'XXYYZZ'
    }
  end

  it 'should start and stop correctly' do
    @plugin.stop_plugin
  end

  it 'should detect when to credit refunds' do
    context = build_call_context
    kb_payment_id = SecureRandom.uuid

    @plugin.should_credit?(SecureRandom.uuid, context).should be_false

    with_transaction(kb_payment_id, :AUTHORIZE, 60.days.ago, build_call_context(SecureRandom.uuid)) { @plugin.should_credit?(kb_payment_id, context).should be_false }
    with_transaction(kb_payment_id, :AUTHORIZE, 59.days.ago, context) { @plugin.should_credit?(kb_payment_id, context).should be_false }
    with_transaction(kb_payment_id, :VOID, 60.days.ago, context) { @plugin.should_credit?(kb_payment_id, context).should be_false }
    with_transaction(SecureRandom.uuid, :AUTHORIZE, 60.days.ago, context) { @plugin.should_credit?(kb_payment_id, context).should be_false }

    with_transaction(kb_payment_id, :AUTHORIZE, 61.days.ago, context) do
      @plugin.should_credit?(kb_payment_id, context, {:disable_auto_credit => true}).should be_false
      @plugin.should_credit?(kb_payment_id, context, {:auto_credit_threshold => 61 * 86400 + 10}).should be_false
      @plugin.should_credit?(kb_payment_id, context).should be_true
    end
  end

  context 'Business Rules' do

    it 'does not ignore AVS nor CVN' do
      ::ActiveMerchant::Billing::CyberSourceGateway.any_instance.stub(:ssl_post) do |host, request_body|
        request_body.should_not match('<ignoreAVSResult>')
        request_body.should_not match('<ignoreCVResult>')
        successful_purchase_response
      end
      purchase_with_token(:PROCESSED, [], expected_successful_params)
      purchase_with_token(:PROCESSED, [build_property('ignore_avs', 'false'), build_property('ignore_cvv', 'false')], expected_successful_params)
    end

    it 'ignores AVS and CVN' do
      ::ActiveMerchant::Billing::CyberSourceGateway.any_instance.stub(:ssl_post) do |host, request_body|
        request_body.should match('<ignoreAVSResult>')
        request_body.should match('<ignoreCVResult>')
        successful_purchase_response
      end
      purchase_with_token(:PROCESSED, [build_property('ignore_avs', 'true'), build_property('ignore_cvv', 'true')], expected_successful_params)
    end

    it 'ignores AVS but not CVN' do
      ::ActiveMerchant::Billing::CyberSourceGateway.any_instance.stub(:ssl_post) do |host, request_body|
        request_body.should match('<ignoreAVSResult>')
        request_body.should_not match('<ignoreCVResult>')
        successful_purchase_response
      end
      purchase_with_token(:PROCESSED, [build_property('ignore_avs', 'true')], expected_successful_params)
      purchase_with_token(:PROCESSED, [build_property('ignore_avs', 'true'), build_property('ignore_cvv', 'false')], expected_successful_params)
    end

    it 'ignores CVN but not AVS' do
      ::ActiveMerchant::Billing::CyberSourceGateway.any_instance.stub(:ssl_post) do |host, request_body|
        request_body.should_not match('<ignoreAVSResult>')
        request_body.should match('<ignoreCVResult>')
        successful_purchase_response
      end
      purchase_with_token(:PROCESSED, [build_property('ignore_cvv', 'true')], expected_successful_params)
      purchase_with_token(:PROCESSED, [build_property('ignore_avs', 'false'), build_property('ignore_cvv', 'true')], expected_successful_params)
    end
  end

  context 'Override parameters' do

    it 'has a default commerceIndicator' do
      ::ActiveMerchant::Billing::CyberSourceGateway.any_instance.stub(:ssl_post) do |host, request_body|
        request_body.should_not match('<commerceIndicator>')
        successful_purchase_response
      end
      purchase_with_token(:PROCESSED, [], expected_successful_params)
    end

    it 'can override commerceIndicator for card-on-file' do
      ::ActiveMerchant::Billing::CyberSourceGateway.any_instance.stub(:ssl_post) do |host, request_body|
        request_body.should match('<commerceIndicator>recurring</commerceIndicator>')
        successful_purchase_response
      end
      purchase_with_card(:PROCESSED, [build_property('commerce_indicator', 'recurring')], expected_successful_params)
    end

    it 'has a default commerceIndicator for Apple Pay' do
      ::ActiveMerchant::Billing::CyberSourceGateway.any_instance.stub(:ssl_post) do |host, request_body|
        request_body.should_not match('<commerceIndicator>internet</commerceIndicator>')
        request_body.should match('<commerceIndicator>vbv</commerceIndicator>')
        successful_purchase_response
      end
      purchase_with_network_tokenization(:PROCESSED, [], expected_successful_params)
    end

    it 'can override commerceIndicator for Apple Pay' do
      ::ActiveMerchant::Billing::CyberSourceGateway.any_instance.stub(:ssl_post) do |host, request_body|
        request_body.should_not match('<commerceIndicator>vbv</commerceIndicator>')
        request_body.should match('<commerceIndicator>internet</commerceIndicator>')
        successful_purchase_response
      end
      purchase_with_network_tokenization(:PROCESSED, [build_property('commerce_indicator', 'internet')], expected_successful_params)
    end
  end

  context 'Errors handling' do

    it 'handles proxy errors as UNDEFINED transactions' do
      ::ActiveMerchant::Billing::CyberSourceGateway.any_instance.stub(:ssl_post) do |_, _|
        raise ::ActiveMerchant::ResponseError.new(OpenStruct.new(:body => 'Oops', :code => 502))
      end
      purchase_with_token(:UNDEFINED).gateway_error.should == 'Failed with 502 '
    end

    it 'handles generic 500 errors as UNDEFINED transactions' do
      ::ActiveMerchant::Billing::CyberSourceGateway.any_instance.stub(:ssl_post) do |_, _|
        raise ::ActiveMerchant::ResponseError.new(OpenStruct.new(:body => nil, :code => 500))
      end
      purchase_with_token(:UNDEFINED).gateway_error.should == 'Failed with 500 '
    end

    it 'handles CyberSource errors as CANCELED transactions' do
      ::ActiveMerchant::Billing::CyberSourceGateway.any_instance.stub(:ssl_post) do |_, _|
        raise ::ActiveMerchant::ResponseError.new(OpenStruct.new(:body => one_or_more_fields_contains_invalid_data, :code => 500))
      end
      purchase_with_token(:CANCELED).gateway_error.should == 'One or more fields contains invalid data'
    end

    it 'handles expired passwords as CANCELED transactions' do
      ::ActiveMerchant::Billing::CyberSourceGateway.any_instance.stub(:ssl_post).and_return(password_expired_response)
      purchase_with_token(:CANCELED).gateway_error.should == 'wsse:FailedCheck: Security Data : Merchant password has expired.'
    end

    it 'handles bad passwords as CANCELED transactions' do
      ::ActiveMerchant::Billing::CyberSourceGateway.any_instance.stub(:ssl_post).and_return(bad_password_response)
      purchase_with_token(:CANCELED).gateway_error.should == 'wsse:FailedCheck: Security Data : UsernameToken authentication failed.'
    end

    it 'handles unsuccessful authorizations as ERROR transactions' do
      ::ActiveMerchant::Billing::CyberSourceGateway.any_instance.stub(:ssl_post).and_return(unsuccessful_authorization_response)
      purchase_with_token(:ERROR).gateway_error.should == 'Invalid account number'
    end

    it 'parses correctly authorization reversal errors' do
      ::ActiveMerchant::Billing::CyberSourceGateway.any_instance.stub(:ssl_post).and_return(unsuccessful_auth_reversal_response)
      payment_response = purchase_with_token(:CANCELED)
      payment_response.gateway_error.should == 'One or more fields contains invalid data'
      payment_response.gateway_error_code.should == '102'
    end

    it 'cancels UNDEFINED transactions with a JSON message' do
      response = Killbill::Cybersource::CybersourceResponse.create(:api_call => 'authorization',
                                                                   :message => '{"exception_message":"Timeout","payment_plugin_status":"UNDEFINED"}',
                                                                   :created_at => Time.now,
                                                                   :updated_at => Time.now)
      response.cancel
      response.message.should == '{"exception_message":"Timeout","payment_plugin_status":"CANCELED"}'
    end

    it 'cancels UNDEFINED transactions with a plain test message' do
      response = Killbill::Cybersource::CybersourceResponse.create(:api_call => 'authorization',
                                                                   :message => 'Internal error',
                                                                   :created_at => Time.now,
                                                                   :updated_at => Time.now)
      response.cancel
      response.message.should == '{"original_message":"Internal error","payment_plugin_status":"CANCELED"}'
    end

    it 'cancels UNDEFINED transactions with no message' do
      response = Killbill::Cybersource::CybersourceResponse.create(:api_call => 'authorization',
                                                                   :created_at => Time.now,
                                                                   :updated_at => Time.now)
      response.cancel
      response.message.should == '{"payment_plugin_status":"CANCELED"}'
    end
  end

  def stub_gateway_for_invoice_header(invoice_match_status)
    ::ActiveMerchant::Billing::CyberSourceGateway.any_instance.stub(:ssl_post) do |host, request_body|
      case(invoice_match_status)
      when :none
        request_body.should_not match('<invoiceHeader>')
      when :all
        request_body.should match('<invoiceHeader>\n        <merchantDescriptor>Ray Qiu               </merchantDescriptor>\n        <merchantDescriptorContact>650-888-3161</merchantDescriptorContact>\n      </invoiceHeader>')
      when :except_authorize
        if request_body.index('ccAuthService').present?
          request_body.should_not match('<invoiceHeader>\n        <amexDataTAA1>Ray Qiu</amexDataTAA1>\n        <amexDataTAA2>6508883161</amexDataTAA2>')
        else
          request_body.should match('<invoiceHeader>\n        <amexDataTAA1>Ray Qiu</amexDataTAA1>\n        <amexDataTAA2>6508883161</amexDataTAA2>')
        end
      end
      successful_purchase_response
    end
  end

  shared_examples 'full payment' do
    before do
      send(add_payment_properties, txn_properties, card_type)
      stub_gateway_for_invoice_header(invoice_match_status)
    end

    it 'should met expectations' do
      auth_responses = create_transaction(card_type, :authorize, nil, :PROCESSED, txn_properties, expected_successful_params)
      capture_responses = create_transaction(card_type, :capture, auth_responses, :PROCESSED, txn_properties, expected_successful_params)
      create_transaction(card_type, :refund, capture_responses, :PROCESSED, txn_properties, expected_successful_params)
    end
  end

  shared_examples 'invoice header example' do
    let(:card_type){ :visa }
    let(:txn_properties){ [] }

    context 'while no descriptor provided' do
      let(:invoice_match_status){ :none }

      context 'visa' do
        it_behaves_like 'full payment'
      end

      context 'amex' do
        let(:card_type){ :amex }
        it_behaves_like 'full payment'
      end
    end

    context 'while descriptor provided' do
      before{ txn_properties << build_property('merchant_descriptor', {"name"=>"Ray Qiu", "contact"=>"6508883161"}.to_json) }

      context 'visa' do
        let(:invoice_match_status){ :all }
        it_behaves_like 'full payment'
      end

      context 'amex' do
        let(:card_type){ :amex }
        let(:invoice_match_status){ :except_authorize }
        it_behaves_like 'full payment'
      end
    end
  end

  context 'Invoice Header' do
    context 'payments with card' do
      let(:add_payment_properties){ :add_card_property }
      it_behaves_like 'invoice header example'
    end

    context 'payments with network tokenization' do
      let(:add_payment_properties){ :add_network_tokenization_properties }
      it_behaves_like 'invoice header example'
    end
  end

  private

  def with_transaction(kb_payment_id, transaction_type, created_at, context)
    t = ::Killbill::Cybersource::CybersourceTransaction.create(:kb_payment_id => kb_payment_id,
                                                               :transaction_type => transaction_type,
                                                               :kb_tenant_id => context.tenant_id,
                                                               :created_at => created_at,
                                                               # The data below doesn't matter
                                                               :updated_at => created_at,
                                                               :kb_account_id => SecureRandom.uuid,
                                                               :kb_payment_transaction_id => SecureRandom.uuid,
                                                               :api_call => :refund,
                                                               :cybersource_response_id => 1)
    t.should_not be_nil
    yield t if block_given?
  ensure
    t.destroy! unless t.nil?
  end

  def add_card_property(properties, card_type = :visa)
    properties << build_property('email', 'foo@bar.com')
    if card_type == :amex
      properties << build_property('cc_number', '378282246310005')
    else
      properties << build_property('cc_number', '4111111111111111')
    end
  end

  def add_token_property(properties)
    properties << build_property('email', 'foo@bar.com')
    properties << build_property('token', '1234')
  end

  def add_network_tokenization_properties(properties, card_type = :visa)
    if card_type == :amex
      properties << build_property('cc_number', '378282246310005')
      properties << build_property('brand', 'american_express')
      properties << build_property('payment_cryptogram', Base64.encode64('111111111100cryptogram'))
    else
      properties << build_property('cc_number', '4111111111111111')
      properties << build_property('brand', 'visa')
      properties << build_property('payment_cryptogram', '111111111100cryptogram')
    end
    properties << build_property('email', 'foo@bar.com')
    properties << build_property('eci', '05')
  end

  def purchase_with_card(expected_status = :PROCESSED, properties = [], expected_params = {})
    add_card_property(properties)
    purchase(expected_status, properties, expected_params)
  end

  def purchase_with_token(expected_status = :PROCESSED, properties = [], expected_params = {})
    add_token_property(properties)
    purchase(expected_status, properties, expected_params)
  end

  def purchase_with_network_tokenization(expected_status = :PROCESSED, properties = [], expected_params = {})
    add_network_tokenization_properties(properties)
    purchase(expected_status, properties, expected_params)
  end

  def verify_response(payment_response, expected_status, expected_params)
    payment_response.status.should eq(expected_status), payment_response.gateway_error

    gw_response = Killbill::Cybersource::CybersourceResponse.last
    expected_params.each do |k, v|
      gw_response.send(k.to_sym).should == v
    end
  end

  def create_transaction(card_type = :visa, txn_type = :authorize, previous_response = nil, expected_status = :PROCESSED, properties = [], expected_params = {})
    if txn_type == :authorize
      authorize(expected_status, properties, expected_params)
    else
      previous_response.shift
      send(txn_type, *previous_response, expected_status, properties, expected_params)
    end
  end

  def authorize(expected_status = :PROCESSED, properties = [], expected_params = {})
    kb_account_id = SecureRandom.uuid
    kb_payment_method_id = SecureRandom.uuid
    kb_payment_id = SecureRandom.uuid
    kb_payment = @plugin.kb_apis.proxied_services[:payment_api].add_payment(kb_payment_id)
    kb_transaction_id = kb_payment.transactions[0].id

    payment_response = @plugin.authorize_payment(kb_account_id, kb_payment_id, kb_transaction_id, kb_payment_method_id, BigDecimal.new('100'), 'USD', properties, build_call_context)
    verify_response(payment_response, expected_status, expected_params)
    return payment_response, kb_account_id, kb_payment_id, kb_transaction_id, kb_payment_method_id
  end

  def capture(kb_account_id, kb_payment_id, kb_transaction_id, kb_payment_method_id, expected_status = :PROCESSED, properties = [], expected_params = {})
    payment_response = @plugin.capture_payment(kb_account_id, kb_payment_id, kb_transaction_id, kb_payment_method_id, BigDecimal.new('100'), 'USD', properties, build_call_context)
    verify_response(payment_response, expected_status, expected_params)
    return payment_response, kb_account_id, kb_payment_id, kb_transaction_id, kb_payment_method_id
  end

  def refund(kb_account_id, kb_payment_id, kb_transaction_id, kb_payment_method_id, expected_status = :PROCESSED, properties = [], expected_params = {})
    payment_response = @plugin.refund_payment(kb_account_id, kb_payment_id, kb_transaction_id, kb_payment_method_id, BigDecimal.new('100'), 'USD', properties, build_call_context)
    verify_response(payment_response, expected_status, expected_params)
    return payment_response, kb_account_id, kb_payment_id, kb_transaction_id, kb_payment_method_id
  end

  def purchase(expected_status = :PROCESSED, properties = [], expected_params = {})
    kb_payment_id = SecureRandom.uuid
    kb_payment = @plugin.kb_apis.proxied_services[:payment_api].add_payment(kb_payment_id)
    kb_transaction_id = kb_payment.transactions[0].id

    payment_response = @plugin.purchase_payment(SecureRandom.uuid, kb_payment_id, kb_transaction_id, SecureRandom.uuid, BigDecimal.new('100'), 'USD', properties, build_call_context)
    verify_response(payment_response, expected_status, expected_params)
    payment_response
  end

  def successful_purchase_response
    <<-XML
<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
<soap:Header>
<wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"><wsu:Timestamp xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" wsu:Id="Timestamp-2636690"><wsu:Created>2008-01-15T21:42:03.343Z</wsu:Created></wsu:Timestamp></wsse:Security></soap:Header><soap:Body><c:replyMessage xmlns:c="urn:schemas-cybersource-com:transaction-data-1.26"><c:merchantReferenceCode>b0a6cf9aa07f1a8495f89c364bbd6a9a</c:merchantReferenceCode><c:requestID>2004333231260008401927</c:requestID><c:decision>ACCEPT</c:decision><c:reasonCode>100</c:reasonCode><c:requestToken>Afvvj7Ke2Fmsbq0wHFE2sM6R4GAptYZ0jwPSA+R9PhkyhFTb0KRjoE4+ynthZrG6tMBwjAtT</c:requestToken><c:purchaseTotals><c:currency>USD</c:currency></c:purchaseTotals><c:ccAuthReply><c:reasonCode>100</c:reasonCode><c:amount>1.00</c:amount><c:authorizationCode>123456</c:authorizationCode><c:avsCode>Y</c:avsCode><c:avsCodeRaw>Y</c:avsCodeRaw><c:cvCode>M</c:cvCode><c:cvCodeRaw>M</c:cvCodeRaw><c:authorizedDateTime>2008-01-15T21:42:03Z</c:authorizedDateTime><c:processorResponse>00</c:processorResponse><c:reconciliationID>ABCDEF</c:reconciliationID><c:authFactorCode>U</c:authFactorCode></c:ccAuthReply><c:paySubscriptionCreateReply><c:reasonCode>100</c:reasonCode><c:subscriptionID>XXYYZZ</c:subscriptionID></c:paySubscriptionCreateReply></c:replyMessage></soap:Body></soap:Envelope>
    XML
  end

  def password_expired_response
    <<-XML
<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
<soap:Header>
<wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"><wsu:Timestamp xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" wsu:Id="Timestamp-2636690"><wsu:Created>2008-01-15T21:42:03.343Z</wsu:Created></wsu:Timestamp></wsse:Security></soap:Header><soap:Body><soap:Fault xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" xmlns:c="urn:schemas-cybersource-com:transaction-data-1.0"><faultcode>wsse:FailedCheck</faultcode><faultstring>Security Data : Merchant password has expired.</faultstring></soap:Fault></soap:Body></soap:Envelope>
    XML
  end

  def bad_password_response
    <<-XML
<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
<soap:Header>
<wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"><wsu:Timestamp xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" wsu:Id="Timestamp-2636690"><wsu:Created>2008-01-15T21:42:03.343Z</wsu:Created></wsu:Timestamp></wsse:Security></soap:Header><soap:Body><soap:Fault xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" xmlns:c="urn:schemas-cybersource-com:transaction-data-1.0"><faultcode>wsse:FailedCheck</faultcode><faultstring>Security Data : UsernameToken authentication failed.</faultstring></soap:Fault></soap:Body></soap:Envelope>
    XML
  end

  def unsuccessful_authorization_response
    <<-XML
<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
<soap:Header>
<wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"><wsu:Timestamp xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" wsu:Id="Timestamp-28121162"><wsu:Created>2008-01-15T21:50:41.580Z</wsu:Created></wsu:Timestamp></wsse:Security></soap:Header><soap:Body><c:replyMessage xmlns:c="urn:schemas-cybersource-com:transaction-data-1.26"><c:merchantReferenceCode>a1efca956703a2a5037178a8a28f7357</c:merchantReferenceCode><c:requestID>2004338415330008402434</c:requestID><c:decision>REJECT</c:decision><c:reasonCode>231</c:reasonCode><c:requestToken>Afvvj7KfIgU12gooCFE2/DanQIApt+G1OgTSA+R9PTnyhFTb0KRjgFY+ynyIFNdoKKAghwgx</c:requestToken><c:ccAuthReply><c:reasonCode>231</c:reasonCode></c:ccAuthReply></c:replyMessage></soap:Body></soap:Envelope>
    XML
  end

  def unsuccessful_auth_reversal_response
    <<-XML
<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
<soap:Header>
<wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"><wsu:Timestamp xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" wsu:Id="Timestamp-28121162"><wsu:Created>2008-01-15T21:50:41.580Z</wsu:Created></wsu:Timestamp></wsse:Security></soap:Header><soap:Body><c:replyMessage xmlns:c="urn:schemas-cybersource-com:transaction-data-1.26"><c:merchantReferenceCode>a1efca956703a2a5037178a8a28f7357</c:merchantReferenceCode><c:requestID>2004338415330008402434</c:requestID><c:decision>REJECT</c:decision><c:reasonCode>102</c:reasonCode><c:requestToken>Afvvj7KfIgU12gooCFE2/DanQIApt+G1OgTSA+R9PTnyhFTb0KRjgFY+ynyIFNdoKKAghwgx</c:requestToken><c:ccAuthReversalReply><c:reasonCode>102</c:reasonCode></c:ccAuthReversalReply><c:originalTransaction><c:amount>0.00</c:amount><c:reasonCode>100</c:reasonCode></c:originalTransaction></c:replyMessage></soap:Body></soap:Envelope>
    XML
  end

  def one_or_more_fields_contains_invalid_data
    <<-XML
<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
<soap:Header>
<wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"><wsu:Timestamp xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" wsu:Id="Timestamp-28121162"><wsu:Created>2008-01-15T21:50:41.580Z</wsu:Created></wsu:Timestamp></wsse:Security></soap:Header><soap:Body><c:replyMessage xmlns:c="urn:schemas-cybersource-com:transaction-data-1.26"><c:requestID>12345</c:requestID><c:decision>REJECT</c:decision><c:reasonCode>102</c:reasonCode><c:invalidField>c:billTo/c:state</c:invalidField><c:requestToken>Afvvj7KfIgU12gooCFE2/DanQIApt+G1OgTSA+R9PTnyhFTb0KRjgFY+ynyIFNdoKKAghwgx</c:requestToken></c:replyMessage></soap:Body></soap:Envelope>
    XML
  end
end
