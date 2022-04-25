const AWS = require('aws-sdk');
const crypto = require('crypto');


async function addToSQSQueue(EMAIL, EMAIL_UUID)
{
    const SQS = new AWS.SQS({apiVersion: '2012-11-05'});
    const queue_params = {
        MessageBody: JSON.stringify({
            email: {S: EMAIL},
            id: {S: EMAIL_UUID}
        }),
        QueueUrl: "${new_subscription_queue_url}"
    };
    
    try
    {
        await SQS.sendMessage(queue_params).promise();
        console.log("Successfully added new subscription message to queue");
    } catch(err)
    {
        console.log("Error", err);
    }
}

async function sendVerificationEmail(EMAIL, EMAIL_UUID)
{
    const SES = new AWS.SES({apiVersion: '2010-12-01'});
    var ses_params = {
        Destination: {
            ToAddresses: [
                EMAIL
            ]
        },
        Message: {
            Body: {
                // Html: {
                //     Charset: "UTF-8",
                //     Data: "HTML_FORMAT_BODY"
                // },
                Text: {
                    Charset: "UTF-8",
                    Data: "Thank-you for subscribing to acatcalledjack.co.uk!\n\nTo confirm your subscription please click on this link:\n\nWe’ll let you know whenever there are updates to the website.  If you wish to unsubscribe at any time please click this link:"
                }
            },
            Subject: {
                Charset: 'UTF-8',
                Data: 'Please confirm your subscription to acatcalledjack.co.uk'
            }
        },
        Source: 'jack@acatcalledjack.co.uk', /* required */
        ReplyToAddresses: [
            'nickcooke@hotmail.com'
        ],
    };
    
    try
    {
        await SES.sendEmail(ses_params).promise();
    } catch(err)
    {
        console.log("Error", err);
    }
}
exports.handler = async(event) =>
{
    try
    {
        console.log(event);
        
        const DDB = new AWS.DynamoDB({apiVersion: '2012-08-10'});
        
        const EMAIL = event.body.email;
        const EMAIL_UUID = crypto.randomUUID()
        
        const params = {
            TableName: "${tableName}",
            Item: {
                email: {S: EMAIL},
                id: {S: EMAIL_UUID},
                verified: {BOOL: false}
            },
            ConditionExpression: "attribute_not_exists(email)"
        };
        let returnMessage = 'email address entered successfully'
        try
        {
            await DDB.putItem(params).promise();
            await addToSQSQueue(EMAIL, EMAIL_UUID);
            await sendVerificationEmail(EMAIL, EMAIL_UUID);
        } catch(err)
        {
            if(err.name === 'ConditionalCheckFailedException')
            {
                const getParams = {
                    TableName: "${tableName}",
                    Key: {
                        email: {S: EMAIL}
                    }
                }
                const subscriptionData = await DDB.getItem(getParams).promise();
                if(subscriptionData.Item.verified.BOOL)
                {
                    returnMessage = 'email address previously entered and verified'
                } else
                {
                    returnMessage = 'email address already submitted, but not verified'
                }
            } else
            {
                console.log("Error: " + err.message);
                throw err;
            }
        }
        
        return {
            'statusCode': 200,
            'body': JSON.stringify({
                message: returnMessage
            }),
            'headers': JSON.stringify({
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    }
            )
        };
    } catch(err)
    {
        console.log("Error: " + err.message);
        return err;
    }
};
