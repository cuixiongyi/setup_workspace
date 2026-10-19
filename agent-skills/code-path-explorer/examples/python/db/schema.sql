CREATE SCHEMA exports;

CREATE TABLE exports.export_job (
  id uuid PRIMARY KEY,
  owner_id uuid NOT NULL,
  state text NOT NULL DEFAULT 'queued'
    CHECK (state IN ('queued', 'running', 'succeeded', 'failed', 'cancelled')),
  cancel_reason text CHECK (cancel_reason IN ('not_started', 'stopped')),
  worker_id text,
  stop_requested_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  finished_at timestamptz
);

CREATE TABLE exports.export_event (
  id bigserial PRIMARY KEY,
  export_id uuid NOT NULL REFERENCES exports.export_job (id),
  old_state text,
  new_state text NOT NULL,
  at timestamptz NOT NULL DEFAULT now()
);

CREATE FUNCTION exports.record_export_event() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO exports.export_event (export_id, old_state, new_state) VALUES (NEW.id, OLD.state, NEW.state);
  RETURN NEW;
END $$;

CREATE TRIGGER export_job_event AFTER UPDATE ON exports.export_job
  FOR EACH ROW EXECUTE FUNCTION exports.record_export_event();
