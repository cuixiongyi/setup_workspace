"""PostgreSQL access to exports.export_job."""


class ExportRepository:
    def __init__(self, pool):
        self.pool = pool

    def owner_of(self, export_id):
        with self.pool.connection() as conn:
            row = conn.execute("SELECT owner_id FROM exports.export_job WHERE id = %s", (export_id,)).fetchone()
            return row and row.owner_id

    def cancel(self, export_id):
        """End a queued export at once; ask a running one to stop. Repeating either is harmless."""
        with self.pool.connection() as conn, conn.transaction():
            job = conn.execute(
                "SELECT * FROM exports.export_job WHERE id = %s FOR UPDATE", (export_id,)
            ).fetchone()
            if job.state == "queued":
                return conn.execute(
                    "UPDATE exports.export_job SET state = 'cancelled', cancel_reason = 'not_started',"
                    " finished_at = now() WHERE id = %s RETURNING *", (export_id,)
                ).fetchone()
            if job.state == "running":
                return conn.execute(
                    "UPDATE exports.export_job SET stop_requested_at = coalesce(stop_requested_at, now())"
                    " WHERE id = %s RETURNING *", (export_id,)
                ).fetchone()
            return job

    def claim_next(self, worker_id):
        with self.pool.connection() as conn:
            return conn.execute(
                "UPDATE exports.export_job SET state = 'running', worker_id = %s, started_at = now()"
                " WHERE id = (SELECT id FROM exports.export_job WHERE state = 'queued'"
                " ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1) RETURNING *", (worker_id,)
            ).fetchone()

    def stop_requested(self, export_id):
        with self.pool.connection() as conn:
            row = conn.execute(
                "SELECT stop_requested_at FROM exports.export_job WHERE id = %s", (export_id,)
            ).fetchone()
            return row.stop_requested_at is not None

    def finish(self, export_id, state, cancel_reason=None):
        with self.pool.connection() as conn:
            return conn.execute(
                "UPDATE exports.export_job SET state = %s, cancel_reason = %s, finished_at = now()"
                " WHERE id = %s AND state = 'running' RETURNING *", (state, cancel_reason, export_id)
            ).fetchone()
