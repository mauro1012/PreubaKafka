## 🚀 Instalación y Configuración

### 1. Carpeta: Auditorio

Encargada de la lógica de GraphQL y la integración con Express.

```bash
cd auditorio
npm init -y
npm install apollo-server-express express graphql kafkajs dotenv cors

```

### 2. Carpeta: Gateway

Encargada de la comunicación con Kafka, persistencia en Redis y almacenamiento en AWS S3.

```bash
cd gateway
npm init -y
npm install kafkajs redis @aws-sdk/client-s3 dotenv

```

---

##  Pruebas de Funcionamiento (Postman)

Para verificar que el flujo de arquitectura está funcionando correctamente, realiza la siguiente consulta:

* **Método:** `POST`
* **URL:** `http://<TU_DIRECCION_DNS>/graphql`
* **Cuerpo (GraphQL):**

```graphql
mutation {
  publicarAccion(
    usuario: "daniel", 
    accion: "Prueba final de arquitectura Kafka"
  ) {
    success
    message
  }
}

```

---

##  Verificación en Base de Datos (Redis)

Si necesitas validar que los logs se están registrando correctamente dentro del contenedor de Redis, sigue estos pasos:

1. **Acceder al contenedor:**
```bash
sudo docker exec -it app_db-redis-logs_1 redis-cli

```


2. **Listar las llaves guardadas:**
```bash
keys *

```


3. **Consultar un log específico:**
*(Reemplaza la llave por la obtenida en el paso anterior)*
```bash
get log-CAMBIA_ESTO_POR_TU_LLAVE

```


4. **Salir:**
```bash
exit

```
