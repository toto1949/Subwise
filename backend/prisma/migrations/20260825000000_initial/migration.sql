-- CreateEnum
CREATE TYPE "BillingFrequency" AS ENUM ('WEEKLY', 'BIWEEKLY', 'MONTHLY', 'QUARTERLY', 'SEMIANNUAL', 'YEARLY', 'IRREGULAR');

-- CreateEnum
CREATE TYPE "SubscriptionStatus" AS ENUM ('ACTIVE', 'TRIAL', 'NEEDS_REVIEW', 'CANCELLED');

-- CreateEnum
CREATE TYPE "SavingsStatus" AS ENUM ('PROPOSED', 'ACCEPTED', 'IN_PROGRESS', 'COMPLETED', 'USER_VERIFIED', 'FAILED', 'DISMISSED');

-- CreateEnum
CREATE TYPE "HouseholdSharingMode" AS ENUM ('OPTIMIZATION_ONLY', 'SERVICE_NAME', 'SERVICE_AND_PRICE');

-- CreateTable
CREATE TABLE "User" (
    "id" UUID NOT NULL,
    "appleSubject" TEXT NOT NULL,
    "email" TEXT,
    "displayName" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "UserSession" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "refreshTokenHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "UserSession_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Household" (
    "id" UUID NOT NULL,
    "ownerId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Household_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "HouseholdMember" (
    "id" UUID NOT NULL,
    "householdId" UUID NOT NULL,
    "userId" UUID,
    "invitedEmail" TEXT,
    "displayName" TEXT NOT NULL,
    "sharingMode" "HouseholdSharingMode" NOT NULL DEFAULT 'OPTIMIZATION_ONLY',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "HouseholdMember_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Merchant" (
    "id" UUID NOT NULL,
    "canonicalName" TEXT NOT NULL,
    "domain" TEXT,
    "category" TEXT NOT NULL,
    "logoUrl" TEXT,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Merchant_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MerchantAlias" (
    "id" UUID NOT NULL,
    "merchantId" UUID NOT NULL,
    "rawAlias" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MerchantAlias_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MerchantPlan" (
    "id" UUID NOT NULL,
    "merchantId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "frequency" "BillingFrequency" NOT NULL,
    "priceCents" INTEGER NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "planType" TEXT NOT NULL,
    "householdSize" INTEGER,
    "eligibilityType" TEXT,
    "sourceUrl" TEXT,
    "verifiedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MerchantPlan_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MerchantBenefit" (
    "id" UUID NOT NULL,
    "merchantId" UUID NOT NULL,
    "provider" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "eligibilityRequirements" TEXT NOT NULL,
    "sourceUrl" TEXT NOT NULL,
    "verifiedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MerchantBenefit_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MerchantAlternative" (
    "id" UUID NOT NULL,
    "sourceMerchantId" UUID NOT NULL,
    "alternativeMerchantId" UUID NOT NULL,
    "rationale" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MerchantAlternative_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Subscription" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "merchantId" UUID,
    "rawMerchantName" TEXT NOT NULL,
    "displayName" TEXT NOT NULL,
    "planName" TEXT,
    "amountCents" INTEGER NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "frequency" "BillingFrequency" NOT NULL,
    "nextRenewalAt" TIMESTAMP(3),
    "status" "SubscriptionStatus" NOT NULL DEFAULT 'ACTIVE',
    "category" TEXT NOT NULL,
    "valueScore" INTEGER,
    "usage" TEXT NOT NULL DEFAULT 'unknown',
    "isImportant" BOOLEAN NOT NULL DEFAULT false,
    "detectedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Subscription_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RecurringTransaction" (
    "id" UUID NOT NULL,
    "subscriptionId" UUID NOT NULL,
    "externalId" TEXT,
    "rawMerchantName" TEXT NOT NULL,
    "amountCents" INTEGER NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "transactedAt" TIMESTAMP(3) NOT NULL,
    "confidence" DOUBLE PRECISION NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "RecurringTransaction_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "InstitutionConnection" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "providerItemId" TEXT NOT NULL,
    "encryptedAccessToken" TEXT NOT NULL,
    "institutionName" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'active',
    "cursor" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InstitutionConnection_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CancellationGuide" (
    "id" UUID NOT NULL,
    "merchantId" UUID NOT NULL,
    "cancellationUrl" TEXT NOT NULL,
    "difficulty" TEXT NOT NULL,
    "estimatedMinutes" INTEGER NOT NULL,
    "verifiedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CancellationGuide_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CancellationStep" (
    "id" UUID NOT NULL,
    "guideId" UUID NOT NULL,
    "sequence" INTEGER NOT NULL,
    "instruction" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CancellationStep_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Recommendation" (
    "id" UUID NOT NULL,
    "subscriptionId" UUID,
    "type" TEXT NOT NULL,
    "estimatedMonthlySavingsCents" INTEGER NOT NULL,
    "estimatedAnnualSavingsCents" INTEGER NOT NULL,
    "confidence" DOUBLE PRECISION NOT NULL,
    "effortMinutes" INTEGER NOT NULL,
    "reasonCodes" JSONB NOT NULL,
    "explanation" TEXT NOT NULL,
    "status" "SavingsStatus" NOT NULL DEFAULT 'PROPOSED',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Recommendation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "OptimizationPlan" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "currentMonthlyCents" INTEGER NOT NULL,
    "projectedMonthlyCents" INTEGER NOT NULL,
    "status" "SavingsStatus" NOT NULL DEFAULT 'PROPOSED',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "OptimizationPlan_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "OptimizationAction" (
    "id" UUID NOT NULL,
    "planId" UUID NOT NULL,
    "recommendationId" UUID NOT NULL,
    "sequence" INTEGER NOT NULL,
    "status" "SavingsStatus" NOT NULL DEFAULT 'PROPOSED',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "OptimizationAction_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SavingsEvent" (
    "id" UUID NOT NULL,
    "subscriptionId" UUID NOT NULL,
    "recommendationId" UUID,
    "action" TEXT NOT NULL,
    "estimatedAnnualSavingsCents" INTEGER NOT NULL,
    "verifiedAnnualSavingsCents" INTEGER,
    "status" "SavingsStatus" NOT NULL DEFAULT 'PROPOSED',
    "completedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SavingsEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Trial" (
    "id" UUID NOT NULL,
    "subscriptionId" UUID NOT NULL,
    "endsAt" TIMESTAMP(3) NOT NULL,
    "renewalPriceCents" INTEGER NOT NULL,
    "frequency" "BillingFrequency" NOT NULL,
    "source" TEXT NOT NULL,
    "extractionConfidence" DOUBLE PRECISION,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Trial_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "NotificationPreference" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "reminderDays" INTEGER[] DEFAULT ARRAY[7, 3, 1]::INTEGER[],
    "renewalAlerts" BOOLEAN NOT NULL DEFAULT true,
    "priceAlerts" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "NotificationPreference_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PriceObservation" (
    "id" UUID NOT NULL,
    "subscriptionId" UUID NOT NULL,
    "amountCents" INTEGER NOT NULL,
    "observedAt" TIMESTAMP(3) NOT NULL,
    "source" TEXT NOT NULL,
    "confirmedIncrease" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PriceObservation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AIConversation" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "title" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AIConversation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AIMessage" (
    "id" UUID NOT NULL,
    "conversationId" UUID NOT NULL,
    "role" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "requestId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AIMessage_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "EligibilityProfile" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "student" BOOLEAN NOT NULL DEFAULT false,
    "educator" BOOLEAN NOT NULL DEFAULT false,
    "military" BOOLEAN NOT NULL DEFAULT false,
    "healthcareWorker" BOOLEAN NOT NULL DEFAULT false,
    "employerBenefits" JSONB,
    "universityBenefits" JSONB,
    "verifiedAttributes" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "EligibilityProfile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AuditEvent" (
    "id" UUID NOT NULL,
    "userId" UUID,
    "operation" TEXT NOT NULL,
    "entityType" TEXT,
    "entityId" TEXT,
    "requestId" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AuditEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "WebhookEvent" (
    "id" UUID NOT NULL,
    "provider" TEXT NOT NULL,
    "externalId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'received',
    "processedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "WebhookEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_appleSubject_key" ON "User"("appleSubject");

-- CreateIndex
CREATE INDEX "UserSession_userId_idx" ON "UserSession"("userId");

-- CreateIndex
CREATE INDEX "Household_ownerId_idx" ON "Household"("ownerId");

-- CreateIndex
CREATE UNIQUE INDEX "HouseholdMember_householdId_userId_key" ON "HouseholdMember"("householdId", "userId");

-- CreateIndex
CREATE UNIQUE INDEX "Merchant_canonicalName_key" ON "Merchant"("canonicalName");

-- CreateIndex
CREATE UNIQUE INDEX "MerchantAlias_rawAlias_key" ON "MerchantAlias"("rawAlias");

-- CreateIndex
CREATE UNIQUE INDEX "MerchantAlternative_sourceMerchantId_alternativeMerchantId_key" ON "MerchantAlternative"("sourceMerchantId", "alternativeMerchantId");

-- CreateIndex
CREATE INDEX "Subscription_userId_status_idx" ON "Subscription"("userId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "RecurringTransaction_externalId_key" ON "RecurringTransaction"("externalId");

-- CreateIndex
CREATE UNIQUE INDEX "InstitutionConnection_providerItemId_key" ON "InstitutionConnection"("providerItemId");

-- CreateIndex
CREATE INDEX "InstitutionConnection_userId_idx" ON "InstitutionConnection"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "CancellationGuide_merchantId_key" ON "CancellationGuide"("merchantId");

-- CreateIndex
CREATE UNIQUE INDEX "CancellationStep_guideId_sequence_key" ON "CancellationStep"("guideId", "sequence");

-- CreateIndex
CREATE UNIQUE INDEX "OptimizationAction_planId_recommendationId_key" ON "OptimizationAction"("planId", "recommendationId");

-- CreateIndex
CREATE UNIQUE INDEX "Trial_subscriptionId_key" ON "Trial"("subscriptionId");

-- CreateIndex
CREATE UNIQUE INDEX "NotificationPreference_userId_key" ON "NotificationPreference"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "EligibilityProfile_userId_key" ON "EligibilityProfile"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "WebhookEvent_provider_externalId_key" ON "WebhookEvent"("provider", "externalId");

-- AddForeignKey
ALTER TABLE "UserSession" ADD CONSTRAINT "UserSession_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Household" ADD CONSTRAINT "Household_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "HouseholdMember" ADD CONSTRAINT "HouseholdMember_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "Household"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "HouseholdMember" ADD CONSTRAINT "HouseholdMember_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MerchantAlias" ADD CONSTRAINT "MerchantAlias_merchantId_fkey" FOREIGN KEY ("merchantId") REFERENCES "Merchant"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MerchantPlan" ADD CONSTRAINT "MerchantPlan_merchantId_fkey" FOREIGN KEY ("merchantId") REFERENCES "Merchant"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MerchantBenefit" ADD CONSTRAINT "MerchantBenefit_merchantId_fkey" FOREIGN KEY ("merchantId") REFERENCES "Merchant"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MerchantAlternative" ADD CONSTRAINT "MerchantAlternative_sourceMerchantId_fkey" FOREIGN KEY ("sourceMerchantId") REFERENCES "Merchant"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MerchantAlternative" ADD CONSTRAINT "MerchantAlternative_alternativeMerchantId_fkey" FOREIGN KEY ("alternativeMerchantId") REFERENCES "Merchant"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Subscription" ADD CONSTRAINT "Subscription_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Subscription" ADD CONSTRAINT "Subscription_merchantId_fkey" FOREIGN KEY ("merchantId") REFERENCES "Merchant"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RecurringTransaction" ADD CONSTRAINT "RecurringTransaction_subscriptionId_fkey" FOREIGN KEY ("subscriptionId") REFERENCES "Subscription"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CancellationGuide" ADD CONSTRAINT "CancellationGuide_merchantId_fkey" FOREIGN KEY ("merchantId") REFERENCES "Merchant"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CancellationStep" ADD CONSTRAINT "CancellationStep_guideId_fkey" FOREIGN KEY ("guideId") REFERENCES "CancellationGuide"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Recommendation" ADD CONSTRAINT "Recommendation_subscriptionId_fkey" FOREIGN KEY ("subscriptionId") REFERENCES "Subscription"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OptimizationPlan" ADD CONSTRAINT "OptimizationPlan_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OptimizationAction" ADD CONSTRAINT "OptimizationAction_planId_fkey" FOREIGN KEY ("planId") REFERENCES "OptimizationPlan"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OptimizationAction" ADD CONSTRAINT "OptimizationAction_recommendationId_fkey" FOREIGN KEY ("recommendationId") REFERENCES "Recommendation"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SavingsEvent" ADD CONSTRAINT "SavingsEvent_subscriptionId_fkey" FOREIGN KEY ("subscriptionId") REFERENCES "Subscription"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SavingsEvent" ADD CONSTRAINT "SavingsEvent_recommendationId_fkey" FOREIGN KEY ("recommendationId") REFERENCES "Recommendation"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Trial" ADD CONSTRAINT "Trial_subscriptionId_fkey" FOREIGN KEY ("subscriptionId") REFERENCES "Subscription"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "NotificationPreference" ADD CONSTRAINT "NotificationPreference_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PriceObservation" ADD CONSTRAINT "PriceObservation_subscriptionId_fkey" FOREIGN KEY ("subscriptionId") REFERENCES "Subscription"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AIConversation" ADD CONSTRAINT "AIConversation_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AIMessage" ADD CONSTRAINT "AIMessage_conversationId_fkey" FOREIGN KEY ("conversationId") REFERENCES "AIConversation"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "EligibilityProfile" ADD CONSTRAINT "EligibilityProfile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AuditEvent" ADD CONSTRAINT "AuditEvent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
