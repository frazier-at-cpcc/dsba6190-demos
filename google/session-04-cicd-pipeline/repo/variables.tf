variable "project_id" {
  description = "Google Cloud project that holds the buckets."
  type        = string
}

variable "region" {
  description = "Location for every bucket. Policy restricts this to an approved set."
  type        = string
  default     = "us-east1"
}

variable "env" {
  description = "Environment label. Policy requires it on every bucket."
  type        = string
  default     = "dev"
}

variable "extra_labels" {
  description = "Labels merged onto every bucket in addition to owner, env, and managed-by."
  type        = map(string)
  default     = {}
}
