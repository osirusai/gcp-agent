output "load_balancer_ip" {
  description = "Global load balancer IP address."
  value       = google_compute_global_address.lb.address
}

output "site_url" {
  description = "Primary site URL (from site_url override, custom domain, or load balancer IP)."
  value       = local.resolved_site_url
}

output "app_cloud_run_url" {
  description = "Direct Cloud Run URL for app service (bypasses load balancer)."
  value       = google_cloud_run_v2_service.app.uri
}

output "api_cloud_run_url" {
  description = "Direct Cloud Run URL for API service (bypasses load balancer)."
  value       = google_cloud_run_v2_service.api.uri
}

output "assets_bucket_name" {
  description = "Assets bucket name used by runtime (GCS in standalone mode, S3 in aws_attached mode)."
  value       = local.resolved_assets_bucket_name
}

output "cloud_sql_private_ip" {
  description = "Cloud SQL private IP used by API and migration job (standalone mode only)."
  value       = local.standalone_mode ? google_sql_database_instance.db[0].private_ip_address : null
}

output "redis_host" {
  description = "Redis host used by runtime."
  value       = local.resolved_redis_host
}

output "redis_port" {
  description = "Redis port used by runtime."
  value       = local.resolved_redis_port
}

output "deployment_mode" {
  description = "Applied deployment mode."
  value       = var.deployment_mode
}

output "migration_job_name" {
  description = "Cloud Run Job name for API migrations."
  value       = google_cloud_run_v2_job.api_migrations.name
}

output "run_migrations_command" {
  description = "Command to run DB migrations after apply."
  value       = "gcloud run jobs execute ${google_cloud_run_v2_job.api_migrations.name} --region ${var.region} --project ${var.project_id} --wait"
}
