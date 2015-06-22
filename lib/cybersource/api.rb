module Killbill #:nodoc:
  module Cybersource #:nodoc:
    class PaymentPlugin < ::Killbill::Plugin::ActiveMerchant::PaymentPlugin

      def initialize
        gateway_builder = Proc.new do |config|
          ::ActiveMerchant::Billing::CyberSourceGateway.new :login => config[:login], :password => config[:password]
        end

        super(gateway_builder,
              :cybersource,
              ::Killbill::Cybersource::CybersourcePaymentMethod,
              ::Killbill::Cybersource::CybersourceTransaction,
              ::Killbill::Cybersource::CybersourceResponse)
      end

      def on_event(event)
        # Require to deal with per tenant configuration invalidation
        super(event)
        #
        # Custom event logic could be added below...
        #
      end

      def start_plugin
        super
        gateway     = lookup_gateway(:on_demand)
        @report_api = CyberSourceOnDemand.new(gateway, logger)
      rescue => e
        @report_api = nil
      end

      def authorize_payment(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        add_required_options(kb_account_id, properties, options, context)

        properties = merge_properties(properties, options)
        super(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
      end

      def capture_payment(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        add_required_options(kb_account_id, properties, options, context)

        properties = merge_properties(properties, options)
        super(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
      end

      def purchase_payment(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        add_required_options(kb_account_id, properties, options, context)

        properties = merge_properties(properties, options)
        super(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
      end

      def void_payment(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        add_required_options(kb_account_id, properties, options, context)

        properties = merge_properties(properties, options)
        super(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, properties, context)
      end

      def credit_payment(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        add_required_options(kb_account_id, properties, options, context)

        properties = merge_properties(properties, options)
        super(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
      end

      def refund_payment(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        add_required_options(kb_account_id, properties, options, context)

        properties = merge_properties(properties, options)
        super(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
      end

      def get_payment_info(kb_account_id, kb_payment_id, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        properties = merge_properties(properties, options)
        transaction_info_plugins = super(kb_account_id, kb_payment_id, properties, context)

        # Can't do much if the report API isn't configured
        return transaction_info_plugins if @report_api.nil? || Killbill::Plugin::ActiveMerchant::Utils.normalized(properties_to_hash(properties), :skip_gw)
        # Should never happen...
        return [] if transaction_info_plugins.nil?

        # Note: this won't handle the case where we don't have any record in the DB. While this should very rarely happen
        # (see Killbill::Plugin::ActiveMerchant::Gateway), we could use the CyberSource Payment Batch Detail Report to fix it.

        stale = false
        transaction_info_plugins.each do |transaction_info_plugin|
          # We only need to fix the UNKNOWN ones
          next unless transaction_info_plugin.status == :UNKNOWN

          authorization = transaction_info_plugin.properties.find { |pp| pp.key == 'authorization' }
          cybersource_response_id = transaction_info_plugin.properties.find { |pp| pp.key == 'cybersourceResponseId' }
          next if authorization.nil? || cybersource_response_id.nil?

          # Retrieve the report from CyberSource
          order_id, _ = authorization.value.split(';')
          report = get_report(order_id, transaction_info_plugin.created_date, options)
          next if report.nil?

          # Update our rows
          response = CybersourceResponse.find_by(:id => cybersource_response_id.value)
          next if response.nil?

          response.update_and_create_transaction(report.response)
          stale = true
        end

        # If we updated the state, re-fetch the latest data
        stale ? super(kb_account_id, kb_payment_id, properties, context) : transaction_info_plugins
      end

      def search_payments(search_key, offset, limit, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        properties = merge_properties(properties, options)
        super(search_key, offset, limit, properties, context)
      end

      def add_payment_method(kb_account_id, kb_payment_method_id, payment_method_props, set_default, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        properties = merge_properties(properties, options)
        super(kb_account_id, kb_payment_method_id, payment_method_props, set_default, properties, context)
      end

      def delete_payment_method(kb_account_id, kb_payment_method_id, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        properties = merge_properties(properties, options)
        super(kb_account_id, kb_payment_method_id, properties, context)
      end

      def get_payment_method_detail(kb_account_id, kb_payment_method_id, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        properties = merge_properties(properties, options)
        super(kb_account_id, kb_payment_method_id, properties, context)
      end

      def set_default_payment_method(kb_account_id, kb_payment_method_id, properties, context)
        # TODO
      end

      def get_payment_methods(kb_account_id, refresh_from_gateway, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        properties = merge_properties(properties, options)
        super(kb_account_id, refresh_from_gateway, properties, context)
      end

      def search_payment_methods(search_key, offset, limit, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        properties = merge_properties(properties, options)
        super(search_key, offset, limit, properties, context)
      end

      def reset_payment_methods(kb_account_id, payment_methods, properties, context)
        super
      end

      def build_form_descriptor(kb_account_id, descriptor_fields, properties, context)
        # Pass extra parameters for the gateway here
        options = {}
        properties = merge_properties(properties, options)

        # Add your custom static hidden tags here
        options = {
            #:token => config[:cybersource][:token]
        }
        descriptor_fields = merge_properties(descriptor_fields, options)

        super(kb_account_id, descriptor_fields, properties, context)
      end

      def process_notification(notification, properties, context)
        # Pass extra parameters for the gateway here
        options = {}
        properties = merge_properties(properties, options)

        super(notification, properties, context) do |gw_notification, service|
          # Retrieve the payment
          # gw_notification.kb_payment_id =
          #
          # Set the response body
          # gw_notification.entity =
        end
      end

      # Make calls idempotent
      def before_gateway(gateway, kb_transaction, last_transaction, payment_source, amount_in_cents, currency, options)
        super

        merchant_reference_code = options[:order_id]
        report = get_report(merchant_reference_code, kb_transaction.created_date, options)
        return nil if report.nil?

        if report.has_transaction_info?(merchant_reference_code)
          logger.info "Skipping gateway call for existing transaction #{kb_transaction.id}, merchant reference code #{merchant_reference_code}"
          options[:skip_gw] = true
        end
      rescue => e
        logger.warn "Error checking for duplicate payment: #{e.message}"
      end

      def get_report(merchant_reference_code, date, options)
        return nil if @report_api.nil? || options[:skip_gw]
        @report_api.single_transaction_report(merchant_reference_code, date.strftime('%Y%m%d'))
      end

      def add_required_options(kb_account_id, properties, options, context)
        if options[:email].nil?
          email = find_value_from_properties(properties, 'email')
          if email.nil?
            # Note: we need to clone the context otherwise it will be transformed back to a Java one here
            kb_account = @kb_apis.account_user_api.get_account_by_id(kb_account_id, @kb_apis.create_context(context.tenant_id))
            email = kb_account.email
          end
          options[:email] = email
        end
      end
    end
  end
end
