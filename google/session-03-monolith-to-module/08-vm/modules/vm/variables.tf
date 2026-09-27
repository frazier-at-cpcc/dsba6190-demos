# Five inputs. The image, the network, and the labels stay in the body.
variable "name" {
  type        = string
  description = "Instance name."
}

variable "environment" {
  type        = string
  description = "dev, test, or prod. prod turns on deletion protection."

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, prod."
  }
}

variable "zone" {
  type        = string
  description = "Zone for the instance."
  default     = "us-east1-b"
}

variable "machine_type" {
  type        = string
  default     = "e2-micro"
  description = "Machine type for the VM."

  validation {
    condition     = can(regex("^e2-(micro|small|medium)$", var.machine_type))
    error_message = "machine_type must be e2-micro, e2-small, or e2-medium."
  }
}

variable "owner" {
  type        = string
  description = "Owning team. Enforced as a label."
}
