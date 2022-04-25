const AWS = require('aws-sdk');
const crypto = require('crypto');

exports.handler = async(event) =>
{
    try
    {
        console.log(event);
        console.log(event.body);
        const obj = event.body;
        
        const DDB = new AWS.DynamoDB({apiVersion: '2012-08-10'});
        
        const EMAIL = obj.email;
        const EMAIL_UUID = obj.id;
        
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