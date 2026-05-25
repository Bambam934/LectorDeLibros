import * as net from 'net';
import {
  MessageType,
  ProtocolMessage,
  serialize,
  parseBuffer,
  generateId,
  SERVER_PORT,
  SERVER_HOST,
} from './protocol';

// --- Base de datos simulada de usuarios ---
const USERS_DB: Record<string, string> = {
  alice: 'alice123',
  bob: 'bob123',
  carlos: 'carlos123',
};

// --- Estado del servidor ---
const connectedClients = new Map<string, net.Socket>();
const socketToUser = new Map<net.Socket, string>();

function timestamp(): string {
  return new Date().toLocaleTimeString('es-CR');
}

function log(msg: string): void {
  console.log(`[${timestamp()}] ${msg}`);
}

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

function handleLogin(socket: net.Socket, msg: ProtocolMessage): void {
  const user = msg.from;
  const password = msg.content;

  if (!user || !password) {
    socket.write(serialize({
      type: MessageType.LOGIN_FAIL,
      content: 'Usuario y contrasena requeridos',
      timestamp: Date.now(),
    }));
    return;
  }

  if (connectedClients.has(user)) {
    socket.write(serialize({
      type: MessageType.LOGIN_FAIL,
      content: `El usuario '${user}' ya tiene una sesion activa`,
      timestamp: Date.now(),
    }));
    return;
  }

  if (USERS_DB[user] !== password) {
    socket.write(serialize({
      type: MessageType.LOGIN_FAIL,
      content: 'Credenciales invalidas',
      timestamp: Date.now(),
    }));
    log(`Intento de login fallido: ${user}`);
    return;
  }

  connectedClients.set(user, socket);
  socketToUser.set(socket, user);

  socket.write(serialize({
    type: MessageType.LOGIN_OK,
    content: `Bienvenido, ${user}. Usuarios conectados: ${connectedClients.size}`,
    timestamp: Date.now(),
  }));

  broadcast(user, `${user} se ha conectado al servidor`);
  log(`LOGIN OK: ${user} (${connectedClients.size} usuarios conectados)`);
}

function handleMessage(socket: net.Socket, msg: ProtocolMessage): void {
  const fromUser = socketToUser.get(socket);
  if (!fromUser) {
    socket.write(serialize({
      type: MessageType.ERROR,
      content: 'Debe iniciar sesion primero',
      timestamp: Date.now(),
    }));
    return;
  }

  const { to, content } = msg;
  if (!to || !content) {
    socket.write(serialize({
      type: MessageType.ERROR,
      content: 'Destinatario y mensaje requeridos',
      timestamp: Date.now(),
    }));
    return;
  }

  const msgId = generateId();

  const targetSocket = connectedClients.get(to);
  if (!targetSocket) {
    socket.write(serialize({
      type: MessageType.ERROR,
      content: `Usuario '${to}' no esta conectado`,
      timestamp: Date.now(),
    }));
    log(`MENSAJE FALLIDO: ${fromUser} -> ${to} (no conectado)`);
    return;
  }

  // Entregar mensaje al destinatario
  targetSocket.write(serialize({
    type: MessageType.MESSAGE,
    id: msgId,
    from: fromUser,
    to,
    content,
    timestamp: Date.now(),
  }));

  // Confirmacion de recepcion (ACK) al remitente
  socket.write(serialize({
    type: MessageType.ACK,
    id: msgId,
    from: 'servidor',
    to: fromUser,
    content: `Mensaje [${msgId}] entregado a ${to}`,
    timestamp: Date.now(),
  }));

  log(`MENSAJE: ${fromUser} -> ${to}: "${content}" [id:${msgId}]`);
}

function handleUserList(socket: net.Socket): void {
  const users = Array.from(connectedClients.keys());
  socket.write(serialize({
    type: MessageType.USER_LIST,
    content: users.length > 0 ? users.join(', ') : '(ninguno)',
    timestamp: Date.now(),
  }));
}

function handleDisconnect(socket: net.Socket): void {
  const user = socketToUser.get(socket);
  if (user) {
    connectedClients.delete(user);
    socketToUser.delete(socket);
    broadcast(user, `${user} se ha desconectado`);
    log(`LOGOUT: ${user} (${connectedClients.size} usuarios conectados)`);
  }
}

// --- Crear servidor TCP ---
const server = net.createServer((socket) => {
  let buffer = '';
  const addr = `${socket.remoteAddress}:${socket.remotePort}`;
  log(`Nueva conexion desde ${addr}`);

  socket.on('data', (data) => {
    buffer += data.toString();
    const result = parseBuffer(buffer);
    buffer = result.remaining;

    for (const msg of result.messages) {
      switch (msg.type) {
        case MessageType.LOGIN:
          handleLogin(socket, msg);
          break;
        case MessageType.MESSAGE:
          handleMessage(socket, msg);
          break;
        case MessageType.USER_LIST:
          handleUserList(socket);
          break;
        default:
          socket.write(serialize({
            type: MessageType.ERROR,
            content: `Tipo de mensaje desconocido: ${msg.type}`,
            timestamp: Date.now(),
          }));
      }
    }
  });

  socket.on('close', () => handleDisconnect(socket));
  socket.on('error', (err) => {
    log(`Error de socket (${addr}): ${err.message}`);
    handleDisconnect(socket);
  });
});

server.listen(SERVER_PORT, SERVER_HOST, () => {
  console.log('');
  console.log('=========================================');
  console.log('   SERVIDOR DE CHAT - SIMULACION DE RED');
  console.log('=========================================');
  console.log(`  Host:     ${SERVER_HOST}`);
  console.log(`  Puerto:   ${SERVER_PORT}`);
  console.log(`  Usuarios: ${Object.keys(USERS_DB).join(', ')}`);
  console.log('=========================================');
  console.log('');
  log('Servidor iniciado. Esperando conexiones...');
});

server.on('error', (err) => {
  console.error(`Error del servidor: ${err.message}`);
  process.exit(1);
});
