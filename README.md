killbill-cybersource-plugin
===========================

Plugin to use [CyberSource](http://www.cybersource.com/) as a gateway.

Release builds are available on [Maven Central](http://search.maven.org/#search%7Cga%7C1%7Cg%3A%22org.kill-bill.billing.plugin.ruby%22%20AND%20a%3A%22cybersource-plugin%22) with coordinates `org.kill-bill.billing.plugin.ruby:cybersource-plugin`.

Kill Bill compatibility
-----------------------

| Plugin version | Kill Bill version |
| -------------: | ----------------: |
| 1.x.y          | 0.14.z            |

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

To store a credit card:

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
