require 'spec_helper'

describe Killbill::Cybersource::CyberSourceOnDemand do

  it 'parses a transaction detail report with a single ApplicationReply correctly' do
    xml_report = <<eos
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE Report SYSTEM "https://ebctest.cybersource.com/ebctest/reports/dtd/tdr_1_3.dtd">
<Report xmlns="https://ebctest.cybersource.com/ebctest/reports/dtd/tdr_1_3.dtd"
        Name="Transaction Detail"
        Version="1.3"
        MerchantID="testMerchant"
        ReportStartDate="2008-09-10 21:46:41.765-08:00"
        ReportEndDate="2008-09-10 21:46:41.765-08:00">
  <Requests>
    <Request MerchantReferenceNumber="33038191"
             RequestDate="2008-09-10T14:00:08-08:00"
             RequestID="2210804330010167904567"
             SubscriptionID=""
             Source="SCMP API"
             User="merchant123"
             TransactionReferenceNumber="0001094522"
             PredecessorRequestID="7904567221330010160804">
      <BillTo>
        <FirstName>JANE</FirstName>
        <LastName>Smith</LastName>
        <Address1>1295 Charleston Rd</Address1>
        <Address2>Suite 2</Address2>
        <City>Mountain View</City>
        <State>CA</State>
        <Zip>06513</Zip>
        <Email>null@cybersource.com</Email>
        <Country>US</Country>
      </BillTo>
      <ShipTo>
        <FirstName>JANE</FirstName>
        <LastName>SMITH</LastName>
        <Address1>1295 Charleston Rd</Address1>
        <Address2>Suite 2</Address2>
        <City>Mountain View</City>
        <State>CA</State>
        <Zip>94043</Zip>
        <Country>US</Country>
      </ShipTo>
      <PaymentMethod>
        <Card>
          <AccountSuffix>1111</AccountSuffix>
          <ExpirationMonth>11</ExpirationMonth>
          <ExpirationYear>2011</ExpirationYear>
          <CardType>Visa</CardType>
        </Card>
      </PaymentMethod>
      <LineItems>
        <LineItem Number="0">
          <FulfillmentType/>
          <Quantity>1</Quantity>
          <UnitPrice>1.56</UnitPrice>
          <TaxAmount>0.25</TaxAmount>
          <MerchantProductSKU>testdl</MerchantProductSKU>
          <ProductName>PName1</ProductName>
          <ProductCode>electronic_software</ProductCode>
        </LineItem>
      </LineItems>
      <ApplicationReplies>
        <ApplicationReply Name="ics_bill">
          <RCode>1</RCode>
          <RFlag>SOK</RFlag>
          <RMsg>Request was processed successfully.</RMsg>
        </ApplicationReply>
      </ApplicationReplies>
      <PaymentData>
        <PaymentProcessor>vital</PaymentProcessor>
        <Amount>1.81</Amount>
        <CurrencyCode>eur</CurrencyCode>
        <TotalTaxAmount>0.25</TotalTaxAmount>
        <EventType>TRANSMITTED</EventType>
      </PaymentData>
    </Request>
  </Requests>
