CREATE TABLE "revoked_tokens" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"token_hash" varchar(64) NOT NULL,
	"user_id" uuid NOT NULL,
	"type" varchar(20) NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "revoked_tokens_token_hash_unique" UNIQUE("token_hash")
);
--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "password_hash" varchar(255);--> statement-breakpoint
ALTER TABLE "revoked_tokens" ADD CONSTRAINT "revoked_tokens_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_revoked_tokens_hash" ON "revoked_tokens" USING btree ("token_hash");--> statement-breakpoint
CREATE INDEX "idx_revoked_tokens_user_id" ON "revoked_tokens" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "idx_revoked_tokens_expires" ON "revoked_tokens" USING btree ("expires_at");