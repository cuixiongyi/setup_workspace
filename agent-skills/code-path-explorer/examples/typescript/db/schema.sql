CREATE SCHEMA shop;

CREATE TABLE shop.orders (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL,
  amount integer NOT NULL CHECK (amount > 0),
  state text NOT NULL DEFAULT 'cart'
    CHECK (state IN ('cart', 'awaiting_payment', 'paid', 'expired', 'refunded')),
  provider_payment_id text UNIQUE,
  payment_started_at timestamptz,
  paid_at timestamptz
);

CREATE TABLE shop.webhook_events (
  event_id text PRIMARY KEY,
  received_at timestamptz NOT NULL DEFAULT now()
);
