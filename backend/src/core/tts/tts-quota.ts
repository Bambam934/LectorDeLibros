/**
 * Cuota diaria de caracteres sintetizados por usuario (proveedores de pago).
 *
 * Sin ella, una cuenta gratuita podía pedir el audio de cada capítulo con
 * tantas voces como quisiera: cada combinación es una síntesis nueva que se
 * paga. En memoria y por proceso, como `realtime-bus`: un reinicio la pone a
 * cero, lo que como mucho duplica el gasto de un día; el día en que haya
 * varias réplicas pasa a la base de datos.
 */
export class TtsQuota {
  private used = new Map<string, number>();
  private day = '';

  constructor(
    private readonly dailyChars: number,
    private readonly now: () => Date = () => new Date()
  ) {}

  /** Reserva `chars` para el usuario; false si se pasaría del tope del día (UTC). */
  tryConsume(userId: string, chars: number): boolean {
    const today = this.now().toISOString().slice(0, 10);
    if (today !== this.day) {
      this.day = today;
      this.used.clear();
    }
    const current = this.used.get(userId) ?? 0;
    if (current + chars > this.dailyChars) return false;
    this.used.set(userId, current + chars);
    return true;
  }

  /** Devuelve una reserva cuya síntesis falló, para no cobrarla. */
  refund(userId: string, chars: number): void {
    const current = this.used.get(userId) ?? 0;
    this.used.set(userId, Math.max(0, current - chars));
  }
}

/**
 * Voces permitidas con un proveedor de pago: la lista configurada más la de
 * por defecto. Vacía = solo la de por defecto.
 */
export function allowedVoiceIds(list: string | undefined, defaultVoiceId: string | undefined): Set<string> {
  const ids = (list ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  if (defaultVoiceId) ids.push(defaultVoiceId);
  return new Set(ids);
}
