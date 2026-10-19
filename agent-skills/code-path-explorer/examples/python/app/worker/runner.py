"""The export worker: claims one queued export at a time and uploads it in parts."""


def run_once(repo, storage, worker_id):
    job = repo.claim_next(worker_id)
    if job:
        run_export(repo, storage, job)


def run_export(repo, storage, job):
    upload = storage.start_upload(job.id)
    for part in render_parts(job):
        if repo.stop_requested(job.id):
            storage.abort_upload(upload)
            return repo.finish(job.id, "cancelled", cancel_reason="stopped")
        storage.upload_part(upload, part)
    storage.complete_upload(upload)
    return repo.finish(job.id, "succeeded")


def render_parts(job):
    yield from job.render()
