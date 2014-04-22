require 'spec_helper'

ActiveMerchant::Billing::Base.mode = :test

describe Killbill::Cybersource::PaymentPlugin do

  include ::Killbill::Plugin::ActiveMerchant::RSpec

  before(:each) do
    @plugin = Killbill::Cybersource::PaymentPlugin.new

    @account_api    = ::Killbill::Plugin::ActiveMerchant::RSpec::FakeJavaUserAccountApi.new
    svcs            = {:account_user_api => @account_api}
    @plugin.kb_apis = Killbill::Plugin::KillbillApi.new('cybersource', svcs)

    @plugin.logger       = Logger.new(STDOUT)
    @plugin.logger.level = Logger::INFO
    @plugin.conf_dir     = File.expand_path(File.dirname(__FILE__) + '../../../../')
    @plugin.start_plugin
  end

  after(:each) do
    @plugin.stop_plugin
  end

  it 'should be able to charge and refund' do
    pm            = create_payment_method(Killbill::Cybersource::CybersourcePaymentMethod)
    amount        = BigDecimal.new("100")
    currency      = 'USD'
    kb_payment_id = SecureRandom.uuid

    payment_response = @plugin.process_payment pm.kb_account_id, kb_payment_id, pm.kb_payment_method_id, amount, currency, nil
    payment_response.amount.should == amount
    payment_response.status.should == :PROCESSED

    # Try a full refund
    refund_response = @plugin.process_refund pm.kb_account_id, kb_payment_id, amount, currency, nil
    refund_response.amount.should == amount
    refund_response.status.should == :PROCESSED
  end

  it 'should be able to auth, capture and refund' do
    pm            = create_payment_method(Killbill::Cybersource::CybersourcePaymentMethod)
    amount        = BigDecimal.new("100")
    currency      = 'USD'
    kb_payment_id = SecureRandom.uuid

    payment_response = @plugin.authorize_payment pm.kb_account_id, kb_payment_id, pm.kb_payment_method_id, amount, currency, nil
    payment_response.amount.should == amount
    payment_response.status.should == :PROCESSED

    # Try multiple partial captures
    partial_capture_amount = BigDecimal.new("10")
    1.upto(3) do
      payment_response = @plugin.capture_payment pm.kb_account_id, kb_payment_id, pm.kb_payment_method_id, partial_capture_amount, currency, nil
      payment_response.amount.should == partial_capture_amount
      payment_response.status.should == :PROCESSED
    end

    # Try a partial refund
    refund_response = @plugin.process_refund pm.kb_account_id, kb_payment_id, partial_capture_amount, currency, nil
    refund_response.amount.should == partial_capture_amount
    refund_response.status.should == :PROCESSED

    # Try to auth again
    payment_response = @plugin.capture_payment pm.kb_account_id, kb_payment_id, pm.kb_payment_method_id, partial_capture_amount, currency, nil
    payment_response.amount.should == partial_capture_amount
    payment_response.status.should == :PROCESSED
  end

  private
end
