"""HTTP routes for exports."""
from fastapi import APIRouter, Depends, HTTPException, Response

from app.auth import current_user
from app.services.exports import ExportService, NotFound

router = APIRouter()


@router.post("/exports/{export_id}/cancel")
def cancel_export(export_id: str, response: Response, user=Depends(current_user), service: ExportService = Depends()):
    try:
        job = service.cancel(export_id, user)
    except NotFound:
        raise HTTPException(status_code=404)
    # 200 when the export has ended; 202 while a running export is still stopping.
    response.status_code = 200 if job.state == "cancelled" else 202
    return {"id": job.id, "state": job.state, "stop_requested": job.stop_requested_at is not None}
