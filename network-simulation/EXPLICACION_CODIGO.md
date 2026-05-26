# Explicacion del Codigo — Paso a Paso Simplificado

---

## Como leer este documento

Cada bloque de codigo se muestra seguido de una explicacion en lenguaje simple.
Se usan analogias con situaciones cotidianas para que sea mas facil de entender.

---

## Antes de empezar: la analogia del restaurante

Toda la simulacion funciona como un **restaurante con mesero**:

```
Cliente A (Alice)  ←→  Mesero (Servidor)  ←→  Cliente B (Bob)
```

- Los **clientes** son las personas sentadas en las mesas. Piden cosas y reciben cosas.
- El **mesero** (servidor) es quien recibe los pedidos, los procesa y los entrega.
- Los clientes **nunca hablan directamente** entre si. Todo pasa por el mesero.

Ahora veamos como se traduce esto a codigo.

---

## Archivo 1: protocol.ts

### Para que sirve

Es el **menu del restaurante**. Define que cosas se pueden pedir, como se piden, y como se responde. Si el mesero y los clientes no tienen el mismo menu, no se entienden.

---

### Los tipos de mensaje

```typescript
export enum MessageType {
  LOGIN = 'LOGIN',
  LOGIN_OK = 'LOGIN_OK',
  LOGIN_FAIL = 'LOGIN_FAIL',
  MESSAGE = 'MESSAGE',
  ACK = 'ACK',
  ERROR = 'ERROR',
  USER_LIST = 'USER_LIST',
  BROADCAST = 'BROADCAST',
}
```

**Que hace:** Define las 8 "categorias" de mensajes que existen.

**Analogia:** Es como los tipos de pedido en un restaurante:

| Tipo | En el restaurante seria... |
|---|---|
| `LOGIN` | "Hola, tengo reservacion a nombre de Alice" |
| `LOGIN_OK` | "Bienvenida, su mesa esta lista" |
| `LOGIN_FAIL` | "Lo siento, no hay reservacion con ese nombre" |
| `MESSAGE` | "Por favor, llevele este postre a la mesa de Bob" |
| `ACK` | "Listo, Bob ya recibio el postre" |
| `ERROR` | "Lo siento, Bob ya se fue del restaurante" |
| `USER_LIST` | "Quienes estan en el restaurante ahora?" |
| `BROADCAST` | Anuncio por megafono: "Bob acaba de llegar" |

---

### La estructura de un mensaje

```typescript
export interface ProtocolMessage {
  type: MessageType;     // Que tipo de mensaje es (obligatorio)
  id?: string;           // Numero de seguimiento (opcional)
  from?: string;         // Quien lo envia (opcional)
  to?: string;           // Para quien es (opcional)
  content?: string;      // El contenido del mensaje (opcional)
  timestamp: number;     // Cuando se envio (obligatorio)
}
```

**Que hace:** Define la "forma" que tiene cada mensaje. Es como un formulario con campos.

**Analogia:** Es como un sobre de carta:

```
┌────────────────────────────────────┐
│  De: Alice              (from)     │
│  Para: Bob              (to)       │
│  Tipo: Mensaje          (type)     │
│  Numero: #a1b2c3d4      (id)      │
│  Fecha: 25/05/2026      (timestamp)│
│                                    │
│  "Hola Bob, como estas?"(content)  │
└────────────────────────────────────┘
```

No todos los sobres necesitan todos los campos. Un sobre de login no necesita "Para" porque va directo al servidor.

El signo `?` significa que ese campo es opcional (puede no incluirse).

---

### Puerto y direccion

```typescript
export const SERVER_PORT = 3500;
export const SERVER_HOST = '127.0.0.1';
```

**Que hace:** Define donde esta el servidor.

**Analogia:**
- `127.0.0.1` = la direccion del restaurante (en este caso, "tu misma computadora")
- `3500` = el numero de puerta por donde se entra

Tanto el servidor como los clientes usan estos mismos valores para encontrarse.

---

### Generar un identificador unico

```typescript
export function generateId(): string {
  return crypto.randomBytes(4).toString('hex');
}
```

**Que hace:** Crea un codigo unico de 8 letras/numeros (ejemplo: `"a1b2c3d4"`).

**Analogia:** Es como el numero de ticket que te dan cuando dejas ropa en la tintoreria. Sirve para identificar exactamente cual mensaje fue entregado.

