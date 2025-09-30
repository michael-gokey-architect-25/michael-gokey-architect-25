import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';

export class CreditAppStack extends cdk.Stack {
  constructor(scope: cdk.App, id: string) {
    super(scope, id);

    const table = new dynamodb.Table(this, 'CreditApps', {
      partitionKey: { name: 'userId', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST
    });

    const fn = new lambda.Function(this, 'ProcessApp', {
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset('lambda'),
      environment: {
        TABLE_NAME: table.tableName
      }
    });

    table.grantReadWriteData(fn); // Auto-creates IAM permissions
  }
}
