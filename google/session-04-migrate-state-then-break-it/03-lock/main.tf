terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # Declared here rather than in 03-lock so that step 5 is a file swap and
    # not a second `terraform init` in front of the room.
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = "us-east1"
}

variable "project_id" {
  type        = string
  description = "The project the demo resources land in."
}

variable "name_suffix" {
  type        = string
  description = "Random suffix so the global bucket namespace does not collide."
}

# Nobody typed this value and nobody chose to store it. Terraform generated it,
# and Terraform therefore records it. Step 1 reads it back out of the file.
resource "random_password" "db_admin" {
  length  = 24
  special = true
}

resource "google_storage_bucket" "raw" {
  name          = "dsba6190-raw-${var.name_suffix}"
  location      = "US-EAST1"
  storage_class = "STANDARD"

  uniform_bucket_level_access = true

  # The honest default. Step 11 is the argument for changing it, and the
  # argument for not leaving it changed.
  force_destroy = false

  labels = {
    environment = "demo"
    owner       = "data-platform"
  }
}

resource "google_pubsub_topic" "events" {
  name = "dsba6190-events-${var.name_suffix}"

  labels = {
    environment = "demo"
    owner       = "data-platform"
  }
}

# Step 5. The lock is only visible if something holds it long enough to see.
# time_sleep is local to the provider, costs nothing, and blocks the apply for
# ninety seconds, which is long enough to switch terminals and read the error.
resource "time_sleep" "slow_apply" {
  create_duration = "90s"

  triggers = {
    suffix = var.name_suffix
  }
}

# sensitive = true suppresses the console. It does nothing to the state file.
output "db_admin_password" {
  value     = random_password.db_admin.result
  sensitive = true
}

output "raw_bucket" {
  value = google_storage_bucket.raw.url
}
