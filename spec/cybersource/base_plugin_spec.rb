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
end
