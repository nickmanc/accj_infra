var AWS = require('aws-sdk');

exports.handler = async (event) => {
    try {
        console.log(event);
        console.log(event.body);
        var obj = event.body;
        console.log(obj.email);
        
        var ddb = new AWS.DynamoDB({apiVersion: '2012-08-10'});
        
        var EMAIL = obj.email;
        
        var params = {
            TableName: "subscriptions",
            Item: {
                email : {S: EMAIL}
            },
            ConditionExpression: "attribute_not_exists(email)"
        };
        
        var returnMessage = 'email address entered successfully'
        try{
            const data = await ddb.putItem(params).promise();
            console.log("Email entered successfully:", data);
        } catch(err){
            if (err.name === 'ConditionalCheckFailedException') {
                returnMessage = 'email address already entered'
            }
            else {console.log("Error: ", err);
                throw err;
            }
        }
        
        var response = {
            'statusCode': 200,
            'body': JSON.stringify({
                message: returnMessage
            }),
            'headers':JSON.stringify( {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            })
        };
    } catch (err) {
        console.log(err);
        return err;
    }
    return response;
};