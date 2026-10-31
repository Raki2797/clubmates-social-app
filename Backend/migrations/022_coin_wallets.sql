CREATE TABLE IF NOT EXISTS wallets (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  balance        INTEGER NOT NULL DEFAULT 0 CHECK (balance >= 0),
  bonus_balance  INTEGER NOT NULL DEFAULT 0,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS wallets_touch_updated_at ON wallets;
CREATE TRIGGER wallets_touch_updated_at
BEFORE UPDATE ON wallets
FOR EACH ROW
EXECUTE FUNCTION touch_updated_at();

CREATE TABLE IF NOT EXISTS coin_transactions (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type         TEXT NOT NULL CHECK (
    type IN ('purchase','welcome_bonus','invite_sent','invite_received','invite_refund','admin_credit','admin_debit')
  ),
  amount       INTEGER NOT NULL,
  balance_after INTEGER NOT NULL,
  reference_id UUID,
  metadata     JSONB,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_coin_tx_user_created
  ON coin_transactions(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS coin_packages (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug      TEXT NOT NULL UNIQUE,
  coins     INTEGER NOT NULL,
  price_inr INTEGER NOT NULL,
  bonus_pct INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  position  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS treat_pricing (
  treat_type      TEXT PRIMARY KEY,
  sender_cost     INTEGER NOT NULL,
  receiver_credit INTEGER NOT NULL,
  is_active       BOOLEAN NOT NULL DEFAULT true
);

ALTER TABLE treat_invites
  ADD COLUMN IF NOT EXISTS coin_tx_id UUID REFERENCES coin_transactions(id);

INSERT INTO coin_packages (slug, coins, price_inr, bonus_pct, is_active, position)
VALUES
  ('starter_pack',  100,  14900, 0, true, 1),
  ('popular_pack',  300,  42500, 0, true, 2),
  ('best_value',    600,  80500, 0, true, 3),
  ('whale_pack',   1500, 189900, 0, true, 4)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO treat_pricing (treat_type, sender_cost, receiver_credit, is_active)
VALUES
  ('coffee',   50,  40, true),
  ('dessert',  75,  60, true),
  ('starter', 100,  80, true),
  ('drink',   150, 120, true)
ON CONFLICT (treat_type) DO NOTHING;
