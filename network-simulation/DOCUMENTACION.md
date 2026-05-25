# Simulacion de Red Cliente-Servidor

## 1. Modelo Cliente-Servidor

El modelo **cliente-servidor** es una arquitectura de red donde:

- **Servidor**: Proceso central que escucha conexiones entrantes, gestiona la logica de negocio y coordina la comunicacion entre clientes. Opera de forma pasiva esperando solicitudes.
- **Cliente**: Proceso que inicia la conexion al servidor para enviar solicitudes y recibir respuestas. Multiples clientes pueden conectarse simultaneamente.

### Caracteristicas del modelo

| Aspecto | Descripcion |
|---------|-------------|
| Comunicacion | Bidireccional (full-duplex sobre TCP) |
| Topologia | Estrella: todos los clientes se comunican a traves del servidor |
| Escalabilidad | El servidor maneja N clientes concurrentes |
| Confiabilidad | TCP garantiza entrega ordenada y sin perdida de datos |

---

## 2. Protocolo de Comunicacion

### 2.1 Protocolo de Transporte: TCP

Se utiliza **TCP (Transmission Control Protocol)** por las siguientes razones:

- **Orientado a conexion**: Se establece un canal confiable antes de transmitir datos.
- **Entrega garantizada**: TCP retransmite paquetes perdidos automaticamente.
- **Orden preservado**: Los mensajes llegan en el mismo orden en que fueron enviados.
- **Control de flujo**: Evita saturar al receptor.

### 2.2 Formato de Mensajes: NDJSON

Cada mensaje se transmite como una linea JSON terminada en `\n` (Newline-Delimited JSON):

```
{"type":"LOGIN","from":"alice","content":"alice123","timestamp":1716556800000}\n
```

**Estructura del mensaje:**

```
ProtocolMessage {
  type:      string   // Tipo de mensaje (ver tabla abajo)
  id?:       string   // Identificador unico del mensaje (generado por servidor)
  from?:     string   // Remitente
  to?:       string   // Destinatario
  content?:  string   // Contenido del mensaje
  timestamp: number   // Marca de tiempo Unix en milisegundos
}
```

### 2.3 Tipos de Mensaje

| Tipo | Direccion | Proposito |
|------|-----------|-----------|
| `LOGIN` | Cliente -> Servidor | Solicitud de inicio de sesion |
| `LOGIN_OK` | Servidor -> Cliente | Confirmacion de autenticacion exitosa |
| `LOGIN_FAIL` | Servidor -> Cliente | Rechazo de autenticacion |
| `MESSAGE` | Bidireccional | Mensaje de texto entre usuarios |
| `ACK` | Servidor -> Cliente | Confirmacion de recepcion/entrega |
| `ERROR` | Servidor -> Cliente | Notificacion de error |
| `USER_LIST` | Bidireccional | Solicitud/respuesta de usuarios conectados |
| `BROADCAST` | Servidor -> Clientes | Notificacion a todos los usuarios |

---

## 3. Flujo de Comunicacion

### 3.1 Inicio de Sesion

```
  Cliente A                 Servidor                 Cliente B
     |                         |                         |
     |--- TCP CONNECT -------->|                         |
     |<-- TCP ACK -------------|                         |
     |                         |                         |
     |--- LOGIN -------------->|                         |
     |    {from:"alice",       |                         |
     |     content:"alice123"} |                         |
     |                         |-- Valida credenciales   |
     |<-- LOGIN_OK ------------|                         |
     |    {content:"Bienvenido"|                         |
     |                         |--- BROADCAST ---------->|
     |                         |    {content:"alice      |
     |                         |     se ha conectado"}   |
```

### 3.2 Envio de Mensaje con Confirmacion (ACK)

