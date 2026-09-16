# Golden-signals dashboard for this environment's 3 Cloud Run services —
# request volume, latency, error rate, and resource usage, all on one page
# so an incident doesn't start with hunting through 3 separate service
# pages in Console. One instance per environment (staging gets its own too,
# same shape, since the module is invoked once per environment) — cheap
# and it means staging traffic patterns are visible before they'd ever hit
# production.
locals {
  monitoring_services = {
    tickets-api  = google_cloud_run_v2_service.tickets_api.name
    auth-service = google_cloud_run_v2_service.auth_service.name
    tickets-web  = google_cloud_run_v2_service.tickets_web.name
  }
}

resource "google_monitoring_dashboard" "main" {
  project = var.project_id

  dashboard_json = jsonencode({
    displayName = "Festival — ${var.environment}"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          xPos = 0, yPos = 0, width = 12, height = 4
          widget = {
            title = "Request count"
            xyChart = {
              dataSets = [
                for key, name in local.monitoring_services : {
                  plotType       = "STACKED_BAR"
                  legendTemplate = key
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter      = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"${name}\" AND metric.type=\"run.googleapis.com/request_count\""
                      aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_RATE", crossSeriesReducer = "REDUCE_SUM" }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          xPos = 0, yPos = 4, width = 12, height = 4
          widget = {
            title = "5xx server errors"
            xyChart = {
              dataSets = [
                for key, name in local.monitoring_services : {
                  plotType       = "LINE"
                  legendTemplate = key
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter      = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"${name}\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.label.response_code_class=\"5xx\""
                      aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_RATE", crossSeriesReducer = "REDUCE_SUM" }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          xPos = 0, yPos = 8, width = 12, height = 4
          widget = {
            title = "Request latency (p95, ms)"
            xyChart = {
              dataSets = [
                for key, name in local.monitoring_services : {
                  plotType       = "LINE"
                  legendTemplate = key
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter      = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"${name}\" AND metric.type=\"run.googleapis.com/request_latencies\""
                      aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_PERCENTILE_95", crossSeriesReducer = "REDUCE_MEAN" }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          xPos = 0, yPos = 12, width = 6, height = 4
          widget = {
            title = "Container CPU utilization"
            xyChart = {
              dataSets = [
                for key, name in local.monitoring_services : {
                  plotType       = "LINE"
                  legendTemplate = key
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter      = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"${name}\" AND metric.type=\"run.googleapis.com/container/cpu/utilizations\""
                      aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_MEAN", crossSeriesReducer = "REDUCE_MEAN" }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          xPos = 6, yPos = 12, width = 6, height = 4
          widget = {
            title = "Container memory utilization"
            xyChart = {
              dataSets = [
                for key, name in local.monitoring_services : {
                  plotType       = "LINE"
                  legendTemplate = key
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter      = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"${name}\" AND metric.type=\"run.googleapis.com/container/memory/utilizations\""
                      aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_MEAN", crossSeriesReducer = "REDUCE_MEAN" }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          xPos = 0, yPos = 16, width = 12, height = 4
          widget = {
            title = "Active instance count"
            xyChart = {
              dataSets = [
                for key, name in local.monitoring_services : {
                  plotType       = "LINE"
                  legendTemplate = key
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter      = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"${name}\" AND metric.type=\"run.googleapis.com/container/instance_count\""
                      aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_MEAN", crossSeriesReducer = "REDUCE_SUM" }
                    }
                  }
                }
              ]
            }
          }
        },
      ]
    }
  })
}

output "monitoring_dashboard_url" {
  value = "https://console.cloud.google.com/monitoring/dashboards/builder/${element(split("/", google_monitoring_dashboard.main.id), 3)}?project=${var.project_id}"
}
