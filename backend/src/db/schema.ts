import {
  doublePrecision,
  index,
  integer,
  jsonb,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
  varchar
} from 'drizzle-orm/pg-core';

export const users = pgTable('users', {
  id: uuid('id').defaultRandom().primaryKey(),
  email: varchar('email', { length: 255 }).notNull().unique(),
  name: varchar('name', { length: 255 }).notNull(),
  passwordHash: varchar('password_hash', { length: 255 }),
  plan: varchar('plan', { length: 20 }).notNull().default('free'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow()
});

export const books = pgTable('books', {
  id: uuid('id').defaultRandom().primaryKey(),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  title: varchar('title', { length: 500 }).notNull(),
  author: varchar('author', { length: 500 }),
  language: varchar('language', { length: 10 }).notNull().default('es'),
  fileKey: text('file_key'),
  fileFormat: varchar('file_format', { length: 10 }).notNull().default('epub'),
  status: varchar('status', { length: 20 }).notNull().default('processing'),
  totalWords: integer('total_words'),
  totalChapters: integer('total_chapters'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow()
}, (table) => ({
  userIdx: index('idx_books_user_id').on(table.userId)
}));

export const chapters = pgTable('chapters', {
  id: uuid('id').defaultRandom().primaryKey(),
  bookId: uuid('book_id').notNull().references(() => books.id, { onDelete: 'cascade' }),
  title: varchar('title', { length: 500 }),
  orderIndex: integer('order_index').notNull(),
  wordCount: integer('word_count').notNull().default(0),
  textContent: text('text_content')
}, (table) => ({
  bookIdx: index('idx_chapters_book_id').on(table.bookId),
  bookOrderUq: uniqueIndex('uq_chapters_book_order').on(table.bookId, table.orderIndex)
}));

export const chapterAudio = pgTable('chapter_audio', {
  id: uuid('id').defaultRandom().primaryKey(),
  chapterId: uuid('chapter_id').notNull().references(() => chapters.id, { onDelete: 'cascade' }),
  voiceId: varchar('voice_id', { length: 100 }).notNull(),
  ttsProvider: varchar('tts_provider', { length: 50 }).notNull(),
  audioKey: text('audio_key').notNull(),
  durationMs: integer('duration_ms').notNull(),
  wordTimestamps: jsonb('word_timestamps').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow()
});

export const readingProgress = pgTable('reading_progress', {
  id: uuid('id').defaultRandom().primaryKey(),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  bookId: uuid('book_id').notNull().references(() => books.id, { onDelete: 'cascade' }),
  chapterId: uuid('chapter_id'),
  wordIndex: integer('word_index').notNull().default(0),
  audioPositionMs: integer('audio_position_ms').notNull().default(0),
  percentage: doublePrecision('percentage').notNull().default(0),
  lastReadAt: timestamp('last_read_at', { withTimezone: true }).notNull().defaultNow()
}, (table) => ({
  userBookUq: uniqueIndex('uq_reading_progress_user_book').on(table.userId, table.bookId),
  userIdx: index('idx_reading_progress_user_id').on(table.userId)
}));

export const revokedTokens = pgTable('revoked_tokens', {
  id: uuid('id').defaultRandom().primaryKey(),
  tokenHash: varchar('token_hash', { length: 64 }).notNull().unique(),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  type: varchar('type', { length: 20 }).notNull(),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow()
}, (table) => ({
  tokenHashIdx: index('idx_revoked_tokens_hash').on(table.tokenHash),
  userIdx: index('idx_revoked_tokens_user_id').on(table.userId),
  expiresIdx: index('idx_revoked_tokens_expires').on(table.expiresAt)
}));