```
  Cliente A                 Servidor                 Cliente B
     |                         |                         |
     |--- MESSAGE ------------>|                         |
     |    {from:"alice",       |                         |
     |     to:"bob",           |                         |
     |     content:"Hola!"}    |                         |
     |                         |--- MESSAGE ------------>|
     |                         |    {id:"a1b2c3d4",     |
     |                         |     from:"alice",       |
     |                         |     content:"Hola!"}    |
     |                         |                         |
     |<-- ACK -----------------|                         |
     |    {id:"a1b2c3d4",      |                         |
     |     content:"Entregado  |                         |
     |     a bob"}             |                         |
```

### 3.3 Mensaje a Usuario Desconectado

```
  Cliente A                 Servidor
     |                         |
     |--- MESSAGE ------------>|
     |    {to:"carlos",        |
     |     content:"Hola"}     |
     |                         |-- carlos no esta
     |<-- ERROR ---------------|   en connectedClients
     |    {content:"Usuario    |
     |     'carlos' no esta    |
     |     conectado"}         |
```

### 3.4 Desconexion

```
  Cliente A                 Servidor                 Cliente B
     |                         |                         |
     |--- TCP CLOSE ---------->|                         |
     |                         |-- Elimina de mapa       |
     |                         |--- BROADCAST ---------->|
     |                         |    {content:"alice      |
     |                         |     se ha desconectado"}|
```

### 3.5 Flujo Completo de una Sesion

```
  Tiempo  Cliente A              Servidor              Cliente B
  ------  ------------------     ------------------    ------------------
  t=0     TCP CONNECT ---------> (acepta conexion)
  t=1     LOGIN {alice} -------> Valida credenciales
  t=2     <--- LOGIN_OK -------  Registra alice
  t=3                            (acepta conexion) <--- TCP CONNECT
  t=4                            Valida credenciales <- LOGIN {bob}
  t=5                            Registra bob -------> LOGIN_OK --->
  t=5                            BROADCAST "bob      -> (recibido)
                                 se ha conectado"
  t=6     MSG "Hola bob" ------> Busca socket de bob
  t=7                            Reenviar a bob -----> MSG de alice
  t=8     <--- ACK [id:x] -----  Confirma entrega
  t=9                                                  MSG "Hola alice"
  t=10                           Busca socket alice <- (recibido)
  t=11    MSG de bob <---------- Reenviar a alice
  t=12                           Confirma entrega ---> ACK [id:y]
  t=13    TCP CLOSE -----------> Elimina alice
  t=14                           BROADCAST ----------> "alice se
                                                        desconecto"
```

---

## 4. Arquitectura del Sistema

```
+-------------------+          +-------------------+
|   CLIENTE A       |   TCP    |                   |   TCP    +-------------------+
|                   |<-------->|     SERVIDOR      |<-------->|   CLIENTE B       |
| - readline (CLI)  |  :3500   |                   |  :3500   | - readline (CLI)  |
| - socket TCP      |          | - net.Server      |          | - socket TCP      |
| - buffer NDJSON   |          | - Map<user,socket>|          | - buffer NDJSON   |
+-------------------+          | - USERS_DB        |          +-------------------+
                               | - buffer NDJSON   |
                               +-------------------+
```

### Componentes

| Componente | Archivo | Responsabilidad |
|------------|---------|-----------------|
| Protocolo | `src/protocol.ts` | Tipos, serializacion, constantes compartidas |
| Servidor | `src/server.ts` | Escucha conexiones, autentica, enruta mensajes |
| Cliente | `src/client.ts` | Interfaz CLI, envia/recibe mensajes |

---

## 5. Manejo del Buffer TCP

TCP es un protocolo de **flujo de bytes** (stream), no de mensajes. Esto significa que:

- Un `data` event puede contener multiples mensajes
- Un mensaje puede llegar dividido en multiples `data` events

**Solucion**: Buffer con delimitador `\n`

```
Datos recibidos:   '{"type":"MSG"...}\n{"type":"ACK"'
                    ^-- mensaje completo  ^-- incompleto

Procesamiento:
1. Concatenar al buffer existente
2. Dividir por '\n'
3. Parsear lineas completas como JSON
4. Guardar el ultimo fragmento incompleto en el buffer
```

