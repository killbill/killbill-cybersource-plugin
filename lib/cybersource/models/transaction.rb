module Killbill #:nodoc:
  module Cybersource #:nodoc:
    class CybersourceTransaction < ::Killbill::Plugin::ActiveMerchant::ActiveRecord::Transaction

      self.table_name = 'cybersource_transactions'

      belongs_to :cybersource_response

    end
  end
end
