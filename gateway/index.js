require('dotenv').config();
const { ApolloServer, gql } = require('apollo-server-express');
const express = require('express');
const { Kafka } = require('kafkajs');
const cors = require('cors');

// Configuracion de Kafka
const kafka = new Kafka({
  clientId: 'gateway-producer',
  brokers: [process.env.KAFKA_BROKER]
});

const producer = kafka.producer();

// Definicion de Esquema GraphQL
const typeDefs = gql`
  type Response {
    success: Boolean
    message: String
  }

  type Query {
    health: String
  }

  type Mutation {
    publicarAccion(usuario: String!, accion: String!): Response
  }
`;

// Resolvers de GraphQL
const resolvers = {
  Query: {
    health: () => "Gateway Producer Operativo"
  },
  Mutation: {
    publicarAccion: async (_, { usuario, accion }) => {
      try {
        // Estructura del mensaje para Kafka
        const mensaje = {
          usuario,
          accion,
          timestamp: new Date().toISOString()
        };

        // Envio del evento al topic 'logs-auditoria'
        await producer.send({
          topic: 'logs-auditoria',
          messages: [
            { value: JSON.stringify(mensaje) }
          ],
        });

        return {
          success: true,
          message: "Evento enviado exitosamente al bus de datos Kafka"
        };
      } catch (error) {
        console.error('Error al producir evento en Kafka:', error.message);
        return {
          success: false,
          message: "Error de conexion con el broker de mensajeria"
        };
      }
    }
  }
};

// Inicializacion del servidor
async function bootstrap() {
  const app = express();
  app.use(cors());

  const server = new ApolloServer({ typeDefs, resolvers });
  await server.start();
  server.applyMiddleware({ app, path: '/graphql' });

  // Conexion con el Broker de Kafka antes de levantar el servidor
  await producer.connect();
  console.log('Conectado al Broker de Kafka');

  // Endpoint de salud para el Load Balancer
  app.get('/health', (req, res) => res.status(200).send('OK'));

  const PORT = process.env.PORT || 3000;
  app.listen(PORT, () => {
    console.log(`Servidor Gateway corriendo en puerto ${PORT}`);
    console.log(`Endpoint GraphQL disponible en /graphql`);
  });
}

bootstrap().catch(console.error);