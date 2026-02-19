-- =============================================================================
-- AI Deal Flow Triage & Matching System — Supabase Schema
-- =============================================================================
-- Run this SQL in your Supabase SQL Editor to create the required tables.
-- These table definitions are inferred from the n8n workflow HTTP request bodies.
-- =============================================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- -----------------------------------------------------------------------------
-- 1. deals — Primary deal records
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS deals (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_name    TEXT NOT NULL,
    website         TEXT NOT NULL,
    sector          TEXT NOT NULL,
    stage           TEXT NOT NULL,
    geography       TEXT NOT NULL,
    raw_pitch       TEXT,
    normalized_payload JSONB,
    memo_json       JSONB,
    fit_score       INTEGER CHECK (fit_score >= 0 AND fit_score <= 100),
    fit_reasoning   TEXT,
    status          TEXT NOT NULL CHECK (status IN ('Qualified', 'Review', 'Pass', 'LLM_Error')),
    owner           TEXT,
    source_hash     TEXT NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Index for idempotency check (source_hash lookup)
CREATE INDEX IF NOT EXISTS idx_deals_source_hash ON deals (source_hash);

-- Index for duplicate detection (website lookup)
CREATE INDEX IF NOT EXISTS idx_deals_website ON deals (website);

-- -----------------------------------------------------------------------------
-- 2. event_logs — Full observability / audit trail
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS event_logs (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    deal_id     UUID REFERENCES deals(id) ON DELETE SET NULL,
    event_type  TEXT NOT NULL,
    source_hash TEXT,
    payload     JSONB,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Index for filtering by event type
CREATE INDEX IF NOT EXISTS idx_event_logs_event_type ON event_logs (event_type);

-- Index for filtering by deal
CREATE INDEX IF NOT EXISTS idx_event_logs_deal_id ON event_logs (deal_id);

-- -----------------------------------------------------------------------------
-- 3. notifications_queue — Outbound notification records
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notifications_queue (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    deal_id     UUID REFERENCES deals(id) ON DELETE SET NULL,
    channel     TEXT NOT NULL DEFAULT 'slack',
    message     TEXT NOT NULL,
    sent_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Index for unsent notifications
CREATE INDEX IF NOT EXISTS idx_notifications_queue_sent ON notifications_queue (sent_at)
    WHERE sent_at IS NULL;

-- -----------------------------------------------------------------------------
-- Row-Level Security (optional — recommended for production)
-- -----------------------------------------------------------------------------
-- ALTER TABLE deals ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE event_logs ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE notifications_queue ENABLE ROW LEVEL SECURITY;
--
-- Create policies as needed for your access patterns.
-- The service_role key used by n8n bypasses RLS by default.
