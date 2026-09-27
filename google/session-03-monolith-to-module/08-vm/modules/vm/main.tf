# The Lab 3 VM, turned into a module body.
locals {
  labels = {
    environment = var.environment
    owner       = var.owner
    cost-center = "dsba6190"
  }
}

resource "google_compute_instance" "vm" {
  name         = var.name
  zone         = var.zone
  machine_type = var.machine_type
  tags         = ["web", var.environment]
  labels       = local.labels

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  # No access_config block, so no external IP address to pay for.
  network_interface {
    network = "default"
  }

  # Google refuses the delete, whatever tool asks.
  deletion_protection = var.environment == "prod"

  # Lab 3, Task 5: a machine type change stops the VM instead of failing.
  allow_stopping_for_update = true
}
