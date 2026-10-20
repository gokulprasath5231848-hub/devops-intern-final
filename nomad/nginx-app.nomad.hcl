variable "image_repository" {
  type        = string
  description = "Container image repository published by the CI pipeline."
  default     = "ghcr.io/gokulprasath5231848-hub/devops-intern-final"
}

variable "image_tag" {
  type        = string
  description = "Image tag to deploy. Use the commit SHA for a reproducible rollout."
  default     = "latest"
}

variable "datacenters" {
  type    = list(string)
  default = ["dc1"]
}

job "nginx-app" {
  datacenters = var.datacenters
  type        = "service"

  group "web" {
    count = 1

    network {
      port "http" {
        to = 8080
      }
    }

    restart {
      attempts = 2
      interval = "5m"
      delay    = "15s"
      mode     = "fail"
    }

    reschedule {
      attempts       = 3
      interval       = "1h"
      delay          = "30s"
      delay_function = "exponential"
      max_delay      = "5m"
      unlimited      = false
    }

    update {
      max_parallel     = 1
      min_healthy_time = "10s"
      healthy_deadline = "2m"
      auto_revert      = true
    }

    service {
      name     = "nginx-app"
      port     = "http"
      provider = "consul"
      tags     = ["nginx", "web"]

      check {
        name     = "healthz"
        type     = "http"
        path     = "/healthz"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "nginx" {
      driver = "docker"

      config {
        image = "${var.image_repository}:${var.image_tag}"
        ports = ["http"]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