**Como funciona:**
1. `crypto.randomBytes(4)` genera 4 bytes aleatorios
2. `.toString('hex')` los convierte a texto legible

---

### Empaquetar un mensaje para enviarlo

```typescript
export function serialize(msg: ProtocolMessage): string {
  return JSON.stringify(msg) + '\n';
}
```

**Que hace:** Convierte un mensaje (objeto de JavaScript) a texto plano para poder enviarlo por la red.

**Analogia:** Es como meter una carta en un sobre y sellarlo. La red no puede enviar "objetos", solo puede enviar texto (bytes).

**Ejemplo de lo que produce:**
```
Entrada: { type: "LOGIN", from: "alice", content: "alice123", timestamp: 123456 }
Salida:  '{"type":"LOGIN","from":"alice","content":"alice123","timestamp":123456}\n'
```

**Por que el `\n` al final?** Es un salto de linea que actua como separador. Si se envian dos mensajes seguidos, el `\n` permite saber donde termina uno y empieza el otro:

```
Mensaje 1: {"type":"LOGIN_OK",...}\n
Mensaje 2: {"type":"BROADCAST",...}\n
```

Sin el `\n` los mensajes se pegarian y seria imposible separarlos.

---

### Desempaquetar mensajes recibidos

```typescript
export function parseBuffer(buffer: string) {
  const lines = buffer.split('\n');
  const remaining = lines.pop() || '';
  const messages = [];

  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      messages.push(JSON.parse(line));
    } catch {
      // si una linea no se puede leer, se ignora
    }
  }

  return { messages, remaining };
}
```

**Que hace:** Recibe texto crudo de la red y extrae los mensajes completos.

**Por que es necesario?** La red a veces entrega los datos en pedazos. Imagina que el servidor envia 2 cartas, pero el cartero las entrega asi:

```
Entrega 1: [carta 1 completa] + [mitad de carta 2]
Entrega 2: [otra mitad de carta 2]
```

Sin esta funcion, la mitad de la carta 2 se perderia.

**Como lo resuelve paso a paso:**

```
Texto recibido: '{"type":"LOGIN_OK"}\n{"type":"BRO'
                 ──────────────────   ──────────────
                 mensaje completo     mensaje INCOMPLETO

Paso 1: split('\n') divide por saltos de linea
        → ['{"type":"LOGIN_OK"}', '{"type":"BRO']

Paso 2: pop() saca el ultimo elemento (puede estar incompleto)
        → remaining = '{"type":"BRO'

Paso 3: parsea las lineas completas con JSON.parse()
        → messages = [{ type: "LOGIN_OK" }]

Paso 4: retorna los mensajes completos + lo que quedo pendiente
        → { messages: [...], remaining: '{"type":"BRO' }
```

La proxima vez que lleguen datos, se concatenan con `remaining` y se vuelve a procesar. Asi se reconstruyen los mensajes que llegaron partidos.

---

## Archivo 2: server.ts

### Para que sirve

Es el **mesero del restaurante**. Espera que lleguen clientes, verifica sus reservaciones, y lleva mensajes de una mesa a otra.

---

### La "base de datos" de usuarios

```typescript
const USERS_DB = {
  alice: 'alice123',
  bob: 'bob123',
  carlos: 'carlos123',
};
```

**Que hace:** Lista de usuarios y sus contrasenas.

**Analogia:** Es el libro de reservaciones del restaurante. Si tu nombre esta ahi y dices la contrasena correcta, puedes entrar.

En una aplicacion real (como LectorSync) esto seria una base de datos PostgreSQL con contrasenas encriptadas. Aqui se simplifica para enfocarnos en la comunicacion.

---

### Registro de clientes conectados

```typescript
const connectedClients = new Map<string, net.Socket>();
const socketToUser = new Map<net.Socket, string>();
```

**Que hace:** Dos listas que el servidor mantiene para saber quien esta conectado.

**Analogia:** El mesero tiene dos libretas:

| Libreta 1 (`connectedClients`) | Libreta 2 (`socketToUser`) |
|---|---|
| "alice" → mesa 3 | mesa 3 → "alice" |
| "bob" → mesa 7 | mesa 7 → "bob" |

- **Libreta 1**: si alguien dice "enviale esto a alice", el mesero busca en que mesa esta
- **Libreta 2**: si una mesa se desocupa, el mesero busca quien estaba ahi para avisar a los demas

