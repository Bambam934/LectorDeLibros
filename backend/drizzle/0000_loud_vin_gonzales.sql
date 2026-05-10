CREATE EXTENSION IF NOT EXISTS "pgcrypto";
--> statement-breakpoint
CREATE TABLE "books" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"title" varchar(500) NOT NULL,
	"author" varchar(500),
	"language" varchar(10) DEFAULT 'es' NOT NULL,
	"file_key" text,
	"file_format" varchar(10) DEFAULT 'epub' NOT NULL,
	"status" varchar(20) DEFAULT 'processing' NOT NULL,
	"total_words" integer,
	"total_chapters" integer,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "chapter_audio" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"chapter_id" uuid NOT NULL,
	"voice_id" varchar(100) NOT NULL,
	"tts_provider" varchar(50) NOT NULL,
	"audio_key" text NOT NULL,
	"duration_ms" integer NOT NULL,
	"word_timestamps" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "chapters" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"book_id" uuid NOT NULL,
	"title" varchar(500),
	"order_index" integer NOT NULL,
	"word_count" integer DEFAULT 0 NOT NULL,
	"text_content" text
);
--> statement-breakpoint
CREATE TABLE "reading_progress" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"book_id" uuid NOT NULL,
	"chapter_id" uuid,
	"word_index" integer DEFAULT 0 NOT NULL,
	"audio_position_ms" integer DEFAULT 0 NOT NULL,
	"percentage" double precision DEFAULT 0 NOT NULL,
	"last_read_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "users" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"email" varchar(255) NOT NULL,
	"name" varchar(255) NOT NULL,
	"plan" varchar(20) DEFAULT 'free' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "users_email_unique" UNIQUE("email")
);
--> statement-breakpoint
ALTER TABLE "books" ADD CONSTRAINT "books_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "chapter_audio" ADD CONSTRAINT "chapter_audio_chapter_id_chapters_id_fk" FOREIGN KEY ("chapter_id") REFERENCES "public"."chapters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "chapters" ADD CONSTRAINT "chapters_book_id_books_id_fk" FOREIGN KEY ("book_id") REFERENCES "public"."books"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "reading_progress" ADD CONSTRAINT "reading_progress_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "reading_progress" ADD CONSTRAINT "reading_progress_book_id_books_id_fk" FOREIGN KEY ("book_id") REFERENCES "public"."books"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_books_user_id" ON "books" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "idx_chapters_book_id" ON "chapters" USING btree ("book_id");--> statement-breakpoint
CREATE UNIQUE INDEX "uq_chapters_book_order" ON "chapters" USING btree ("book_id","order_index");--> statement-breakpoint
CREATE UNIQUE INDEX "uq_reading_progress_user_book" ON "reading_progress" USING btree ("user_id","book_id");--> statement-breakpoint
CREATE INDEX "idx_reading_progress_user_id" ON "reading_progress" USING btree ("user_id");