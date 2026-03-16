resource "random_id" "bucket_suffix" {
  byte_length = 3
}

locals {
  required_services = var.manage_project_services ? toset([
    "compute.googleapis.com",
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "redis.googleapis.com",
    "vpcaccess.googleapis.com",
    "servicenetworking.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
  ]) : toset([])

  normalized_stack_name                  = lower(replace(var.stack_name, "/[^a-z0-9-]/", "-"))
  aws_attached_mode                      = var.deployment_mode == "aws_attached"
  standalone_mode                        = !local.aws_attached_mode
  use_existing_runtime_service_account   = trimspace(var.runtime_service_account_email) != ""
  resolved_runtime_service_account_email = local.use_existing_runtime_service_account ? trimspace(var.runtime_service_account_email) : google_service_account.runtime[0].email
  runtime_roles = var.manage_runtime_service_account_roles ? toset([
    "roles/cloudsql.client",
    "roles/storage.objectAdmin",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ]) : toset([])

  generated_assets_bucket_name = substr("${local.normalized_stack_name}-assets-${random_id.bucket_suffix.hex}", 0, 63)

  resolved_assets_bucket_name = local.aws_attached_mode ? trimspace(var.aws_assets_bucket_name) : (
    trimspace(var.assets_bucket_name) != "" ? trimspace(var.assets_bucket_name) : local.generated_assets_bucket_name
  )

  use_custom_domain = trimspace(var.domain_name) != ""

  resolved_site_url = trimspace(var.site_url) != "" ? trimspace(var.site_url) : (
    local.use_custom_domain ? "https://${trimspace(var.domain_name)}" : "http://${google_compute_global_address.lb.address}"
  )

  resolved_image_base_url = trimspace(var.image_base_url) != "" ? trimspace(var.image_base_url) : (
    local.aws_attached_mode ? "https://${local.resolved_assets_bucket_name}.s3.amazonaws.com" : "https://storage.googleapis.com/${local.resolved_assets_bucket_name}"
  )

  runtime_google_project_id = trimspace(var.google_project_id_runtime) != "" ? trimspace(var.google_project_id_runtime) : var.project_id

  runtime_google_location = trimspace(var.google_location) != "" ? trimspace(var.google_location) : var.region

  resolved_db_host = local.aws_attached_mode ? trimspace(var.aws_database_host) : google_sql_database_instance.db[0].private_ip_address

  resolved_db_name = local.aws_attached_mode && trimspace(var.aws_database_name) != "" ? trimspace(var.aws_database_name) : var.database_name

  resolved_db_port = local.aws_attached_mode ? tostring(var.aws_database_port) : tostring(var.database_port)

  resolved_db_user = local.aws_attached_mode && trimspace(var.aws_database_username) != "" ? trimspace(var.aws_database_username) : var.database_username

  resolved_redis_host = local.aws_attached_mode ? trimspace(var.aws_redis_host) : google_redis_instance.cache[0].host

  resolved_redis_port = local.aws_attached_mode ? tostring(var.aws_redis_port) : tostring(google_redis_instance.cache[0].port)

  dockerhub_remote_enabled = var.dockerhub_use_remote_repository
  dockerhub_remote_host    = "${var.region}-docker.pkg.dev/${var.project_id}/${var.dockerhub_remote_repository_id}"

  dockerhub_app_image_path = replace(
    replace(trimspace(var.app_container_image), "docker.io/", ""),
    "index.docker.io/",
    ""
  )
  dockerhub_api_image_path = replace(
    replace(trimspace(var.api_container_image), "docker.io/", ""),
    "index.docker.io/",
    ""
  )
  dockerhub_migration_image_path = replace(
    replace(trimspace(var.migration_container_image), "docker.io/", ""),
    "index.docker.io/",
    ""
  )

  resolved_app_container_image       = local.dockerhub_remote_enabled ? "${local.dockerhub_remote_host}/${local.dockerhub_app_image_path}" : trimspace(var.app_container_image)
  resolved_api_container_image       = local.dockerhub_remote_enabled ? "${local.dockerhub_remote_host}/${local.dockerhub_api_image_path}" : trimspace(var.api_container_image)
  resolved_migration_container_image = local.dockerhub_remote_enabled ? "${local.dockerhub_remote_host}/${local.dockerhub_migration_image_path}" : trimspace(var.migration_container_image)

  app_env_all = {
    APP_ENV                = "prod"
    SITE_URL               = local.resolved_site_url
    PROVIDER_DOMAIN_MAP    = var.provider_domain_map
    STRIPE_PUBLISHABLE_KEY = var.stripe_publishable_key
    GTM_ID                 = var.gtm_id
    CUSTOMER_IO_SITE_ID    = var.customer_io_site_id
    RECAPTCHA_SITE_KEY     = var.recaptcha_site_key
  }

  app_env = {
    for k, v in local.app_env_all :
    k => tostring(v)
    if trimspace(tostring(v)) != ""
  }

  api_env_all = {
    APP_ENV                       = "prod"
    AWS_REGION                    = var.region
    BEDROCK_AWS_ACCESS_KEY_ID     = var.bedrock_aws_access_key_id
    BEDROCK_AWS_SECRET_ACCESS_KEY = var.bedrock_aws_secret_access_key
    BEDROCK_AWS_REGION            = var.bedrock_aws_region
    OPENAI_API_KEY                = var.openai_api_key
    HUGGINGFACE_API_TOKEN         = var.huggingface_api_token
    ANTHROPIC_API_KEY             = var.anthropic_api_key
    GOOGLE_API_KEY                = var.google_api_key
    GOOGLE_PROJECT_ID             = local.runtime_google_project_id
    GOOGLE_LOCATION               = local.runtime_google_location
    GOOGLE_SERVICE_ACCOUNT        = var.google_service_account_json
    MAGINARY_API_KEY              = var.maginary_api_key
    BUCKET_NAME                   = local.resolved_assets_bucket_name
    IMAGE_BASE_URL                = local.resolved_image_base_url
    DB_HOST                       = local.resolved_db_host
    DB_NAME                       = local.resolved_db_name
    DB_PASSWORD                   = var.database_password
    DB_PORT                       = local.resolved_db_port
    DB_USER                       = local.resolved_db_user
    CUSTOMER_IO_API_KEY           = var.customer_io_api_key
    CUSTOMER_IO_TRACKING_API_KEY  = var.customer_io_tracking_api_key
    CUSTOMER_IO_SITE_ID           = var.customer_io_site_id
    REDIS_HOST                    = local.resolved_redis_host
    REDIS_PORT                    = local.resolved_redis_port
    REDIS_TLS                     = var.redis_tls
    REDIS_TOKEN                   = var.redis_token
    RECAPTCHA_SECRET_KEY          = var.recaptcha_secret_key
    SEARXNG_BASE_URL              = var.searxng_base_url
    PROVIDER_DOMAIN_MAP           = var.provider_domain_map
    SESSION_SECRET                = var.session_secret
    TOKEN_ENCRYPT_VECTOR          = var.token_encrypt_vector
    SITE_URL                      = local.resolved_site_url
    STRIPE_SECRET_KEY             = var.stripe_secret_key
    STRIPE_WEBHOOK_SECRET_KEY     = var.stripe_webhook_secret_key
    TOKEN_PEPPER                  = var.token_pepper
    TOKEN_PREFIX                  = var.token_prefix
    TOKEN_BYTE_LENGTH             = var.token_byte_length
    OPENSEARCH_NODE_URL           = var.opensearch_node_url
    OPENSEARCH_HOST               = var.opensearch_host
    OPENSEARCH_PORT               = var.opensearch_port
    OPENSEARCH_PROTOCOL           = var.opensearch_protocol
  }

  api_env = {
    for k, v in local.api_env_all :
    k => tostring(v)
    if trimspace(tostring(v)) != ""
  }

  migration_env_all = {
    APP_ENV              = "prod"
    AWS_REGION           = var.region
    BUCKET_NAME          = local.resolved_assets_bucket_name
    IMAGE_BASE_URL       = local.resolved_image_base_url
    DB_HOST              = local.resolved_db_host
    DB_NAME              = local.resolved_db_name
    DB_PASSWORD          = var.database_password
    DB_PORT              = local.resolved_db_port
    DB_USER              = local.resolved_db_user
    REDIS_HOST           = local.resolved_redis_host
    REDIS_PORT           = local.resolved_redis_port
    REDIS_TLS            = var.redis_tls
    REDIS_TOKEN          = var.redis_token
    SESSION_SECRET       = var.session_secret
    TOKEN_ENCRYPT_VECTOR = var.token_encrypt_vector
    PROVIDER_DOMAIN_MAP  = var.provider_domain_map
    SITE_URL             = local.resolved_site_url
    TOKEN_PEPPER         = var.token_pepper
    TOKEN_PREFIX         = var.token_prefix
    TOKEN_BYTE_LENGTH    = var.token_byte_length
    OPENSEARCH_NODE_URL  = var.opensearch_node_url
    OPENSEARCH_HOST      = var.opensearch_host
    OPENSEARCH_PORT      = var.opensearch_port
    OPENSEARCH_PROTOCOL  = var.opensearch_protocol
  }

  migration_env = {
    for k, v in local.migration_env_all :
    k => tostring(v)
    if trimspace(tostring(v)) != ""
  }
}