Se necesitan las dos porque a veces buscamos por nombre y a veces buscamos por mesa (socket).

---

### Notificar a todos (broadcast)

```typescript
function broadcast(fromUser: string, content: string): void {
  const msg = serialize({
    type: MessageType.BROADCAST,
    from: 'servidor',
    content,
    timestamp: Date.now(),
  });
  for (const [user, sock] of connectedClients) {
    if (user !== fromUser) {
      sock.write(msg);
    }
  }
}
```

**Que hace:** Envia un aviso a todos los clientes conectados, excepto al que causo el evento.

**Analogia:** El mesero anuncia por megafono "Bob acaba de llegar" a todas las mesas, menos a la de Bob (porque Bob ya sabe que llego).

**Paso a paso:**
1. Crea el mensaje una sola vez
2. Recorre la lista de clientes conectados
3. Si el cliente NO es el que origino el evento → le envia el aviso
4. `sock.write()` es como decirle algo a esa mesa especifica

---

### Proceso de login

```typescript
function handleLogin(socket, msg): void {
  const user = msg.from;       // quien quiere entrar
  const password = msg.content; // contrasena que dio
```

**Que hace:** El mesero recibe a alguien que quiere entrar al restaurante.

Luego hace 3 verificaciones:

```typescript
  // Verificacion 1: dio nombre y contrasena?
  if (!user || !password) {
    // "Necesito su nombre y contrasena para dejarlo pasar"
    socket.write(serialize({ type: MessageType.LOGIN_FAIL, ... }));
    return;
  }

  // Verificacion 2: ya hay alguien con ese nombre adentro?
  if (connectedClients.has(user)) {
    // "Ya hay un 'alice' adentro, no puede haber dos"
    socket.write(serialize({ type: MessageType.LOGIN_FAIL, ... }));
    return;
  }

  // Verificacion 3: la contrasena es correcta?
  if (USERS_DB[user] !== password) {
    // "La contrasena no coincide con nuestro registro"
    socket.write(serialize({ type: MessageType.LOGIN_FAIL, ... }));
    return;
  }
```

**Analogia:** El mesero revisa:
1. "Me dio su nombre y contrasena?" → si no, "vuelva a intentar"
2. "Ya hay alguien con ese nombre adentro?" → si si, "no puede entrar dos veces"
3. "La contrasena coincide con el libro de reservaciones?" → si no, "contrasena incorrecta"

Si pasa las 3 verificaciones:

```typescript
  // Registrar al usuario
  connectedClients.set(user, socket);  // anotar: "alice esta en mesa 3"
  socketToUser.set(socket, user);      // anotar: "mesa 3 es de alice"

  // Decirle que fue aceptada
  socket.write(serialize({ type: MessageType.LOGIN_OK, content: "Bienvenido, alice" }));

  // Avisar a todos los demas
  broadcast(user, "alice se ha conectado al servidor");
```

---

### Enviar un mensaje de un cliente a otro

```typescript
function handleMessage(socket, msg): void {
```

Esta funcion se ejecuta cuando un cliente quiere enviar un mensaje a otro. Es la funcion mas importante del servidor.

```typescript
  // Paso 1: Verificar que el remitente tiene sesion
  const fromUser = socketToUser.get(socket);
  if (!fromUser) {
    // "No puede enviar mensajes si no ha iniciado sesion"
    return;
  }
```

**Analogia:** El mesero verifica que la persona que pide algo realmente es un cliente del restaurante, no alguien que entro sin reservacion.

```typescript
  // Paso 2: Generar un numero de seguimiento
  const msgId = generateId();  // ejemplo: "a1b2c3d4"
```

**Analogia:** El mesero le pone un numero al pedido, como cuando pides comida a domicilio y te dan un numero de orden.

```typescript
  // Paso 3: Buscar al destinatario
  const targetSocket = connectedClients.get(to);
  if (!targetSocket) {
    // "Bob no esta en el restaurante, no puedo entregarle su mensaje"
    socket.write(serialize({ type: MessageType.ERROR, ... }));
    return;
  }
```

**Analogia:** Alice dice "llevale esto a Bob". El mesero busca en su libreta. Si Bob no esta, le dice a Alice "Bob no esta aqui".

```typescript
  // Paso 4: Entregar el mensaje a Bob
  targetSocket.write(serialize({
    type: MessageType.MESSAGE,
    id: msgId,
    from: fromUser,
    to,
    content,
    timestamp: Date.now(),
  }));
```

