ALTER TABLE "Subscription"
ADD COLUMN "source" TEXT NOT NULL DEFAULT 'manual',
ADD COLUMN "sourceExternalId" TEXT,
ADD COLUMN "paymentMethodLabel" TEXT;

CREATE UNIQUE INDEX "Subscription_userId_source_sourceExternalId_key"
ON "Subscription"("userId", "source", "sourceExternalId");

ALTER TABLE "InstitutionConnection"
ADD CONSTRAINT "InstitutionConnection_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
