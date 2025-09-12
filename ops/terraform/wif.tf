# --- Workload Identity Federation (Securely connect GitHub Actions to GCP) ---
resource "google_iam_workload_identity_pool" "github" {
  # Note: Workload Identity Pools are soft-deleted in GCP and cannot be recreated with the same ID for ~30 days.
  # To prevent breaking re-provisioning flows after a destroy, we forbid destroying this resource via Terraform.
  # If you truly need to delete the pool, remove it manually in GCP and also remove it from state explicitly.
  workload_identity_pool_id = "ga-pool-keycloak-v1"
  display_name              = "GitHub Actions (Keycloak)"

  lifecycle {
    prevent_destroy = false # need to be able to drop this at will, since this is a test setup.
  }
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "ga-provider-keycloak-v1"
  display_name                       = "GitHub Actions (Keycloak)"
  attribute_condition                = "assertion.repository=='${var.github_repo}'"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  lifecycle {
    prevent_destroy = false # need to be able to drop this at will, since this is a test setup.
  }
}

resource "google_service_account_iam_member" "workload_identity_user" {
  service_account_id = google_service_account.github_actions_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}
