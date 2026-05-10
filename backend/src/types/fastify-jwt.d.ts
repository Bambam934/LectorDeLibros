import '@fastify/jwt';

declare module '@fastify/jwt' {
  interface FastifyJWT {
    payload: {
      sub: string;
      email: string;
      type: 'access' | 'refresh';
    };
    user: {
      sub: string;
      email: string;
      type: 'access' | 'refresh';
    };
  }
}