**Analogia:** El mesero camina hasta la mesa de Bob y le entrega el mensaje de Alice.

```typescript
  // Paso 5: Confirmar a Alice que fue entregado (ACK)
  socket.write(serialize({
    type: MessageType.ACK,
    id: msgId,
    content: `Mensaje [${msgId}] entregado a ${to}`,
    timestamp: Date.now(),
  }));
```

**Analogia:** El mesero vuelve a la mesa de Alice y le dice "listo, Bob ya recibio tu mensaje. El numero de su pedido era #a1b2c3d4".

**Flujo visual completo:**

```
Alice                    Mesero (Servidor)               Bob
  |                           |                            |
  |-- "dale esto a Bob" ----->|                            |
  |                           |--- "esto es de Alice" ---->|
  |                           |                            |
  |<-- "listo, entregado" ----|                            |
  |    (ACK #a1b2c3d4)       |                            |
```

---

### Cuando un cliente se desconecta

```typescript
function handleDisconnect(socket): void {
  const user = socketToUser.get(socket);  // buscar quien era
  if (user) {
    connectedClients.delete(user);         // borrar de libreta 1
    socketToUser.delete(socket);           // borrar de libreta 2
    broadcast(user, `${user} se ha desconectado`);  // avisar a todos
  }
}
```

**Analogia:** Una mesa se desocupa. El mesero:
1. Revisa en su libreta 2 quien estaba ahi → "era alice"
2. Borra a alice de ambas libretas
3. Anuncia por megafono "alice se fue del restaurante"

---

### Crear el servidor y empezar a escuchar

```typescript
const server = net.createServer((socket) => {
  let buffer = '';

  socket.on('data', (data) => {
    buffer += data.toString();
    const result = parseBuffer(buffer);
    buffer = result.remaining;

    for (const msg of result.messages) {
      switch (msg.type) {
        case MessageType.LOGIN:     handleLogin(socket, msg); break;
        case MessageType.MESSAGE:   handleMessage(socket, msg); break;
        case MessageType.USER_LIST: handleUserList(socket); break;
      }
    }
  });

  socket.on('close', () => handleDisconnect(socket));
});

server.listen(3500, '127.0.0.1');
```

**Que hace:** Crea el servidor y le dice que hacer cuando lleguen datos.

**Paso a paso simplificado:**

```
1. net.createServer() → "Abrir el restaurante"

2. Cada vez que llega un nuevo cliente (nueva conexion TCP):
   → Se crea un buffer vacio para ese cliente
   → Se registran los eventos:

3. socket.on('data') → "Cuando un cliente me diga algo":
   a. Agregar lo que dijo al buffer
   b. Extraer mensajes completos con parseBuffer()
   c. Para cada mensaje, ver que tipo es:
      - LOGIN?    → ejecutar handleLogin()
      - MESSAGE?  → ejecutar handleMessage()
      - USER_LIST? → ejecutar handleUserList()

4. socket.on('close') → "Cuando un cliente se vaya":
   → ejecutar handleDisconnect()

5. server.listen(3500) → "Abrir la puerta 3500 y empezar a atender"
```

El `switch` es como un recepcionista que lee el tipo de solicitud y la envia al departamento correcto.

---

## Archivo 3: client.ts

### Para que sirve

Es el **cliente del restaurante**. Se sienta en una mesa, da su nombre al mesero, y puede enviar/recibir mensajes.

---

### Variables del cliente

```typescript
let username = '';        // nombre del usuario (se llena al hacer login)
let isLoggedIn = false;   // ya inicio sesion? (empieza en "no")
let buffer = '';          // almacen temporal de datos de la red

const socket = new net.Socket();   // la conexion al servidor
```

**Analogia:**
- `username` → tu nombre en el restaurante
- `isLoggedIn` → "ya me dieron mesa?" (empieza en NO)
- `buffer` → una bandeja donde se acumulan los mensajes que van llegando del servidor
- `socket` → el telefono por el que hablas con el mesero

---

### Leer lo que el usuario escribe

```typescript
const rl = readline.createInterface({
  input: process.stdin,    // el teclado
  output: process.stdout,  // la pantalla
});
```

**Que hace:** Crea un "lector de teclado". Le permite al programa:
- Mostrar preguntas en la pantalla
- Esperar que el usuario escriba algo y presione Enter
- Capturar lo que escribio

