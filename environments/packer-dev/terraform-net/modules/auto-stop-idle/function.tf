resource "google_storage_bucket" "function_src" {
  name                        = "${var.project_id}-${var.instance_name}-auto-stop-src"
  location                    = "EU"
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = true
}

data "archive_file" "function_zip" {
  type        = "zip"
  source_dir  = "${path.module}/function"
  output_path = "${path.module}/function.zip"
}

resource "google_storage_bucket_object" "function_zip" {
  name   = "function-${data.archive_file.function_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_src.name
  source = data.archive_file.function_zip.output_path
}

resource "google_cloudfunctions2_function" "auto_stop" {
  name     = "${var.instance_name}-auto-stop"
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = "python311"
    entry_point = "auto_stop"
    source {
      storage_source {
        bucket = google_storage_bucket.function_src.name
        object = google_storage_bucket_object.function_zip.name
      }
    }
  }

  service_config {
    service_account_email = google_service_account.auto_stop_sa.email
    timeout_seconds       = 60
    available_memory      = "256M"
    environment_variables = {
      PROJECT_ID    = var.project_id
      INSTANCE_NAME = var.instance_name
      ZONE          = var.zone
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.idle_stop[0].id
    retry_policy   = "RETRY_POLICY_DO_NOT_RETRY"
  }
}