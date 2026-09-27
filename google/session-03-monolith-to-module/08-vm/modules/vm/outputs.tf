output "summary" {
  value = {
    name                = google_compute_instance.vm.name
    machine_type        = google_compute_instance.vm.machine_type
    deletion_protection = google_compute_instance.vm.deletion_protection
  }
  description = "Name, machine type, and deletion protection of the instance."
}