check "dockerhub_remote_repo_required_values" {
  assert {
    condition = !var.dockerhub_use_remote_repository || (
      trimspace(var.dockerhub_username) != "" &&
      trimspace(var.dockerhub_password_secret_id) != "" &&
      trimspace(var.dockerhub_password_secret_version) != ""
    )
    error_message = "When dockerhub_use_remote_repository=true, set dockerhub_username, dockerhub_password_secret_id, and dockerhub_password_secret_version."
  }
}

check "dockerhub_secret_version_matches_secret_id" {
  assert {
    condition = !var.dockerhub_use_remote_repository || startswith(
      trimspace(var.dockerhub_password_secret_version),
      "${trimspace(var.dockerhub_password_secret_id)}/versions/"
    )
    error_message = "dockerhub_password_secret_version must belong to dockerhub_password_secret_id."
  }
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

resource "google_secret_manager_secret_iam_member" "dockerhub_secret_accessor" {
  count = local.dockerhub_remote_enabled ? 1 : 0

  project   = var.project_id
  secret_id = var.dockerhub_password_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-artifactregistry.iam.gserviceaccount.com"

  depends_on = [google_project_service.required]
}

resource "google_artifact_registry_repository" "dockerhub_remote" {
  count = local.dockerhub_remote_enabled ? 1 : 0

  project       = var.project_id
  location      = var.region
  repository_id = var.dockerhub_remote_repository_id
  description   = "Docker Hub remote repository with upstream credentials."
  format        = "DOCKER"
  mode          = "REMOTE_REPOSITORY"

  remote_repository_config {
    description = "Docker Hub upstream"

    docker_repository {
      public_repository = "DOCKER_HUB"
    }

    upstream_credentials {
      username_password_credentials {
        username                = var.dockerhub_username
        password_secret_version = var.dockerhub_password_secret_version
      }
    }
  }

  depends_on = [
    google_project_service.required,
    google_secret_manager_secret_iam_member.dockerhub_secret_accessor,
  ]
}

resource "google_compute_network" "vpc" {
  name                    = "${local.normalized_stack_name}-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.required]
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${local.normalized_stack_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
}

resource "google_compute_global_address" "private_services_range" {
  count = local.standalone_mode ? 1 : 0

  name          = "${local.normalized_stack_name}-private-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  count = local.standalone_mode ? 1 : 0

  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services_range[0].name]

  depends_on = [google_project_service.required]
}

resource "google_compute_global_address" "lb" {
  name = "${local.normalized_stack_name}-lb-ip"

  depends_on = [google_project_service.required]
}

resource "google_sql_database_instance" "db" {
  count = local.standalone_mode ? 1 : 0

  name                = "${local.normalized_stack_name}-db"
  database_version    = "MYSQL_8_0"
  region              = var.region
  root_password       = var.database_password
  deletion_protection = var.deletion_protection

  settings {
    tier      = var.database_tier
    disk_size = var.database_disk_size_gb

    availability_type = "ZONAL"

    backup_configuration {
      enabled            = true
      binary_log_enabled = true
      start_time         = "03:00"
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.vpc.id
      enable_private_path_for_google_cloud_services = true
    }
  }

  depends_on = [google_service_networking_connection.private_vpc_connection[0]]
}

resource "google_sql_database" "database" {
  count = local.standalone_mode ? 1 : 0

  name     = var.database_name
  instance = google_sql_database_instance.db[0].name
}

resource "google_sql_user" "db_user" {
  count = local.standalone_mode && var.database_username != "root" ? 1 : 0

  instance = google_sql_database_instance.db[0].name
  name     = var.database_username
  password = var.database_password
}

resource "google_redis_instance" "cache" {
  count = local.standalone_mode ? 1 : 0

  name           = "${local.normalized_stack_name}-redis"
  tier           = "BASIC"
  memory_size_gb = var.redis_memory_size_gb
  region         = var.region
  redis_version  = "REDIS_7_0"

  authorized_network = google_compute_network.vpc.id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"

  depends_on = [google_service_networking_connection.private_vpc_connection[0]]
}

resource "google_vpc_access_connector" "connector" {
  name          = "${local.normalized_stack_name}-connector"
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = var.vpc_connector_cidr

  min_instances = 2
  max_instances = 3
}

resource "google_service_account" "runtime" {
  count = local.use_existing_runtime_service_account ? 0 : 1

  account_id   = substr(replace("${local.normalized_stack_name}-runtime", "_", "-"), 0, 30)
  display_name = "${var.stack_name} runtime"
}

resource "google_project_iam_member" "runtime_roles" {
  for_each = local.runtime_roles

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${local.resolved_runtime_service_account_email}"
}

resource "google_storage_bucket" "assets" {
  count = local.standalone_mode ? 1 : 0

  name                        = local.resolved_assets_bucket_name
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true

  public_access_prevention = "inherited"

  depends_on = [google_project_service.required]
}

resource "google_storage_bucket_iam_member" "assets_public_read" {
  count  = local.standalone_mode ? 1 : 0
  bucket = google_storage_bucket.assets[0].name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_cloud_run_v2_service" "app" {
  name                = "${local.normalized_stack_name}-app"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  deletion_protection = var.cloud_run_deletion_protection

  template {
    service_account = local.resolved_runtime_service_account_email

    scaling {
      min_instance_count = var.instance_count
      max_instance_count = max(1, var.instance_count * 2)
    }

    containers {
      name  = "app"
      image = local.resolved_app_container_image

      ports {
        container_port = 3000
      }

      resources {
        limits = {
          cpu    = var.app_service_cpu
          memory = var.app_service_memory
        }
      }

      dynamic "env" {
        for_each = local.app_env
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  depends_on = [google_project_service.required]
}

resource "google_cloud_run_v2_service_iam_member" "app_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.app.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service" "api" {
  name                = "${local.normalized_stack_name}-api"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  deletion_protection = var.cloud_run_deletion_protection

  template {
    service_account = local.resolved_runtime_service_account_email

    scaling {
      min_instance_count = var.instance_count
      max_instance_count = max(1, var.instance_count * 2)
    }

    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      name  = "api"
      image = local.resolved_api_container_image

      ports {
        container_port = 3001
      }

      resources {
        limits = {
          cpu    = var.api_service_cpu
          memory = var.api_service_memory
        }
      }

      dynamic "env" {
        for_each = local.api_env
        content {
          name  = env.key
          value = env.value
        }
      }
    }

    containers {
      name  = "searxng"
      image = var.searxng_container_image

      resources {
        limits = {
          cpu    = var.searxng_sidecar_cpu
          memory = var.searxng_sidecar_memory
        }
      }

      env {
        name  = "BASE_URL"
        value = "http://localhost:8080/"
      }

      env {
        name  = "SEARXNG_SECRET"
        value = var.searxng_secret
      }
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  depends_on = [
    google_project_iam_member.runtime_roles,
    google_vpc_access_connector.connector,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "api_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_job" "api_migrations" {
  name                = "${local.normalized_stack_name}-api-migrations"
  location            = var.region
  deletion_protection = var.cloud_run_deletion_protection

  template {
    template {
      service_account = local.resolved_runtime_service_account_email
      max_retries     = 0
      timeout         = "3600s"

      vpc_access {
        connector = google_vpc_access_connector.connector.id
        egress    = "PRIVATE_RANGES_ONLY"
      }

      containers {
        image = local.resolved_migration_container_image

        resources {
          limits = {
            cpu    = var.api_service_cpu
            memory = var.api_service_memory
          }
        }

        dynamic "env" {
          for_each = local.migration_env
          content {
            name  = env.key
            value = env.value
          }
        }
      }
    }
  }

  depends_on = [
    google_project_iam_member.runtime_roles,
    google_vpc_access_connector.connector,
  ]
}

resource "google_compute_region_network_endpoint_group" "app_neg" {
  name                  = "${local.normalized_stack_name}-app-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_v2_service.app.name
  }
}

resource "google_compute_region_network_endpoint_group" "api_neg" {
  name                  = "${local.normalized_stack_name}-api-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_v2_service.api.name
  }
}

resource "google_compute_backend_service" "app" {
  name                  = "${local.normalized_stack_name}-app-backend"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_region_network_endpoint_group.app_neg.id
  }
}

resource "google_compute_backend_service" "api" {
  name                  = "${local.normalized_stack_name}-api-backend"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_region_network_endpoint_group.api_neg.id
  }
}

resource "google_compute_backend_bucket" "assets" {
  count = local.standalone_mode ? 1 : 0

  name        = "${substr(local.normalized_stack_name, 0, 40)}-assets-bkt"
  bucket_name = google_storage_bucket.assets[0].name
  enable_cdn  = var.enable_cdn
}

resource "google_compute_url_map" "main" {
  name            = "${local.normalized_stack_name}-url-map"
  default_service = google_compute_backend_service.app.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "all-routes"
  }

  path_matcher {
    name            = "all-routes"
    default_service = google_compute_backend_service.app.id

    path_rule {
      paths   = ["/api/*"]
      service = google_compute_backend_service.api.id
    }

    dynamic "path_rule" {
      for_each = local.standalone_mode ? [1] : []
      content {
        paths   = ["/ms-content/*"]
        service = google_compute_backend_bucket.assets[0].id
      }
    }
  }
}

resource "google_compute_managed_ssl_certificate" "main" {
  count = local.use_custom_domain ? 1 : 0

  name = "${local.normalized_stack_name}-managed-cert"

  managed {
    domains = [trimspace(var.domain_name)]
  }
}

resource "google_compute_target_https_proxy" "main" {
  count = local.use_custom_domain ? 1 : 0

  name             = "${local.normalized_stack_name}-https-proxy"
  url_map          = google_compute_url_map.main.id
  ssl_certificates = [google_compute_managed_ssl_certificate.main[0].id]
}

resource "google_compute_global_forwarding_rule" "https" {
  count = local.use_custom_domain ? 1 : 0

  name                  = "${local.normalized_stack_name}-https-fr"
  ip_address            = google_compute_global_address.lb.id
  target                = google_compute_target_https_proxy.main[0].id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_compute_url_map" "https_redirect" {
  count = local.use_custom_domain ? 1 : 0

  name = "${local.normalized_stack_name}-redirect-map"

  default_url_redirect {
    https_redirect         = true
    strip_query            = false
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  count = local.use_custom_domain ? 1 : 0

  name    = "${local.normalized_stack_name}-redirect-proxy"
  url_map = google_compute_url_map.https_redirect[0].id
}

resource "google_compute_global_forwarding_rule" "http_redirect" {
  count = local.use_custom_domain ? 1 : 0

  name                  = "${local.normalized_stack_name}-http-redirect-fr"
  ip_address            = google_compute_global_address.lb.id
  target                = google_compute_target_http_proxy.redirect[0].id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_compute_target_http_proxy" "http" {
  count = local.use_custom_domain ? 0 : 1

  name    = "${local.normalized_stack_name}-http-proxy"
  url_map = google_compute_url_map.main.id
}

resource "google_compute_global_forwarding_rule" "http" {
  count = local.use_custom_domain ? 0 : 1

  name                  = "${local.normalized_stack_name}-http-fr"
  ip_address            = google_compute_global_address.lb.id
  target                = google_compute_target_http_proxy.http[0].id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