</Report>
eos
    report = Killbill::Cybersource::CyberSourceOnDemand::CyberSourceOnDemandTransactionReport.new(xml_report, Logger.new(STDOUT))
    response = report.response
    response.success?.should be_true
    response.message.should == 'Request was processed successfully.'
    response.params['merchantReferenceCode'].should == '33038191'
    response.params['requestID'].should == '2210804330010167904567'
    response.params['decision'].should be_nil
    response.params['reasonCode'].should be_nil
    response.params['requestToken'].should be_nil
    response.params['currency'].should == 'eur'
    response.params['amount'].should == '1.81'
    response.params['authorizationCode'].should be_nil
    response.params['avsCode'].should be_nil
    response.params['avsCodeRaw'].should be_nil
    response.params['cvCode'].should be_nil
    response.params['authorizedDateTime'].should be_nil
    response.params['processorResponse'].should be_nil
    response.params['reconciliationID'].should == '0001094522'
    response.params['subscriptionID'].should == ''
  end

  it 'parses a transaction detail report with multiple ApplicationReplies correctly' do
    xml_report = <<eos
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE Report SYSTEM "https://ebctest.cybersource.com/ebctest/reports/dtd/tdr_1_6.dtd">
<Report xmlns="https://ebctest.cybersource.com/ebctest/reports/dtd/tdr_1_6.dtd"
        Name="Transaction Detail"
        Version="1.6"
        MerchantID="ok_go"
        ReportStartDate="2009-05-26T18:30:00-08:00"
        ReportEndDate="2009-05-27T18:30:00-08:00">
  <Requests>
    <Request RequestID="2434465504100167904567"
             RequestDate="2009-05-27T17:49:10+05:30"
             MerchantReferenceNumber="1234"
             Source="SCMP API"
             User=""
             SubscriptionID=""
             TransactionReferenceNumber="00013791KV8BZF3P">
      <BillTo>
        <FirstName>sample</FirstName>
        <LastName>merchant</LastName>
        <Address1>11 Lico Ave</Address1>
        <City>Big City</City>
        <State>CA</State>
        <Zip>99999</Zip>
        <Email>smerchant@example.com</Email>
        <Country>US</Country>
        <Phone/>
      </BillTo>
      <ShipTo>
        <City>xyz</City>
        <Zip>95117</Zip>
      </ShipTo>
      <PaymentMethod>
        <Card>
          <AccountSuffix>7392</AccountSuffix>
          <ExpirationMonth>12</ExpirationMonth>
          <ExpirationYear>2009</ExpirationYear>
          <CardType>Visa</CardType>
        </Card>
      </PaymentMethod>
      <LineItems>
        <LineItem Number="0">
          <FulfillmentType>P</FulfillmentType>
          <Quantity>1</Quantity>
          <UnitPrice>2.00</UnitPrice>
          <TaxAmount>0.00</TaxAmount>
          <ProductCode>default</ProductCode>
        </LineItem>
      </LineItems>
      <ApplicationReplies>
        <ApplicationReply Name="ics_auth">
          <RCode>1</RCode>
          <RFlag>SOK</RFlag>
          <RMsg>Request was processed successfully.</RMsg>
        </ApplicationReply>
        <ApplicationReply Name="ics_decision">
          <RCode>0</RCode>
          <RFlag>DREVIEW</RFlag>
          <RMsg>Decision is REVIEW.</RMsg>
        </ApplicationReply>
        <ApplicationReply Name="ics_decision_early">
          <RCode>1</RCode>
          <RFlag/>
        </ApplicationReply>
        <ApplicationReply Name="ics_score">
          <RCode>1</RCode>
          <RFlag>DSCORE</RFlag>
          <RMsg>Score exceeds threshold. Score = 84</RMsg>
        </ApplicationReply>
      </ApplicationReplies>
      <PaymentData>
        <PaymentRequestID>2434465504100167904567</PaymentRequestID>
        <PaymentProcessor>smartpay</PaymentProcessor>
        <Amount>2.00</Amount>
        <CurrencyCode>USD</CurrencyCode>
        <TotalTaxAmount>0.00</TotalTaxAmount>
        <AuthorizationType>O</AuthorizationType>
        <AuthorizationCode>888888</AuthorizationCode>
        <AVSResult>I1</AVSResult>
        <AVSResultMapped>X</AVSResultMapped>
        <GrandTotal>2.00</GrandTotal>
        <ACHVerificationResult>100</ACHVerificationResult>
      </PaymentData>
      <MerchantDefinedData>
        <field1 name="mdd1">ca</field1>
      </MerchantDefinedData>
      <RiskData>
        <Factors>C,Y,Z</Factors>
        <HostSeverity>1</HostSeverity>
        <Score>84</Score>
        <TimeLocal>2009-05-27T10:49:10</TimeLocal>
        <AppliedThreshold>20</AppliedThreshold>
        <AppliedTimeHedge>normal</AppliedTimeHedge>
        <AppliedVelocityHedge>high</AppliedVelocityHedge>
        <AppliedHostHedge>normal</AppliedHostHedge>
        <AppliedCategoryGift>n</AppliedCategoryGift>
        <AppliedCategoryTime/>
        <AppliedAVS>X</AppliedAVS>
        <BinAccountType>CN</BinAccountType>
        <BinScheme>Visa Credit</BinScheme>
        <BinIssuer>Sample issuer</BinIssuer>
        <BinCountry>us</BinCountry>
        <InfoCodes>
          <InfoCode>
            <CodeType>address</CodeType>
            <CodeValue>MM-C,MM-Z</CodeValue>
          </InfoCode>
          <InfoCode>
            <CodeType>velocity</CodeType>
            <CodeValue>VEL-CC</CodeValue>
          </InfoCode>
        </InfoCodes>
      </RiskData>
      <ProfileList>
        <Profile Name="Default Profile">
          <ProfileMode>Active</ProfileMode>
          <ProfileDecision>ACCEPT</ProfileDecision>
          <RuleList>
            <Rule>
              <RuleName>sample rule name</RuleName>
              <RuleDecision>IGNORE</RuleDecision>
            </Rule>
          </RuleList>
        </Profile>
      </ProfileList>
      <TravelData>
        <TripInfo>
          <CompleteRoute>AB-CD:EF-GH</CompleteRoute>
          <JourneyType>round trip</JourneyType>
          <DepartureDateTime>sample date &amp; time</DepartureDateTime>
        </TripInfo>
        <PassengerInfo>
          <Passenger Number="0">
            <PassengerFirstName>jane</PassengerFirstName>
            <PassengerLastName>doe</PassengerLastName>
            <PassengerID>Sing-001</PassengerID>
          </Passenger>
          <Passenger Number="1">
            <PassengerFirstName>john</PassengerFirstName>
            <PassengerLastName>doe</PassengerLastName>
            <PassengerID>sing-002</PassengerID>
            <PassengerStatus>Adult</PassengerStatus>
            <PassengerType>Gold</PassengerType>
            <PassengerPhone>9995551212</PassengerPhone>
            <PassengerEmail>jdoe@example.com</PassengerEmail>
          </Passenger>
        </PassengerInfo>
      </TravelData>
    </Request>
  </Requests>
</Report>
eos
    report = Killbill::Cybersource::CyberSourceOnDemand::CyberSourceOnDemandTransactionReport.new(xml_report, Logger.new(STDOUT))
    response = report.response
    response.success?.should be_false
    response.message.should == 'Score exceeds threshold. Score = 84'
    response.params['merchantReferenceCode'].should == '1234'
    response.params['requestID'].should == '2434465504100167904567'
    response.params['decision'].should == 'ACCEPT'
    response.params['reasonCode'].should be_nil
    response.params['requestToken'].should be_nil
    response.params['currency'].should == 'USD'
    response.params['amount'].should == '2.00'
    response.params['authorizationCode'].should == '888888'
    response.params['avsCode'].should == 'X'
    response.params['avsCodeRaw'].should == 'I1'
    response.params['cvCode'].should be_nil
    response.params['authorizedDateTime'].should be_nil
    response.params['processorResponse'].should be_nil
    response.params['reconciliationID'].should == '00013791KV8BZF3P'
    response.params['subscriptionID'].should == ''
  end
end
