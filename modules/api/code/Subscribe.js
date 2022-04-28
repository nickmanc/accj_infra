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
    const template_data = JSON.stringify({
        "verification_url": "https://${api_address}${verify_resource}?email=" + EMAIL + "&id=" + EMAIL_UUID,
        "unsubscribe_url": "https://${api_address}${unsubscribe_resource}?email=" + EMAIL + "&id=" + EMAIL_UUID,
        "root_domain_name": "${root_domain_name}"
    });
    const ses_params = {
        Destination: {
            ToAddresses: [
                EMAIL
            ]
        },
        Source: "${email_from}@${root_domain_name}",
        Template: "${email_template_name}",
        TemplateData: template_data,
        ReplyToAddresses: [
            "noreply@${root_domain_name}"
        ],
    };
    
    try
    {
        await SES.sendTemplatedEmail(ses_params).promise();
        console.log("Successfully submitted templated email");
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
        let body = JSON.parse(event.body)
        
        const DDB = new AWS.DynamoDB({apiVersion: '2012-08-10'});
        
        const EMAIL = body.email;
        const EMAIL_UUID = crypto.randomUUID()
        console.log("email: " + EMAIL)
        const params = {
            TableName: "${tableName}",
            Item: {
                email: {S: EMAIL},
                id: {S: EMAIL_UUID},
                verified: {BOOL: false}
            },
            ConditionExpression: "attribute_not_exists(email)"
        };
        let returnMessage = 'Email address entered successfully, please confirm your subscription by clicking the link in the email I\'ve just sent.'
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
                    returnMessage = 'You\'re already signed up!'
                } else
                {
                    returnMessage = 'Email address previously added, please confirm your subscription by clicking the link in the email I sent.'
                }
            } else
            {
                console.log("Error: " + err.message);
                throw err;
            }
        }
        
        let response = {
            "isBase64Encoded": false,
            "statusCode": '200',
            "headers": {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            "body": JSON.stringify({"message": returnMessage})
        };
        console.log(response)
        return response
    } catch(err)
    {
        console.log("Error: " + err.message);
        return err;
    }
};
