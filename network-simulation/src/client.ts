import * as net from 'net';
import * as readline from 'readline';
import {
  MessageType,
  ProtocolMessage,
  serialize,
  parseBuffer,
  SERVER_PORT,
  SERVER_HOST,
} from './protocol';

// --- Estado del cliente ---
let username = '';
let isLoggedIn = false;
let buffer = '';

const socket = new net.Socket();

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

function timestamp(): string {
  return new Date().toLocaleTimeString('es-CR');
}

function printMsg(prefix: string, msg: string): void {
  process.stdout.clearLine?.(0);
  process.stdout.cursorTo?.(0);
  console.log(`  [${timestamp()}] ${prefix} ${msg}`);
  if (isLoggedIn) {
    showPrompt();
  }
}

function showPrompt(): void {
  rl.setPrompt(`  [${username}] > `);
  rl.prompt();
}

function showHelp(): void {
  console.log('');
  console.log('  +-----------------------------------------+');
  console.log('  |  COMANDOS DISPONIBLES                   |');
  console.log('  +-----------------------------------------+');
  console.log('  |  /msg <usuario> <texto>  Enviar mensaje |');
  console.log('  |  /users                 Listar usuarios |');
  console.log('  |  /help                  Ver ayuda       |');
  console.log('  |  /quit                  Desconectarse   |');
  console.log('  +-----------------------------------------+');
  console.log('');
}

// --- Manejar mensajes del servidor ---
function handleServerMessage(msg: ProtocolMessage): void {
  switch (msg.type) {
    case MessageType.LOGIN_OK:
      isLoggedIn = true;
      printMsg('[OK]', msg.content || 'Sesion iniciada');
      showHelp();
      showPrompt();
      break;

    case MessageType.LOGIN_FAIL:
      printMsg('[FALLO]', msg.content || 'Error de autenticacion');
      askLogin();
      break;

    case MessageType.MESSAGE:
      printMsg(`[DE ${msg.from}]`, msg.content || '');
      break;

    case MessageType.ACK:
      printMsg('[ACK]', msg.content || 'Entregado');
      break;

    case MessageType.ERROR:
      printMsg('[ERROR]', msg.content || 'Error desconocido');
      break;

    case MessageType.USER_LIST:
      printMsg('[USUARIOS]', msg.content || '(ninguno)');
      break;

    case MessageType.BROADCAST:
      printMsg('[INFO]', msg.content || '');
      break;
  }
}

socket.on('data', (data) => {
  buffer += data.toString();
  const result = parseBuffer(buffer);
  buffer = result.remaining;

  for (const msg of result.messages) {
    handleServerMessage(msg);
  }
});

// --- Login interactivo ---
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

// --- Procesar comandos del usuario ---
rl.on('line', (line) => {
  const input = line.trim();
  if (!input) {
    showPrompt();
    return;
  }

  if (input.startsWith('/msg ')) {
    const rest = input.slice(5);
    const spaceIdx = rest.indexOf(' ');
    if (spaceIdx === -1) {
      console.log('  Uso: /msg <usuario> <mensaje>');
    } else {
      const to = rest.slice(0, spaceIdx);
      const content = rest.slice(spaceIdx + 1);
      socket.write(serialize({
        type: MessageType.MESSAGE,
        from: username,
        to,
        content,
        timestamp: Date.now(),
      }));
    }
  } else if (input === '/users') {
    socket.write(serialize({
      type: MessageType.USER_LIST,
      timestamp: Date.now(),
    }));
  } else if (input === '/help') {
    showHelp();
  } else if (input === '/quit') {
    console.log('  Desconectando...');
    socket.destroy();
    rl.close();
    process.exit(0);
  } else {
    console.log('  Comando desconocido. Escriba /help para ver comandos.');
  }

  showPrompt();
});

// --- Conectar al servidor ---
socket.connect(SERVER_PORT, SERVER_HOST, () => {
  console.log('');
  console.log('  +-----------------------------------------+');
  console.log('  |  CLIENTE CHAT - SIMULACION DE RED       |');
  console.log('  +-----------------------------------------+');
  console.log(`  |  Conectado a ${SERVER_HOST}:${SERVER_PORT}          |`);
  console.log('  +-----------------------------------------+');
  console.log('');
  askLogin();
});

socket.on('close', () => {
  console.log('\n  Conexion cerrada por el servidor.');
  process.exit(0);
});

socket.on('error', (err) => {
  console.error(`\n  Error de conexion: ${err.message}`);
  console.error('  Asegurese de que el servidor este ejecutandose.');
  process.exit(1);
});
