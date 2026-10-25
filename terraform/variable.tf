variable "aws_region" {
  default = "ap-south-1"
}

variable "project_name" {
  default = "travelmemory"
}

variable "my_ip_cidr" {
  description = "103.69.24.243/32"
  type        = string
}

variable "key_name" {
  description = "travelmemory-key"
  type        = string
}