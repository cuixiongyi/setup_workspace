"""Export use cases. The service checks who may act; the repository owns state changes."""
from app.db.exports_repo import ExportRepository


class NotFound(Exception):
    pass


class ExportService:
    def __init__(self, repo: ExportRepository):
        self.repo = repo

    def cancel(self, export_id, user):
        self._require_owner(export_id, user)
        return self.repo.cancel(export_id)

    def _require_owner(self, export_id, user):
        # Another user's export answers NotFound, so the id leaks nothing.
        if self.repo.owner_of(export_id) != user.id:
            raise NotFound(export_id)
