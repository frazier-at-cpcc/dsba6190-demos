# The module's contract. Five inputs a caller must think about, one optional.
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

  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE"], var.storage_class)
    error_message = "storage_class must be STANDARD, NEARLINE, or COLDLINE."
  }
}

variable "owner" {
  type        = string
  description = "Owning team. Enforced as a label so callers cannot forget it."
}

variable "extra_labels" {
  type        = map(string)
  description = "Additional labels. Keys the module enforces are overruled."
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.extra_labels) : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))])
    error_message = "Label keys must start with a lowercase letter and use only a-z, 0-9, _ and -."
  }
}

variable "force_destroy" {
  type        = bool
  description = "Delete the bucket even when it holds objects. Leave false for data."
  default     = false
}
