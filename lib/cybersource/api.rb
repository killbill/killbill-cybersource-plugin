module Killbill #:nodoc:
  module Cybersource #:nodoc:
    class PaymentPlugin < ::Killbill::Plugin::ActiveMerchant::PaymentPlugin

      SIXTY_DAYS_AGO = (60 * 86400)

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

      def authorize_payment(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
        # Pass extra parameters for the gateway here
        options = {}

        add_required_options(kb_account_id, properties, options, context)

        properties = merge_properties(properties, options)
        auth_response = super(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)

        # Error 234 is "A problem exists with your CyberSource merchant configuration", most likely the processor used doesn't support $0 auth for this card type
        if auth_response.gateway_error_code == '234' && to_cents(amount, currency) == 0
          h_props = properties_to_hash(properties)
          if ::Killbill::Plugin::ActiveMerchant::Utils.normalized(h_props, :force_validation)
            force_validation_amount = (::Killbill::Plugin::ActiveMerchant::Utils.normalized(h_props, :force_validation_amount) || 1).to_f
            auth_response = force_validation(auth_response, kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, force_validation_amount, currency, properties, context)
          end
        end

        auth_response
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
        if should_credit?(kb_payment_id, context, properties_to_hash(properties))
          # Note: from the plugin perspective, this transaction is a CREDIT but Kill Bill doesn't care about PaymentTransactionInfoPlugin#TransactionType
          return credit_payment(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
        end

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

        # Should never happen...
        return [] if transaction_info_plugins.nil?

        # Note: this won't handle the case where we don't have any record in the DB. While this should very rarely happen
        # (see Killbill::Plugin::ActiveMerchant::Gateway), we could use the CyberSource Payment Batch Detail Report to fix it.

        options = properties_to_hash(properties)

        stale = false
        transaction_info_plugins.each do |transaction_info_plugin|
          # We only need to fix the UNDEFINED ones
          next unless transaction_info_plugin.status == :UNDEFINED

          cybersource_response_id = find_value_from_properties(transaction_info_plugin.properties, 'cybersourceResponseId')
          next if cybersource_response_id.nil?

          report_date = transaction_info_plugin.created_date
          authorization = find_value_from_properties(transaction_info_plugin.properties, 'authorization')

          order_id = Killbill::Plugin::ActiveMerchant::Utils.normalized(options, :order_id)
          # authorization is very likely nil, as we didn't get an answer from the gateway in the first place
          order_id ||= authorization.split(';')[0] unless authorization.nil?

          # Retrieve the report from CyberSource
          if order_id.nil?
            # order_id undetermined - try the defaults (see PaymentPlugin#dispatch_to_gateways)
            report = get_report(transaction_info_plugin.kb_transaction_payment_id, report_date, options, context)
            if report.nil?
              kb_transaction = get_kb_transaction(kb_payment_id, transaction_info_plugin.kb_transaction_payment_id, context.tenant_id)
              report = get_report(kb_transaction.external_key, report_date, options, context)
            end
          else
            report = get_report(order_id, report_date, options, context)
          end

          # Report API not configured or skip_gw=true
          next if report.nil?

          # Report not found
          if report.empty?
            logger.info("Unable to fix UNDEFINED transaction #{transaction_info_plugin.kb_transaction_payment_id} (not found in CyberSource)")
            next
          end

          # Update our rows
          response = CybersourceResponse.find_by(:id => cybersource_response_id)
          next if response.nil?

          logger.info("Fixing UNDEFINED transaction #{transaction_info_plugin.kb_transaction_payment_id}: success? = #{report.response.success?}")

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

      def should_credit?(kb_payment_id, context, options = {})
        # Transform refunds on old payments into credits automatically unless the disable_auto_credit property is passed
        return false if Killbill::Plugin::ActiveMerchant::Utils.normalized(options, :disable_auto_credit)

        transaction = @transaction_model.find_candidate_transaction_for_refund(kb_payment_id, context.tenant_id)
        return false if transaction.nil?

        threshold = (Killbill::Plugin::ActiveMerchant::Utils.normalized(options, :auto_credit_threshold) || SIXTY_DAYS_AGO).to_i

        # we might want a 'util' function to make the conversion joda DateTime to a ruby Time object
        now = Time.parse(@clock.get_clock.get_utc_now.to_s)
        (now - transaction.created_at) >= threshold
      end

      # Make calls idempotent
      def before_gateway(gateway, kb_transaction, last_transaction, payment_source, amount_in_cents, currency, options, context)
        super

        merchant_reference_code = options[:order_id]
        report = get_report_for_kb_transaction(merchant_reference_code, kb_transaction, options, context)
        return nil if report.nil? || report.empty?

        logger.info "Skipping gateway call for existing kb_transaction_id='#{kb_transaction.id}', merchant_reference_code='#{merchant_reference_code}'"
        options[:skip_gw] = true
      rescue => e
        logger.warn "Error checking for duplicate payment for merchant_reference_code='#{merchant_reference_code}': #{e.message}\n#{e.backtrace.join("\n")}"
      end

      # Duplicate check
      def get_report_for_kb_transaction(merchant_reference_code, kb_transaction, options, context)
        report_api = get_report_api(options, context)
        return nil if report_api.nil? || !report_api.check_for_duplicates?
        # kb_transaction is a Utils::LazyEvaluator, delay evaluation as much as possible
        get_single_transaction_report(report_api, merchant_reference_code, kb_transaction.created_date)
      end

      # Janitor path
      def get_report(merchant_reference_code, date, options, context)
        report_api = get_report_api(options, context)
        return nil if report_api.nil?
        get_single_transaction_report(report_api, merchant_reference_code, date)
      end

      def get_single_transaction_report(report_api, merchant_reference_code, date)
        report_api.single_transaction_report(merchant_reference_code, date.strftime('%Y%m%d'))
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

        ::Killbill::Plugin::ActiveMerchant::Utils.normalize_property(properties, 'ignore_avs')
        ::Killbill::Plugin::ActiveMerchant::Utils.normalize_property(properties, 'ignore_cvv')
      end

      def get_report_api(options, context)
        return nil if options[:skip_gw] || options[:bypass_duplicate_check]
        cybersource_config = config(context.tenant_id)[:cybersource]
        return nil unless cybersource_config.is_a?(Array)
        on_demand_config = cybersource_config.find { |c| c[:account_id].to_s == 'on_demand' }
        return nil if on_demand_config.nil?
        CyberSourceOnDemand.new(on_demand_config, logger)
      rescue => e
        @logger.warn("Unexpected exception while looking-up reporting API for kb_tenant_id='#{context.tenant_id}': #{e.message}\n#{e.backtrace.join("\n")}")
        nil
      end

      # TODO: should this eventually be hardened and extracted into the base framework?
      def force_validation(auth_response, kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
        # Trigger a non-$0 auth
        new_auth_response = nil
        begin
          # If duplicate checks are enabled, we need to bypass them (since a transaction for that merchant reference code was already attempted)
          properties << build_property(:bypass_duplicate_check, true)
          new_auth_response = authorize_payment(kb_account_id, kb_payment_id, kb_payment_transaction_id, kb_payment_method_id, amount, currency, properties, context)
        rescue => e
          # Note: state might be broken here (potentially two responses with the same kb_payment_transaction_id)
          @logger.warn("Unexpected exception while forcing validation for kb_payment_id='#{kb_payment_id}', kb_payment_transaction_id='#{kb_payment_transaction_id}': #{e.message}\n#{e.backtrace.join("\n")}")
          return auth_response
        end

        # Void it right away on success (make sure we didn't skip the gateway call too)
        if new_auth_response.status == :PROCESSED && !new_auth_response.first_payment_reference_id.blank?
          # The transaction id here is bogus, since it doesn't exist in Kill Bill
          void_properties = merge_properties(properties, { :external_key_as_order_id => false })
          begin
            void_payment(kb_account_id, kb_payment_id, SecureRandom.uuid, kb_payment_method_id, void_properties, context)
          rescue => e
            @logger.warn("Unexpected exception while voiding forced validation for kb_payment_id='#{kb_payment_id}', kb_payment_transaction_id='#{kb_payment_transaction_id}': #{e.message}\n#{e.backtrace.join("\n")}")
          end
        end

        # Finally, clean up the state of the original (failed) auth
        cybersource_response_id = find_value_from_properties(auth_response.properties, 'cybersourceResponseId')
        if cybersource_response_id.nil?
          @logger.warn "Unable to find cybersourceResponseId matching failed authorization for kb_payment_id='#{kb_payment_id}', kb_payment_transaction_id='#{kb_payment_transaction_id}'"
        else
          response = CybersourceResponse.find_by(:id => cybersource_response_id)
          if response.nil?
            @logger.warn "Unable to find response matching failed authorization for kb_payment_id='#{kb_payment_id}', kb_payment_transaction_id='#{kb_payment_transaction_id}'"
          else
            # Change the kb_payment_transaction_id to avoid confusing Kill Bill (there is no transaction row to update since the call wasn't successful)
            response.update(:kb_payment_transaction_id => SecureRandom.uuid)
          end
        end

        new_auth_response
      end
    end
  end
end
