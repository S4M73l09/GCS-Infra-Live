locals {
  target = "${var.project_id}/${var.zone}/${var.instance_name}"
}

resource "google_pubsub_topic" "idle_stop" {
  count = var.enable_idle_policy ? 1 : 0
  name  = "${var.instance_name}-idle-stop"
}

resource "google_monitoring_notification_channel" "idle_pubsub" {
  count        = var.enable_idle_policy ? 1 : 0
  display_name = "${var.instance_name}-idle-pubsub"
  type         = "pubsub"
  labels = {
    topic = google_pubsub_topic.idle_stop[0].id
  }
}

resource "google_monitoring_alert_policy" "vm_idle_cpu" {
  count        = var.enable_idle_policy ? 1 : 0
  display_name = "${var.instance_name}-idle-cpu"
  combiner     = "OR"

  conditions {
    display_name = "CPU idle"
    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND resource.labels.project_id=\"${var.project_id}\" AND resource.labels.zone=\"${var.zone}\" AND resource.labels.instance_id=\"${var.instance_id}\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\""
      comparison      = "COMPARISON_LT"
      threshold_value = var.idle_cpu_threshold
      duration        = "${var.idle_duration_seconds}s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  notification_channels = [google_monitoring_notification_channel.idle_pubsub[0].name]
  enabled               = true
}