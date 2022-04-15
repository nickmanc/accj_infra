const AWS = require('aws-sdk');

exports.handler = async function (event, context) {
    const cloudFront = new AWS.CloudFront();
    
    const invalidationParams = {
        DistributionId: "${distributionId}",
        InvalidationBatch: {
            CallerReference: Date.now().toString(),
            Paths: {
                Quantity: 1,
                Items: [
                    "/*"
                ]
            }
        }
    };
    
    await cloudFront.createInvalidation(invalidationParams).promise();
};