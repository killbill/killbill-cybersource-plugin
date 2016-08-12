require 'spec_helper'

ActiveMerchant::Billing::Base.mode = :test

describe Killbill::Cybersource::PaymentPlugin do

  include ::Killbill::Plugin::ActiveMerchant::RSpec

  before(:each) do
    ::Killbill::Cybersource::CybersourcePaymentMethod.delete_all
    ::Killbill::Cybersource::CybersourceResponse.delete_all
    ::Killbill::Cybersource::CybersourceTransaction.delete_all

    @plugin = build_plugin(::Killbill::Cybersource::PaymentPlugin, 'cybersource')
    @plugin.start_plugin

    @call_context = build_call_context

    @properties = []
    @pm         = create_payment_method(::Killbill::Cybersource::CybersourcePaymentMethod, nil, @call_context.tenant_id, @properties)
    @amount     = BigDecimal.new('100')
    @currency   = 'USD'

    @kb_payment = setup_kb_payment(6)
  end

  after(:each) do
    @plugin.stop_plugin
  end

  let(:report_api) do
    @plugin.get_report_api({}, @call_context)
  end

  let(:with_report_api) do
    report_api.present?
  end

  it 'should be able to charge a Credit Card directly and calls should be idempotent' do
    properties = build_pm_properties

    # We created the payment method, hence the rows
    Killbill::Cybersource::CybersourceResponse.all.size.should == 1
    Killbill::Cybersource::CybersourceTransaction.all.size.should == 0

    payment_response = @plugin.purchase_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[0].id, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
    check_response(payment_response, @amount, :PURCHASE, :PROCESSED, 'Successful transaction', '100')
    payment_response.first_payment_reference_id.should_not be_nil
    payment_response.second_payment_reference_id.should_not be_nil

    responses = Killbill::Cybersource::CybersourceResponse.all
    responses.size.should == 2
    responses[0].api_call.should == 'add_payment_method'
    responses[0].message.should == 'Successful transaction'
    responses[1].api_call.should == 'purchase'
    responses[1].message.should == 'Successful transaction'
    transactions = Killbill::Cybersource::CybersourceTransaction.all
    transactions.size.should == 1
    transactions[0].api_call.should == 'purchase'

    # Skip the rest of the test if the report API isn't configured to check for duplicates
    break unless with_report_api && report_api.check_for_duplicates?

    # The report API can be delayed
    await { !@plugin.get_single_transaction_report(report_api, @kb_payment.transactions[0].id, Time.now.utc).empty? }

    payment_response = @plugin.purchase_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[0].id, @pm.kb_payment_method_id, @amount, @currency, @properties, @call_context)
    payment_response.amount.should == @amount
    payment_response.status.should == :PROCESSED
    payment_response.transaction_type.should == :PURCHASE
    # No extra data when handling dups - use the get API to retrieve the details (what Kill Bill does internally too)
    payment_response.first_payment_reference_id.should be_nil
    payment_response.second_payment_reference_id.should be_nil
    payment_response.gateway_error_code.should be_nil

    responses = Killbill::Cybersource::CybersourceResponse.all
    responses.size.should == 3
    responses[0].api_call.should == 'add_payment_method'
    responses[0].message.should == 'Successful transaction'
    responses[1].api_call.should == 'purchase'
    responses[1].message.should == 'Successful transaction'
    responses[2].api_call.should == 'purchase'
    responses[2].message.should == 'Skipped Gateway call'
    transactions = Killbill::Cybersource::CybersourceTransaction.all
    transactions.size.should == 2
    transactions[0].api_call.should == 'purchase'
    transactions[0].txn_id.should_not be_nil
    transactions[1].api_call.should == 'purchase'
    transactions[1].txn_id.should be_nil
  end

  it 'should be able to verify a Credit Card' do
    # Valid card
    properties = build_pm_properties
    kb_payment = setup_kb_payment(2)
    payment_response = @plugin.authorize_payment(@pm.kb_account_id, kb_payment.id, kb_payment.transactions[0].id, @pm.kb_payment_method_id, 0, @currency, properties, @call_context)
    check_response(payment_response, 0, :AUTHORIZE, :PROCESSED, 'Successful transaction', '100')
    payment_response.first_payment_reference_id.should_not be_nil
    payment_response.second_payment_reference_id.should_not be_nil

    # Note that you won't be able to void the $0 auth
    payment_response = @plugin.void_payment(@pm.kb_account_id, kb_payment.id, kb_payment.transactions[1].id, @pm.kb_payment_method_id, @properties, @call_context)
    check_response(payment_response, nil, :VOID, :CANCELED, 'One or more fields contains invalid data', '102')

    # Invalid card
    # See http://www.cybersource.com/developers/getting_started/test_and_manage/simple_order_api/HTML/General_testing_info/soapi_general_test.html
    properties = build_pm_properties(nil, { :cc_exp_year => 1998 })
    kb_payment = setup_kb_payment
    payment_response = @plugin.authorize_payment(@pm.kb_account_id, kb_payment.id, kb_payment.transactions[0].id, @pm.kb_payment_method_id, 0, @currency, properties, @call_context)
    check_response(payment_response, nil, :AUTHORIZE, :ERROR, 'Expired card', '202')
    payment_response.first_payment_reference_id.should_not be_nil
    payment_response.second_payment_reference_id.should be_nil

    # Discover card (doesn't support $0 auth on Paymentech)
    # See http://www.cybersource.com/developers/other_resources/quick_references/test_cc_numbers/
    properties = build_pm_properties(nil, { :cc_number => '6011111111111117', :cc_type => :discover })
    kb_payment = setup_kb_payment
    payment_response = @plugin.authorize_payment(@pm.kb_account_id, kb_payment.id, kb_payment.transactions[0].id, @pm.kb_payment_method_id, 0, @currency, properties, @call_context)
    check_response(payment_response, nil, :AUTHORIZE, :CANCELED, 'A problem exists with your CyberSource merchant configuration', '234')
    payment_response.first_payment_reference_id.should_not be_nil
    payment_response.second_payment_reference_id.should be_nil
    # Verify the GET path
    transaction_info_plugins = @plugin.get_payment_info(@pm.kb_account_id, kb_payment.id, @properties, @call_context)
    transaction_info_plugins.size.should == 1
    transaction_info_plugins.first.transaction_type.should eq(:AUTHORIZE)
    transaction_info_plugins.first.status.should eq(:CANCELED)

    # Force the validation on Discover
    properties << build_property('force_validation', 'true')
    kb_payment = setup_kb_payment
    payment_response = @plugin.authorize_payment(@pm.kb_account_id, kb_payment.id, kb_payment.transactions[0].id, @pm.kb_payment_method_id, 0, @currency, properties, @call_context)
    check_response(payment_response, 1, :AUTHORIZE, :PROCESSED, 'Successful transaction', '100')
    payment_response.first_payment_reference_id.should_not be_nil
    payment_response.second_payment_reference_id.should_not be_nil
    # Verify the GET path
    transaction_info_plugins = @plugin.get_payment_info(@pm.kb_account_id, kb_payment.id, @properties, @call_context)
    transaction_info_plugins.size.should == 3
    transaction_info_plugins[0].transaction_type.should eq(:AUTHORIZE)
    transaction_info_plugins[0].status.should eq(:CANCELED)
    transaction_info_plugins[0].kb_transaction_payment_id.should_not eq(kb_payment.transactions[0].id)
    transaction_info_plugins[1].transaction_type.should eq(:AUTHORIZE)
    transaction_info_plugins[1].status.should eq(:PROCESSED)
    transaction_info_plugins[1].kb_transaction_payment_id.should eq(kb_payment.transactions[0].id)
    transaction_info_plugins[2].transaction_type.should eq(:VOID)
    transaction_info_plugins[2].status.should eq(:PROCESSED)
    transaction_info_plugins[2].kb_transaction_payment_id.should_not eq(kb_payment.transactions[0].id)
  end

  it 'should be able to bypass AVS and CVV rules with Apple Pay' do
    properties = build_pm_properties(nil,
                                     {
                                         :cc_number => 4111111111111111,
                                         :cc_type => 'visa',
                                         :payment_cryptogram => 'EHuWW9PiBkWvqE5juRwDzAUFBAk=',
                                         :ignore_avs => true,
                                         :ignore_cvv => true
                                     })
    kb_payment = setup_kb_payment
    payment_response = @plugin.purchase_payment(@pm.kb_account_id, kb_payment.id, kb_payment.transactions[0].id, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
    check_response(payment_response, @amount, :PURCHASE, :PROCESSED, 'Successful transaction', '100')

    properties = build_pm_properties(nil,
                                     {
                                         :cc_number => 5555555555554444,
                                         :cc_type => 'master',
                                         :payment_cryptogram => 'EHuWW9PiBkWvqE5juRwDzAUFBAk=',
                                         :ignore_avs => true,
                                         :ignore_cvv => true
                                     })
    kb_payment = setup_kb_payment
    payment_response = @plugin.purchase_payment(@pm.kb_account_id, kb_payment.id, kb_payment.transactions[0].id, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
    check_response(payment_response, @amount, :PURCHASE, :PROCESSED, 'Successful transaction', '100')

    properties = build_pm_properties(nil,
                                     {
                                         :cc_number => 378282246310005,
                                         :cc_type => 'american_express',
                                         :payment_cryptogram => 'AAAAAAAAAAAAAAAAAAAAAAAAAAABBBBBBBBBBBBBBBBBBBBBBBBBBB==',
                                         :ignore_avs => true,
                                         :ignore_cvv => true
                                     })
    kb_payment = setup_kb_payment
    payment_response = @plugin.purchase_payment(@pm.kb_account_id, kb_payment.id, kb_payment.transactions[0].id, @pm.kb_payment_method_id, @amount, @currency, properties, @call_context)
    check_response(payment_response, @amount, :PURCHASE, :PROCESSED, 'Successful transaction', '100')
  end

  it 'should be able to fix UNDEFINED payments' do
    payment_response = @plugin.purchase_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[0].id, @pm.kb_payment_method_id, @amount, @currency, @properties, @call_context)
    check_response(payment_response, @amount, :PURCHASE, :PROCESSED, 'Successful transaction', '100')

    # Force a transition to :UNDEFINED
    Killbill::Cybersource::CybersourceTransaction.last.delete
    response = Killbill::Cybersource::CybersourceResponse.last
    response.update(:message => {:payment_plugin_status => 'UNDEFINED'}.to_json)

    skip_gw = Killbill::Plugin::Model::PluginProperty.new
    skip_gw.key = 'skip_gw'
    skip_gw.value = 'true'
    properties_with_skip_gw = @properties.clone
    properties_with_skip_gw << skip_gw

    # Set skip_gw=true, to avoid calling the report API
    transaction_info_plugins = @plugin.get_payment_info(@pm.kb_account_id, @kb_payment.id, properties_with_skip_gw, @call_context)
    transaction_info_plugins.size.should == 1
    transaction_info_plugins.first.status.should eq(:UNDEFINED)

    # Skip if the report API isn't configured
    if with_report_api
      # The report API can be delayed
      await { !@plugin.get_single_transaction_report(report_api, @kb_payment.transactions[0].id, Time.now.utc).empty? }

      # Fix it
      transaction_info_plugins = @plugin.get_payment_info(@pm.kb_account_id, @kb_payment.id, @properties, @call_context)
      transaction_info_plugins.size.should == 1
      transaction_info_plugins.first.status.should eq(:PROCESSED)

      # Set skip_gw=true, to check the local state
      transaction_info_plugins = @plugin.get_payment_info(@pm.kb_account_id, @kb_payment.id, properties_with_skip_gw, @call_context)
      transaction_info_plugins.size.should == 1
      transaction_info_plugins.first.status.should eq(:PROCESSED)
    end

    # Compare the state of the old and new response
    new_response = Killbill::Cybersource::CybersourceResponse.last
    new_response.id.should == response.id
    new_response.api_call.should == 'purchase'
    new_response.kb_tenant_id.should == @call_context.tenant_id
    new_response.kb_account_id.should == @pm.kb_account_id
    new_response.kb_payment_id.should == @kb_payment.id
    new_response.kb_payment_transaction_id.should == @kb_payment.transactions[0].id
    new_response.transaction_type.should == 'PURCHASE'
    new_response.payment_processor_account_id.should == 'default'
    # The report API doesn't give us the token
    new_response.authorization.split(';')[0..1].should == response.authorization.split(';')[0..1]
    new_response.test.should be_true
    new_response.params_merchant_reference_code.should == response.params_merchant_reference_code
    new_response.params_decision.should == response.params_decision
    new_response.params_request_token.should == response.params_request_token
    new_response.params_currency.should == response.params_currency
    new_response.params_amount.should == response.params_amount
    new_response.params_authorization_code.should == response.params_authorization_code
    new_response.params_avs_code.should == response.params_avs_code
    new_response.params_avs_code_raw.should == response.params_avs_code_raw
    new_response.params_reconciliation_id.should == response.params_reconciliation_id
    new_response.success.should be_true
    new_response.message.should == (with_report_api ? 'Request was processed successfully.' : '{"payment_plugin_status":"UNDEFINED"}')
  end

  it 'should eventually cancel UNDEFINED payments' do
    response = Killbill::Cybersource::CybersourceResponse.create(:api_call => 'authorization',
                                                                 :kb_account_id => @pm.kb_account_id,
                                                                 :kb_payment_id => @kb_payment.id,
                                                                 :kb_payment_transaction_id => @kb_payment.transactions[0].id,
                                                                 :kb_tenant_id => @call_context.tenant_id,
                                                                 :message => '{"exception_message":"Timeout","payment_plugin_status":"UNDEFINED"}',
                                                                 :created_at => Time.now,
                                                                 :updated_at => Time.now)

    # Set skip_gw=true, to avoid calling the report API
    skip_gw = Killbill::Plugin::Model::PluginProperty.new
    skip_gw.key = 'skip_gw'
    skip_gw.value = 'true'
    properties_with_cancel_threshold = @properties.clone
    properties_with_cancel_threshold << skip_gw
    transaction_info_plugins = @plugin.get_payment_info(@pm.kb_account_id, @kb_payment.id, properties_with_cancel_threshold, @call_context)
    transaction_info_plugins.size.should == 1
    transaction_info_plugins.first.status.should eq(:UNDEFINED)

    # Call the reporting API (if configured) and verify the state still cannot be fixed
    transaction_info_plugins = @plugin.get_payment_info(@pm.kb_account_id, @kb_payment.id, @properties, @call_context)
    transaction_info_plugins.size.should == 1
    transaction_info_plugins.first.status.should eq(:UNDEFINED)

    # Transition to CANCEL won't work if the reporting API isn't configured
    break unless with_report_api

    # Force a transition to CANCEL
    cancel_threshold = Killbill::Plugin::Model::PluginProperty.new
    cancel_threshold.key = 'cancel_threshold'
    cancel_threshold.value = '0'
    properties_with_cancel_threshold = @properties.clone
    properties_with_cancel_threshold << cancel_threshold
    transaction_info_plugins = @plugin.get_payment_info(@pm.kb_account_id, @kb_payment.id, properties_with_cancel_threshold, @call_context)
    transaction_info_plugins.size.should == 1
    transaction_info_plugins.first.status.should eq(:CANCELED)

    # Verify the state is sticky
    transaction_info_plugins = @plugin.get_payment_info(@pm.kb_account_id, @kb_payment.id, @properties, @call_context)
    transaction_info_plugins.size.should == 1
    transaction_info_plugins.first.status.should eq(:CANCELED)
  end

  it 'should be able to charge and refund' do
    payment_response = @plugin.purchase_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[0].id, @pm.kb_payment_method_id, @amount, @currency, @properties, @call_context)
    check_response(payment_response, @amount, :PURCHASE, :PROCESSED, 'Successful transaction', '100')

    # Try a full refund
    refund_response = @plugin.refund_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[1].id, @pm.kb_payment_method_id, @amount, @currency, @properties, @call_context)
    check_response(refund_response, @amount, :REFUND, :PROCESSED, 'Successful transaction', '100')
  end

  it 'should be able to auth, capture and refund' do
    payment_response = @plugin.authorize_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[0].id, @pm.kb_payment_method_id, @amount, @currency, @properties, @call_context)
    check_response(payment_response, @amount, :AUTHORIZE, :PROCESSED, 'Successful transaction', '100')

    # Try multiple partial captures
    partial_capture_amount = BigDecimal.new('10')
    1.upto(3) do |i|
      payment_response = @plugin.capture_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[i].id, @pm.kb_payment_method_id, partial_capture_amount, @currency, @properties, @call_context)
      check_response(payment_response, partial_capture_amount, :CAPTURE, :PROCESSED, 'Successful transaction', '100')
    end

    # Try a partial refund
    refund_response = @plugin.refund_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[4].id, @pm.kb_payment_method_id, partial_capture_amount, @currency, @properties, @call_context)
    check_response(refund_response, partial_capture_amount, :REFUND, :PROCESSED, 'Successful transaction', '100')

    # Try to capture again
    payment_response = @plugin.capture_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[5].id, @pm.kb_payment_method_id, partial_capture_amount, @currency, @properties, @call_context)
    check_response(payment_response, partial_capture_amount, :CAPTURE, :PROCESSED, 'Successful transaction', '100')
  end

  it 'should be able to auth and void' do
    payment_response = @plugin.authorize_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[0].id, @pm.kb_payment_method_id, @amount, @currency, @properties, @call_context)
    check_response(payment_response, @amount, :AUTHORIZE, :PROCESSED, 'Successful transaction', '100')

    payment_response = @plugin.void_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[1].id, @pm.kb_payment_method_id, @properties, @call_context)
    check_response(payment_response, nil, :VOID, :PROCESSED, 'Successful transaction', '100')
  end

  it 'should be able to auth and void in CAD', :ci_skip => true do
    payment_response = @plugin.authorize_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[0].id, @pm.kb_payment_method_id, @amount, 'CAD', @properties, @call_context)
    check_response(payment_response, @amount, :AUTHORIZE, :PROCESSED, 'Successful transaction', '100')

    payment_response = @plugin.void_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[1].id, @pm.kb_payment_method_id, @properties, @call_context)
    check_response(payment_response, nil, :VOID, :PROCESSED, 'Successful transaction', '100')
  end

  it 'should be able to auth, partial capture and void' do
    payment_response = @plugin.authorize_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[0].id, @pm.kb_payment_method_id, @amount, @currency, @properties, @call_context)
    check_response(payment_response, @amount, :AUTHORIZE, :PROCESSED, 'Successful transaction', '100')

    partial_capture_amount = BigDecimal.new('10')
    payment_response       = @plugin.capture_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[1].id, @pm.kb_payment_method_id, partial_capture_amount, @currency, @properties, @call_context)
    check_response(payment_response, partial_capture_amount, :CAPTURE, :PROCESSED, 'Successful transaction', '100')

    payment_response = @plugin.void_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[2].id, @pm.kb_payment_method_id, @properties, @call_context)
    check_response(payment_response, nil, :VOID, :PROCESSED, 'Successful transaction', '100')
    Killbill::Cybersource::CybersourceResponse.last.params_amount.should == '10.00'

    # From the CyberSource documentation:
    # When you void a capture, a hold remains on the unused credit card funds. If you are not going to re-capture the authorization as described in "Capture After Void," page 71, and if
    # your processor supports authorization reversal after void as described in "Authorization Reversal After Void," page 39, CyberSource recommends that you request an authorization reversal
    # to release the hold on the unused credit card funds.
    payment_response = @plugin.void_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[3].id, @pm.kb_payment_method_id, @properties, @call_context)
    check_response(payment_response, nil, :VOID, :PROCESSED, 'Successful transaction', '100')
    Killbill::Cybersource::CybersourceResponse.last.params_amount.should == '100.00'
  end

  it 'should be able to credit' do
    payment_response = @plugin.credit_payment(@pm.kb_account_id, @kb_payment.id, @kb_payment.transactions[0].id, @pm.kb_payment_method_id, @amount, @currency, @properties, @call_context)
    check_response(payment_response, @amount, :CREDIT, :PROCESSED, 'Successful transaction', '100')
  end

  # See https://github.com/killbill/killbill-cybersource-plugin/issues/4
  it 'handles 500 errors gracefully' do
    properties_with_no_expiration_year = build_pm_properties
    cc_exp_year = properties_with_no_expiration_year.find { |prop| prop.key == 'ccExpirationYear' }
    cc_exp_year.value = nil

    kb_payment = setup_kb_payment
    payment_response = @plugin.purchase_payment(@pm.kb_account_id, kb_payment.id, kb_payment.transactions[0].id, SecureRandom.uuid, @amount, @currency, properties_with_no_expiration_year, @call_context)
    check_response(payment_response, nil, :PURCHASE, :CANCELED, '{"exception_message":"soap:Client: \\nXML parse error.\\n","payment_plugin_status":"CANCELED"}', nil)
  end

  # See http://www.cybersource.com/developers/getting_started/test_and_manage/simple_order_api/HTML/General_testing_info/soapi_general_test.html
  it 'sets the correct transaction status' do
    properties = build_pm_properties

    kb_payment = setup_kb_payment
    payment_response = @plugin.purchase_payment(@pm.kb_account_id, kb_payment.id, kb_payment.transactions[0].id, SecureRandom.uuid, -1, @currency, properties, @call_context)
    check_response(payment_response, nil, :PURCHASE, :CANCELED, 'One or more fields contains invalid data', '102')

    kb_payment = setup_kb_payment
    payment_response = @plugin.purchase_payment(@pm.kb_account_id, kb_payment.id, kb_payment.transactions[0].id, SecureRandom.uuid, 100000000000, @currency, properties, @call_context)
    check_response(payment_response, nil, :PURCHASE, :CANCELED, 'One or more fields contains invalid data', '102')

    kb_payment = setup_kb_payment
    bogus_properties = build_pm_properties(nil, {:cc_number => '4111111111111112'})
    payment_response = @plugin.purchase_payment(@pm.kb_account_id, kb_payment.id, kb_payment.transactions[0].id, SecureRandom.uuid, @amount, @currency, bogus_properties, @call_context)
    check_response(payment_response, nil, :PURCHASE, :ERROR, 'Invalid account number', '231')

    kb_payment = setup_kb_payment
    bogus_properties = build_pm_properties(nil, {:cc_number => '412345678912345678914'})
    payment_response = @plugin.purchase_payment(@pm.kb_account_id, kb_payment.id, kb_payment.transactions[0].id, SecureRandom.uuid, @amount, @currency, bogus_properties, @call_context)
    check_response(payment_response, nil, :PURCHASE, :ERROR, 'Invalid account number', '231')

    kb_payment = setup_kb_payment
    bogus_properties = build_pm_properties(nil, {:cc_exp_month => '13'})
    payment_response = @plugin.purchase_payment(@pm.kb_account_id, kb_payment.id, kb_payment.transactions[0].id, SecureRandom.uuid, @amount, @currency, bogus_properties, @call_context)
    check_response(payment_response, nil, :PURCHASE, :CANCELED, 'One or more fields contains invalid data', '102')
  end

  context 'Processors' do

    # See http://www.cybersource.com/developers/getting_started/test_and_manage/simple_order_api/HTML/Paymentech/soapi_ptech_err.html
    it 'handles Chase Paymentech Solutions errors' do
      properties = build_pm_properties

      %w(000 236 248 265 266 267 301 519 769 902 905 906).each do |expected_processor_response|
        kb_payment = setup_kb_payment
        amount = 2000 + expected_processor_response.to_i
        payment_response = @plugin.purchase_payment(@pm.kb_account_id, kb_payment.id, kb_payment.transactions[0].id, SecureRandom.uuid, amount, @currency, properties, @call_context)
        check_response(payment_response, nil, :PURCHASE, :CANCELED, 'General failure', '150', expected_processor_response)
      end

      %w(239 241 249 833).each do |expected_processor_response|
        kb_payment = setup_kb_payment
        amount = 2000 + expected_processor_response.to_i
        payment_response = @plugin.purchase_payment(@pm.kb_account_id, kb_payment.id, kb_payment.transactions[0].id, SecureRandom.uuid, amount, @currency, properties, @call_context)
        check_response(payment_response, nil, :PURCHASE, :CANCELED, 'A problem exists with your CyberSource merchant configuration', '234', expected_processor_response)
      end

      {'201' => '231',
       '202' => '233',
       '203' => '233',
       # Disable most of the checks by default (test lasts for 7 minutes otherwise)
=begin
       '204' => '233',
       '205' => '233',
       '218' => '233',
       '219' => '233',
       '220' => '233',
       '225' => '233',
       '227' => '233',
       '231' => '233',
       '233' => '233',
       '234' => '233',
       '238' => '233',
       '243' => '233',
       '244' => '233',
       '245' => '233',
       '246' => '233',
       '247' => '233',
       '253' => '233',
       '257' => '233',
       '258' => '233',
       '261' => '233',
       '263' => '233',
       '264' => '233',
       '268' => '233',
       '269' => '203',
       '270' => '203',
       '271' => '203',
       '273' => '203',
       '275' => '203',
       '302' => '210',
       '303' => '203',
       '304' => '231',
       '401' => '201',
       '402' => '201',
       '501' => '205',
       '502' => '205',
       '503' => '209',
       '505' => '203',
       '508' => '203',
       '509' => '204',
       '510' => '203',
       '521' => '204',
       '522' => '202',
       '523' => '233',
       '524' => '211',
       '530' => '203',
       '531' => '211',
       '540' => '203',
       '541' => '205',
       '542' => '203',
       '543' => '203',
       '544' => '203',
       '545' => '203',
       '546' => '203',
       '547' => '233',
       '548' => '233',
       '549' => '203',
       '550' => '203',
       '551' => '233',
       '560' => '203',
       '561' => '203',
       '562' => '203',
       '563' => '203',
       '564' => '203',
       '567' => '203',
       '570' => '203',
       '571' => '203',
       '572' => '203',
       '591' => '231',
       '592' => '203',
       '594' => '203',
       '595' => '208',
       '596' => '205',
       '597' => '233',
       '602' => '233',
       '603' => '233',
       '605' => '233',
       '606' => '208',
       '607' => '233',
       '610' => '231',
       '617' => '203',
       '719' => '203',
       '740' => '233',
       '741' => '233',
       '742' => '233',
       '747' => '233',
       '750' => '233',
       '751' => '233',
       '752' => '233',
       '753' => '233',
       '754' => '233',
       '755' => '233',
       '756' => '233',
       '757' => '233',
       '758' => '233',
       '759' => '233',
       '760' => '233',
       '763' => '233',
       '764' => '233',
       '765' => '233',
       '766' => '233',
       '767' => '233',
       '768' => '233',
       '802' => '203',
       '806' => '203',
=end
       '811' => '209',
       '813' => '203',
       '825' => '231',
       '834' => '203',
       '903' => '203',
       '904' => '203'}.each do |expected_processor_response, expected_reason_code|
        kb_payment = setup_kb_payment
        amount = 2000 + expected_processor_response.to_i
        payment_response = @plugin.purchase_payment(@pm.kb_account_id, kb_payment.id, kb_payment.transactions[0].id, SecureRandom.uuid, amount, @currency, properties, @call_context)
        expected_error = ::ActiveMerchant::Billing::CyberSourceGateway.class_variable_get(:@@response_codes)[('r' + expected_reason_code).to_sym]
        check_response(payment_response, nil, :PURCHASE, :ERROR, expected_error, expected_reason_code, expected_processor_response)
      end
    end
  end

  shared_examples 'success_auth_capture_and_refund' do
    it 'should be able to auth, capture and refund with descriptors' do
      @pm = create_payment_method(::Killbill::Cybersource::CybersourcePaymentMethod, nil, @call_context.tenant_id, @properties)

      payment_response = @plugin.authorize_payment(@pm.kb_account_id, payment_id, SecureRandom.uuid, @pm.kb_payment_method_id, @amount, @currency, @properties, @call_context)
      check_response(payment_response, @amount, :AUTHORIZE, :PROCESSED, 'Successful transaction', '100')

      # Try a capture
      payment_response = @plugin.capture_payment(@pm.kb_account_id, payment_id, SecureRandom.uuid, @pm.kb_payment_method_id, @amount, @currency, @properties, @call_context)
      check_response(payment_response, @amount, :CAPTURE, :PROCESSED, 'Successful transaction', '100')

      # Try a refund
      refund_response = @plugin.refund_payment(@pm.kb_account_id, payment_id, SecureRandom.uuid, @pm.kb_payment_method_id, @amount, @currency, @properties, @call_context)
      check_response(refund_response, @amount, :REFUND, :PROCESSED, 'Successful transaction', '100')
    end
  end

  describe 'with merchant descriptor' do
    before do
      @properties << build_property('merchant_descriptor', {"name"=>"Ray Qiu", "contact"=>"6508883161"}.to_json)
    end
    let(:payment_id){ SecureRandom.uuid }

    context 'using cybersource token' do
      it_behaves_like 'success_auth_capture_and_refund'
    end

    context 'using credit card' do
      before do
        @properties << build_property('email', 'foo@bar.com')
        @properties << build_property('cc_number', '4111111111111111')
      end
      it_behaves_like 'success_auth_capture_and_refund'
    end
  end

  private

  def check_response(payment_response, amount, transaction_type, expected_status, expected_error, expected_error_code, expected_processor_response = nil)
    payment_response.amount.should == amount
    payment_response.transaction_type.should == transaction_type
    payment_response.status.should eq(expected_status), payment_response.gateway_error

    gw_response = Killbill::Cybersource::CybersourceResponse.last
    gw_response.gateway_error.should == expected_error
    gw_response.gateway_error_code.should == expected_error_code
    gw_response.params_processor_response.should == expected_processor_response unless expected_processor_response.nil?
  end

  def setup_kb_payment(nb_transactions=1, kb_payment_id=SecureRandom.uuid)
    kb_payment = nil
    1.upto(nb_transactions) do
      kb_payment = @plugin.kb_apis.proxied_services[:payment_api].add_payment(kb_payment_id)
    end
    kb_payment
  end

  def await(timeout=15)
    timeout.times do
      return if block_given? && yield
      sleep(1)
    end
    fail('Timeout')
  end
end
