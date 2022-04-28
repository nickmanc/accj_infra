const AWS = require('aws-sdk');

exports.handler = async(event) =>
{
    try
    {
        const DDB = new AWS.DynamoDB({apiVersion: '2012-08-10'});
        const EMAIL = event.queryStringParameters.email;
        const EMAIL_UUID = event.queryStringParameters.id;
        
        const params = {
            TableName: "subscriptions",
            Key: {
                email: {S: EMAIL}
            },
            UpdateExpression: "set verified = :verified",
            ConditionExpression: "id = :uid",
            ExpressionAttributeValues: {
                ":uid": {S: EMAIL_UUID},
                ":verified": {BOOL: true}
            }
        };
        let response;
        try
        {
            await DDB.updateItem(params).promise();
            response =  {
                "isBase64Encoded": false,
                "statusCode": '200',
                "headers": {
                    'Access-Control-Allow-Origin': '*',
                    'Content-Type': 'text/html'
                },
                "body": "<html lang=\"en\"><head><style>.messageText {color: black; font-weight: 800; letter-spacing: 0.075em; text-transform: uppercase; font-size: 32px; font-family: \"Raleway\", \"Helvetica\", sans-serif; text-align: center;}</style></head>" +
                        "<body></body><div class=\"messageText\"><h1>Welcome to ${root_domain_name}</h1><p>" + EMAIL
                        + " has successfully subscribed.</p><p>I'll let you know whenever the content on the website changes</p><br/><p>Jack</p>"
                        + "<small>To unsubscribe just click <a href=\"https://${api_address}${unsubscribe_resource}?email=" + EMAIL + "&id=" + EMAIL_UUID+"\">here</a></small><img src='https://www.acatcalledjack.co.uk/images/verification.jpg'\"></img></div></body></html>"};
        }
        catch(err)
        {
            if(err.name === 'ConditionalCheckFailedException')
            {
                response =  {
                "isBase64Encoded": false,
                "statusCode": '200',
                "headers": {
                    'Access-Control-Allow-Origin': '*',
                    'Content-Type': 'text/html'
                },
                "body": "<html lang=\"en\"><h1>:-(</h1><p>" + EMAIL
                        + " failed to subscribe.</p></html>"};
            }
        }
        
        return response
    } catch(err)
    {
        console.log("Error: " + err.message);
        return err;
    }
};