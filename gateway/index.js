require('dotenv').config();
const { ApolloServer, gql } = require('apollo-server-express');
const express = require('express');
const { Kafka } = require('kafkajs');
const cors = require('cors');

const kafka = new Kafka({
  clientId: 'gateway-producer',
  brokers: [process.env.KAFKA_BROKER || 'localhost:9092'],
  retry: {
    initialRetryTime: 1000,
    retries: 15 // Intenta conectar durante 15 segundos antes de fallar
  }
});

const producer = kafka.producer();

const typeDefs = gql`
  type Response { success: Boolean, message: String }
  type Query { health: String }
  type Mutation { publicarAccion(usuario: String!, accion: String!): Response }
`;

const resolvers = {
  Query: { health: () => "OK" },
  Mutation: {
    publicarAccion: async (_, { usuario, accion }) => {
      try {
        await producer.send({
          topic: 'logs-auditoria',
          messages: [{ value: JSON.stringify({ usuario, accion, timestamp: new Date() }) }],
        });
        return { success: true, message: "Evento enviado a Kafka" };
      } catch (error) {
        return { success: false, message: error.message };
      }
    }
  }
};

async function start() {
  const app = express();
  app.use(cors());

  const server = new ApolloServer({ typeDefs, resolvers });
  await server.start();
  server.applyMiddleware({ app });

  // Intento de conexion con reintentos
  console.log('Esperando conexion con Kafka...');
  await producer.connect();
  console.log('Conectado a Kafka exitosamente');

  app.get('/health', (req, res) => res.status(200).send('OK'));

  app.listen(3000, () => console.log("Gateway Producer activo en puerto 3000"));
}

start().catch(console.error);