---

### Proceso de login

```typescript
function askLogin(): void {
  rl.question('  Usuario: ', (user) => {
    rl.question('  Contrasena: ', (pass) => {
      username = user.trim();
      socket.write(serialize({
        type: MessageType.LOGIN,
        from: username,
        content: pass.trim(),
        timestamp: Date.now(),
      }));
    });
  });
}
```

**Que hace:** Pide usuario y contrasena, y los envia al servidor.

**Paso a paso:**

```
1. Muestra en pantalla: "Usuario: "
2. Espera que el usuario escriba algo (ejemplo: "alice") y presione Enter
3. Muestra en pantalla: "Contrasena: "
4. Espera que el usuario escriba algo (ejemplo: "alice123") y presione Enter
5. Empaqueta los datos en un mensaje LOGIN
6. Lo envia al servidor con socket.write()
```

**Que se envia por la red:**
```json
{"type":"LOGIN","from":"alice","content":"alice123","timestamp":1716692400000}
```

El servidor recibe esto, lo valida, y responde LOGIN_OK o LOGIN_FAIL. Esa respuesta la procesa la siguiente funcion.

---

### Recibir mensajes del servidor

```typescript
socket.on('data', (data) => {
  buffer += data.toString();
  const result = parseBuffer(buffer);
  buffer = result.remaining;

  for (const msg of result.messages) {
    handleServerMessage(msg);
  }
});
```

**Que hace:** Cada vez que el servidor envia algo, esta funcion se activa.

**Paso a paso:**
1. Llegan bytes del servidor
2. Se agregan al buffer (por si vienen datos parciales)
3. Se extraen los mensajes completos
4. Se procesa cada mensaje con `handleServerMessage()`

---

### Que hacer con cada tipo de respuesta

```typescript
function handleServerMessage(msg): void {
  switch (msg.type) {

    case MessageType.LOGIN_OK:
      // El servidor acepto mi login
      isLoggedIn = true;
      // Mostrar: "[OK] Bienvenido, alice"
      // Mostrar el menu de comandos
      break;

    case MessageType.LOGIN_FAIL:
      // El servidor rechazo mi login
      // Mostrar: "[FALLO] Credenciales invalidas"
      // Volver a pedir usuario y contrasena
      askLogin();
      break;

    case MessageType.MESSAGE:
      // Alguien me envio un mensaje
      // Mostrar: "[DE bob] Hola Alice!"
      break;

    case MessageType.ACK:
      // Mi mensaje fue entregado
      // Mostrar: "[ACK] Mensaje [a1b2c3d4] entregado a bob"
      break;

    case MessageType.ERROR:
      // Algo salio mal
      // Mostrar: "[ERROR] Usuario 'carlos' no esta conectado"
      break;

    case MessageType.BROADCAST:
      // Aviso general del servidor
      // Mostrar: "[INFO] bob se ha conectado al servidor"
      break;
  }
}
```

**Analogia:** Es como revisar el correo. Dependiendo del tipo de carta:
- Si es una confirmacion de reserva → guardar y celebrar
- Si es un rechazo → volver a intentar
- Si es un mensaje de alguien → leerlo
- Si es un recibo de entrega → saber que mi mensaje llego

---

### Procesar los comandos que escribe el usuario

```typescript
rl.on('line', (line) => {
  const input = line.trim();
```

Cada vez que el usuario escribe algo y presiona Enter, se ejecuta esta funcion.

```typescript
  if (input.startsWith('/msg ')) {
    // ENVIAR MENSAJE
    // Ejemplo: /msg bob Hola Bob!

    const rest = input.slice(5);        // quitar "/msg " → "bob Hola Bob!"
    const spaceIdx = rest.indexOf(' '); // encontrar el primer espacio → posicion 3
    const to = rest.slice(0, spaceIdx); // desde inicio hasta el espacio → "bob"
    const content = rest.slice(spaceIdx + 1); // despues del espacio → "Hola Bob!"

    socket.write(serialize({
      type: MessageType.MESSAGE,
      from: username,
      to: to,
      content: content,
      timestamp: Date.now(),
    }));
  }
```

**Paso a paso visual:**

```
El usuario escribe:  /msg bob Hola Bob!
                     ─────┬── ──┬─ ──────┬──
                     comando  a   contenido
                     (se quita) quien  del mensaje

slice(5) quita "/msg " →  "bob Hola Bob!"
indexOf(' ') encuentra espacio → posicion 3
slice(0,3) extrae destinatario → "bob"
slice(4) extrae mensaje → "Hola Bob!"
```

