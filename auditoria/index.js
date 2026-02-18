require('dotenv').config();
const { Kafka } = require('kafkajs');
const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const redis = require('redis');

// Configuracion de AWS S3
const s3 = new S3Client({
    region: process.env.AWS_REGION,
    credentials: {
        accessKey_id: process.env.AWS_ACCESS_KEY_ID,
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
        sessionToken: process.env.AWS_SESSION_TOKEN
    }
});

// Configuracion de Redis
const redisClient = redis.createClient({
    url: `redis://${process.env.REDIS_HOST}:6379`
});

// Configuracion de Kafka Consumer
const kafka = new Kafka({
    clientId: 'auditoria-consumer',
    brokers: [process.env.KAFKA_BROKER]
});

const consumer = kafka.consumer({ groupId: 'grupo-auditoria-logs' });

/**
 * Funcion para procesar y persistir el mensaje recibido
 */
async function persistirLog(data) {
    const logId = `kafka-log-${Date.now()}`;
    
    try {
        // 1. Persistencia en Redis (Cache de acceso rapido)
        await redisClient.set(logId, JSON.stringify(data));
        console.log(`Guardado en Redis: ${logId}`);

        // 2. Persistencia en S3 (Almacenamiento de larga duracion)
        const command = new PutObjectCommand({
            Bucket: process.env.BUCKET_NAME,
            Key: `eventos/${logId}.json`,
            Body: JSON.stringify({ id: logId, ...data }),
            ContentType: "application/json"
        });
        await s3.send(command);
        console.log(`Guardado en S3: eventos/${logId}.json`);

    } catch (error) {
        console.error('Error durante la persistencia:', error.message);
    }
}

/**
 * Inicio del proceso de escucha de Kafka
 */
async function iniciarConsumidor() {
    await redisClient.connect();
    await consumer.connect();
    
    // Suscripcion al topic definido en el Gateway
    await consumer.subscribe({ topic: 'logs-auditoria', fromBeginning: true });

    console.log('Consumidor de Auditoria esperando eventos en Kafka...');

    await consumer.run({
        eachMessage: async ({ topic, partition, message }) => {
            const data = JSON.parse(message.value.toString());
            console.log(`Evento recibido de topic [${topic}]:`, data.accion);
            
            // Ejecutar persistencia
            await persistirLog(data);
        },
    });
}

iniciarConsumidor().catch(err => {
    console.error('Error fatal en el consumidor:', err);
    process.exit(1);
});