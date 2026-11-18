import '@fastify/jwt';

declare module '@fastify/jwt' {
  interface FastifyJWT {
    payload: {
      sub: string;
      email: string;
      type: 'access' | 'refresh';
      /** Id único: dos tokens emitidos en el mismo segundo no son iguales. */
      jti?: string;
    };
    user: {
      sub: string;
      email: string;
      type: 'access' | 'refresh';
      jti?: string;
      /** Segundos Unix; lo añade el firmador. */
      exp?: number;
    };
  }
}