---

## 6. Instrucciones de Ejecucion

### Requisitos

- Node.js 18 o superior

### Instalacion

```bash
cd network-simulation
npm install
```

### Ejecucion

Abrir **3 terminales** en la carpeta `network-simulation/`:

**Terminal 1 - Servidor:**
```bash
npm run server
```

**Terminal 2 - Cliente A:**
```bash
npm run client
```
- Usuario: `alice`, Contrasena: `alice123`

**Terminal 3 - Cliente B:**
```bash
npm run client
```
- Usuario: `bob`, Contrasena: `bob123`

### Usuarios Disponibles

| Usuario | Contrasena |
|---------|------------|
| alice | alice123 |
| bob | bob123 |
| carlos | carlos123 |

### Comandos del Cliente

| Comando | Descripcion |
|---------|-------------|
| `/msg <usuario> <texto>` | Enviar mensaje a un usuario |
| `/users` | Ver usuarios conectados |
| `/help` | Mostrar ayuda |
| `/quit` | Desconectarse |

---

## 7. Ejemplo de Sesion

### Consola del Servidor
```
=========================================
   SERVIDOR DE CHAT - SIMULACION DE RED
=========================================
  Host:     127.0.0.1
  Puerto:   3500
  Usuarios: alice, bob, carlos
=========================================

[10:00:01] Servidor iniciado. Esperando conexiones...
[10:00:05] Nueva conexion desde 127.0.0.1:52431
[10:00:08] LOGIN OK: alice (1 usuarios conectados)
[10:00:12] Nueva conexion desde 127.0.0.1:52432
[10:00:15] LOGIN OK: bob (2 usuarios conectados)
[10:00:20] MENSAJE: alice -> bob: "Hola Bob!" [id:a1b2c3d4]
[10:00:25] MENSAJE: bob -> alice: "Hola Alice!" [id:e5f6a7b8]
[10:00:30] LOGOUT: alice (1 usuarios conectados)
```

### Consola de Cliente A (alice)
```
  +-----------------------------------------+
  |  CLIENTE CHAT - SIMULACION DE RED       |
  +-----------------------------------------+
  |  Conectado a 127.0.0.1:3500             |
  +-----------------------------------------+

  Usuario: alice
  Contrasena: alice123
  [10:00:08] [OK] Bienvenido, alice. Usuarios conectados: 1

  [alice] > /msg bob Hola Bob!
  [10:00:20] [ACK] Mensaje [a1b2c3d4] entregado a bob
  [10:00:25] [DE bob] Hola Alice!
  [alice] > /quit
  Desconectando...
```

### Consola de Cliente B (bob)
```
  +-----------------------------------------+
  |  CLIENTE CHAT - SIMULACION DE RED       |
  +-----------------------------------------+
  |  Conectado a 127.0.0.1:3500             |
  +-----------------------------------------+

  Usuario: bob
  Contrasena: bob123
  [10:00:15] [OK] Bienvenido, bob. Usuarios conectados: 2

  [10:00:20] [DE alice] Hola Bob!
  [bob] > /msg alice Hola Alice!
  [10:00:25] [ACK] Mensaje [e5f6a7b8] entregado a alice
  [10:00:30] [INFO] alice se ha desconectado
```

---

## 8. Tecnologias Utilizadas

| Tecnologia | Uso |
|------------|-----|
| **Node.js** | Entorno de ejecucion JavaScript del lado del servidor |
| **TypeScript** | Tipado estatico para mayor robustez |
| **Modulo `net`** | Sockets TCP nativos de Node.js (sin dependencias externas) |
| **Modulo `readline`** | Interfaz CLI interactiva nativa de Node.js |
| **NDJSON** | Formato de serializacion de mensajes sobre TCP |
| **TCP** | Protocolo de transporte confiable y orientado a conexion |
