require('dotenv').config();
const { Kafka } = require('kafkajs');
const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const redis = require('redis');

const s3 = new S3Client({
    region: "us-east-1",
    credentials: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID,
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
        sessionToken: process.env.AWS_SESSION_TOKEN
    }
});

const redisClient = redis.createClient({
    url: `redis://${process.env.REDIS_HOST}:6379`
});

const kafka = new Kafka({
    clientId: 'auditoria-consumer',
    brokers: [process.env.KAFKA_BROKER],
    retry: { retries: 15 }
});

const consumer = kafka.consumer({ groupId: 'grupo-auditoria-logs' });

async function run() {
    await redisClient.connect();
    await consumer.connect();
    await consumer.subscribe({ topic: 'logs-auditoria', fromBeginning: true });

    await consumer.run({
        eachMessage: async ({ message }) => {
            const data = JSON.parse(message.value.toString());
            const id = `log-${Date.now()}`;

            // Persistencia en Redis
            await redisClient.set(id, JSON.stringify(data));

            // Persistencia en S3
            await s3.send(new PutObjectCommand({
                Bucket: process.env.BUCKET_NAME,
                Key: `${id}.json`,
                Body: JSON.stringify(data)
            }));
            
            console.log(`Log procesado y persistido: ${id}`);
        },
    });
}

run().catch(console.error);