```typescript
  } else if (input === '/users') {
    // PEDIR LISTA DE USUARIOS
    socket.write(serialize({
      type: MessageType.USER_LIST,
      timestamp: Date.now(),
    }));

  } else if (input === '/quit') {
    // SALIR
    socket.destroy();  // cerrar la conexion
    rl.close();        // cerrar el lector de teclado
    process.exit(0);   // terminar el programa
  }
```

- `/users` → le pide al servidor la lista de quien esta conectado
- `/quit` → cierra todo y termina

---

### Conectar al servidor

```typescript
socket.connect(SERVER_PORT, SERVER_HOST, () => {
  // Esta funcion se ejecuta cuando la conexion fue exitosa
  console.log('  Conectado a 127.0.0.1:3500');
  askLogin();  // pedir credenciales inmediatamente
});
```

**Que hace:** Le dice al programa "conectate al servidor en la direccion 127.0.0.1, puerta 3500".

**Analogia:** "Llegar al restaurante y tocar la puerta". Cuando el mesero abre (conexion exitosa), lo primero que hace es pedir tu nombre y reservacion (askLogin).

```typescript
socket.on('error', (err) => {
  console.error('  Error de conexion: ' + err.message);
  console.error('  Asegurese de que el servidor este ejecutandose.');
  process.exit(1);
});
```

Si el servidor no esta corriendo, `socket.connect()` falla. Este manejador de error muestra un mensaje claro: "asegurese de que el servidor este ejecutandose".

**Analogia:** "Llegaste al restaurante pero esta cerrado".

---

## Resumen: como fluyen los datos

```
PASO 1 — ARRANCAR EL SERVIDOR
  server.ts:  net.createServer() + server.listen(3500)
  Resultado:  El servidor esta esperando en la puerta 3500

PASO 2 — ALICE SE CONECTA
  client.ts:  socket.connect(3500)
  server.ts:  detecta nueva conexion, crea buffer para Alice
  client.ts:  pide usuario y contrasena

PASO 3 — ALICE HACE LOGIN
  client.ts:  envia {"type":"LOGIN","from":"alice","content":"alice123"}
  server.ts:  recibe → parseBuffer → handleLogin()
              verifica contrasena → correcta
              guarda en connectedClients: "alice" → socket
              envia {"type":"LOGIN_OK","content":"Bienvenido"}
  client.ts:  recibe LOGIN_OK → isLoggedIn = true → muestra menu

PASO 4 — BOB SE CONECTA Y HACE LOGIN
  (mismo flujo que Alice)
  server.ts:  broadcast a Alice → "bob se ha conectado"
  Alice ve:   [INFO] bob se ha conectado al servidor

PASO 5 — ALICE ENVIA MENSAJE A BOB
  Alice escribe: /msg bob Hola Bob!
  client.ts:  parsea comando → to="bob", content="Hola Bob!"
              envia {"type":"MESSAGE","from":"alice","to":"bob","content":"Hola Bob!"}
  server.ts:  recibe → parseBuffer → handleMessage()
              genera id: "a1b2c3d4"
              busca socket de bob → lo encuentra
              envia a Bob:   {"type":"MESSAGE","from":"alice","content":"Hola Bob!"}
              envia a Alice: {"type":"ACK","id":"a1b2c3d4","content":"entregado a bob"}
  Bob ve:     [DE alice] Hola Bob!
  Alice ve:   [ACK] Mensaje [a1b2c3d4] entregado a bob

PASO 6 — ALICE SE DESCONECTA
  Alice escribe: /quit
  client.ts:  socket.destroy() → cierra conexion TCP
  server.ts:  detecta close → handleDisconnect()
              borra de connectedClients y socketToUser
              broadcast a Bob → "alice se ha desconectado"
  Bob ve:     [INFO] alice se ha desconectado
```

---

## Los 3 archivos en una frase

| Archivo | Que es | Que hace |
|---|---|---|
| `protocol.ts` | El idioma comun | Define como se ven los mensajes y como se empacan/desempacan |
| `server.ts` | El mesero | Recibe clientes, verifica identidad, lleva mensajes entre mesas |
| `client.ts` | El cliente | Se sienta, da su nombre, envia y recibe mensajes |
