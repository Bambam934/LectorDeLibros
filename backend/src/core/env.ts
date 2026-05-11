import { z } from 'zod';

const isProduction = process.env.NODE_ENV === 'production';
const isTest = process.env.NODE_ENV === 'test';

const optionalString = z.preprocess(
	(val) => (typeof val === 'string' && val.trim() === '' ? undefined : val),
	z.string().min(1).optional()
);

const envSchema = z.object({
	NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
	PORT: z.coerce.number().int().positive().default(3000),
	HOST: z.string().min(1).default('127.0.0.1'),
	DATABASE_URL: isProduction
		? z.string().url('DATABASE_URL is required in production')
		: z.string().url().optional(),
	JWT_SECRET: isTest
		? z.string().min(1).default('test-secret-that-is-at-least-32-characters-long!!')
		: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
	RATE_LIMIT_MAX: z.coerce.number().int().positive().default(100),
	RATE_LIMIT_WINDOW: z.string().default('1 minute'),
	AUTH_RATE_LIMIT_MAX: z.coerce.number().int().positive().default(5),
	AUTH_RATE_LIMIT_WINDOW: z.string().default('15 minute'),
	NVIDIA_API_KEY: optionalString,
	NVIDIA_API_BASE_URL: z.string().url().default('https://integrate.api.nvidia.com/v1'),
	TTS_PROVIDER: z.enum(['elevenlabs', 'mock']).default('mock'),
	ELEVENLABS_API_KEY: optionalString,
	ELEVENLABS_DEFAULT_VOICE_ID: optionalString,
	CORS_ORIGINS: z.string().optional(),
	HELMET_ENABLED: z.coerce.number().int().min(0).max(1).default(1)
});

export const env = envSchema.parse(process.env);
