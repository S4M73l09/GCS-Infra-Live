output "target" {
  value = local.target
}

output "idle_stop_topic" {
  value = try(google_pubsub_topic.idle_stop[0].id, null)
}