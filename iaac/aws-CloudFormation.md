Resources:
  MyLambda:
    Type: AWS::Lambda::Function
    Properties:
      Runtime: nodejs18.x
      Handler: index.handler
      Code:
        S3Bucket: my-code-bucket
        S3Key: lambda.zip
      Environment:
        Variables:
          DYNAMODB_TABLE: !Ref MyTable
  
  MyTable:
    Type: AWS::DynamoDB::Table
    Properties:
      TableName: CreditApplications
      BillingMode: PAY_PER_REQUEST
      AttributeDefinitions:
        - AttributeName: userId
          AttributeType: S
      KeySchema:
        - AttributeName: userId
          KeyType: HASH
