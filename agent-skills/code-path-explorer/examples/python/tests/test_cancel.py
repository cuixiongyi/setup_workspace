def test_cancel_queued_export_ends_it(repo, queued_export):
    job = repo.cancel(queued_export.id)
    assert (job.state, job.cancel_reason) == ("cancelled", "not_started")


def test_cancel_running_export_requests_stop(repo, running_export):
    job = repo.cancel(running_export.id)
    assert job.state == "running" and job.stop_requested_at is not None


def test_cancel_other_users_export_is_not_found(client, other_users_export):
    response = client.post(f"/exports/{other_users_export.id}/cancel")
    assert response.status_code == 404
