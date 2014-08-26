require 'spec_helper'

ActiveMerchant::Billing::Base.mode = :test

describe Killbill::Cybersource::PaymentPlugin do

  include ::Killbill::Plugin::ActiveMerchant::RSpec

  before(:each) do
    @plugin = Killbill::Cybersource::PaymentPlugin.new

    @account_api    = ::Killbill::Plugin::ActiveMerchant::RSpec::FakeJavaUserAccountApi.new
    svcs            = {:account_user_api => @account_api}
    @plugin.kb_apis = Killbill::Plugin::KillbillApi.new('cybersource', svcs)

    @call_context           = Killbill::Plugin::Model::CallContext.new
    @call_context.tenant_id = '00000011-0022-0033-0044-000000000055'
    @call_context           = @call_context.to_ruby(@call_context)

    @plugin.logger       = Logger.new(STDOUT)
    @plugin.logger.level = Logger::INFO
    @plugin.conf_dir     = File.expand_path(File.dirname(__FILE__) + '../../../../')
    @plugin.start_plugin
  end

  after(:each) do
    @plugin.stop_plugin
  end

  it 'should be able to charge a Credit Card directly' do
    properties = build_pm_properties
    amount     = BigDecimal.new("100")
    currency   = 'USD'

    payment_response = @plugin.purchase_payment SecureRandom.uuid, SecureRandom.uuid, SecureRandom.uuid, nil, amount, currency, properties, @call_context
    payment_response.amount.should == amount
    payment_response.status.should == :PROCESSED
    payment_response.transaction_type.should == :PURCHASE
  end

  it 'should be able to charge and refund' do
    pm                        = create_payment_method(Killbill::Cybersource::CybersourcePaymentMethod, nil, @call_context.tenant_id)
    amount                    = BigDecimal.new("100")
    currency                  = 'USD'
    kb_payment_id             = SecureRandom.uuid
    kb_payment_transaction_id = SecureRandom.uuid

    payment_response = @plugin.purchase_payment pm.kb_account_id, kb_payment_id, kb_payment_transaction_id, pm.kb_payment_method_id, amount, currency, [], @call_context
    payment_response.amount.should == amount
    payment_response.status.should == :PROCESSED
    payment_response.transaction_type.should == :PURCHASE

    # Try a full refund
    refund_response = @plugin.refund_payment pm.kb_account_id, kb_payment_id, kb_payment_transaction_id, pm.kb_payment_method_id, amount, currency, [], @call_context
    refund_response.amount.should == amount
    refund_response.status.should == :PROCESSED
    refund_response.transaction_type.should == :REFUND
  end

  it 'should be able to auth, capture and refund' do
    pm            = create_payment_method(Killbill::Cybersource::CybersourcePaymentMethod, nil, @call_context.tenant_id)
    amount        = BigDecimal.new("100")
    currency      = 'USD'
    kb_payment_id = SecureRandom.uuid

    payment_response = @plugin.authorize_payment pm.kb_account_id, kb_payment_id, SecureRandom.uuid, pm.kb_payment_method_id, amount, currency, [], @call_context
    payment_response.amount.should == amount
    payment_response.status.should == :PROCESSED
    payment_response.transaction_type.should == :AUTHORIZE

    # Try multiple partial captures
    partial_capture_amount = BigDecimal.new("10")
    1.upto(3) do
      payment_response = @plugin.capture_payment pm.kb_account_id, kb_payment_id, SecureRandom.uuid, pm.kb_payment_method_id, partial_capture_amount, currency, [], @call_context
      payment_response.amount.should == partial_capture_amount
      payment_response.status.should == :PROCESSED
      payment_response.transaction_type.should == :CAPTURE
    end

    # Try a partial refund
    refund_response = @plugin.refund_payment pm.kb_account_id, kb_payment_id, SecureRandom.uuid, pm.kb_payment_method_id, partial_capture_amount, currency, [], @call_context
    refund_response.amount.should == partial_capture_amount
    refund_response.status.should == :PROCESSED
    refund_response.transaction_type.should == :REFUND

    # Try to capture again
    payment_response = @plugin.capture_payment pm.kb_account_id, kb_payment_id, SecureRandom.uuid, pm.kb_payment_method_id, partial_capture_amount, currency, [], @call_context
    payment_response.amount.should == partial_capture_amount
    payment_response.status.should == :PROCESSED
    payment_response.transaction_type.should == :CAPTURE
  end
end
