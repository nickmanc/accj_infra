const AWS = require('aws-sdk');
const crypto = require('crypto');

exports.handler = async(event) =>
{
    try
    {
        console.log(event);
        
        const DDB = new AWS.DynamoDB({apiVersion: '2012-08-10'});
    
        const EMAIL = event.queryStringParameters.email;
        const EMAIL_UUID = event.queryStringParameters.id;
        
        const params = {
            TableName: "${tableName}",
            Key: {
                email: {S: EMAIL}
            },
            ConditionExpression: "id = :uid",
            ExpressionAttributeValues: {
                ":uid": {S: EMAIL_UUID}
            }
        };
        let returnMessage = EMAIL + ' has been unsubscribed'
        
        try
        {
            await DDB.deleteItem(params).promise();
        }
        catch(err) {
            if(err.name === 'ConditionalCheckFailedException')
            {
                const getParams = {
                    TableName: "${tableName}",
                    Key: {
                        email: {S: EMAIL}
                    }
                }
                const subscriptionData = await DDB.getItem(getParams).promise();
                if(subscriptionData.Item != null)
                {
                    returnMessage = 'incorrect unsuscribe request, please contact jack@acatcalledjack.co.uk for further help'
                } else
                {
                    returnMessage = EMAIL + ' was not found in the system'
                }
            } else
            {
                console.log("Error: " + err.message);
                throw err;
            }
        }
        console.log("about to return")
        return {
            "isBase64Encoded": false,
            "statusCode": '200',
            "headers": {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'text/html'
            },
            "body": "<html lang=\"en\"><head><style>.messageText {color: black; font-weight: 800; letter-spacing: 0.075em; text-transform: uppercase; font-size: 32px; font-family: \"Raleway\", \"Helvetica\", sans-serif; text-align: center;}</style></head>" +
                    "<div class=\"messageText\"><h1>Sorry to see you go :-(</h1><p>" + EMAIL
                    + "</p><p>I've removed you from the mailing list</p><br/>Best Wishes<p>Jack</p>"
                    + "<img src='https://www.acatcalledjack.co.uk/images/sad_jack.jpg'\"></img></div></body></html>"}
        
    } catch(err)
    {
        console.log("Error: " + err.message);
        return err;
    }
};