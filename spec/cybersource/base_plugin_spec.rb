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
      @plugin.should_credit?(kb_payment_id, context, {:auto_credit_threshold => 61 * 86400}).should be_false
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
      purchase
      purchase([build_property('ignore_avs', 'false'), build_property('ignore_cvv', 'false')])
    end

    it 'ignores AVS and CVN' do
      ::ActiveMerchant::Billing::CyberSourceGateway.any_instance.stub(:ssl_post) do |host, request_body|
        request_body.should match('<ignoreAVSResult>')
        request_body.should match('<ignoreCVResult>')
        successful_purchase_response
      end
      purchase([build_property('ignore_avs', 'true'), build_property('ignore_cvv', 'true')])
    end

    it 'ignores AVS but not CVN' do
      ::ActiveMerchant::Billing::CyberSourceGateway.any_instance.stub(:ssl_post) do |host, request_body|
        request_body.should match('<ignoreAVSResult>')
        request_body.should_not match('<ignoreCVResult>')
        successful_purchase_response
      end
      purchase([build_property('ignore_avs', 'true')])
      purchase([build_property('ignore_avs', 'true'), build_property('ignore_cvv', 'false')])
    end

    it 'ignores CVN but not AVS' do
      ::ActiveMerchant::Billing::CyberSourceGateway.any_instance.stub(:ssl_post) do |host, request_body|
        request_body.should_not match('<ignoreAVSResult>')
        request_body.should match('<ignoreCVResult>')
        successful_purchase_response
      end
      purchase([build_property('ignore_cvv', 'true')])
      purchase([build_property('ignore_avs', 'false'), build_property('ignore_cvv', 'true')])
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

  def purchase(properties = [])
    kb_payment_id = SecureRandom.uuid
    kb_payment = @plugin.kb_apis.proxied_services[:payment_api].add_payment(kb_payment_id)
    kb_transaction_id = kb_payment.transactions[0].id

    properties << build_property('email', 'foo@bar.com')
    properties << build_property('token', '1234')

    payment_response = @plugin.purchase_payment(SecureRandom.uuid, kb_payment_id, kb_transaction_id, SecureRandom.uuid, BigDecimal.new('100'), 'USD', properties, build_call_context)
    payment_response.status.should eq(:PROCESSED), payment_response.gateway_error
  end

  def successful_purchase_response
    <<-XML
<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
<soap:Header>
<wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"><wsu:Timestamp xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" wsu:Id="Timestamp-2636690"><wsu:Created>2008-01-15T21:42:03.343Z</wsu:Created></wsu:Timestamp></wsse:Security></soap:Header><soap:Body><c:replyMessage xmlns:c="urn:schemas-cybersource-com:transaction-data-1.26"><c:merchantReferenceCode>b0a6cf9aa07f1a8495f89c364bbd6a9a</c:merchantReferenceCode><c:requestID>2004333231260008401927</c:requestID><c:decision>ACCEPT</c:decision><c:reasonCode>100</c:reasonCode><c:requestToken>Afvvj7Ke2Fmsbq0wHFE2sM6R4GAptYZ0jwPSA+R9PhkyhFTb0KRjoE4+ynthZrG6tMBwjAtT</c:requestToken><c:purchaseTotals><c:currency>USD</c:currency></c:purchaseTotals><c:ccAuthReply><c:reasonCode>100</c:reasonCode><c:amount>1.00</c:amount><c:authorizationCode>123456</c:authorizationCode><c:avsCode>Y</c:avsCode><c:avsCodeRaw>Y</c:avsCodeRaw><c:cvCode>M</c:cvCode><c:cvCodeRaw>M</c:cvCodeRaw><c:authorizedDateTime>2008-01-15T21:42:03Z</c:authorizedDateTime><c:processorResponse>00</c:processorResponse><c:authFactorCode>U</c:authFactorCode></c:ccAuthReply></c:replyMessage></soap:Body></soap:Envelope>
    XML
  end
end
