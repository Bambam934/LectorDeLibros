# Guia Paso a Paso — Laboratorio de Simulacion Cliente-Servidor

---

## Tabla de Contenido

1. [Objetivo del laboratorio](#1-objetivo-del-laboratorio)
2. [Conceptos teoricos](#2-conceptos-teoricos)
3. [Estructura del proyecto](#3-estructura-del-proyecto)
4. [Explicacion del codigo fuente](#4-explicacion-del-codigo-fuente)
5. [Instalacion y preparacion](#5-instalacion-y-preparacion)
6. [Ejecucion paso a paso](#6-ejecucion-paso-a-paso)
7. [Escenarios de prueba](#7-escenarios-de-prueba)
8. [Resumen del flujo de comunicacion](#8-resumen-del-flujo-de-comunicacion)

---

## 1. Objetivo del laboratorio

Construir una simulacion funcional del modelo cliente-servidor que demuestre:

- **Inicio de sesion**: Un cliente se autentica ante el servidor con usuario y contrasena.
- **Envio de mensajes**: Un cliente envia un mensaje a otro cliente a traves del servidor.
- **Confirmacion de recepcion (ACK)**: El servidor confirma al remitente que el mensaje fue entregado al destinatario.

La simulacion usa **sockets TCP** reales sobre `localhost`, lo que significa que los datos viajan por la pila de red del sistema operativo igual que en una red fisica.

---

## 2. Conceptos teoricos

### 2.1 Modelo Cliente-Servidor

Es una arquitectura de red donde los roles estan divididos:

| Rol | Descripcion |
|-----|-------------|
| **Servidor** | Programa que permanece **escuchando** en un puerto. Acepta conexiones de clientes, procesa sus solicitudes y coordina la comunicacion. No inicia conexiones por si mismo. |
| **Cliente** | Programa que **inicia** la conexion hacia el servidor. Envia solicitudes y espera respuestas. Puede haber multiples clientes conectados al mismo tiempo. |

En nuestra simulacion el servidor actua como intermediario: los clientes nunca se comunican directamente entre si. Todo pasa a traves del servidor.

```
  Cliente A  ──TCP──>  SERVIDOR  <──TCP──  Cliente B
      \                   |                   /
       \                  |                  /
        ---- Toda comunicacion pasa --------
             por el servidor central
```

### 2.2 Protocolo TCP

TCP (Transmission Control Protocol) es el protocolo de transporte que usamos. Sus caracteristicas clave:

- **Orientado a conexion**: Antes de enviar datos, se establece una conexion (handshake de 3 pasos: SYN, SYN-ACK, ACK).
- **Entrega confiable**: Si un paquete se pierde, TCP lo retransmite automaticamente.
- **Orden garantizado**: Los datos llegan en el mismo orden en que se enviaron.
- **Flujo de bytes**: TCP no tiene concepto de "mensajes"; envia bytes en un flujo continuo. Por eso necesitamos un delimitador (`\n`) para separar mensajes.

### 2.3 NDJSON (Newline-Delimited JSON)

Como TCP envia un flujo continuo de bytes, necesitamos una forma de saber donde termina un mensaje y empieza otro. Usamos **NDJSON**: cada mensaje es un objeto JSON en una sola linea, terminado con `\n`.

```
{"type":"LOGIN","from":"alice","content":"alice123","timestamp":1716556800000}\n
{"type":"MESSAGE","from":"alice","to":"bob","content":"Hola","timestamp":1716556801000}\n
```

Ventajas: simple de implementar, legible para depuracion, y permite parsear mensajes completos a medida que llegan.

### 2.4 Confirmacion de Recepcion (ACK)

ACK (Acknowledgment) es un patron donde el receptor de un mensaje confirma que lo recibio. En nuestra simulacion:

1. Alice envia un mensaje dirigido a Bob
2. El servidor recibe el mensaje y lo reenvia a Bob
3. El servidor envia un ACK de vuelta a Alice confirmando que el mensaje fue entregado

Esto le da a Alice la certeza de que su mensaje llego a destino.

---

## 3. Estructura del proyecto

```
network-simulation/
├── package.json          # Dependencias y scripts de ejecucion
├── tsconfig.json         # Configuracion de TypeScript
├── DOCUMENTACION.md      # Documentacion tecnica del protocolo
├── GUIA_LABORATORIO.md   # Esta guia (explicacion paso a paso)
└── src/
    ├── protocol.ts       # Definiciones compartidas (tipos, serializacion)
    ├── server.ts         # Programa del servidor
    └── client.ts         # Programa del cliente
```

**Tres archivos de codigo, tres responsabilidades claras:**

| Archivo | Que hace | Quien lo usa |
|---------|----------|--------------|
| `protocol.ts` | Define el "idioma" comun: tipos de mensaje, formato, puerto | Servidor y Cliente |
| `server.ts` | Escucha conexiones, valida logins, enruta mensajes, envia ACKs | Solo el servidor |
| `client.ts` | Se conecta al servidor, muestra interfaz CLI, envia/recibe mensajes | Solo los clientes |

---

## 4. Explicacion del codigo fuente

### 4.1 protocol.ts — El idioma comun

Este archivo define todo lo que servidor y clientes necesitan entender por igual.

**Tipos de mensaje (MessageType):**

```typescript
export enum MessageType {
  LOGIN = 'LOGIN',           // Cliente pide iniciar sesion
  LOGIN_OK = 'LOGIN_OK',     // Servidor confirma login exitoso
  LOGIN_FAIL = 'LOGIN_FAIL', // Servidor rechaza login
  MESSAGE = 'MESSAGE',       // Mensaje de texto entre usuarios
  ACK = 'ACK',               // Confirmacion de entrega
  ERROR = 'ERROR',           // Error generico
  USER_LIST = 'USER_LIST',   // Lista de usuarios conectados
  BROADCAST = 'BROADCAST',   // Notificacion a todos
}
```

**Estructura de un mensaje (ProtocolMessage):**

```typescript
export interface ProtocolMessage {
  type: MessageType;     // Tipo (obligatorio) - que clase de mensaje es
  id?: string;           // ID unico - lo genera el servidor para rastrear mensajes
  from?: string;         // Remitente
  to?: string;           // Destinatario
  content?: string;      // Contenido del mensaje
  timestamp: number;     // Marca de tiempo (obligatorio) - cuando se creo
}
```

**Funcion serialize — Convertir objeto a texto para enviar por TCP:**

```typescript
export function serialize(msg: ProtocolMessage): string {
  return JSON.stringify(msg) + '\n';  // Convierte a JSON + salto de linea
}
```

Ejemplo: `serialize({type: 'LOGIN', from: 'alice', ...})` produce:
```
{"type":"LOGIN","from":"alice","content":"alice123","timestamp":1716556800000}\n
```

**Funcion parseBuffer — Extraer mensajes del flujo TCP:**

```typescript
export function parseBuffer(buffer: string): { messages: ProtocolMessage[]; remaining: string } {
  const lines = buffer.split('\n');       // Dividir por saltos de linea
  const remaining = lines.pop() || '';    // Ultimo fragmento (puede estar incompleto)
  const messages: ProtocolMessage[] = [];

  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      messages.push(JSON.parse(line));    // Parsear cada linea completa
    } catch {
      // Si una linea no es JSON valido, se ignora
    }
  }

  return { messages, remaining };         // Mensajes completos + lo que queda en buffer
}
```

**Por que se necesita el buffer?** TCP puede entregar datos fragmentados:

```
Escenario: El servidor envia dos mensajes seguidos.
TCP puede entregarlos asi:

data event 1: '{"type":"LOGIN_OK","content":"Bienvenido"}\n{"type":"BR'
data event 2: 'OADCAST","content":"alice conectado"}\n'

Sin buffer, el segundo mensaje se perderia porque llego partido en dos.
Con buffer, se guarda 'OADCAST","content":"alice conectado"}' y se
concatena cuando llega el resto.
```

---

### 4.2 server.ts — El servidor central

El servidor tiene cuatro responsabilidades principales:

#### A) Base de datos de usuarios (simulada)

```typescript
const USERS_DB: Record<string, string> = {
  alice: 'alice123',
  bob: 'bob123',
  carlos: 'carlos123',
};
```

En una aplicacion real esto seria una base de datos con contrasenas hasheadas. Aqui se simplifica con un objeto en memoria para enfocarnos en la comunicacion de red.

#### B) Estado de conexiones

```typescript
const connectedClients = new Map<string, net.Socket>();  // usuario -> socket
const socketToUser = new Map<net.Socket, string>();       // socket -> usuario
```

Se usan dos mapas para buscar en ambas direcciones:
- `connectedClients`: Dado un nombre de usuario, obtener su socket para enviarle datos.
- `socketToUser`: Dado un socket, saber que usuario lo usa (util cuando se desconecta).

#### C) Crear el servidor TCP

```typescript
const server = net.createServer((socket) => {
  // Este callback se ejecuta por CADA nueva conexion
  let buffer = '';

  socket.on('data', (data) => {
    // Se ejecuta cada vez que llegan datos de este cliente
    buffer += data.toString();
    const result = parseBuffer(buffer);
    buffer = result.remaining;

    for (const msg of result.messages) {
      // Despachar segun el tipo de mensaje
      switch (msg.type) {
        case MessageType.LOGIN:     handleLogin(socket, msg); break;
        case MessageType.MESSAGE:   handleMessage(socket, msg); break;
        case MessageType.USER_LIST: handleUserList(socket); break;
      }
    }
  });

  socket.on('close', () => handleDisconnect(socket));
});

server.listen(SERVER_PORT, SERVER_HOST);
```

**Flujo de datos:**
1. `net.createServer()` crea un servidor TCP
2. `server.listen(3500, '127.0.0.1')` le dice que escuche en el puerto 3500
3. Cada vez que un cliente se conecta, se ejecuta el callback con el `socket` de ese cliente
4. Cada vez que ese cliente envia datos, se dispara el evento `'data'`
5. Se parsean los mensajes y se despachan a la funcion correspondiente

#### D) Funciones de manejo

**handleLogin** — Proceso de autenticacion:
```
1. Recibe usuario y contrasena del mensaje
2. Verifica que el usuario no este ya conectado (evita sesiones duplicadas)
3. Compara credenciales contra USERS_DB
4. Si son validas:
   - Registra el socket en connectedClients y socketToUser
   - Envia LOGIN_OK al cliente
   - Hace broadcast a los demas: "alice se ha conectado"
5. Si son invalidas:
   - Envia LOGIN_FAIL con el motivo del error
```

**handleMessage** — Enrutamiento de mensajes:
```
1. Verifica que el remitente este autenticado (tiene sesion)
2. Genera un ID unico para el mensaje (ej: "a1b2c3d4")
3. Busca el socket del destinatario en connectedClients
4. Si el destinatario esta conectado:
   - Reenvia el mensaje al socket del destinatario
   - Envia ACK al remitente: "Mensaje [a1b2c3d4] entregado a bob"
5. Si el destinatario NO esta conectado:
   - Envia ERROR al remitente: "Usuario 'carlos' no esta conectado"
```

**handleDisconnect** — Limpieza al desconectarse:
```
1. Busca que usuario tenia ese socket
2. Elimina las entradas de ambos mapas
3. Notifica a los demas usuarios con broadcast
```

**broadcast** — Notificacion a todos:
```
1. Recorre todos los sockets en connectedClients
2. Envia el mensaje a todos EXCEPTO al usuario que origino el evento
```

---

### 4.3 client.ts — El cliente interactivo

El cliente combina dos flujos que ocurren simultaneamente:

#### A) Flujo de entrada del usuario (readline)

```typescript
const rl = readline.createInterface({
  input: process.stdin,   // Lee del teclado
  output: process.stdout, // Escribe en la pantalla
});
```

Cuando el usuario escribe un comando y presiona Enter:

```typescript
rl.on('line', (line) => {
  const input = line.trim();

  if (input.startsWith('/msg ')) {
    // Extraer destinatario y mensaje, enviar al servidor
    socket.write(serialize({
      type: MessageType.MESSAGE,
      from: username,
      to: destinatario,
      content: texto,
      timestamp: Date.now(),
    }));
  } else if (input === '/users') {
    // Pedir lista de usuarios al servidor
    socket.write(serialize({
      type: MessageType.USER_LIST,
      timestamp: Date.now(),
    }));
  } else if (input === '/quit') {
    socket.destroy();  // Cerrar conexion TCP
    process.exit(0);   // Terminar programa
  }
});
```

#### B) Flujo de datos del servidor (socket)

```typescript
socket.on('data', (data) => {
  // Parsear mensajes del servidor y mostrar en pantalla
  for (const msg of result.messages) {
    switch (msg.type) {
      case MessageType.LOGIN_OK:   // "Bienvenido, alice"
      case MessageType.MESSAGE:    // "De bob: Hola!"
      case MessageType.ACK:        // "Mensaje entregado a bob"
      case MessageType.ERROR:      // "Usuario no conectado"
      case MessageType.BROADCAST:  // "bob se ha conectado"
      // ... mostrar en pantalla con formato
    }
  }
});
```

#### C) Proceso de login

```typescript
function askLogin(): void {
  rl.question('  Usuario: ', (user) => {
    rl.question('  Contrasena: ', (pass) => {
      username = user.trim();
      socket.write(serialize({
        type: MessageType.LOGIN,
        from: username,
        content: pass.trim(),         // La contrasena va en "content"
        timestamp: Date.now(),
      }));
    });
  });
}
```

El login se solicita inmediatamente despues de conectar al servidor. Si las credenciales son incorrectas, el servidor responde `LOGIN_FAIL` y `askLogin()` se llama de nuevo.

---

## 5. Instalacion y preparacion

### Paso 5.1 — Verificar Node.js

Abrir una terminal y ejecutar:

```bash
node --version
```

Debe mostrar `v18.x.x` o superior. Si no esta instalado, descargar de https://nodejs.org

### Paso 5.2 — Navegar a la carpeta

```bash
cd network-simulation
```

### Paso 5.3 — Instalar dependencias

```bash
npm install
```

Esto instala:
- `tsx`: Ejecuta archivos TypeScript directamente sin compilar
- `typescript`: Compilador y verificador de tipos

La salida esperada es:

```
added 4 packages, and audited 5 packages in 2s
found 0 vulnerabilities
```

### Paso 5.4 — Verificar que compila

```bash
npx tsc --noEmit
```

Si no hay errores, el comando no imprime nada. Eso significa que todo el codigo esta correctamente tipado.

---

## 6. Ejecucion paso a paso

Se necesitan **3 terminales** abiertas simultaneamente, todas dentro de la carpeta `network-simulation/`.

---

### Paso 6.1 — Iniciar el servidor (Terminal 1)

```bash
npm run server
```

**Salida esperada:**

```
=========================================
   SERVIDOR DE CHAT - SIMULACION DE RED
=========================================
  Host:     127.0.0.1
  Puerto:   3500
  Usuarios: alice, bob, carlos
=========================================

[10:00:01] Servidor iniciado. Esperando conexiones...
```

**Que esta pasando:**
- El servidor creo un socket TCP con `net.createServer()`
- Ejecuto `server.listen(3500, '127.0.0.1')` para empezar a escuchar
- Ahora esta bloqueado esperando conexiones entrantes en el puerto 3500
- El servidor no hace nada mas hasta que un cliente se conecte

**Dejar esta terminal abierta.** El servidor debe seguir corriendo.

---

### Paso 6.2 — Conectar Cliente A: alice (Terminal 2)

Abrir una **segunda terminal** en la misma carpeta y ejecutar:

```bash
npm run client
```

**Salida esperada en el Cliente:**

```
  +-----------------------------------------+
  |  CLIENTE CHAT - SIMULACION DE RED       |
  +-----------------------------------------+
  |  Conectado a 127.0.0.1:3500             |
  +-----------------------------------------+

  Usuario:
```

**Que esta pasando:**
- El cliente ejecuto `socket.connect(3500, '127.0.0.1')` para conectar al servidor
- TCP realizo el handshake de 3 pasos (SYN -> SYN-ACK -> ACK) automaticamente
- La conexion se establecio exitosamente
- El cliente llama a `askLogin()` y espera que escribas el usuario

**En el Servidor (Terminal 1) aparecera:**

```
[10:00:05] Nueva conexion desde 127.0.0.1:52431
```

Esto confirma que el servidor detecto la nueva conexion TCP.

**Escribir las credenciales:**

```
  Usuario: alice
  Contrasena: alice123
```

**Salida esperada en el Cliente despues del login:**

```
  [10:00:08] [OK] Bienvenido, alice. Usuarios conectados: 1

  +-----------------------------------------+
  |  COMANDOS DISPONIBLES                   |
  +-----------------------------------------+
  |  /msg <usuario> <texto>  Enviar mensaje |
  |  /users                 Listar usuarios |
  |  /help                  Ver ayuda       |
  |  /quit                  Desconectarse   |
  +-----------------------------------------+

  [alice] >
```

**En el Servidor:**

```
[10:00:08] LOGIN OK: alice (1 usuarios conectados)
```

**Que paso internamente:**
1. El cliente envio: `{"type":"LOGIN","from":"alice","content":"alice123","timestamp":...}`
2. El servidor recibio el mensaje y ejecuto `handleLogin()`
3. El servidor comparo `USERS_DB["alice"]` con `"alice123"` -> coinciden
4. El servidor registro a alice en `connectedClients` y `socketToUser`
5. El servidor respondio: `{"type":"LOGIN_OK","content":"Bienvenido, alice..."}`
6. El cliente recibio el `LOGIN_OK`, cambio `isLoggedIn = true` y mostro el menu

---

### Paso 6.3 — Conectar Cliente B: bob (Terminal 3)

Abrir una **tercera terminal** y ejecutar:

```bash
npm run client
```

**Escribir las credenciales:**

```
  Usuario: bob
  Contrasena: bob123
```

**Salida en el Cliente B:**

```
  [10:00:15] [OK] Bienvenido, bob. Usuarios conectados: 2
```

**Salida en el Cliente A (notificacion automatica):**

```
  [10:00:15] [INFO] bob se ha conectado al servidor
```

**Salida en el Servidor:**

```
[10:00:12] Nueva conexion desde 127.0.0.1:52432
[10:00:15] LOGIN OK: bob (2 usuarios conectados)
```

**Que paso internamente:**
1. Bob se conecto y se autentico (mismo flujo que Alice)
2. El servidor ejecuto `broadcast("bob", "bob se ha conectado al servidor")`
3. La funcion `broadcast` recorrio `connectedClients`, encontro a alice y le envio un `BROADCAST`
4. El cliente de Alice recibio el `BROADCAST` y mostro `[INFO] bob se ha conectado al servidor`

---

### Paso 6.4 — Enviar mensaje de Alice a Bob

**En el Cliente A (Terminal 2), escribir:**

```
  [alice] > /msg bob Hola Bob, como estas?
```

**Salida en el Cliente A:**

```
  [10:00:20] [ACK] Mensaje [a1b2c3d4] entregado a bob
```

**Salida en el Cliente B:**

```
  [10:00:20] [DE alice] Hola Bob, como estas?
```

**Salida en el Servidor:**

```
[10:00:20] MENSAJE: alice -> bob: "Hola Bob, como estas?" [id:a1b2c3d4]
```

**Que paso internamente (paso a paso detallado):**

```
1. Alice escribe "/msg bob Hola Bob, como estas?" y presiona Enter

2. El cliente de Alice parsea el comando:
   - Destinatario: "bob"
   - Contenido: "Hola Bob, como estas?"

3. El cliente serializa y envia por TCP:
   {"type":"MESSAGE","from":"alice","to":"bob",
    "content":"Hola Bob, como estas?","timestamp":1716556820000}

4. El servidor recibe los bytes en el evento 'data' del socket de Alice

5. parseBuffer() extrae el mensaje JSON completo

6. switch(msg.type) despacha a handleMessage()

7. handleMessage() ejecuta:
   a. Verifica que Alice tiene sesion activa (socketToUser tiene su socket)
   b. Genera ID unico: "a1b2c3d4" (usando crypto.randomBytes)
   c. Busca "bob" en connectedClients -> encuentra el socket de Bob
   d. Escribe el MESSAGE en el socket de Bob (reenvio)
   e. Escribe el ACK en el socket de Alice (confirmacion)

8. El cliente de Bob recibe el MESSAGE y muestra:
   "[DE alice] Hola Bob, como estas?"

9. El cliente de Alice recibe el ACK y muestra:
   "[ACK] Mensaje [a1b2c3d4] entregado a bob"
```

---

### Paso 6.5 — Responder de Bob a Alice

**En el Cliente B (Terminal 3), escribir:**

```
  [bob] > /msg alice Todo bien! Estoy probando el chat
```

**Salida en el Cliente B:**

```
  [10:00:25] [ACK] Mensaje [e5f6a7b8] entregado a alice
```

**Salida en el Cliente A:**

```
  [10:00:25] [DE bob] Todo bien! Estoy probando el chat
```

**En el Servidor:**

```
[10:00:25] MENSAJE: bob -> alice: "Todo bien! Estoy probando el chat" [id:e5f6a7b8]
```

El flujo es identico al paso anterior pero en direccion inversa. Esto demuestra que la comunicacion es **bidireccional**.

---

### Paso 6.6 — Consultar usuarios conectados

**En cualquier cliente, escribir:**

```
  [alice] > /users
```

**Salida:**

```
  [10:00:28] [USUARIOS] alice, bob
```

**Que paso:**
1. El cliente envio `{"type":"USER_LIST","timestamp":...}`
2. El servidor ejecuto `handleUserList()` que lee las keys de `connectedClients`
3. El servidor respondio con la lista: `"alice, bob"`

---

### Paso 6.7 — Probar mensaje a usuario desconectado

**En el Cliente A, escribir:**

```
  [alice] > /msg carlos Estas ahi?
```

**Salida en el Cliente A:**

```
  [10:00:30] [ERROR] Usuario 'carlos' no esta conectado
```

**En el Servidor:**

```
[10:00:30] MENSAJE FALLIDO: alice -> carlos (no conectado)
```

**Que paso:**
1. El servidor busco "carlos" en `connectedClients`
2. Carlos no esta conectado, asi que el Map retorno `undefined`
3. El servidor envio un `ERROR` a Alice en lugar de un `ACK`
4. No se genero ID de mensaje porque el mensaje no fue entregado

---

### Paso 6.8 — Desconexion

**En el Cliente A, escribir:**

```
  [alice] > /quit
```

**Salida en el Cliente A:**

```
  Desconectando...
```

**Salida en el Cliente B:**

```
  [10:00:35] [INFO] alice se ha desconectado
```

**Salida en el Servidor:**

```
[10:00:35] LOGOUT: alice (1 usuarios conectados)
```

**Que paso:**
1. El cliente ejecuto `socket.destroy()` que cierra la conexion TCP (envia FIN)
2. El servidor detecto el cierre en el evento `'close'` del socket
3. El servidor ejecuto `handleDisconnect()`:
   - Elimino a alice de `connectedClients` y `socketToUser`
   - Ejecuto `broadcast()` para notificar a Bob
4. El cliente termino con `process.exit(0)`

---

### Paso 6.9 — Detener el servidor

En la Terminal 1, presionar `Ctrl + C` para detener el servidor.

---

## 7. Escenarios de prueba

### 7.1 Login con credenciales incorrectas

```
  Usuario: alice
  Contrasena: incorrecta
```

Resultado esperado:
```
  [FALLO] Credenciales invalidas
  Usuario:
```

El servidor rechaza el login y el cliente vuelve a pedir credenciales.

### 7.2 Login duplicado

Si Alice ya esta conectada en otra terminal e intentas conectar con "alice" de nuevo:

```
  [FALLO] El usuario 'alice' ya tiene una sesion activa
```

El servidor no permite dos sesiones con el mismo usuario.

### 7.3 Mensaje sin estar autenticado

Si un cliente envia un MESSAGE sin haber hecho login primero, el servidor responde:

```
  [ERROR] Debe iniciar sesion primero
```

### 7.4 Tres clientes simultaneos

Se pueden abrir 4 terminales (1 servidor + 3 clientes) usando alice, bob y carlos. Los tres pueden enviarse mensajes entre si y todos reciben las notificaciones de conexion/desconexion.

---

## 8. Resumen del flujo de comunicacion

### Diagrama completo de una sesion tipica

```
  TIEMPO   CLIENTE A (alice)        SERVIDOR                  CLIENTE B (bob)
  ======   =================        =================         =================

  t=0      --- TCP CONNECT -------> Acepta conexion
                                    Registra socket

  t=1      --- LOGIN ------------->
           {from:alice,             Valida credenciales
            content:alice123}       alice123 == alice123? SI

  t=2      <-- LOGIN_OK ---------- Agrega a connectedClients
           {content:Bienvenido}     connectedClients.size = 1

  t=3                               Acepta conexion         <--- TCP CONNECT
                                    Registra socket

  t=4                               Valida credenciales     <--- LOGIN
                                    bob123 == bob123? SI         {from:bob}

  t=5                               Agrega a connectedClients --> LOGIN_OK
                                    connectedClients.size = 2

  t=5      <-- BROADCAST --------- broadcast("bob se         (no se envia
           {content:bob conectado}  ha conectado")             a bob mismo)

  t=6      --- MESSAGE ----------->
           {from:alice,             generateId() = "a1b2c3d4"
            to:bob,                 Busca bob en Map -> EXISTE
            content:Hola}

  t=7                               Reenvia a bob -----------> MESSAGE
                                    {id:a1b2c3d4,               {id:a1b2c3d4,
                                     from:alice}                 from:alice,
                                                                 content:Hola}

  t=8      <-- ACK ---------------- Confirma entrega
           {id:a1b2c3d4,
            content:Entregado}

  t=9                                                          --- MESSAGE --->
                                                               {from:bob,
                                                                to:alice,
                                    <--- Recibe de bob ------   content:Hola!}

  t=10     <-- MESSAGE ------------ Reenvia a alice
           {from:bob,               generateId() = "e5f6a7b8"
            content:Hola!}

  t=11                              Confirma entrega ----------> ACK
                                                                {id:e5f6a7b8}

  t=12     --- TCP CLOSE --------->
           (socket.destroy)         Detecta cierre
                                    handleDisconnect()
                                    Elimina de Maps

  t=13                              broadcast("alice ----------> BROADCAST
                                    se ha desconectado")        {content:alice
                                                                 desconectada}
```

### Resumen de los 3 requisitos cumplidos

| Requisito | Como se demuestra | Mensajes involucrados |
|-----------|-------------------|-----------------------|
| **Inicio de sesion** | Cliente envia usuario/contrasena, servidor valida y responde OK o FAIL | `LOGIN` -> `LOGIN_OK` o `LOGIN_FAIL` |
| **Envio de mensajes** | Cliente A envia mensaje, servidor lo reenvia a Cliente B | `MESSAGE` (A->Server) -> `MESSAGE` (Server->B) |
| **Confirmacion de recepcion** | Servidor confirma al remitente que el mensaje fue entregado | `ACK` (Server->A) con el ID del mensaje |

---

## Creditos

- **Tecnologia**: Node.js + TypeScript
- **Protocolo de transporte**: TCP (modulo `net` de Node.js)
- **Formato de mensajes**: NDJSON (JSON delimitado por linea)
- **Interfaz**: CLI interactiva (modulo `readline` de Node.js)
