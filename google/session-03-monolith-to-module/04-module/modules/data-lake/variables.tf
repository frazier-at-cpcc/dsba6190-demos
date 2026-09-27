# The module's contract. These are its parameters.
variable "environment" {
  type        = string
  description = "Environment this lake serves. Becomes part of the name and a label."

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, prod."
  }
}

variable "name_suffix" {
  type        = string
  description = "Random suffix so the global bucket namespace does not collide."
}

variable "location" {
  type        = string
  description = "Bucket location."
  default     = "US-EAST1"
}

variable "storage_class" {
  type        = string
  description = "Storage class for the zone."
  default     = "STANDARD"
}

variable "owner" {
  type        = string
  description = "Owning team. Enforced as a label so callers cannot forget it."
}
