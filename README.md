killbill-cybersource-plugin
===========================

Plugin to use [CyberSource](http://www.cybersource.com/) as a gateway.

Release builds are available on [Maven Central](http://search.maven.org/#search%7Cga%7C1%7Cg%3A%22org.kill-bill.billing.plugin.ruby%22%20AND%20a%3A%22cybersource-plugin%22) with coordinates `org.kill-bill.billing.plugin.ruby:cybersource-plugin`.

Kill Bill compatibility
-----------------------

| Plugin version | Kill Bill version |
| -------------: | ----------------: |
| 1.x.y          | 0.14.z            |
| 3.x.y          | 0.15.z            |
| 4.x.y          | 0.16.z            |

Requirements
------------

The plugin needs a database. The latest version of the schema can be found [here](https://github.com/killbill/killbill-cybersource-plugin/blob/master/db/ddl.sql).

Configuration
-------------

```
curl -v \
     -X POST \
     -u admin:password \
     -H 'X-Killbill-ApiKey: bob' \
     -H 'X-Killbill-ApiSecret: lazar' \
     -H 'X-Killbill-CreatedBy: admin' \
     -H 'Content-Type: text/plain' \
     -d ':cybersource:
  - :account_id: "merchant_account_1"
    :login: "your-login"
    :password: "your-password"
  - :account_id: "merchant_account_2"
    :login: "your-login"
    :password: "your-password"' \
     http://127.0.0.1:8080/1.0/kb/tenants/uploadPluginConfig/killbill-cybersource
```

To go to production, create a `cybersource.yml` configuration file under `/var/tmp/bundles/plugins/ruby/killbill-cybersource/x.y.z/` containing the following:

```
:cybersource:
  :test: false
```

Usage
-----

To store a credit card (note that CyberSource requires a full billing address, hence the various fields below):

```
curl -v \
     -X POST \
     -u admin:password \
     -H 'X-Killbill-ApiKey: bob' \
     -H 'X-Killbill-ApiSecret: lazar' \
     -H 'X-Killbill-CreatedBy: admin' \
     -H 'Content-Type: application/json' \
     -d '{
       "pluginName": "killbill-cybersource",
       "pluginInfo": {
         "properties": [
           {
             "key": "ccFirstName",
             "value": "John"
           },
           {
             "key": "ccLastName",
             "value": "Doe"
           },
           {
             "key": "address1",
             "value": "5th Street"
           },
           {
             "key": "city",
             "value": "San Francisco"
           },
           {
             "key": "zip",
             "value": "94111"
           },
           {
             "key": "state",
             "value": "CA"
           },
           {
             "key": "country",
             "value": "USA"
           },
           {
             "key": "ccExpirationMonth",
             "value": 12
           },
           {
             "key": "ccExpirationYear",
             "value": 2017
           },
           {
             "key": "ccNumber",
             "value": "4111111111111111"
           }
         ]
       }
     }' \
     "http://127.0.0.1:8080/1.0/kb/accounts/2a55045a-ce1d-4344-942d-b825536328f9/paymentMethods?isDefault=true&pluginProperty=skip_gw=true"
```

CyberSource also requires an email address during the payment call. The plugin will pull the one from the Kill Bill account. Alternatively, you can pass it as a plugin property:

```
curl -v \
     -X POST \
     -u admin:password \
     -H 'X-Killbill-ApiKey: bob' \
     -H 'X-Killbill-ApiSecret: lazar' \
     -H 'X-Killbill-CreatedBy: admin' \
     -H 'Content-Type: application/json' \
     -d '{
       "transactionType": "AUTHORIZE",
       "amount": 5
     }' \
     http://127.0.0.1:8080/1.0/kb/accounts/2a55045a-ce1d-4344-942d-b825536328f9/payments?pluginProperty=email=john@doe.com
```

Plugin properties
-----------------

| Key                          | Description                                                             |
| ---------------------------: | ------------------------------------------------------------------------|
| skip_gw                      | If true, skip the call to CyberSource                                   |
| payment_processor_account_id | Config entry name of the merchant account to use                        |
| external_key_as_order_id     | If true, set the payment external key as the CyberSource order id       |
| ignore_avs                   | If true, ignore the results of AVS checking                             |
| ignore_cvv                   | If true, ignore the results of CVN checking                             |
| cc_first_name                | Credit card holder first name                                           |
| cc_last_name                 | Credit card holder last name                                            |
| cc_type                      | Credit card brand                                                       |
| cc_expiration_month          | Credit card expiration month                                            |
| cc_expiration_year           | Credit card expiration year                                             |
| cc_verification_value        | CVC/CVV/CVN                                                             |
| email                        | Purchaser email                                                         |
| address1                     | Billing address first line                                              |
| address2                     | Billing address second line                                             |
| city                         | Billing address city                                                    |
| zip                          | Billing address zip code                                                |
| state                        | Billing address state                                                   |
| country                      | Billing address country                                                 |
| commerce_indicator           | Override the commerce indicator field                                   |
| eci                          | Network tokenization attribute                                          |
| payment_cryptogram           | Network tokenization attribute                                          |
| transaction_id               | Network tokenization attribute                                          |
| payment_instrument_name      | ApplePay tokenization attribute                                         |
| payment_network              | ApplePay tokenization attribute                                         |
| transaction_identifier       | ApplePay tokenization attribute                                         |
| force_validation             | If true, trigger a non-$0 auth to validate cards not supporting $0 auth |
| force_validation_amount      | Amount to use when force_validation is set                              |
| merchant_descriptor          | Merchant descriptor as `{"name":"Merchant Name","contact":"8888888888"}`|
